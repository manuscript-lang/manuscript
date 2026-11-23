/* cli/inspect_command.c: `ms inspect`. Port of `inspect_command` in crates/ms-cli/src/engine/tooling.rs. */
#include "cli/inspect_command.h"

#include <stdio.h>

#include "base/file.h"
#include "cli/checked_input.h"
#include "tooling/inspect.h"
#include "cli/invocation.h"

static int write_output(MsSpan output, MsSpan text) {
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

int ms_inspect_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "inspect", argc, argv, &invocation);
  if (status == 0) {
    MsCheckedInput checked = {0};
    if (ms_checked_input_load(&arena, &checked, invocation.filename, MS_INPUT_ANALYSIS)) {
      MsStrBuild text = ms_strbuild_new();
      ms_inspect_document(&arena, &checked.program, &text);
      status = write_output(invocation.output, ms_strbuild_span(&text));
      ms_strbuild_free(&text);
    } else {
      status = invocation.json ? ms_checked_input_report_json(&checked) : ms_checked_input_report(&checked);
    }
    ms_checked_input_free(&checked);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
