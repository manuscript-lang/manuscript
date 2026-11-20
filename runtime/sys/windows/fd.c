/* Descriptor primitives on Windows: the reactor has no descriptor flags or ppoll here, so each reports "not available". */
#include "ms_rt/sys.h"

bool ms_sys_fd_get_nonblocking(int fd, bool *on) {
    (void)fd;
    (void)on;
    return false;
}

bool ms_sys_fd_set_nonblocking(int fd, bool on) {
    (void)fd;
    (void)on;
    return false;
}

bool ms_sys_fd_wait_readable(int fd, int64_t timeout_ns) {
    (void)fd;
    (void)timeout_ns;
    return false;
}

void ms_sys_sync_environ(void) {}

char **ms_sys_swap_libc_environ(char **replacement) { return replacement; }

