/* Letting another thread run on Linux and macOS. */
#include "ms_rt/sys.h"

extern int sched_yield(void);

void ms_sys_yield(void) { (void)sched_yield(); }
