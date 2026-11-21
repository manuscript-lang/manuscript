/* Unit test of the libuv reactor (src/runtime/io/reactor.c): readiness, one-shot watches, timeouts, wake-ups from
 * another thread, and the files that cannot be polled. Run under the sanitizers by `make c-test`. */
#define _POSIX_C_SOURCE 200809L /* clock_gettime and nanosleep under -std=c11 */

#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#include "../io/reactor.h"

#define CHECK(condition)                                                                \
    do {                                                                                \
        if (!(condition)) {                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #condition); \
            exit(1);                                                                    \
        }                                                                               \
    } while (0)

enum { CAPACITY = 8, MILLISECOND = 1000000 };

static MsIoReactor *open_reactor(void) {
    MsIoReactor *reactor = NULL;
    CHECK(ms_io_open(false, &reactor));
    return reactor;
}

static size_t wait_for(int64_t timeout_ns, MsIoReady *ready) {
    size_t count = 0;
    CHECK(ms_io_wait(timeout_ns, ready, CAPACITY, &count));
    return count;
}

static void write_byte(int fd) {
    const char byte = 'x';
    CHECK(write(fd, &byte, 1) == 1);
}

static void test_readable_pipe_reports_once(void) {
    int fds[2];
    CHECK(pipe(fds) == 0);
    MsIoReactor *reactor = open_reactor();
    MsIoReady ready[CAPACITY];
    CHECK(ms_io_watch(fds[0], MS_IO_BIT_READ) == MS_IO_WATCH_ARMED);
    CHECK(wait_for(0, ready) == 0);
    write_byte(fds[1]);
    CHECK(wait_for(-1, ready) == 1);
    CHECK(ready[0].fd == (uintptr_t)fds[0] && (ready[0].bits & MS_IO_BIT_READ) != 0);
    CHECK(wait_for(0, ready) == 0); /* one-shot */
    CHECK(ms_io_watch(fds[0], MS_IO_BIT_READ) == MS_IO_WATCH_ARMED); /* level-like: still readable */
    CHECK(wait_for(0, ready) == 1);
    ms_io_close(false);
    close(fds[0]);
    close(fds[1]);
    (void)reactor;
}

static void test_timeout_waits_about_that_long(void) {
    MsIoReactor *reactor = open_reactor();
    MsIoReady ready[CAPACITY];
    struct timespec before;
    struct timespec after;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &before) == 0);
    CHECK(wait_for(5 * MILLISECOND, ready) == 0);
    CHECK(clock_gettime(CLOCK_MONOTONIC, &after) == 0);
    const long elapsed_ns = (after.tv_sec - before.tv_sec) * 1000000000L + (after.tv_nsec - before.tv_nsec);
    CHECK(elapsed_ns >= 4 * MILLISECOND && elapsed_ns < 500 * MILLISECOND);
    ms_io_close(false);
    (void)reactor;
}

static void *wake_later(void *argument) {
    struct timespec pause = {.tv_sec = 0, .tv_nsec = 20 * MILLISECOND};
    nanosleep(&pause, NULL);
    ms_io_wake(argument);
    return NULL;
}

static void test_wake_ends_a_blocking_wait(void) {
    MsIoReactor *reactor = open_reactor();
    MsIoReady ready[CAPACITY];
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, wake_later, reactor) == 0);
    CHECK(wait_for(-1, ready) == 0);
    CHECK(pthread_join(thread, NULL) == 0);
    ms_io_close(false);
}

static void test_regular_file_is_ready_at_once(void) {
    MsIoReactor *reactor = open_reactor();
    const int fd = open("/dev/null", O_RDONLY);
    CHECK(fd >= 0);
    CHECK(ms_io_watch(fd, MS_IO_BIT_READ) == MS_IO_WATCH_ALWAYS);
    CHECK(ms_io_watch(-1, MS_IO_BIT_READ) == MS_IO_WATCH_FAILED);
    close(fd);
    ms_io_close(false);
    (void)reactor;
}

static void test_blocking_descriptor_stays_blocking(void) {
    int fds[2];
    CHECK(pipe(fds) == 0);
    MsIoReactor *reactor = open_reactor();
    CHECK(ms_io_watch(fds[0], MS_IO_BIT_READ) == MS_IO_WATCH_ARMED);
    CHECK((fcntl(fds[0], F_GETFL) & O_NONBLOCK) == 0);
    ms_io_close(false);
    close(fds[0]);
    close(fds[1]);
    (void)reactor;
}

static void test_kept_and_forgotten_handles(void) {
    int fds[2];
    CHECK(pipe(fds) == 0);
    MsIoReactor *reactor = open_reactor();
    MsIoReady ready[CAPACITY];
    CHECK(ms_io_watch(fds[0], MS_IO_BIT_READ | MS_IO_BIT_KEEP) == MS_IO_WATCH_ARMED);
    ms_io_unwatch(fds[0]);
    write_byte(fds[1]);
    CHECK(wait_for(0, ready) == 0); /* unwatched: nothing reported */
    CHECK(ms_io_watch(fds[0], MS_IO_BIT_READ | MS_IO_BIT_KEEP) == MS_IO_WATCH_ARMED);
    CHECK(wait_for(0, ready) == 1);
    ms_io_forget(fds[0]);
    close(fds[0]);
    close(fds[1]);
    ms_io_close(false);
    (void)reactor;
}

int main(void) {
    test_readable_pipe_reports_once();
    test_timeout_waits_about_that_long();
    test_wake_ends_a_blocking_wait();
    test_regular_file_is_ready_at_once();
    test_blocking_descriptor_stays_blocking();
    test_kept_and_forgotten_handles();
    puts("io_reactor: ok");
    return 0;
}
