/* The helpers the tree operations of @std/fs share (fs_tree.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/fs_tree.h"

void ms_fs_absolute(MsSpan path, MsStrBuild *out) {
  char buffer[1024];
  size_t size = sizeof buffer;
  if (ms_fs_is_absolute(path) || uv_cwd(buffer, &size) != 0) {
    ms_strbuild_append(out, path);
    return;
  }
  ms_fs_path_join(ms_span_of((const uint8_t *)buffer, size), path, out);
}

bool ms_fs_within_path(MsSpan source, MsSpan target) {
  MsStrBuild clean_source = ms_strbuild_new();
  MsStrBuild clean_target = ms_strbuild_new();
  ms_fs_path_clean(source, &clean_source);
  ms_fs_path_clean(target, &clean_target);
  const MsSpan prefix = ms_strbuild_span(&clean_source);
  const MsSpan whole = ms_strbuild_span(&clean_target);
  const bool rooted = prefix.len > 0 && ms_fs_is_separator(prefix.ptr[prefix.len - 1]);
  const bool inside = ms_span_starts_with(whole, prefix) &&
                      (rooted || whole.len == prefix.len || ms_fs_is_separator(whole.ptr[prefix.len]));
  ms_strbuild_free(&clean_source);
  ms_strbuild_free(&clean_target);
  return inside;
}

void ms_fs_names_push(MsStrBuild *names, MsSpan name) {
  ms_strbuild_append(names, ms_span_of((const uint8_t *)&name.len, sizeof name.len));
  ms_strbuild_append(names, name);
}

bool ms_fs_names_next(MsSpan names, size_t *cursor, MsSpan *name) {
  size_t length = 0;
  if (*cursor >= names.len || names.len - *cursor < sizeof length) {
    return false;
  }
  length = (size_t)ms_load64(names.ptr + *cursor);
  const size_t start = *cursor + sizeof length;
  if (names.len - start < length) {
    return false;
  }
  *name = ms_span_of(names.ptr + start, length);
  *cursor = start + length;
  return true;
}

bool ms_fs_names_contain(const MsStrBuild *names, MsSpan name) {
  size_t cursor = 0;
  MsSpan entry;
  while (ms_fs_names_next(ms_strbuild_span(names), &cursor, &entry)) {
    if (ms_span_equal(entry, name)) {
      return true;
    }
  }
  return false;
}

bool ms_fs_names_read(MsSpan directory, MsStrBuild *names, MsFail *fail) {
  size_t at = 0;
  if (directory.len == 0 || ms_span_find(directory, ms_span_of((const uint8_t *)"\0", 1), &at)) {
    ms_fail_status(fail, MS_STATUS_INVALID_INPUT);
    return false;
  }
  MsOsText text = ms_os_text_new(directory);
  uv_fs_t request;
  const int code = uv_fs_scandir(NULL, &request, text.ptr, 0, NULL);
  ms_os_text_free(&text);
  if (code < 0) {
    ms_fail_uv(fail, code, "open", directory);
    uv_fs_req_cleanup(&request);
    return false;
  }
  uv_dirent_t entry;
  while (uv_fs_scandir_next(&request, &entry) != UV_EOF) {
    ms_fs_names_push(names, ms_span_of_text(entry.name));
  }
  uv_fs_req_cleanup(&request);
  return true;
}

void ms_fs_arguments_set(MsFsArguments *arguments, MsSpan first, MsSpan second) {
  arguments->first = ms_string_from_span(first);
  arguments->second = ms_string_from_span(second);
  arguments->live = true;
}

void ms_fs_arguments_free(MsFsArguments *arguments) {
  if (arguments->live) {
    ms_string_release(&arguments->first);
    ms_string_release(&arguments->second);
    arguments->live = false;
  }
}
