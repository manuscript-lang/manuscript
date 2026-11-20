/* Unit test of the C promise table (runtime/core/promise.c) on the C scheduler: completion, errors, waits with
 * timeouts, sleeps, limits, cancellation, faults, deferred work, I/O continuations and the cancel of a frame that
 * started many promises. Run under the sanitizers by `make c-test`. */
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../core/cancel.h"
#include "../core/group.h"
#include "../core/promise.h"
#include "../core/scheduler.h"
#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_promise: failed: %s\n", what);
        exit(1);
    }
}

/* ---- environment ---- */

enum { MAX_FDS = 64 };

static uint32_t watched[MAX_FDS]; /* events asked for each descriptor, 0 when not watched */

static int fake_watch(int fd, uint32_t events) {
    watched[fd] = events;
    return MS_POLL_ARMED;
}

static void fake_unwatch(int fd) { watched[fd] = 0; }

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

static void fake_fault(MsFaultKind kind, const char *message) {
    (void)kind;
    MsFaultText text = {.bytes = msrt_alloc(strlen(message) + 1), .length = strlen(message)};
    memcpy(text.bytes, message, text.length + 1);
    if (!ms_guard_leave(MS_GUARD_FAULT, text)) {
        fprintf(stderr, "core_promise: fault with no guard: %s\n", message);
        exit(1);
    }
    for (;;) {
    }
}

static void fake_exit(int status) {
    fprintf(stderr, "core_promise: unexpected process exit %d\n", status);
    exit(1);
}

static void install(void) {
    MsSchedHooks hooks = {.fault = fake_fault, .exit_process = fake_exit};
    ms_promise_hooks(&hooks);
    const MsPollOps poll_ops = {.watch = fake_watch, .unwatch = fake_unwatch, .forget = fake_unwatch, .wait = fake_wait};
    ms_sched_set_hooks(&hooks, &poll_ops);
}

/* ---- closures ---- */

typedef struct Work {
    MsObj header;
    void (*code)(struct Work *);
    MsPromise id;
    int64_t value;
    int64_t sleep_ns;
    bool fail;
    bool fault;
    int64_t notice; /* a switch the work polls: it finishes once it has fired */
} Work;

static size_t drops;

static void work_drop(MsObj *object) {
    drops++;
    msrt_free(object);
}

static Work *make_work(MsPromise id, void (*code)(Work *)) {
    Work *const work = msrt_alloc_zeroed(sizeof *work);
    work->header.drop = work_drop;
    work->code = code;
    work->id = id;
    return work;
}

static void put_value(Work *work) {
    if (work->sleep_ns > 0) {
        if (ms_task_sleep(work->sleep_ns) == MS_WAIT_CANCELLED) {
            ms_cancelled();
        }
    }
    if (work->fault) {
        ms_sched()->hooks.fault(MS_FAULT_KIND_FAULT, "boom");
    }
    ms_promise_put(work->id, (uint8_t *)&work->value, &msrt_desc_int, work->fail);
}

/* Works until the notice switch fires, then finishes with its value. */
static void until_notice(Work *work) {
    while (!ms_cancel_fired(work->notice)) {
        if (ms_task_sleep(2LL * 1000 * 1000) == MS_WAIT_CANCELLED) {
            ms_cancelled();
        }
    }
    ms_promise_put(work->id, (uint8_t *)&work->value, &msrt_desc_int, false);
}

static void sleep_forever(Work *work) {
    if (ms_task_sleep(work->sleep_ns) == MS_WAIT_CANCELLED) {
        ms_cancelled();
    }
}

static int64_t take_int(MsPromise id) {
    int64_t value = -1;
    expect(ms_promise_take(id, &msrt_desc_int, (uint8_t *)&value), "take");
    return value;
}

/* ---- tests ---- */

static void test_value(void) {
    const MsPromise id = ms_promise_new();
    Work *const work = make_work(id, put_value);
    work->value = 42;
    ms_promise_start(id, &work->header);
    expect(ms_promise_wait(id, -1) == MS_PROMISE_OK, "wait ok");
    expect(take_int(id) == 42, "value");
    expect(ms_promise_wait(id, -1) == MS_PROMISE_CLOSED, "closed after take");
    expect(ms_promise_done(id), "done");
    ms_promise_drop(id);
    expect(ms_promise_done(id), "a dropped id reads as done");
}

