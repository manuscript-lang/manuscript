/* Owns files.h. */
#include "cli/files.h"

#include <stdio.h>

#include "base/bytes.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/strbuild.h"

MsSpan ms_cli_read_text(MsArena *arena, MsSpan path) {
  MsBytes bytes = {0};
  MsSpan text = {0};
  if (ms_file_read(path, &bytes)) {
    text = ms_arena_copy(arena, ms_bytes_span(&bytes));
  }
  ms_bytes_free(&bytes);
  return text;
}

int ms_cli_write_output(MsSpan output, MsSpan text) {
  if (output.len == 0) {
    (void)fwrite(text.ptr, 1, text.len, stdout);
    return 0;
  }
  if (!ms_file_write(output, text)) {
    (void)fprintf(stderr, "cannot write %.*s\n", (int)output.len, (const char *)output.ptr);
    return 1;
  }
  return 0;
}

MsSpan ms_cli_absolute(MsArena *arena, MsSpan path) {
  MsString cwd = ms_string_empty();
  MsStrBuild joined = ms_strbuild_new();
  if (ms_path_is_absolute(path) || !ms_dir_current(&cwd)) {
    ms_strbuild_append(&joined, path);
  } else {
    ms_path_append_joined(&joined, ms_string_span(&cwd), path);
  }
  ms_string_release(&cwd);
  MsStrBuild cleaned = ms_strbuild_new();
  ms_path_clean(&cleaned, ms_strbuild_span(&joined));
  const MsSpan result = ms_arena_copy(arena, ms_strbuild_span(&cleaned));
  ms_strbuild_free(&joined);
  ms_strbuild_free(&cleaned);
  return result;
}

MsSpan ms_cli_joined(MsArena *arena, MsSpan left, MsSpan right) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, left, right);
  const MsSpan copy = ms_message_from_builder(arena, &path);
  ms_strbuild_free(&path);
  return copy;
}
