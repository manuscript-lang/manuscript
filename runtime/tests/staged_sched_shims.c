/* Unit test of the staged scheduler shims (runtime/staged/sched_shims.c): the blocking pool over the libuv reactor
 * (a job that finishes, one that is given up on and released later, a shielded one), admission permits shared by
 * tasks, and the cancel and read-limit queries. Run under the sanitizers by `make c-test`. */
#define _POSIX_C_SOURCE 200809L /* nanosleep under -std=c11 */
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "ms_sched.h"
#include "../core/scheduler.h"
#include "../io/reactor.h"
#include "support/sched_env.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "staged_sched_shims: failed: %s\n", what);
        exit(1);
    }
}

static void pause_for_ms(long ms) {
    const struct timespec span = {.tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L};
    nanosleep(&span, NULL);
}

/* ---- the reactor as the scheduler's poller ---- */

static int poll_watch(int fd, uint32_t events) { return (int)ms_io_watch(fd, events); }
static void poll_unwatch(int fd) { ms_io_unwatch(fd); }
static void poll_forget(int fd) { ms_io_forget(fd); }

static long poll_wait(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
    MsIoReady ready[8];
    size_t count = 0;
    if (!ms_io_wait(timeout_ns, ready, capacity < 8 ? capacity : 8, &count)) {
        return -1;
    }
    for (size_t i = 0; i < count; i++) {
        out[i] = (MsPollReady){.fd = ready[i].fd, .bits = ready[i].bits};
    }
    return (long)count;
}

static void install(void) {
    ms_test_sched_install();
    const MsSchedHooks hooks = ms_sched()->hooks;
    const MsPollOps poll = {.watch = poll_watch, .unwatch = poll_unwatch, .forget = poll_forget, .wait = poll_wait};
    ms_sched_set_hooks(&hooks, &poll);
    MsIoReactor *reactor = NULL;
    expect(ms_io_open(true, &reactor), "the reactor opens");
    ms_io_set_completion_sink(ms_sched_post_completion);
}

/* ---- jobs ---- */

typedef struct Data {
    int value;
    bool on_pool;
    long sleep_ms;
    atomic_int released;
} Data;

static void job_run(void *data) {
    Data *const job = data;
    if (job->sleep_ms > 0) {
        pause_for_ms(job->sleep_ms);
    }
    job->on_pool = ms_sched_on_pool_thread();
    job->value = 42;
}

static void job_release(void *data) { atomic_fetch_add(&((Data *)data)->released, 1); }

static void test_job_finishes(void) {
    Data data = {0};
    expect(ms_sched_pool_run(job_run, job_release, &data, -1) == MS_SCHED_DONE, "a finished job is done");
    expect(data.value == 42 && data.on_pool, "it ran on a pool thread and the data is back");
    expect(!ms_sched_on_pool_thread(), "the caller is not a pool thread");
    expect(atomic_load(&data.released) == 0, "a finished job's data is not released");
}

static void test_shielded_job(void) {
    Data data = {.sleep_ms = 20};
    expect(ms_sched_pool_run_shielded(job_run, &data) == MS_SCHED_DONE, "a shielded job is done");
    expect(data.value == 42, "it completed before the call returned");
}

static void test_given_up_job_is_released_once_finished(void) {
    Data *const data = calloc(1, sizeof *data);
    data->sleep_ms = 150;
    expect(ms_sched_pool_run(job_run, job_release, data, 20 * 1000000LL) == MS_SCHED_TIMED_OUT, "the wait times out");
    expect(atomic_load(&data->released) == 0, "the data is not released while the job runs");
    pause_for_ms(300);
    Data later = {0};
    expect(ms_sched_pool_run(job_run, job_release, &later, -1) == MS_SCHED_DONE, "a later call works");
    expect(atomic_load(&data->released) == 1, "and released the abandoned job's data exactly once");
    free(data);
}

/* ---- admission ---- */

enum { HOLDERS = 7, BIG = 64 * 1024 };
static int holding;
static int most_holding;
static int finished;

static void holder(void *unused) {
    (void)unused;
    bool cancelled = false;
    expect(ms_sched_pool_admit(BIG, &cancelled), "a big payload gets a permit");
    holding++;
    most_holding = holding > most_holding ? holding : most_holding;
    ms_task_yield();
    ms_task_yield();
    holding--;
    ms_sched_pool_release();
    finished++;
}

static void test_admission_is_bounded(void) {
    bool cancelled = false;
    expect(!ms_sched_pool_admit(BIG - 1, &cancelled) && !cancelled, "a small payload needs no permit");
    MsTaskHandle handles[HOLDERS];
    for (int i = 0; i < HOLDERS; i++) {
        MsTaskStatus status = MS_TASK_OK;
        handles[i] = ms_task_spawn(holder, NULL, 0, 0, &status);
        expect(handles[i] != 0, "spawn");
    }
    for (int i = 0; i < HOLDERS; i++) {
        uint8_t outcome = 0;
        MsFaultText text = {0};
        expect(ms_task_join(handles[i], &outcome, &text) == MS_TASK_OK && outcome == 0, "join");
    }
    expect(finished == HOLDERS, "every holder finished");
    expect(most_holding <= 4, "no more permits than the pool has threads were out at once");
    expect(most_holding > 1, "and permits were shared");
}

static void test_queries(void) {
    expect(!ms_sched_cancel_pending(), "no cancel is pending");
    expect(!ms_sched_read_limit_passed(), "no read limit has passed");
    const int64_t before = ms_task_read_limit(1);
    ms_task_sleep(2000000);
    expect(ms_sched_read_limit_passed(), "a read limit that ran out is reported");
    ms_task_read_limit_restore(before);
}

static void main_task(void *unused) {
    (void)unused;
    test_job_finishes();
    test_shielded_job();
    test_given_up_job_is_released_once_finished();
    test_admission_is_bounded();
    test_queries();
}

int main(void) {
    install();
    uint8_t outcome = 1;
    MsFaultText text = {0};
    expect(ms_task_run_main(main_task, NULL, 0, &outcome, &text) == MS_TASK_OK && outcome == 0, "the main task ends");
    puts("staged_sched_shims: ok");
    return 0;
}