static void test_error_value(void) {
    const MsPromise id = ms_promise_new();
    Work *const work = make_work(id, put_value);
    work->value = 7;
    work->fail = true;
    ms_promise_start(id, &work->header);
    expect(ms_promise_wait(id, -1) == MS_PROMISE_ERROR, "error code");
    expect(take_int(id) == 7, "error value");
    ms_promise_drop(id);
}

static void test_wait_timeout_cancels(void) {
    const MsPromise id = ms_promise_new();
    Work *const work = make_work(id, sleep_forever);
    work->sleep_ns = 10LL * 1000 * 1000 * 1000;
    ms_promise_start(id, &work->header);
    expect(ms_promise_wait(id, 10 * 1000 * 1000) == MS_PROMISE_TIMEOUT, "wait times out");
    expect(!ms_promise_end(id), "ended without a value");
    expect(ms_promise_wait(id, -1) == MS_PROMISE_CANCELLED, "then reads cancelled");
    ms_promise_drop(id);
}

static void test_cancel(void) {
    const size_t before = drops;
    const MsPromise id = ms_promise_new();
    Work *const work = make_work(id, sleep_forever);
    work->sleep_ns = 10LL * 1000 * 1000 * 1000;
    ms_promise_start(id, &work->header);
    ms_task_yield();
    ms_promise_cancel(id);
    expect(ms_promise_wait(id, -1) == MS_PROMISE_CANCELLED, "cancelled");
    ms_promise_drop(id);
    expect(drops == before + 1, "the closure was dropped once");
}

static void test_limit(void) {
    const MsPromise id = ms_promise_new();
    Work *const work = make_work(id, sleep_forever);
    work->sleep_ns = 10LL * 1000 * 1000 * 1000;
    ms_promise_start(id, &work->header);
    ms_promise_limit(id, 15 * 1000 * 1000);
    expect(ms_promise_wait(id, -1) == MS_PROMISE_TIMEOUT, "the limit reports a timeout");
    ms_promise_drop(id);
}

static void test_fault_report(void) {
    const MsPromise id = ms_promise_new();
    Work *const work = make_work(id, put_value);
    work->fault = true;
    ms_promise_start(id, &work->header);
    expect(ms_promise_wait(id, -1) == MS_PROMISE_FAILED, "failed");
    const MsFaultText report = ms_promise_fault_report(id);
    expect(report.length == 4 && memcmp(report.bytes, "boom", 4) == 0, "the report names the fault");
    msrt_free(report.bytes);
    ms_promise_drop(id);
}

static void test_sleep(void) {
    const MsPromise slow = ms_promise_sleep(30 * 1000 * 1000);
    const MsPromise fast = ms_promise_sleep(5 * 1000 * 1000);
    expect(!ms_promise_done(fast), "not done at once");
    expect(ms_promise_wait(fast, -1) == MS_PROMISE_OK, "fast sleep");
    expect(!ms_promise_done(slow), "the slow one still sleeps");
    expect(ms_promise_wait(slow, 1000) == MS_PROMISE_TIMEOUT || ms_promise_done(slow), "wait with a short limit");
    expect(ms_promise_wait(slow, -1) == MS_PROMISE_OK, "slow sleep");
    ms_promise_drop(fast);
    ms_promise_drop(slow);
}

static void test_deferred(void) {
    const MsPromise id = ms_promise_new();
    Work *const work = make_work(id, put_value);
    work->value = 5;
    ms_promise_defer(id, &work->header);
    expect(!ms_promise_done(id), "deferred work waits for a waiter");
    expect(ms_promise_wait(id, -1) == MS_PROMISE_OK, "the waiter runs it");
    expect(take_int(id) == 5, "deferred value");
    ms_promise_drop(id);

    const size_t before = drops;
    const MsPromise unused = ms_promise_new();
    ms_promise_defer(unused, &make_work(unused, put_value)->header);
    ms_promise_cancel(unused);
    expect(drops == before + 1, "cancelling deferred work drops it unrun");
    expect(ms_promise_wait(unused, -1) == MS_PROMISE_CANCELLED, "and reads cancelled");
    ms_promise_drop(unused);
}

static size_t cancels_seen;
static uintptr_t last_state;

static bool io_retry(MsPromise id, uintptr_t state, uint32_t bits) {
    (void)id;
    last_state = state;
    if (bits == MS_WAIT_CANCELLED) {
        cancels_seen++;
    }
    return false;
}

