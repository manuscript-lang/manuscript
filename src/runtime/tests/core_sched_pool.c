/* Test of the blocking pool (src/runtime/std/pool.c) over the C scheduler: a job that finishes, one given up on, a
 * shielded one, and admission permits shared by tasks. A job's thread posts the task's token through the isolate's
 * mail, so the poller here sleeps on a wake pipe, as the real one does. */
#define _DEFAULT_SOURCE 1
#include <poll.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#include "ms_sched.h"
#include "../core/scheduler.h"
#include "../core/task.h"
#include "support/sched_env.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_sched_pool: failed: %s\n", what);
        exit(1);
    }
}

static void pause_for_ms(long ms) {
    const struct timespec span = {.tv_sec = ms / 1000, .tv_nsec = (ms % 1000) * 1000000L};
    nanosleep(&span, NULL);
}

static int wake_pipe[2];

static void wake(void *argument) {
    (void)argument;
    const char byte = 1;
    (void)!write(wake_pipe[1], &byte, 1);
}

static int idle_watch(int fd, uint32_t events) {
    (void)fd;
    (void)events;
    return MS_POLL_ARMED;
}

static void idle_fd(int fd) { (void)fd; }

static long wake_wait(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
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
    pause_for_ms(300);
    Data later = {0};
    expect(ms_sched_pool_run(job_run, job_release, &later, -1) == MS_SCHED_DONE, "a later call works");
    expect(atomic_load(&data->released) == 1, "and released the abandoned job's data exactly once");
    free(data);
}

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
    uint64_t handles[HOLDERS];
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

static void main_task(void *unused) {
    (void)unused;
    test_job_finishes();
    test_shielded_job();
    test_given_up_job_is_released_once_finished();
    test_admission_is_bounded();
}

int main(void) {
    expect(pipe(wake_pipe) == 0, "wake pipe");
    ms_test_sched_install();
    const MsSchedHooks hooks = ms_sched()->hooks;
    const MsPollOps poll = {.watch = idle_watch, .unwatch = idle_fd, .forget = idle_fd, .wait = wake_wait};
    ms_sched_set_hooks(&hooks, &poll);
    expect(ms_sched_attach(wake, NULL) != MS_NO_ISOLATE, "register the isolate");
    uint8_t outcome = 1;
    MsFaultText text = {0};
    expect(ms_task_run_main(main_task, NULL, 0, &outcome, &text) == MS_TASK_OK && outcome == 0, "the main task ends");
    puts("core_sched_pool: ok");
    return 0;
}
