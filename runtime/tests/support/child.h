/* A child process of a C unit test: the test starts its own executable in a mode, sends it a stop request and reads
 * how it ended. The same calls work on every platform; the one request Windows cannot send is "terminate". */
#ifndef MS_TEST_CHILD_H
#define MS_TEST_CHILD_H

#include <stdbool.h>

typedef struct MsTestChild MsTestChild;

/* Starts `program` with `argv` (argv[0] included, NULL-terminated) in its own process group. NULL on failure. */
MsTestChild *ms_test_child_start(const char *program, char *const *argv);
/* Sends the interrupt request: SIGINT, or Ctrl-Break on Windows. */
bool ms_test_child_interrupt(MsTestChild *child);
/* Sends SIGTERM. Windows programs only see a terminate request when their console closes, which no process can
 * send to another, so this is false there. */
bool ms_test_child_terminate(MsTestChild *child);
/* Waits for the child and releases it: its exit status, or 1000 + the signal that ended it; -1 when it did not end
 * within `seconds`, in which case it was killed. */
int ms_test_child_wait(MsTestChild *child, int seconds);

#endif