static void test_io_continuation(void) {
    const MsPromise id = ms_promise_new();
    ms_promise_on_drop(id, io_retry, 99);
    ms_promise_cancel(id);
    expect(cancels_seen == 1 && last_state == 99, "the continuation hears the cancel");
    expect(ms_promise_wait(id, -1) == MS_PROMISE_CANCELLED, "cancelled");
    ms_promise_drop(id);
    ms_promise_io_done_unit(id); /* a stale id: ignored */
}

static void test_stale_ids(void) {
    const MsPromise first = ms_promise_new();
    ms_promise_drop(first);
    const MsPromise second = ms_promise_new();
    expect(first != second, "a reused row has a new generation");
    expect(ms_promise_done(first), "the stale id reads as done");
    expect(!ms_promise_done(second), "the new one is pending");
    ms_promise_io_done_int(second, 3);
    expect(ms_promise_wait(second, -1) == MS_PROMISE_OK, "completed");
    ms_promise_drop(second);
}

static void test_ready(void) {
    int fds[2];
    expect(pipe(fds) == 0, "pipe");
    const MsPromise id = ms_promise_ready(fds[0], MS_WAIT_READ, -1);
    expect(id > 0 && !ms_promise_done(id), "a readiness promise is pending");
    expect(write(fds[1], "x", 1) == 1, "write");
    expect(ms_promise_wait(id, -1) == MS_PROMISE_OK, "ready");
    expect(take_int(id) == MS_WAIT_READ, "the ready bits");
    ms_promise_drop(id);

    const MsPromise late = ms_promise_ready(fds[1], MS_WAIT_READ, 5 * 1000 * 1000);
    expect(ms_promise_wait(late, -1) == MS_PROMISE_OK && take_int(late) == MS_WAIT_TIMEOUT, "timeout bits");
    ms_promise_drop(late);

    char byte = 0;
    expect(read(fds[0], &byte, 1) == 1, "drain");
    const MsPromise cancelled = ms_promise_ready(fds[0], MS_WAIT_READ, -1);
    ms_promise_cancel(cancelled);
    expect(ms_promise_wait(cancelled, -1) == MS_PROMISE_CANCELLED && watched[fds[0]] == 0, "cancel unwatches");
    ms_promise_drop(cancelled);
    close(fds[0]);
    close(fds[1]);
}

static size_t retries;

static bool retry_after_two(MsPromise id, uintptr_t state, uint32_t bits) {
    (void)state;
    retries++;
    if (retries < 2) {
        return false;
    }
    expect((bits & MS_WAIT_READ) != 0, "read bits");
    ms_promise_io_done_unit(id);
    return true;
}

static void test_io_on_ready(void) {
    int fds[2];
    expect(pipe(fds) == 0, "pipe");
    const MsPromise id = ms_promise_new();
    expect(ms_promise_io_on_ready(id, fds[0], MS_WAIT_READ, -1, retry_after_two, 0), "registered");
    expect(write(fds[1], "xy", 2) == 2, "write");
    expect(ms_promise_wait(id, -1) == MS_PROMISE_OK && retries == 2, "a retry that answers false waits again");
    ms_promise_drop(id);
    close(fds[0]);
    close(fds[1]);
}

static void test_wait_any(void) {
    const MsPromise slow = ms_promise_sleep(40 * 1000 * 1000);
    const MsPromise fast = ms_promise_sleep(5 * 1000 * 1000);
    const MsPromise ids[2] = {slow, fast};
    expect(ms_promise_wait_any(ids, 2, -1) == 1, "the fast sleep finishes first");
    expect(ms_promise_wait_any(ids, 2, 1000) == 1, "a finished promise answers at once");
    ms_promise_drop(fast);
    const MsPromise lone[1] = {slow};
    expect(ms_promise_wait_any(lone, 1, 1000 * 1000) == -1, "a short limit times out");
    expect(ms_promise_wait(slow, -1) == MS_PROMISE_OK, "the slow one still finishes");
    ms_promise_drop(slow);
}

static void test_group(void) {
    const int64_t group = ms_group_new();
    const MsPromise slow = ms_promise_sleep(30 * 1000 * 1000);
    const MsPromise fast = ms_promise_sleep(5 * 1000 * 1000);
    const MsPromise ids[2] = {slow, fast};
    expect(ms_group_join(group, ids, 2, 0) == MS_GROUP_JOINED_ALL, "joined");
    expect(ms_group_poll(group) == -1, "nothing finished yet");
    expect(ms_group_next(group) == 1, "the fast one is reported first");
    expect(ms_group_next(group) == 0, "then the slow one");
    expect(ms_group_next(group) == -1, "then none is left");
    ms_promise_drop(slow);
    ms_promise_drop(fast);
    ms_group_free(group);
}

