/* Owns path text operations (see path.h). */
#include "base/path.h"

#include "base/list.h"

static bool is_separator(uint8_t byte) {
  return byte == '/' || byte == '\\';
}

void ms_path_append_joined(MsStrBuild *out, MsSpan left, MsSpan right) {
  ms_strbuild_append(out, left);
  if (left.len != 0 && !is_separator(left.ptr[left.len - 1])) {
    ms_strbuild_append_byte(out, '/');
  }
  ms_strbuild_append(out, right);
}

static size_t last_separator_end(MsSpan path) {
  size_t end = path.len;
  while (end > 0 && !is_separator(path.ptr[end - 1])) {
    end--;
  }
  return end;
}

MsSpan ms_path_file_name(MsSpan path) {
  size_t start = last_separator_end(path);
  return ms_span_of(path.ptr + start, path.len - start);
}

MsSpan ms_path_parent(MsSpan path) {
  size_t end = last_separator_end(path);
  if (end > 1) {
    end--;
  }
  return end == path.len ? ms_span_of(path.ptr, 0) : ms_span_of(path.ptr, end);
}

void ms_path_from_os(char *text, size_t size) {
#ifdef _WIN32
  for (size_t at = 0; at < size; at++) {
    text[at] = text[at] == '\\' ? '/' : text[at];
  }
#else
  (void)text;
  (void)size;
#endif
}

/* Rooted at `/`, or on Windows at a drive such as `D:/`. */
bool ms_path_is_absolute(MsSpan path) {
  if (path.len > 0 && path.ptr[0] == '/') {
    return true;
  }
#ifdef _WIN32
  return path.len >= 3 && ((path.ptr[0] | 0x20) >= 'a' && (path.ptr[0] | 0x20) <= 'z') && path.ptr[1] == ':' && path.ptr[2] == '/';
#else
  return false;
#endif
}

MsSpan ms_path_ext(MsSpan path) {
  for (size_t at = path.len; at > 0 && path.ptr[at - 1] != '/'; at--) {
    if (path.ptr[at - 1] == '.') {
      return ms_span_of(path.ptr + at - 1, path.len - at + 1);
    }
  }
  return ms_span_of(path.ptr + path.len, 0);
}

MS_LIST_DEFINE(PathParts, path_parts, MsSpan)

/* The next element of `path` from `*at`, skipping separators; false at the end. */
static bool next_element(MsSpan path, size_t *at, MsSpan *element) {
  while (*at < path.len && path.ptr[*at] == '/') {
    (*at)++;
  }
  if (*at >= path.len) {
    return false;
  }
  size_t start = *at;
  while (*at < path.len && path.ptr[*at] != '/') {
    (*at)++;
  }
  *element = ms_span_of(path.ptr + start, *at - start);
  return true;
}

void ms_path_clean(MsStrBuild *out, MsSpan path) {
  const bool rooted = ms_path_is_absolute(path);
  PathParts parts = {0};
  const bool drive = rooted && path.ptr[0] != '/';
  size_t at = drive ? 2 : 0;
  MsSpan element = {0};
  while (next_element(path, &at, &element)) {
    if (ms_span_is_text(element, ".")) {
      continue;
    }
    const bool up = ms_span_is_text(element, "..");
    const bool can_drop = parts.len > 0 && !ms_span_is_text(parts.ptr[parts.len - 1], "..");
    if (up && can_drop) {
      parts.len--;
    } else if (!up || !rooted) {
      path_parts_push(&parts, element);
    }
  }
  if (drive) {
    ms_strbuild_append(out, ms_span_of(path.ptr, 2));
  }
  if (rooted) {
    ms_strbuild_append_byte(out, '/');
  }
  if (parts.len == 0 && !rooted) {
    ms_strbuild_append_byte(out, '.');
  }
  for (size_t index = 0; index < parts.len; index++) {
    if (index > 0) {
      ms_strbuild_append_byte(out, '/');
    }
    ms_strbuild_append(out, parts.ptr[index]);
  }
  path_parts_free(&parts);
}

bool ms_path_escapes(MsSpan relative) {
  if (ms_span_is_text(relative, "..")) {
    return true;
  }
  return ms_span_starts_with(relative, ms_span_of_text("../"));
}

bool ms_path_relative(MsStrBuild *out, MsSpan base, MsSpan target) {
  if (ms_path_is_absolute(base) != ms_path_is_absolute(target)) {
    return false;
  }
  MsStrBuild base_clean = ms_strbuild_new();
  MsStrBuild target_clean = ms_strbuild_new();
  ms_path_clean(&base_clean, base);
  ms_path_clean(&target_clean, target);
  const MsSpan from = ms_strbuild_span(&base_clean);
  const MsSpan to = ms_strbuild_span(&target_clean);
  size_t from_at = 0, to_at = 0;
  MsSpan from_element = {0}, to_element = {0};
  /* Skip the shared leading elements. */
  size_t common_from = 0, common_to = 0;
  while (true) {
    size_t next_from = from_at, next_to = to_at;
    const bool has_from = next_element(from, &next_from, &from_element) && !ms_span_is_text(from_element, ".");
    const bool has_to = next_element(to, &next_to, &to_element) && !ms_span_is_text(to_element, ".");
    if (!has_from || !has_to || !ms_span_equal(from_element, to_element)) {
      break;
    }
    from_at = next_from;
    to_at = next_to;
    common_from = from_at;
    common_to = to_at;
  }
  bool first = true;
  size_t rest = common_from;
  while (next_element(from, &rest, &from_element)) {
    if (ms_span_is_text(from_element, "..")) { /* cannot walk up out of an unknown directory */
      ms_strbuild_free(&base_clean);
      ms_strbuild_free(&target_clean);
      return false;
    }
    ms_strbuild_append_text(out, first ? ".." : "/..");
    first = false;
  }
  rest = common_to;
  while (next_element(to, &rest, &to_element)) {
    if (!first) {
      ms_strbuild_append_byte(out, '/');
    }
    ms_strbuild_append(out, to_element);
    first = false;
  }
  if (first) {
    ms_strbuild_append_byte(out, '.');
  }
  ms_strbuild_free(&base_clean);
  ms_strbuild_free(&target_clean);
  return true;
}
