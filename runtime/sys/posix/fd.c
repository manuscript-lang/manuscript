/* Descriptor primitives for the reactor: the only place it reaches the system for them. Declares the few
 * system functions it calls by hand, so no C library header is needed (see ms_rt/base.h). */
#include "ms_rt/sys.h"


int fcntl(int fd, int command, ...);

enum { FCNTL_GET_FLAGS = 3, FCNTL_SET_FLAGS = 4 };

#if defined(__APPLE__)
enum { OPEN_NONBLOCK = 0x0004 };
#else
enum { OPEN_NONBLOCK = 04000 };
#endif

bool ms_sys_fd_get_nonblocking(int fd, bool *on) {
    const int flags = fcntl(fd, FCNTL_GET_FLAGS);
    if (flags < 0) {
        return false;
    }
    *on = (flags & OPEN_NONBLOCK) != 0;
    return true;
}

bool ms_sys_fd_set_nonblocking(int fd, bool on) {
    const int flags = fcntl(fd, FCNTL_GET_FLAGS);
    if (flags < 0) {
        return false;
    }
    const int wanted = on ? (flags | OPEN_NONBLOCK) : (flags & ~OPEN_NONBLOCK);
    return wanted == flags || fcntl(fd, FCNTL_SET_FLAGS, wanted) == 0;
}

#if defined(__linux__)

typedef struct {
    int fd;
    short events;
    short revents;
} PollEntry;

typedef struct {
    long seconds;
    long nanoseconds;
} PollTime;

int ppoll(PollEntry *entries, unsigned long count, const PollTime *timeout, const void *signal_mask);

extern char **environ;
extern char **__environ; // NOLINT(bugprone-reserved-identifier,cert-dcl37-c,cert-dcl51-cpp,readability-identifier-naming): glibc's own copy of environ

enum { POLL_READABLE = 1, NANOSECONDS_PER_SECOND = 1000000000 };

bool ms_sys_fd_wait_readable(int fd, int64_t timeout_ns) {
    if (timeout_ns < 0) {
        return false;
    }
    PollEntry entry = {.fd = fd, .events = POLL_READABLE, .revents = 0};
    const PollTime timeout = {.seconds = (long)(timeout_ns / NANOSECONDS_PER_SECOND),
                              .nanoseconds = (long)(timeout_ns % NANOSECONDS_PER_SECOND)};
    (void)ppoll(&entry, 1, &timeout, 0);
    return true;
}

void ms_sys_sync_environ(void) {
    environ = __environ;
}

#else

bool ms_sys_fd_wait_readable(int fd, int64_t timeout_ns) {
    (void)fd;
    (void)timeout_ns;
    return false;
}

void ms_sys_sync_environ(void) {}

#endif
