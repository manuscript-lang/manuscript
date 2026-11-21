/* Owns path text operations (see path.h). */
#include "base/path.h"

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
