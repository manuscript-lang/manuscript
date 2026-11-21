/* Unit tests of src/runtime/std/signals.c over src/runtime/sys/posix/signal.c: argument checks, buffering up to the capacity,
 * the order of arrival and close. A signal raised before `next` is waiting in the pipe, so no scheduler is needed. */
#include <signal.h>
#include <stdio.h>
#include <string.h>

#include "../std/abi.h"
#include "fake_rt.h"
#include "ms_rt/signals.h"

static int failures;
static MsStr err;
#define RUN(call) ({ const uint8_t status_ = (call); msrt_string_free(&err); err = (MsStr){0}; status_; })
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static MsVec ints(int64_t *items, size_t count) { return (MsVec){.ptr = items, .len = count, .cap = count}; }

static void validation(void) {
    MsObj *watcher = NULL;
    int64_t usr1[] = {SIGUSR1}, kill_signal[] = {SIGKILL}, stop_signal[] = {SIGSTOP}, high[] = {65}, zero[] = {0};
    MsVec none = ints(usr1, 0);
    CHECK(RUN(msstd_process_watch_signals(&none, 0, 0, &watcher, &err)) == STATUS_INVALID_INPUT);
    MsVec one = ints(usr1, 1);
    CHECK(RUN(msstd_process_watch_signals(&one, 1, 0, &watcher, &err)) == STATUS_INVALID_INPUT);
    CHECK(RUN(msstd_process_watch_signals(&one, 1, 1048577, &watcher, &err)) == STATUS_INVALID_INPUT);
    MsVec bad = ints(kill_signal, 1);
    CHECK(RUN(msstd_process_watch_signals(&bad, 0, 0, &watcher, &err)) == STATUS_INVALID_INPUT);
    bad = ints(stop_signal, 1);
    CHECK(RUN(msstd_process_watch_signals(&bad, 0, 0, &watcher, &err)) == STATUS_INVALID_INPUT);
    bad = ints(high, 1);
    CHECK(RUN(msstd_process_watch_signals(&bad, 0, 0, &watcher, &err)) == STATUS_INVALID_INPUT);
    bad = ints(zero, 1);
    CHECK(RUN(msstd_process_watch_signals(&bad, 0, 0, &watcher, &err)) == STATUS_INVALID_INPUT);
    CHECK(watcher == NULL);
}

static void observes_buffers_and_closes(void) {
    int64_t both[] = {SIGUSR1, SIGUSR2};
    MsVec list = ints(both, 2);
    MsObj *watcher = NULL;
    CHECK(RUN(msstd_process_watch_signals(&list, 1, 2, &watcher, &err)) == STATUS_OK);
    CHECK(watcher != NULL);
    raise(SIGUSR1);
    raise(SIGUSR2);
    raise(SIGUSR1); /* beyond the capacity of 2: dropped */
    int64_t got = 0;
    CHECK(RUN(msstd_process_signal_next(watcher, &got, &err)) == STATUS_OK && got == SIGUSR1);
    CHECK(RUN(msstd_process_signal_next(watcher, &got, &err)) == STATUS_OK && got == SIGUSR2);
    msstd_process_signal_close(watcher);
    msstd_process_signal_close(watcher);
    CHECK(RUN(msstd_process_signal_next(watcher, &got, &err)) == STATUS_CLOSED);
    watcher->drop(watcher);
}

static void a_second_watcher_shares_a_signal(void) {
    int64_t usr1[] = {SIGUSR1};
    MsVec list = ints(usr1, 1);
    MsObj *first = NULL, *second = NULL;
    CHECK(RUN(msstd_process_watch_signals(&list, 0, 0, &first, &err)) == STATUS_OK);
    CHECK(RUN(msstd_process_watch_signals(&list, 0, 0, &second, &err)) == STATUS_OK);
    raise(SIGUSR1);
    int64_t got = 0;
    CHECK(RUN(msstd_process_signal_next(first, &got, &err)) == STATUS_OK && got == SIGUSR1);
    CHECK(RUN(msstd_process_signal_next(second, &got, &err)) == STATUS_OK && got == SIGUSR1);
    first->drop(first);
    raise(SIGUSR1); /* the second watcher still holds the handler */
    CHECK(RUN(msstd_process_signal_next(second, &got, &err)) == STATUS_OK && got == SIGUSR1);
    second->drop(second);
}

int main(void) {
    validation();
    observes_buffers_and_closes();
    a_second_watcher_shares_a_signal();
    if (failures == 0) {
        printf("std_signals ok\n");
    }
    return failures == 0 ? 0 : 1;
}
