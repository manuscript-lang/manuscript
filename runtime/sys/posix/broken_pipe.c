/* Signal disposition the runtime sets for the whole process on Linux and macOS. */
#include "ms_rt/sys.h"

typedef void (*SignalHandler)(int);

extern SignalHandler signal(int signal_number, SignalHandler handler);

enum { SIGNAL_PIPE = 13 }; /* SIGPIPE on Linux and macOS */

#define SIGNAL_IGNORE ((SignalHandler)1) /* SIG_IGN on both */

void ms_sys_ignore_broken_pipe(void) { (void)signal(SIGNAL_PIPE, SIGNAL_IGNORE); }
