/* Signal disposition the runtime sets for the whole process on Windows: a write to a closed pipe is an error
 * status there, not a signal, so there is nothing to do. */
#include "runtime/sys/sys.h"

void ms_sys_ignore_broken_pipe(void) {}
