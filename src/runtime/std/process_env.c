/* The @std/process natives for the working directory and the environment. libuv answers all of them, so the
 * same code serves Linux, macOS and Windows; nothing here blocks or parks. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <uv.h>

#include "base/alloc.h"
#include "base/list.h"
#include "base/ostext.h"
#include "base/path.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "runtime/std/process_env.h"
#include "abi/status.h"

enum { FIRST_PATH = 1024 };

/* Ends a native with `status`, which carries no text. */
static uint8_t finish(uint8_t status, MsString *err) {
  *err = ms_string_empty();
  return status;
}

/* A failed libuv call of `operation` on `name` (empty for none): not found, permission denied and unsupported
 * keep their status; the rest are MS_STATUS_FAILED with `operation name: reason`. */
static uint8_t fail_uv(int code, const char *operation, MsSpan name, MsString *err) {
  if (code == UV_ENOENT) {
    return finish(MS_STATUS_NOT_FOUND, err);
  }
  if (code == UV_EACCES || code == UV_EPERM) {
    return finish(MS_STATUS_PERMISSION_DENIED, err);
  }
  if (code == UV_ENOTSUP || code == UV_ENOSYS) {
    return finish(MS_STATUS_UNSUPPORTED, err);
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, operation);
  if (name.len != 0) {
    ms_strbuild_append_byte(&text, ' ');
    ms_strbuild_append(&text, name);
  }
  ms_strbuild_append_text(&text, ": ");
  ms_strbuild_append_text(&text, uv_strerror(code));
  *err = ms_strbuild_finish(&text);
  ms_strbuild_free(&text);
  return MS_STATUS_FAILED;
}

/* A name or value the host gave us as a String: false when it is not UTF-8. */
static bool is_text(const char *text) {
  const MsSpan span = ms_span_of_text(text);
  return ms_utf8_is_valid(span.ptr, span.len);
}

/* ---- working directory ---- */

uint8_t msstd_process_working_directory(MsString *out, MsString *err) {
  size_t capacity = FIRST_PATH;
  char *buffer = ms_alloc(capacity);
  size_t size = capacity;
  int code = uv_cwd(buffer, &size);
  if (code == UV_ENOBUFS) {
    capacity = size > capacity ? size : capacity * 2;
    buffer = ms_realloc(buffer, capacity);
    size = capacity;
    code = uv_cwd(buffer, &size);
  }
  uint8_t status = MS_STATUS_OK;
  if (code != 0) {
    status = fail_uv(code, "getwd", ms_span_of(NULL, 0), err);
  } else if (!ms_utf8_is_valid((const uint8_t *)buffer, size)) {
    status = finish(MS_STATUS_UNSUPPORTED, err);
  } else {
    ms_path_from_os(buffer, size);
    *out = ms_string_from_span(ms_span_of((const uint8_t *)buffer, size));
    *err = ms_string_empty();
  }
  ms_free(buffer);
  return status;
}

uint8_t msstd_process_change_directory(const MsString *path, MsString *err) {
  const MsSpan name = ms_string_span(path);
  size_t at = 0;
  if (name.len == 0 || ms_span_find(name, ms_span_of((const uint8_t *)"\0", 1), &at)) {
    return finish(MS_STATUS_INVALID_INPUT, err);
  }
  MsOsText text = ms_os_text_new(name);
  const int code = uv_chdir(text.ptr);
  ms_os_text_free(&text);
  if (code != 0) {
    return fail_uv(code, "chdir", name, err);
  }
  return finish(MS_STATUS_OK, err);
}

/* ---- environment ---- */

/* A variable whose name or value is not UTF-8 cannot be a String; one such variable must not hide the rest
 * (PATH, the test runner's settings), so listings skip it. */
static bool usable(const uv_env_item_t *item) {
  return is_text(item->name) && is_text(item->value);
}

static MsString text_of(const char *text) {
  return ms_string_from_span(ms_span_of_text(text));
}

uint8_t msstd_process_environment(MsBytes *names, MsBytes *values, MsString *err) {
  *names = (MsBytes){0};
  *values = (MsBytes){0};
  uv_env_item_t *items = NULL;
  int count = 0;
  const int code = uv_os_environ(&items, &count);
  if (code != 0) {
    return fail_uv(code, "environ", ms_span_of(NULL, 0), err);
  }
  ms_list_reserve(names, sizeof(MsString), (size_t)count);
  ms_list_reserve(values, sizeof(MsString), (size_t)count);
  for (int i = 0; i < count; i++) {
    if (usable(&items[i])) {
      const MsString name = text_of(items[i].name);
      const MsString value = text_of(items[i].value);
      ms_list_push(names, sizeof name, &name);
      ms_list_push(values, sizeof value, &value);
    }
  }
  uv_os_free_environ(items, count);
  return finish(MS_STATUS_OK, err);
}

uint8_t msstd_process_environment_map(MsMap *out, MsString *err) {
  *out = (MsMap){0};
  uv_env_item_t *items = NULL;
  int count = 0;
  const int code = uv_os_environ(&items, &count);
  if (code != 0) {
    return fail_uv(code, "environ", ms_span_of(NULL, 0), err);
  }
  for (int i = 0; i < count; i++) {
    if (usable(&items[i])) {
      MsString key = text_of(items[i].name);
      MsString value = text_of(items[i].value);
      ms_map_insert(out, &ms_desc_string, &ms_desc_string, (uint8_t *)&key, (uint8_t *)&value);
    }
  }
  uv_os_free_environ(items, count);
  return finish(MS_STATUS_OK, err);
}

uint8_t msstd_process_set_environment(const MsString *name, uint8_t has_value, const MsString *value,
                                      MsString *err) {
  const MsSpan key = ms_string_span(name);
  const MsSpan text = ms_string_span(value);
  if (key.len == 0 || ms_span_has_byte(key, 0) || ms_span_has_byte(key, '=') || (has_value != 0 && ms_span_has_byte(text, 0))) {
    return finish(MS_STATUS_INVALID_INPUT, err);
  }
  MsOsText key_text = ms_os_text_new(key);
  int code = 0;
  if (has_value == 0) {
    code = uv_os_unsetenv(key_text.ptr);
  } else {
    MsOsText value_text = ms_os_text_new(text);
    code = uv_os_setenv(key_text.ptr, value_text.ptr);
    ms_os_text_free(&value_text);
  }
  ms_os_text_free(&key_text);
  return code != 0 ? fail_uv(code, "setenv", key, err) : finish(MS_STATUS_OK, err);
}

uint8_t msstd_process_environment_is_set(const MsString *name) {
  const MsSpan key = ms_string_span(name);
  if (ms_span_has_byte(key, '=') || ms_span_has_byte(key, 0)) {
    return 0;
  }
  MsOsText text = ms_os_text_new(key);
  char buffer[FIRST_PATH];
  size_t size = sizeof buffer;
  int code = uv_os_getenv(text.ptr, buffer, &size);
  ms_os_text_free(&text);
  return code == 0 || code == UV_ENOBUFS ? (uint8_t)1 : (uint8_t)0;
}
