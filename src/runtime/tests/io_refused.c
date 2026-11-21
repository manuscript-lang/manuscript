/* Unit test of the refused-descriptor watcher (src/runtime/io/refused.c): a watch reports once when its descriptor
 * becomes ready, a removed watch never reports, and a removal returns only when the descriptor may be closed. */
#define _POSIX_C_SOURCE 200809L /* nanosleep under -std=c11 */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#include "../io/refused.h"

#define CHECK(condition)                                                                \
    do {                                                                                \
        if (!(condition)) {                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #condition); \
            exit(1);                                                                    \
        }                                                                               \
    } while (0)

enum { MAX_REPORTS = 8, SLEEP_NS = 20000000 };

typedef struct Reports {
    int fds[MAX_REPORTS];
    int count;
    bool refuse; /* answer "no room" until cleared */
} Reports;

static bool on_ready(void *context, int fd) {
    Reports *reports = context;
    if (reports->refuse) {
        return false;
    }
    CHECK(reports->count < MAX_REPORTS);
    reports->fds[reports->count++] = fd;
    return true;
}

/* Runs the loop until `count` reports have arrived or about two seconds pass. */
static void run_until(uv_loop_t *loop, const Reports *reports, int count) {
    for (int pass = 0; pass < 100 && reports->count < count; pass++) {
        (void)uv_run(loop, UV_RUN_NOWAIT);
        const struct timespec nap = {.tv_sec = 0, .tv_nsec = SLEEP_NS / 10};
        (void)nanosleep(&nap, NULL);
    }
}

static void write_byte(int fd) {
    CHECK(write(fd, "x", 1) == 1);
}

static void reports_once_when_ready(uv_loop_t *loop, MsIoRefused *refused, Reports *reports) {
    int fds[2];
    CHECK(pipe(fds) == 0);
    CHECK(ms_io_refused_add(refused, fds[0], false));
    run_until(loop, reports, 1);
    CHECK(reports->count == 0); /* nothing written yet */
    write_byte(fds[1]);
    run_until(loop, reports, 1);
    CHECK(reports->count == 1 && reports->fds[0] == fds[0]);
    run_until(loop, reports, 2);
    CHECK(reports->count == 1); /* one-shot: the byte is still unread and does not report again */
    reports->count = 0;
    close(fds[0]);
    close(fds[1]);
}

static void a_hang_up_reports(uv_loop_t *loop, MsIoRefused *refused, Reports *reports) {
    int fds[2];
    CHECK(pipe(fds) == 0);
    CHECK(ms_io_refused_add(refused, fds[0], false));
    close(fds[1]); /* the last writer going away is what kqueue cannot report */
    run_until(loop, reports, 1);
    CHECK(reports->count == 1 && reports->fds[0] == fds[0]);
    reports->count = 0;
    close(fds[0]);
}

static void a_removed_watch_stays_silent(uv_loop_t *loop, MsIoRefused *refused, Reports *reports) {
    int fds[2];
    CHECK(pipe(fds) == 0);
    CHECK(ms_io_refused_add(refused, fds[0], false));
    ms_io_refused_remove(refused, fds[0]); /* returns once the thread is not polling fds[0]: closing is safe */
    close(fds[0]);
    close(fds[1]);
    run_until(loop, reports, 1);
    CHECK(reports->count == 0);
}

static void a_full_ring_is_retried(uv_loop_t *loop, MsIoRefused *refused, Reports *reports) {
    int fds[2];
    CHECK(pipe(fds) == 0);
    reports->refuse = true;
    CHECK(ms_io_refused_add(refused, fds[0], false));
    write_byte(fds[1]);
    run_until(loop, reports, 1);
    CHECK(reports->count == 0);
    reports->refuse = false;
    run_until(loop, reports, 1);
    CHECK(reports->count == 1 && reports->fds[0] == fds[0]);
    reports->count = 0;
    close(fds[0]);
    close(fds[1]);
}

static void a_write_watch_reports_a_pipe_with_room(uv_loop_t *loop, MsIoRefused *refused, Reports *reports) {
    int fds[2];
    CHECK(pipe(fds) == 0);
    CHECK(ms_io_refused_add(refused, fds[1], true));
    run_until(loop, reports, 1);
    CHECK(reports->count == 1 && reports->fds[0] == fds[1]);
    reports->count = 0;
    close(fds[0]);
    close(fds[1]);
}

int main(void) {
    uv_loop_t loop;
    CHECK(uv_loop_init(&loop) == 0);
    Reports reports = {0};
    MsIoRefused *refused = ms_io_refused_open(&loop, on_ready, &reports);
    CHECK(refused != NULL);
    reports_once_when_ready(&loop, refused, &reports);
    a_hang_up_reports(&loop, refused, &reports);
    a_removed_watch_stays_silent(&loop, refused, &reports);
    a_full_ring_is_retried(&loop, refused, &reports);
    a_write_watch_reports_a_pipe_with_room(&loop, refused, &reports);
    ms_io_refused_close(refused);
    while (uv_loop_close(&loop) == UV_EBUSY) {
        (void)uv_run(&loop, UV_RUN_DEFAULT);
    }
    printf("ok\n");
    return 0;
}
