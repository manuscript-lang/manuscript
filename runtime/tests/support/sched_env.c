#ifdef _WIN32
#include <uv.h>
#else
#include <poll.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../core/promise.h"
#include "../../core/scheduler.h"
#include "ms_rt/alloc.h"
#include "sched_env.h"

enum { MAX_FDS = 64 };

static uint32_t watched[MAX_FDS]; /* events asked for each descriptor, 0 when not watched */

static int fake_watch(int fd, uint32_t events) {
    watched[fd] = events;
    return MS_POLL_ARMED;
}

static void fake_unwatch(int fd) { watched[fd] = 0; }

#ifdef _WIN32
/* Windows tests that use this environment wait on no descriptor: nothing becomes ready, so a wait is a short sleep. */
static long fake_wait(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
    (void)out;
    (void)capacity;
    if (timeout_ns != 0) {
        uv_sleep(1);
    }
    return 0;
}
#else
/* A real poll(2) over the watched descriptors; an interest is one-shot, as in the reactor. */
static long fake_wait(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
    struct pollfd fds[MAX_FDS];
    size_t count = 0;
    for (int fd = 0; fd < MAX_FDS; fd++) {
        if (watched[fd] != 0) {
            const short events = (short)(((watched[fd] & MS_WAIT_READ) != 0 ? POLLIN : 0) |
                                         ((watched[fd] & MS_WAIT_WRITE) != 0 ? POLLOUT : 0));
            fds[count++] = (struct pollfd){.fd = fd, .events = events};
        }
    }
    const int ms = timeout_ns < 0 ? -1 : (int)((timeout_ns + 999999) / 1000000);
    if (poll(fds, count, timeout_ns == 0 ? 0 : ms) <= 0) {
        return 0;
    }
    long ready = 0;
    for (size_t i = 0; i < count && (size_t)ready < capacity; i++) {
        uint32_t bits = 0;
        bits |= (fds[i].revents & (POLLIN | POLLHUP)) != 0 ? MS_WAIT_READ : 0;
        bits |= (fds[i].revents & POLLOUT) != 0 ? MS_WAIT_WRITE : 0;
        if (bits != 0) {
            watched[fds[i].fd] = 0;
            out[ready++] = (MsPollReady){.fd = (uintptr_t)fds[i].fd, .bits = bits};
        }
    }
    return ready;
}
#endif

static void fake_fault(MsFaultKind kind, const char *message) {
    (void)kind;
    MsFaultText text = {.bytes = msrt_alloc(strlen(message) + 1), .length = strlen(message)};
    memcpy(text.bytes, message, text.length + 1);
    if (!ms_guard_leave(MS_GUARD_FAULT, text)) {
        fprintf(stderr, "test: fault with no guard: %s\n", message);
        exit(1);
    }
    for (;;) {
    }
}

static void fake_exit(int status) {
    fprintf(stderr, "test: unexpected process exit %d\n", status);
    exit(1);
}

void ms_test_sched_install(void) {
    MsSchedHooks hooks = {.fault = fake_fault, .exit_process = fake_exit};
    ms_promise_hooks(&hooks);
    const MsPollOps poll_ops = {.watch = fake_watch, .unwatch = fake_unwatch, .forget = fake_unwatch, .wait = fake_wait};
    ms_sched_set_hooks(&hooks, &poll_ops);
}
