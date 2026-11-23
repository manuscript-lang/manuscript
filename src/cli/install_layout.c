#include "cli/install_layout.h"

#include "base/bytes.h"
#include "base/file.h"
#include "base/path.h"
#include "base/process.h"

#ifdef _WIN32
enum { LIST_SEPARATOR = ';' };
#define TOOL_SUFFIX ".exe"
#else
enum { LIST_SEPARATOR = ':' };
#define TOOL_SUFFIX ""
#endif

bool ms_install_root(MsStrBuild *root) {
  MsString executable = ms_string_empty();
  MsString real = ms_string_empty();
  bool found = ms_process_executable(&executable) && ms_file_real_path(ms_string_span(&executable), &real);
  if (found) {
    const MsSpan bin = ms_path_parent(ms_string_span(&real));
    MsStrBuild candidate = ms_strbuild_new();
    ms_path_append_joined(&candidate, ms_path_parent(bin), ms_span_of_text("lib/ms"));
    MsStrBuild files = ms_strbuild_new();
    ms_path_append_joined(&files, ms_strbuild_span(&candidate), ms_span_of_text("files"));
    found = ms_dir_exists(ms_strbuild_span(&files));
    if (found) {
      ms_strbuild_append(root, ms_strbuild_span(&candidate));
    }
    ms_strbuild_free(&files);
    ms_strbuild_free(&candidate);
  }
  ms_string_release(&real);
  ms_string_release(&executable);
  return found;
}

void ms_install_tool(MsSpan root, const char *name, MsStrBuild *out) {
  MsStrBuild file = ms_strbuild_new();
  ms_strbuild_append_text(&file, "bin/");
  ms_strbuild_append_text(&file, name);
  ms_strbuild_append_text(&file, TOOL_SUFFIX);
  ms_path_append_joined(out, root, ms_strbuild_span(&file));
  ms_strbuild_free(&file);
}

bool ms_install_runtime(MsSpan root, bool static_libc, MsStrBuild *out) {
  MsStrBuild directory = ms_strbuild_new();
  ms_path_append_joined(&directory, root, ms_span_of_text(static_libc ? "runtime-static" : "runtime"));
  MsStrBuild list_path = ms_strbuild_new();
  ms_path_append_joined(&list_path, ms_strbuild_span(&directory), ms_span_of_text("archives"));
  MsBytes list = {0};
  const bool ok = ms_file_read(ms_strbuild_span(&list_path), &list);
  if (ok) {
    const MsSpan text = ms_bytes_span(&list);
    size_t start = 0;
    for (size_t at = 0; at <= text.len; at++) {
      if (at < text.len && text.ptr[at] != '\n') {
        continue;
      }
      size_t end = at;
      if (end > start && text.ptr[end - 1] == '\r') {
        end--;
      }
      if (end > start) {
        if (ms_strbuild_span(out).len != 0) {
          ms_strbuild_append_byte(out, LIST_SEPARATOR);
        }
        ms_path_append_joined(out, ms_strbuild_span(&directory), ms_span_of(text.ptr + start, end - start));
      }
      start = at + 1;
    }
  }
  ms_bytes_free(&list);
  ms_strbuild_free(&list_path);
  ms_strbuild_free(&directory);
  return ok;
}
