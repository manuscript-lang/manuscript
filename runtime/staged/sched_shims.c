/* The scheduler services C natives call through ms_sched.h, over the C scheduler (runtime/core) and the libuv
 * reactor's thread pool (ms_io_work). Staged with fault_abi.c: nothing builds this directory into the archive
 * until the flip replaces crates/ms-rt/src/glue/c_sched.rs. The Windows pipe and waitable-object calls of
 * ms_sched.h, stdout_error and flush_stdout are not here.
 *
 * A pool job runs on a libuv thread, where it may not call the runtime. Its record is allocated and freed on the
 * runtime thread; the pool thread touches only `run`, `data` and `done`. The submitting task parks on a token that
 * the completion sink posts (ms_sched_post_completion). A wait that gives up (timeout or cancel) leaves the job to
 * finish: the record joins `abandoned`, and the next pool call on this thread releases the data of every finished
 * one. No wake is needed for that: `done` is set by the pool thread before the job's completion is queued.
 */
#include <stdatomic.h>

#include "ms_sched.h"
#include "scheduler.h"
#include "unwind.h"
#include "../io/reactor.h"
#include "ms_rt/alloc.h"
#include "ms_rt/array.h"

enum {
    POOL_PERMITS = 4,           /* payload copies in flight, as many as libuv's default pool has threads */
    ADMIT_BYTES = 64 * 1024,    /* a smaller payload needs no permit */
};

typedef struct Job {
    MsSchedJobFn run;
    MsSchedJobFn release;
    void *data;
    atomic_bool done; /* set by the pool thread after run returns */
    uint64_t token;
} Job;

typedef struct Pool {
    size_t permits;
    uint64_t *waiters; /* tokens of callers parked in ms_sched_pool_admit, oldest first */
    size_t waiter_count;
    size_t waiter_capacity;
    Job **abandoned; /* jobs whose waiter gave up while they ran */
    size_t abandoned_count;
    size_t abandoned_capacity;
} Pool;

static _Thread_local Pool pool;      /* per scheduler thread, like the scheduler's own state */
static _Thread_local bool on_pool;   /* set on a libuv thread that ran a job */

bool ms_sched_cancel_pending(void) { return ms_cancel_flag() != 0; }

bool ms_sched_read_limit_passed(void) { return ms_task_read_limit_passed(); }

bool ms_sched_on_pool_thread(void) { return on_pool; }

bool ms_sched_pool_alone(void) { return ms_task_count() <= 1 || ms_task_others_stalled(); }

/* ---- jobs ---- */

static int32_t work(void *argument) {
    Job *const job = argument;
    on_pool = true;
    job->run(job->data);
    atomic_store_explicit(&job->done, true, memory_order_release);
    return 0;
}

static void job_free(Job *job) {
    (void)ms_token_free(job->token);
    msrt_free(job);
}

/* Releases the data of every abandoned job that has finished. */
static void reap(void) {
    size_t kept = 0;
    for (size_t i = 0; i < pool.abandoned_count; i++) {
        Job *const job = pool.abandoned[i];
        if (atomic_load_explicit(&job->done, memory_order_acquire)) {
            job->release(job->data);
            job_free(job);
        } else {
            pool.abandoned[kept++] = job;
        }
    }
    pool.abandoned_count = kept;
    if (kept == 0) {
        msrt_free(pool.abandoned);
        pool.abandoned = NULL;
        pool.abandoned_capacity = 0;
    }
}

static void abandon(Job *job) {
    void *items = pool.abandoned;
    if (!ms_array_reserve(&items, &pool.abandoned_capacity, pool.abandoned_count + 1, sizeof *pool.abandoned)) {
        /* No room to remember it: the record and the data leak until the pool thread ends the job. */
        return;
    }
    pool.abandoned = items;
    pool.abandoned[pool.abandoned_count++] = job;
}

/* Starts `run(data)` on the pool. NULL when it cannot be queued, and the caller runs it itself. */
static Job *submit(MsSchedJobFn run, MsSchedJobFn release, void *data) {
    reap();
    Job *const job = msrt_alloc(sizeof *job);
    job->run = run;
    job->release = release;
    job->data = data;
    atomic_init(&job->done, false);
    job->token = ms_token_new(MS_TOKEN_REMOTE);
    if (!ms_io_work(work, job, job->token)) {
        job_free(job);
        return NULL;
    }
    return job;
}

