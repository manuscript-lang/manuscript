/* Owns `ms test` (test_command.h): reads and validates the arguments, then loads and checks each input with its test
 * files and reports what is wrong as `ms check` does. Running the tests needs the back end's test lowering and the
 * runner protocol of crates/ms-cli/src/engine/testing.rs, which the C pipeline does not have yet: a program that
 * checks ends with status 70 and a message saying so. */
#include "driver/test_command.h"

#include <stdio.h>

#include "base/message.h"
#include "driver/compile_front.h"
#include "driver/invocation.h"

enum { STATUS_FAILED = 1, STATUS_NOT_IMPLEMENTED = 70 };

/* The first input that does not compile gives the status; its diagnostics are on stderr. */
static int check_inputs(MsArena *arena, const MsInvocation *invocation) {
  int status = 0;
  for (size_t i = 0; i < invocation->targets.len && status == 0; i++) {
    MsFront front = {0};
    if (invocation->targets.len > 1) {
      (void)fprintf(stderr, "ms: testing %.*s\n", (int)invocation->targets.ptr[i].len,
                    (const char *)invocation->targets.ptr[i].ptr);
    }
    if (!ms_front_compile(arena, &front, invocation->targets.ptr[i], MS_FRONT_TESTS)) {
      status = ms_front_report(&front);
    }
    ms_front_free(&front);
  }
  return status;
}

int ms_test_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "test", argc, argv, &invocation);
  if (status == 0 && invocation.watch) {
    (void)fprintf(stderr, "ms test: --watch is not implemented yet\n");
    status = STATUS_NOT_IMPLEMENTED;
  } else if (status == 0) {
    status = check_inputs(&arena, &invocation);
    if (status == 0) {
      (void)fprintf(stderr, "ms test: the input checks, but running tests is not implemented yet (needs the back end's "
                            "test lowering)\n");
      status = STATUS_NOT_IMPLEMENTED;
    }
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
