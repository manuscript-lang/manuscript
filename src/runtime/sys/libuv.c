/* The monotonic clock and the process id, the same on every platform over libuv (ms_rt/sys.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */
#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#endif

#include <uv.h>

#include "ms_rt/sys.h"

int64_t ms_sys_monotonic_ns(void) { return (int64_t)uv_hrtime(); }

uint32_t ms_sys_process_id(void) { return (uint32_t)uv_os_getpid(); }
