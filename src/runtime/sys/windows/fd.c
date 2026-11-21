/* Descriptor primitives on Windows: the reactor has no descriptor flags or ppoll here, so each reports "not available". */
#include "runtime/sys/sys.h"

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

bool ms_sys_fd_ready(int fd, bool writes, bool *ready) {
    (void)fd;
    (void)writes;
    (void)ready;
    return false;
}

bool ms_sys_fd_wait_any(MsSysFdWait *entries, size_t count) {
    (void)entries;
    (void)count;
    return false;
}

bool ms_sys_wake_open(int fds[2]) {
    (void)fds;
    return false;
}

void ms_sys_wake_send(int write_fd) { (void)write_fd; }

void ms_sys_wake_drain(int read_fd) { (void)read_fd; }

void ms_sys_wake_close(const int fds[2]) { (void)fds; }

/* A standard-input read blocks its thread until data or the end arrives, and a pipe read answers would-block
 * instead, so there is nothing to poll first. */
bool ms_sys_fd_readable_now(int fd) {
    (void)fd;
    return true;
}
