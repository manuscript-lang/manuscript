/* Letting another thread run on Windows. */
#include "runtime/sys/sys.h"
#include "runtime/sys/windows/winapi.h"

void ms_sys_yield(void) { SwitchToThread(); }
