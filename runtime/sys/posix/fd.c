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

typedef struct {
    int fd;
    short events;
    short revents;
} ReadyEntry;

int poll(ReadyEntry *entries, unsigned long count, int timeout_ms);

enum { READY_IN = 0x1, READY_OUT = 0x4, READY_INVALID = 0x20 };

bool ms_sys_fd_ready(int fd, bool writes, bool *ready) {
    ReadyEntry entry = {.fd = fd, .events = writes ? READY_OUT : READY_IN, .revents = 0};
    if (poll(&entry, 1, 0) < 0 || (entry.revents & READY_INVALID) != 0) {
        return false;
    }
    *ready = entry.revents != 0;
    return true;
}

enum { WAKE_BYTES = 64, FD_CLOEXEC_FLAG = 1, FCNTL_SET_DESCRIPTOR_FLAGS = 2 };

_Static_assert(sizeof(MsSysFdWait) == sizeof(ReadyEntry), "a wait entry is poll(2)'s entry");

/* Everything poll(2) reports besides "readable" or "writable" (hang-up, error, invalid) counts as ready: the next read
 * or write names the cause. */
bool ms_sys_fd_wait_any(MsSysFdWait *entries, size_t count) {
    for (size_t i = 0; i < count; i++) {
        entries[i].got = 0;
    }
    (void)poll((ReadyEntry *)entries, count, -1);
    return true;
}

long read(int fd, void *buffer, unsigned long count);
long write(int fd, const void *buffer, unsigned long count);
int close(int fd);

#if defined(__linux__)
int pipe2(int fds[2], int flags);

enum { PIPE_CLOEXEC = 02000000 };

bool ms_sys_wake_open(int fds[2]) {
    return pipe2(fds, PIPE_CLOEXEC | OPEN_NONBLOCK) == 0;
}
#else
int pipe(int fds[2]);

/* No pipe2 here: the flags are set after the fact, before the descriptors can reach a child. */
bool ms_sys_wake_open(int fds[2]) {
    if (pipe(fds) != 0) { // NOLINT(android-cloexec-pipe)
        return false;
    }
    for (int end = 0; end < 2; end++) {
        const int flags = fcntl(fds[end], FCNTL_GET_FLAGS);
        if (flags < 0 || fcntl(fds[end], FCNTL_SET_FLAGS, flags | OPEN_NONBLOCK) != 0 ||
            fcntl(fds[end], FCNTL_SET_DESCRIPTOR_FLAGS, FD_CLOEXEC_FLAG) != 0) {
            ms_sys_wake_close(fds);
            return false;
        }
    }
    return true;
}
#endif

void ms_sys_wake_send(int write_fd) {
    const char byte = 1;
    (void)write(write_fd, &byte, 1);
}

void ms_sys_wake_drain(int read_fd) {
    char sink[WAKE_BYTES];
    while (read(read_fd, sink, sizeof sink) == (long)sizeof sink) {
    }
}

void ms_sys_wake_close(const int fds[2]) {
    (void)close(fds[0]);
    (void)close(fds[1]);
}

bool ms_sys_fd_readable_now(int fd) {
    ReadyEntry entry = {.fd = fd, .events = READY_IN, .revents = 0};
    return poll(&entry, 1, 0) != 0; /* a hang-up or an error is readable too: the read reports it */
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

#else

bool ms_sys_fd_wait_readable(int fd, int64_t timeout_ns) {
    (void)fd;
    (void)timeout_ns;
    return false;
}


#endif