MsSchedWait ms_sched_pool_run(MsSchedJobFn run, MsSchedJobFn release, void *data, int64_t timeout_ns) {
    Job *const job = submit(run, release, data);
    if (job == NULL) {
        run(data); /* the pool is full or absent: run in line */
        return MS_SCHED_DONE;
    }
    uint64_t value = 0;
    uint32_t result = 0;
    (void)ms_token_park(job->token, timeout_ns, &value, &result);
    const bool cancelled = (result & MS_WAIT_CANCELLED) != 0;
    const bool gave_up = (result & (MS_WAIT_TIMEOUT | MS_WAIT_CANCELLED)) != 0;
    const bool finished = atomic_load_explicit(&job->done, memory_order_acquire);
    if (gave_up && !finished) {
        abandon(job);
        return cancelled ? MS_SCHED_CANCELLED : MS_SCHED_TIMED_OUT;
    }
    if (cancelled) {
        release(data); /* the job ended as the cancel arrived: the data is released as for an abandoned job */
        job_free(job);
        return MS_SCHED_CANCELLED;
    }
    job_free(job);
    return MS_SCHED_DONE;
}

MsSchedWait ms_sched_pool_run_shielded(MsSchedJobFn run, void *data) {
    Job *const job = submit(run, NULL, data);
    if (job == NULL) {
        run(data);
        return ms_cancel_flag() != 0 ? MS_SCHED_CANCELLED : MS_SCHED_DONE;
    }
    uint64_t value = 0;
    uint32_t result = 0;
    ms_shield_enter();
    (void)ms_token_park(job->token, -1, &value, &result);
    ms_shield_exit();
    job_free(job);
    return ms_cancel_flag() != 0 ? MS_SCHED_CANCELLED : MS_SCHED_DONE;
}

/* ---- admission ---- */

static void waiter_remove(uint64_t token) {
    for (size_t i = 0; i < pool.waiter_count; i++) {
        if (pool.waiters[i] == token) {
            pool.waiter_count--;
            for (size_t j = i; j < pool.waiter_count; j++) {
                pool.waiters[j] = pool.waiters[j + 1];
            }
            return;
        }
    }
}

static bool waiter_add(uint64_t token) {
    void *items = pool.waiters;
    if (!ms_array_reserve(&items, &pool.waiter_capacity, pool.waiter_count + 1, sizeof *pool.waiters)) {
        return false;
    }
    pool.waiters = items;
    pool.waiters[pool.waiter_count++] = token;
    return true;
}

void ms_sched_pool_release(void) {
    if (pool.waiter_count == 0) {
        if (pool.permits > 0) {
            pool.permits--;
        }
        return;
    }
    const uint64_t next = pool.waiters[0];
    waiter_remove(next);
    ms_token_post(next, 1); /* the permit passes to the oldest waiter */
}

bool ms_sched_pool_admit(size_t bytes, bool *cancelled) {
    *cancelled = false;
    if (bytes < ADMIT_BYTES || ms_sched_on_pool_thread() || ms_sched_pool_alone()) {
        return false;
    }
    if (pool.permits < POOL_PERMITS) {
        pool.permits++;
        return true;
    }
    const uint64_t token = ms_token_new(0);
    if (!waiter_add(token)) {
        (void)ms_token_free(token);
        return false;
    }
    uint64_t value = 0;
    uint32_t result = 0;
    (void)ms_token_park(token, -1, &value, &result);
    bool granted = true;
    if ((result & MS_WAIT_CANCELLED) != 0) {
        /* Still queued: no permit was handed over. Otherwise release already passed it to this caller. */
        for (size_t i = 0; i < pool.waiter_count; i++) {
            if (pool.waiters[i] == token) {
                waiter_remove(token);
                granted = false;
                break;
            }
        }
    }
    (void)ms_token_free(token);
    if ((result & MS_WAIT_CANCELLED) != 0) {
        if (granted) {
            ms_sched_pool_release();
        }
        *cancelled = true;
        return false;
    }
    return true;
}
