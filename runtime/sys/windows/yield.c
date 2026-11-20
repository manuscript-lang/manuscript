/* Letting another thread run on Windows. */
#include "ms_rt/sys.h"
#include "winapi.h"

void ms_sys_yield(void) { SwitchToThread(); }
