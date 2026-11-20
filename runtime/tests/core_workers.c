/* Worker isolates (runtime/core/worker.c, promise.c): queued promises are run inline by their waiter or taken by an
 * idle worker, results and cancels cross by mail. Runs under the sanitizers by `make c-test`. */
#define _DEFAULT_SOURCE 1
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../core/cancel.h"
#include "../core/promise.h"
#include "../core/scheduler.h"
#include "../core/worker.h"
#include "ms_rt/alloc.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_workers: failed: %s\n", what);
        exit(1);
    }
}

/* ---- a poller per thread: a pipe that the isolate's wake writes ---- */

static _Thread_local int wake_pipe[2] = {-1, -1};

static void wake_thread(void *argument) {
    const int *const fds = argument;
    const char byte = 1;
    (void)!write(fds[1], &byte, 1);
}

static int fake_watch(int fd, uint32_t events) {
    (void)fd;
    (void)events;
    return MS_POLL_ARMED;
}

static void fake_unwatch(int fd) { (void)fd; }

static long fake_wait(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
    (void)out;
    (void)capacity;
    struct pollfd fds[1] = {{.fd = wake_pipe[0], .events = POLLIN}};
    const int ms = timeout_ns < 0 ? -1 : (int)((timeout_ns + 999999) / 1000000);
    if (poll(fds, 1, timeout_ns == 0 ? 0 : ms) > 0) {
        char drain[64];
        (void)!read(wake_pipe[0], drain, sizeof drain);
    }
    return 0;
}

static void fake_fault(MsFaultKind kind, const char *message) {
    (void)kind;
    MsFaultText text = {.bytes = msrt_alloc(strlen(message) + 1), .length = strlen(message)};
    memcpy(text.bytes, message, text.length + 1);
    if (!ms_guard_leave(MS_GUARD_FAULT, text)) {
        fprintf(stderr, "core_workers: fault with no guard: %s\n", message);
        exit(1);
    }
    for (;;) {
    }
}

static void fake_exit(int status) {
    fprintf(stderr, "core_workers: unexpected process exit %d\n", status);
    exit(1);
}

static const MsPollOps poll_ops = {.watch = fake_watch, .unwatch = fake_unwatch, .forget = fake_unwatch, .wait = fake_wait};

static bool worker_setup(MsPollOps *poll, MsWakeFn *wake, void **wake_argument) {
    if (pipe(wake_pipe) != 0) {
        return false;
    }
    *poll = poll_ops;
    *wake = wake_thread;
    *wake_argument = wake_pipe;
    return true;
}

static void worker_finish(void) {
    close(wake_pipe[0]);
    close(wake_pipe[1]);
}

/* ---- closures ---- */

typedef struct Work {
    MsObj header;
    void (*code)(struct Work *);
    MsPromise id;
    int64_t value;
    int64_t sleep_ns;
} Work;

static _Atomic size_t drops;
static _Atomic int ran_on_main;
static _Atomic int ran_elsewhere;
static pthread_t main_thread;

static void work_drop(MsObj *object) {
    atomic_fetch_add(&drops, 1);
    msrt_free(object);
}

static Work *make_work(MsPromise id, void (*code)(Work *), int64_t value) {
    Work *const work = msrt_alloc_zeroed(sizeof *work);
    work->header.drop = work_drop;
    work->code = code;
    work->id = id;
    work->value = value;
    return work;
}

static void put_value(Work *work) {
    atomic_fetch_add(pthread_equal(pthread_self(), main_thread) ? &ran_on_main : &ran_elsewhere, 1);
    ms_promise_put(work->id, (uint8_t *)&work->value, &msrt_desc_int, false);
}

static _Atomic int started_elsewhere;

static void sleep_until_cancelled(Work *work) {
    atomic_fetch_add(&started_elsewhere, 1);
    for (;;) {
        if (ms_task_sleep(work->sleep_ns) == MS_WAIT_CANCELLED) {
            ms_cancelled();
        }
    }
}

/* A worker's work uses promises of the main isolate: waits for `dep`, takes its value, cancels `victim`. */
typedef struct Cross {
    MsObj header;
    void (*code)(struct Cross *);
    MsPromise id;
    int64_t value;
    int64_t sleep_ns;
    MsPromise dep;
    MsPromise victim;
} Cross;

static _Atomic int cross_started;

