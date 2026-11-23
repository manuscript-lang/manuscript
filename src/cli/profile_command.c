/* Owns `ms profile` (profile_command.h): reads the arguments and checks the input as `ms build` does. Running the
 * program under the sampling profiler and converting its samples is not ported yet: that step reports "not
 * implemented" (status 70). */
#include "cli/profile_command.h"

#include <stdio.h>

#include "cli/checked_input.h"
#include "cli/invocation.h"

enum { STATUS_NOT_IMPLEMENTED = 70 };

int ms_profile_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "profile", argc, argv, &invocation);
  if (status == 0) {
    MsCheckedInput checked = {0};
    if (ms_checked_input_load(&arena, &checked, invocation.filename, MS_INPUT_PROGRAM)) {
      (void)fputs("ms profile: running under the sampling profiler is not implemented yet\n", stderr);
      status = STATUS_NOT_IMPLEMENTED;
    } else {
      status = invocation.json ? ms_checked_input_report_json(&checked) : ms_checked_input_report(&checked);
    }
    ms_checked_input_free(&checked);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