/* A failed member interrupts the deferred promise a waiter runs inline for the group. */
static void blocked_work(Work *work) {
    const MsPromise long_sleep = ms_promise_sleep(work->sleep_ns);
    (void)ms_promise_wait(long_sleep, -1);
    ms_promise_drop(long_sleep);
}

static void test_run_watched(void) {
    const int64_t group = ms_group_new();
    const MsPromise failing = ms_promise_new();
    Work *const failer = make_work(failing, put_value);
    failer->sleep_ns = 5 * 1000 * 1000;
    failer->fail = true;
    ms_promise_start(failing, &failer->header);
    const MsPromise inline_run = ms_promise_new();
    Work *const slow = make_work(inline_run, blocked_work);
    slow->sleep_ns = 20LL * 1000 * 1000 * 1000;
    ms_promise_defer(inline_run, &slow->header);
    const MsPromise ids[2] = {failing, inline_run};
    const int64_t start = ms_sched_now();
    expect(ms_promise_run_watched(inline_run, group, ids, 2, 0) == MS_RUN_INTERRUPTED, "the failure ends the run");
    expect((ms_sched_now() - start) < 5LL * 1000 * 1000 * 1000, "it did not wait for the slow work");
    ms_promise_drop(inline_run);
    ms_promise_drop(failing);
    ms_group_free(group);
}

static void test_cancel_switch(void) {
    const int64_t first = ms_cancel_new();
    const int64_t second = ms_cancel_new();
    expect(!ms_cancel_fired(first), "a new switch has not fired");
    const MsPromise id = ms_promise_new();
    ms_promise_on_cancel(id, first);
    ms_promise_on_cancel(id, second); /* rebinding releases the first */
    ms_cancel_fire(first);
    expect(!ms_promise_done(id), "only the replacement switch cancels it");
    ms_cancel_fire(second);
    expect(ms_promise_wait(id, -1) == MS_PROMISE_CANCELLED, "the second switch cancelled it");
    ms_cancel_fire(second); /* firing twice does nothing */
    expect(ms_cancel_fired(second), "fired");
    ms_promise_drop(id);

    const MsPromise late = ms_promise_new();
    ms_promise_on_cancel(late, second); /* already fired: cancelled at once */
    expect(ms_promise_wait(late, -1) == MS_PROMISE_CANCELLED, "listening to a fired switch cancels");
    ms_promise_drop(late);
    ms_cancel_free(first);
    ms_cancel_free(second);
    const int64_t unfired = ms_cancel_new();
    ms_cancel_free(unfired);
    expect(!ms_cancel_fired(unfired), "a freed switch reads as not fired");
}

static MsPromise start_drainable(int64_t notice, int64_t grace_ns, void (*code)(Work *)) {
    const MsPromise id = ms_promise_new();
    Work *const work = make_work(id, code);
    work->value = 41;
    work->sleep_ns = 10LL * 1000 * 1000 * 1000;
    work->notice = notice;
    ms_promise_start(id, &work->header);
    ms_promise_drain(id, notice, grace_ns);
    ms_task_yield();
    return id;
}

/* Ending a promise with a drain switch tells it first: work that winds down on the notice keeps its result. */
static void test_drain_notice(void) {
    const int64_t notice = ms_cancel_new();
    const MsPromise id = start_drainable(notice, -1, until_notice);
    expect(ms_promise_end(id), "the notice let the work finish with a value");
    expect(ms_cancel_fired(notice), "ending fired the switch");
    expect(take_int(id) == 41, "the value is the work's own");
    ms_promise_drop(id);
    ms_cancel_free(notice);
}

/* Work that ignores the notice is cancelled when its grace runs out; an explicit cancel gives no notice. */
static void test_drain_grace(void) {
    const int64_t notice = ms_cancel_new();
    const MsPromise id = start_drainable(notice, 20LL * 1000 * 1000, sleep_forever);
    const int64_t start = ms_sched_now();
    expect(!ms_promise_end(id), "work that ignores the notice ends without a value");
    expect(ms_sched_now() - start >= 15LL * 1000 * 1000, "it had its grace first");
    expect(ms_cancel_fired(notice), "the notice went out");
    ms_promise_drop(id);
    ms_cancel_free(notice);

    const int64_t quiet = ms_cancel_new();
    const MsPromise cancelled = start_drainable(quiet, -1, sleep_forever);
    ms_promise_cancel(cancelled);
    expect(ms_promise_wait(cancelled, -1) == MS_PROMISE_CANCELLED, "an explicit cancel is at once");
    expect(!ms_cancel_fired(quiet), "and gives no notice");
    ms_promise_drop(cancelled);
    ms_cancel_free(quiet);
}