static void use_foreign_promises(Cross *work) {
    expect(!ms_promise_done(work->dep), "foreign done: still pending");
    atomic_store(&cross_started, 1);
    ms_promise_set_grouped(work->dep, true);
    ms_promise_set_grouped(work->dep, false);
    const MsPromise both[2] = {work->dep, ms_promise_sleep(60LL * 1000 * 1000 * 1000)};
    expect(ms_promise_wait_any(both, 2, -1) == 0, "foreign wait_any: the foreign promise finished first");
    ms_promise_cancel(both[1]);
    ms_promise_drop(both[1]);
    expect(ms_promise_wait(work->dep, -1) == MS_PROMISE_OK, "foreign wait: ok");
    int64_t value = 0;
    expect(ms_promise_take(work->dep, &msrt_desc_int, (uint8_t *)&value), "foreign take");
    ms_promise_cancel(work->victim);
    expect(ms_promise_wait(work->victim, -1) == MS_PROMISE_CANCELLED, "foreign wait: cancelled");
    int64_t twice = value * 2;
    ms_promise_put(work->id, (uint8_t *)&twice, &msrt_desc_int, false);
}

/* A worker completes a promise of the main isolate with no value, as a pipe's last writer ends a parked read. */
static void finish_foreign_without_value(Cross *work) {
    atomic_store(&cross_started, 1);
    ms_promise_io_done(work->dep);
}

static int64_t take_int(MsPromise id) {
    int64_t value = -1;
    expect(ms_promise_take(id, &msrt_desc_int, (uint8_t *)&value), "a value to take");
    return value;
}

/* ---- tests ---- */

static void queued_work_runs_inline(void) {
    const MsPromise id = ms_promise_new();
    ms_promise_start(id, (MsObj *)make_work(id, put_value, 41));
    expect(ms_promise_wait(id, -1) == MS_PROMISE_OK, "inline: ok");
    expect(take_int(id) == 41, "inline: value");
    ms_promise_drop(id);
}

static void idle_worker_takes_old_work(void) {
    atomic_store(&ran_elsewhere, 0);
    const MsPromise id = ms_promise_new();
    ms_promise_start(id, (MsObj *)make_work(id, put_value, 7));
    /* This thread blocks outside the scheduler, so only a worker can take the work. */
    for (int i = 0; i < 500 && atomic_load(&ran_elsewhere) == 0; i++) {
        usleep(2000);
    }
    expect(ms_promise_wait(id, -1) == MS_PROMISE_OK, "stolen: ok");
    expect(take_int(id) == 7, "stolen: value");
    expect(atomic_load(&ran_elsewhere) == 1, "stolen: ran on a worker");
    ms_promise_drop(id);
}

static void cancel_reaches_the_worker(void) {
    const MsPromise id = ms_promise_new();
    Work *const work = make_work(id, sleep_until_cancelled, 0);
    work->sleep_ns = 1000 * 1000;
    const size_t before = atomic_load(&drops);
    ms_promise_start(id, (MsObj *)work);
    for (int i = 0; i < 500 && atomic_load(&started_elsewhere) == 0; i++) {
        usleep(2000); /* blocked outside the scheduler until a worker runs it */
    }
    expect(atomic_load(&started_elsewhere) == 1, "cancel: a worker started the work");
    ms_promise_cancel(id);
    expect(ms_promise_wait(id, -1) == MS_PROMISE_CANCELLED, "cancel: cancelled");
    ms_promise_drop(id);
    expect(atomic_load(&drops) == before + 1, "cancel: closure dropped once");
}

static void foreign_operations(void) {
    const MsPromise dep = ms_promise_new();
    const MsPromise victim = ms_promise_new();
    const MsPromise id = ms_promise_new();
    Cross *const work = msrt_alloc_zeroed(sizeof *work);
    work->header.drop = work_drop;
    work->code = use_foreign_promises;
    work->id = id;
    work->dep = dep;
    work->victim = victim;
    atomic_store(&cross_started, 0);
    ms_promise_start(id, (MsObj *)work);
    for (int i = 0; i < 500 && atomic_load(&cross_started) == 0; i++) {
        (void)ms_task_sleep(1000 * 1000); /* inside the scheduler: this isolate answers the worker's asks */
    }
    expect(atomic_load(&cross_started) == 1, "foreign: a worker started the work");
    int64_t value = 21;
    ms_promise_put(dep, (uint8_t *)&value, &msrt_desc_int, false);
    expect(ms_promise_wait(id, -1) == MS_PROMISE_OK, "foreign: ok");
    expect(take_int(id) == 42, "foreign: value");
    ms_promise_drop(id);
    ms_promise_drop(dep);
    ms_promise_drop(victim);
}

/* The completion reaches a promise another isolate owns: the owner, parked on it, wakes. */
static void foreign_completion_without_value(void) {
    const MsPromise dep = ms_promise_new();
    ms_promise_set_remote_wake(dep);
    const MsPromise id = ms_promise_new();
    Cross *const work = msrt_alloc_zeroed(sizeof *work);
    work->header.drop = work_drop;
    work->code = finish_foreign_without_value;
    work->id = id;
    work->dep = dep;
    atomic_store(&cross_started, 0);
    ms_promise_start(id, (MsObj *)work);
    for (int i = 0; i < 500 && atomic_load(&cross_started) == 0; i++) {
        usleep(2000); /* blocked outside the scheduler, so only a worker can run the work */
    }
    expect(atomic_load(&cross_started) == 1, "foreign completion: a worker ran the work");
    expect(ms_promise_wait(dep, 10LL * 1000 * 1000 * 1000) == MS_PROMISE_OK, "foreign completion: the owner wakes");
    ms_promise_drop(dep);
    ms_promise_drop(id);
}

