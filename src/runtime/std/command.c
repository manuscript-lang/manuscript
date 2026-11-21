/* A command's strings as the OS wants them (see command.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/command.h"

#include <uv.h>

#include "base/alloc.h"
#include "base/strbuild.h"

static const MsString *string_at(const MsList *list, size_t index) { return (const MsString *)(const void *)list->ptr + index; }

static char *copy_text(MsSpan text) {
  char *copy = ms_alloc(text.len + 1);
  if (text.len > 0) {
    __builtin_memcpy(copy, text.ptr, text.len);
  }
  copy[text.len] = '\0';
  return copy;
}

static bool has_nul(const MsString *text) {
  const MsSpan span = ms_string_span(text);
  return span.len > 0 && __builtin_memchr(span.ptr, 0, span.len) != NULL;
}

static bool has_equals(const MsString *text) {
  const MsSpan span = ms_string_span(text);
  return span.len > 0 && __builtin_memchr(span.ptr, '=', span.len) != NULL;
}

static bool command_valid(const MsString *program, const MsList *arguments, bool has_cwd, const MsString *cwd,
                          const MsList *names, const MsList *values) {
  if (ms_string_is_empty(program) || has_nul(program) || names->len != values->len) {
    return false;
  }
  for (size_t i = 0; i < arguments->len; i++) {
    if (has_nul(string_at(arguments, i))) {
      return false;
    }
  }
  for (size_t i = 0; i < names->len; i++) {
    const MsString *name = string_at(names, i);
    if (ms_string_is_empty(name) || has_nul(name) || has_equals(name) || has_nul(string_at(values, i))) {
      return false;
    }
  }
  return !has_cwd || (!ms_string_is_empty(cwd) && !has_nul(cwd));
}

static char **list_alloc(size_t count) { return ms_alloc_zeroed((count + 1) * sizeof(char *)); }

static void list_free(char **items) {
  for (size_t i = 0; items != NULL && items[i] != NULL; i++) {
    ms_free(items[i]);
  }
  ms_free(items);
}

/* `NAME=value` as a new C string. */
static char *assignment(MsSpan name, MsSpan value) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, name);
  ms_strbuild_append_byte(&text, '=');
  ms_strbuild_append(&text, value);
  char *copy = copy_text(ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return copy;
}

/* Whether the inherited variable called `name` is the one an item names; Windows names ignore case. */
static bool is_variable(const char *name, const MsString *given) {
  const MsSpan wanted = ms_string_span(given);
  const size_t length = __builtin_strlen(name);
  if (length != wanted.len) {
    return false;
  }
  for (size_t i = 0; i < length; i++) {
    uint8_t a = (uint8_t)name[i];
    uint8_t b = wanted.ptr[i];
#ifdef _WIN32
    a = (uint8_t)(a >= 'a' && a <= 'z' ? a - 'a' + 'A' : a);
    b = (uint8_t)(b >= 'a' && b <= 'z' ? b - 'a' + 'A' : b);
#endif
    if (a != b) {
      return false;
    }
  }
  return true;
}

static bool is_replaced(const char *name, const MsList *names) {
  for (size_t i = 0; i < names->len; i++) {
    if (is_variable(name, string_at(names, i))) {
      return true;
    }
  }
  return false;
}

/* The environment of the child: `inherit`ed variables that the given ones do not replace, then the given ones. */
static char **build_environment(const MsList *names, const MsList *values, bool inherit) {
  uv_env_item_t *inherited = NULL;
  int count = 0;
  if (!inherit || uv_os_environ(&inherited, &count) != 0) {
    inherited = NULL;
    count = 0;
  }
  char **env = list_alloc((size_t)count + names->len);
  size_t used = 0;
  for (int i = 0; i < count; i++) {
    if (!is_replaced(inherited[i].name, names)) {
      env[used++] = assignment(ms_span_of_text(inherited[i].name), ms_span_of_text(inherited[i].value));
    }
  }
  if (inherited != NULL) {
    uv_os_free_environ(inherited, count);
  }
  for (size_t i = 0; i < names->len; i++) {
    env[used++] = assignment(ms_string_span(string_at(names, i)), ms_string_span(string_at(values, i)));
  }
  return env;
}

bool ms_command_build(MsCommand *command, const MsString *program, const MsList *arguments, bool has_cwd,
                      const MsString *cwd, const MsList *names, const MsList *values, bool inherit, MsFail *fail) {
  if (!command_valid(program, arguments, has_cwd, cwd, names, values)) {
    ms_fail_status(fail, MS_STATUS_INVALID_INPUT);
    return false;
  }
  command->program = copy_text(ms_string_span(program));
  command->cwd = has_cwd ? copy_text(ms_string_span(cwd)) : NULL;
  command->argv = list_alloc(arguments->len + 1);
  command->argv[0] = copy_text(ms_string_span(program));
  for (size_t i = 0; i < arguments->len; i++) {
    command->argv[i + 1] = copy_text(ms_string_span(string_at(arguments, i)));
  }
  command->env = build_environment(names, values, inherit);
  return true;
}

void ms_command_free(MsCommand *command) {
  ms_free(command->program);
  list_free(command->argv);
  list_free(command->env);
  ms_free(command->cwd);
  *command = (MsCommand){0};
}

void ms_command_start_failure(MsFail *fail, int error, const char *program) {
  if (error == UV_ENOENT || error == UV_ENOTDIR) {
    ms_fail_status(fail, MS_STATUS_NOT_FOUND);
  } else if (error == UV_EACCES || error == UV_EPERM) {
    ms_fail_status(fail, MS_STATUS_PERMISSION_DENIED);
  } else {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "fork/exec ");
    ms_strbuild_append_text(&text, program);
    ms_strbuild_append_text(&text, ": ");
    ms_strbuild_append_text(&text, uv_strerror(error));
    ms_fail_free(fail);
    fail->status = MS_STATUS_FAILED;
    fail->message = ms_strbuild_finish(&text);
  }
}

/* Whether `directory` is a path that does not exist. */
static bool directory_missing(const MsString *directory) {
  char *path = copy_text(ms_string_span(directory));
  uv_fs_t request;
  const bool missing = uv_fs_stat(NULL, &request, path, NULL) != 0;
  uv_fs_req_cleanup(&request);
  ms_free(path);
  return missing;
}

uint8_t ms_command_finish(MsFail *fail, const MsString *program, const MsString *cwd, MsString *err) {
  if (fail->status != MS_STATUS_NOT_FOUND && fail->status != MS_STATUS_PERMISSION_DENIED) {
    return ms_fail_finish(fail, err);
  }
  if (cwd == NULL || !directory_missing(cwd)) {
    return ms_fail_finish_at(fail, ms_string_span(program), err);
  }
  MsStrBuild detail = ms_strbuild_new();
  ms_strbuild_append_text(&detail, "working directory ");
  ms_strbuild_append(&detail, ms_string_span(cwd));
  const uint8_t status = ms_fail_finish_at(fail, ms_strbuild_span(&detail), err);
  ms_strbuild_free(&detail);
  return status;
}