static int64_t unwind_notice;
static MsPromise unwound_id;

static void drainer(void *argument) {
    (void)argument;
    unwound_id = start_drainable(unwind_notice, -1, until_notice);
    for (;;) {
        if (ms_task_sleep(100LL * 1000 * 1000 * 1000) == MS_WAIT_CANCELLED) {
            ms_cancelled();
        }
    }
}

/* A cancelled frame drains its started promises instead of cancelling them. */
static void test_drain_on_unwind(void) {
    unwind_notice = ms_cancel_new();
    MsTaskStatus status = MS_TASK_OK;
    const MsTaskHandle owner = ms_task_spawn(drainer, NULL, 0, 0, &status);
    expect(owner != 0, "spawn owner");
    for (int i = 0; i < 3; i++) {
        ms_task_yield();
    }
    ms_task_cancel(owner);
    uint8_t outcome = 0;
    MsFaultText text = {0};
    expect(ms_task_join(owner, &outcome, &text) == MS_TASK_OK && outcome == 2, "owner cancelled");
    expect(ms_cancel_fired(unwind_notice), "unwinding fired the notice");
    expect(ms_promise_wait(unwound_id, -1) == MS_PROMISE_OK, "the drained work finished");
    expect(take_int(unwound_id) == 41, "with its own value");
    ms_promise_drop(unwound_id);
    ms_cancel_free(unwind_notice);
}

/* A frame that started many promises: cancelling it ends them all, linearly. */
enum { MANY = 20000 };
static MsPromise many_ids[MANY];

static void starter(void *argument) {
    (void)argument;
    for (size_t i = 0; i < MANY; i++) {
        many_ids[i] = ms_promise_new();
        Work *const work = make_work(many_ids[i], sleep_forever);
        work->sleep_ns = 100LL * 1000 * 1000 * 1000;
        ms_promise_start(many_ids[i], &work->header);
    }
    for (;;) {
        if (ms_task_sleep(100LL * 1000 * 1000 * 1000) == MS_WAIT_CANCELLED) {
            ms_cancelled();
        }
    }
}

static void test_cancelled_frame_ends_its_promises(void) {
    const size_t before = drops;
    MsTaskStatus status = MS_TASK_OK;
    const MsTaskHandle creator = ms_task_spawn(starter, NULL, 0, 0, &status);
    expect(creator != 0, "spawn creator");
    for (int i = 0; i < 3; i++) {
        ms_task_yield();
    }
    const int64_t start = ms_sched_now();
    ms_task_cancel(creator);
    uint8_t outcome = 0;
    MsFaultText text = {0};
    expect(ms_task_join(creator, &outcome, &text) == MS_TASK_OK && outcome == 2, "creator cancelled");
    const int64_t took_ms = (ms_sched_now() - start) / 1000000;
    expect(drops == before + MANY, "every started closure was dropped");
    for (size_t i = 0; i < MANY; i++) {
        expect(ms_promise_wait(many_ids[i], -1) == MS_PROMISE_CANCELLED, "each promise ended cancelled");
        ms_promise_drop(many_ids[i]);
    }
    printf("core_promise: cancelling a frame with %d started promises took %lld ms\n", MANY, (long long)took_ms);
}

static void entry(void *argument) {
    (void)argument;
    test_value();
    test_error_value();
    test_wait_timeout_cancels();
    test_cancel();
    test_limit();
    test_fault_report();
    test_sleep();
    test_deferred();
    test_io_continuation();
    test_stale_ids();
    test_ready();
    test_io_on_ready();
    test_wait_any();
    test_group();
    test_cancel_switch();
    test_drain_notice();
    test_drain_grace();
    test_drain_on_unwind();
    test_run_watched();
    test_cancelled_frame_ends_its_promises();
}

int main(void) {
    msrt_heap_claim();
    install();
    uint8_t outcome = 9;
    MsFaultText message = {0};
    expect(ms_task_run_main(entry, NULL, 0, &outcome, &message) == MS_TASK_OK && outcome == 0, "main task runs");
    ms_sched_teardown();
    puts("core_promise: ok");
    return 0;
}