/* A worker listens to a switch of the main isolate, sees it fire, and fires another one of the main isolate's. */
static void use_foreign_switches(Cross *work) {
    const int64_t watched = (int64_t)work->victim;
    const int64_t raised = (int64_t)work->dep;
    const MsPromise sleeper = ms_promise_sleep(60LL * 1000 * 1000 * 1000);
    expect(!ms_cancel_register(watched, sleeper), "switch: not fired yet");
    expect(!ms_cancel_fired(watched), "switch: reads not fired on a worker");
    atomic_store(&cross_started, 1);
    expect(ms_promise_wait(sleeper, -1) == MS_PROMISE_CANCELLED, "switch: the foreign listener is cancelled");
    expect(ms_cancel_fired(watched), "switch: reads fired on a worker");
    ms_promise_drop(sleeper);
    ms_cancel_fire(raised);
    int64_t one = 1;
    ms_promise_put(work->id, (uint8_t *)&one, &msrt_desc_int, false);
}

static void foreign_switches(void) {
    const int64_t watched = ms_cancel_new();
    const int64_t raised = ms_cancel_new();
    const MsPromise id = ms_promise_new();
    Cross *const work = msrt_alloc_zeroed(sizeof *work);
    work->header.drop = work_drop;
    work->code = use_foreign_switches;
    work->id = id;
    work->victim = (MsPromise)watched;
    work->dep = (MsPromise)raised;
    atomic_store(&cross_started, 0);
    ms_promise_start(id, (MsObj *)work);
    for (int i = 0; i < 500 && atomic_load(&cross_started) == 0; i++) {
        (void)ms_task_sleep(1000 * 1000);
    }
    expect(atomic_load(&cross_started) == 1, "switch: a worker started the work");
    (void)ms_task_sleep(5 * 1000 * 1000); /* let the register mail arrive */
    ms_cancel_fire(watched);
    expect(ms_promise_wait(id, -1) == MS_PROMISE_OK, "switch: ok");
    expect(take_int(id) == 1, "switch: value");
    expect(ms_cancel_fired(raised), "switch: a worker fired a main switch");
    ms_promise_drop(id);
    ms_cancel_free(watched);
    ms_cancel_free(raised);
}

enum { MANY = 300 };

static void many_promises_all_finish(void) {
    MsPromise ids[MANY];
    for (int i = 0; i < MANY; i++) {
        ids[i] = ms_promise_new();
        ms_promise_start(ids[i], (MsObj *)make_work(ids[i], put_value, i));
        if (i % 50 == 0) {
            (void)ms_task_sleep(200 * 1000);
        }
    }
    int64_t sum = 0;
    for (int i = MANY - 1; i >= 0; i--) {
        expect(ms_promise_wait(ids[i], -1) == MS_PROMISE_OK, "many: ok");
        sum += take_int(ids[i]);
        ms_promise_drop(ids[i]);
    }
    expect(sum == (int64_t)MANY * (MANY - 1) / 2, "many: every value arrived once");
}

/* Work started and never waited for: what a worker took or what is still queued must be freed at teardown. */
static void abandoned_work_is_freed(void) {
    for (int i = 0; i < 20; i++) {
        const MsPromise id = ms_promise_new();
        ms_promise_start(id, (MsObj *)make_work(id, put_value, i));
    }
}

static void entry(void *argument) {
    (void)argument;
    queued_work_runs_inline();
    idle_worker_takes_old_work();
    cancel_reaches_the_worker();
    foreign_operations();
    foreign_completion_without_value();
    foreign_switches();
    many_promises_all_finish();
    abandoned_work_is_freed();
}

int main(void) {
    msrt_heap_claim();
    main_thread = pthread_self();
    expect(pipe(wake_pipe) == 0, "pipe");
    MsWorkerEnv env = {.limit = 3, .setup = worker_setup, .finish = worker_finish};
    env.hooks = (MsSchedHooks){.fault = fake_fault, .exit_process = fake_exit};
    ms_promise_hooks(&env.hooks);
    ms_workers_configure(&env);
    MsSchedHooks hooks = env.hooks;
    hooks.service = false;
    ms_sched_set_hooks(&hooks, &poll_ops);
    expect(ms_sched_attach(wake_thread, wake_pipe) != MS_NO_ISOLATE, "attach");
    uint8_t outcome = 9;
    MsFaultText message = {0};
    expect(ms_task_run_main(entry, NULL, 0, &outcome, &message) == MS_TASK_OK && outcome == 0, "main task runs");
    ms_workers_shutdown();
    ms_sched_teardown();
    puts("core_workers: ok");
    return 0;
}
