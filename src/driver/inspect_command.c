/* driver/inspect_command.c: `ms inspect`. Port of `inspect_command` in crates/ms-cli/src/engine/tooling.rs. */
#include "driver/inspect_command.h"

#include <stdio.h>

#include "driver/checked_input.h"
#include "driver/invocation.h"

enum { EXIT_NOT_IMPLEMENTED = 70 };

int ms_inspect_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "inspect", argc, argv, &invocation);
  if (status == 0) {
    MsCheckedInput checked = {0};
    if (ms_checked_input_load(&arena, &checked, invocation.filename, MS_INPUT_ANALYSIS)) {
      (void)fprintf(stderr, "ms inspect: the inspection document is not implemented in this build\n");
      status = EXIT_NOT_IMPLEMENTED;
    } else {
      status = invocation.json ? ms_checked_input_report_json(&checked) : ms_checked_input_report(&checked);
    }
    ms_checked_input_free(&checked);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
