/* pool.c: the blocking pool for calls the kernel cannot wait on (file-system calls, regular-file reads and writes,
 * console and pipe reads on Windows). A few threads, started on demand, run jobs from one queue; the submitting task
 * parks on a remote token that the thread posts when the job ends. `MS_POOL_THREADS` sets the thread count
 * (default 4).
 *
 * Memory: the runtime thread's allocator frees only what the runtime thread allocated, so a job's record is
 * allocated and freed on the runtime thread, and a job function runs where nothing may call into the runtime.
 *
 * A wait that times out or is cancelled gives the job up. A queued job is removed and released at once. A running
 * one is abandoned: its token is freed, and the thread that finishes it hands it back on a list the runtime thread
 * empties at the next submit, calling the job's release function there.
 *
 * Admission: a caller about to copy a large payload for a pool job first takes a permit; at most `threads` are out
 * at once and the others park on a token until one is returned. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include <stdatomic.h>
#include <stdlib.h>
#include <uv.h>

#include "ms_sched.h"

enum {
    TOKEN_REMOTE = 1,
    DEFAULT_THREADS = 4,
    MAX_THREADS = 64,
    STACK_BYTES = 512 * 1024,
    ADMIT_BYTES = 64 * 1024,
};

typedef enum { JOB_QUEUED, JOB_RUNNING, JOB_DONE } JobState;

typedef struct PoolJob {
    MsSchedJobFn run, release;
    void *data;
    uint64_t token;
    JobState state; /* guarded by pool.lock */
    bool abandoned; /* the waiter gave up; guarded by pool.lock */
    struct PoolJob *next;
} PoolJob;

typedef struct Waiter {
    uint64_t token;
    struct Waiter *next;
} Waiter;

static struct {
    uv_once_t once;
    uv_mutex_t lock;
    uv_cond_t wake;     /* a job is queued */
    uv_cond_t finished; /* a job ended (a shielded wait that cannot park blocks on it) */
    PoolJob *head, *tail;       /* the queue */
    PoolJob *done;              /* abandoned jobs that ended, for the runtime thread to release */
    Waiter *waiters_head, *waiters_tail; /* callers parked in admit, oldest first */
    size_t threads, started, idle, finish_waiters, permits;
} pool = {.once = UV_ONCE_INIT};

static _Thread_local bool on_pool;

static void pool_init(void) {
    char text[16];
    size_t size = sizeof text;
    long wanted = uv_os_getenv("MS_POOL_THREADS", text, &size) == 0 ? strtol(text, NULL, 10) : 0;
    if (wanted > MAX_THREADS) {
        wanted = MAX_THREADS;
    }
    pool.threads = wanted > 0 ? (size_t)wanted : DEFAULT_THREADS;
    (void)uv_mutex_init(&pool.lock);
    (void)uv_cond_init(&pool.wake);
    (void)uv_cond_init(&pool.finished);
}

static void pool_ready(void) { uv_once(&pool.once, pool_init); }

bool ms_sched_on_pool_thread(void) { return on_pool; }

bool ms_sched_pool_alone(void) { return msrt_task_count() <= 1 || msrt_task_others_stalled(); }

/* ---- the threads ---- */

static void worker(void *unused) {
    (void)unused;
    on_pool = true;
    uv_mutex_lock(&pool.lock);
    for (;;) {
        while (pool.head == NULL) {
            pool.idle++;
            uv_cond_wait(&pool.wake, &pool.lock);
            pool.idle--;
        }
        PoolJob *job = pool.head;
        pool.head = job->next;
        if (pool.head == NULL) {
            pool.tail = NULL;
        }
        job->next = NULL;
        job->state = JOB_RUNNING;
        uv_mutex_unlock(&pool.lock);
        job->run(job->data);
        uv_mutex_lock(&pool.lock);
        job->state = JOB_DONE;
        if (job->abandoned) {
            job->next = pool.done;
            pool.done = job;
        } else {
            msrt_token_post_remote(job->token, 1);
        }
        if (pool.finish_waiters > 0) {
            uv_cond_broadcast(&pool.finished);
        }
    }
}

/* Starts a thread when every one is busy and there is room. Called with the lock held. */
static void grow(void) {
    if (pool.idle > 0 || pool.started >= pool.threads) {
        return;
    }
    uv_thread_t thread;
    const uv_thread_options_t options = {.flags = UV_THREAD_HAS_STACK_SIZE, .stack_size = STACK_BYTES};
    if (uv_thread_create_ex(&thread, &options, worker, NULL) == 0) {
        pool.started++;
    }
}

/* ---- jobs ---- */

/* Releases the data of abandoned jobs that ended. Runs on the runtime thread. */
static void reap(void) {
    uv_mutex_lock(&pool.lock);
    PoolJob *ended = pool.done;
    pool.done = NULL;
    uv_mutex_unlock(&pool.lock);
    while (ended != NULL) {
        PoolJob *next = ended->next;
        ended->release(ended->data);
        free(ended);
        ended = next;
    }
}

/* Queues run(data); NULL when no record or token could be made, where the caller runs the job inline. */
static PoolJob *submit(MsSchedJobFn run, MsSchedJobFn release, void *data) {
    pool_ready();
    reap();
    PoolJob *job = calloc(1, sizeof *job);
    if (job == NULL) {
        return NULL;
    }
    job->token = msrt_token_new(TOKEN_REMOTE);
    if (job->token == 0) {
        free(job);
        return NULL;
    }
    job->run = run;
    job->release = release;
    job->data = data;
    uv_mutex_lock(&pool.lock);
    if (pool.tail != NULL) {
        pool.tail->next = job;
    } else {
        pool.head = job;
    }
    pool.tail = job;
    grow();
    uv_cond_signal(&pool.wake);
    uv_mutex_unlock(&pool.lock);
    return job;
}

/* Ends the wait for an unfinished job: a queued one is removed and released, a running one is abandoned. False when
 * the job finished meanwhile and the caller takes it. */
static bool give_up(PoolJob *job) {
    uv_mutex_lock(&pool.lock);
    if (job->state == JOB_DONE) {
        uv_mutex_unlock(&pool.lock);
        return false;
    }
    bool queued = false;
    if (job->state == JOB_QUEUED) {
        PoolJob *before = NULL;
        for (PoolJob *at = pool.head; at != NULL; before = at, at = at->next) {
            if (at != job) {
                continue;
            }
            if (before != NULL) {
                before->next = at->next;
            } else {
                pool.head = at->next;
            }
            if (pool.tail == at) {
                pool.tail = before;
            }
            queued = true;
            break;
        }
    }
    job->abandoned = !queued;
    uv_mutex_unlock(&pool.lock);
    msrt_token_free(job->token);
    if (queued) {
        job->release(job->data);
        free(job);
    }
    return true;
}

static void job_end(PoolJob *job) {
    msrt_token_free(job->token);
    free(job);
}

MsSchedWait ms_sched_pool_run(MsSchedJobFn run, MsSchedJobFn release, void *data, int64_t timeout_ns) {
    PoolJob *job = submit(run, release, data);
    if (job == NULL) {
        run(data);
        return MS_SCHED_DONE;
    }
    uint64_t value = 0;
    const uint32_t got = msrt_token_park(job->token, timeout_ns, &value);
    if ((got & (MS_WAIT_TIMEOUT | MS_WAIT_CANCELLED)) != 0 && give_up(job)) {
        return (got & MS_WAIT_CANCELLED) != 0 ? MS_SCHED_CANCELLED : MS_SCHED_TIMED_OUT;
    }
    job_end(job);
    if ((got & MS_WAIT_CANCELLED) != 0) {
        release(data); /* the cancelled caller does not take the data back */
        return MS_SCHED_CANCELLED;
    }
    return MS_SCHED_DONE;
}

MsSchedWait ms_sched_pool_run_shielded(MsSchedJobFn run, void *data) {
    PoolJob *job = submit(run, NULL, data);
    if (job == NULL) {
        run(data);
        return MS_SCHED_DONE;
    }
    ms_sched_task_pin(true); /* the data may lie on this task's stack, which must keep its pages while the job reads it */
    uint64_t value = 0;
    const uint32_t got = msrt_token_park(job->token, -1, &value);
    if ((got & MS_WAIT_CANCELLED) != 0) {
        /* A pending stop ends every park at once: block the thread until the job is done. */
        uv_mutex_lock(&pool.lock);
        while (job->state != JOB_DONE) {
            pool.finish_waiters++;
            uv_cond_wait(&pool.finished, &pool.lock);
            pool.finish_waiters--;
        }
        uv_mutex_unlock(&pool.lock);
    }
    ms_sched_task_pin(false);
    job_end(job);
    return (got & MS_WAIT_CANCELLED) != 0 ? MS_SCHED_CANCELLED : MS_SCHED_DONE;
}

/* ---- admission ---- */

static void waiter_remove(uint64_t token, bool *found) {
    Waiter *before = NULL;
    for (Waiter *at = pool.waiters_head; at != NULL; before = at, at = at->next) {
        if (at->token != token) {
            continue;
        }
        if (before != NULL) {
            before->next = at->next;
        } else {
            pool.waiters_head = at->next;
        }
        if (pool.waiters_tail == at) {
            pool.waiters_tail = before;
        }
        free(at);
        *found = true;
        return;
    }
}

bool ms_sched_pool_admit(size_t bytes, bool *cancelled) {
    *cancelled = false;
    if (bytes < ADMIT_BYTES || ms_sched_on_pool_thread() || ms_sched_pool_alone()) {
        return false;
    }
    pool_ready();
    uv_mutex_lock(&pool.lock);
    if (pool.permits < pool.threads) {
        pool.permits++;
        uv_mutex_unlock(&pool.lock);
        return true;
    }
    Waiter *waiter = calloc(1, sizeof *waiter);
    const uint64_t token = msrt_token_new(TOKEN_REMOTE);
    if (waiter == NULL || token == 0) {
        free(waiter);
        uv_mutex_unlock(&pool.lock);
        return false; /* no permit: the copy proceeds unbounded, as for a small payload */
    }
    waiter->token = token;
    if (pool.waiters_tail != NULL) {
        pool.waiters_tail->next = waiter;
    } else {
        pool.waiters_head = waiter;
    }
    pool.waiters_tail = waiter;
    uv_mutex_unlock(&pool.lock);

    uint64_t value = 0;
    const uint32_t got = msrt_token_park(token, -1, &value);
    bool granted = true;
    if ((got & MS_WAIT_CANCELLED) != 0) {
        /* Still queued: leave. Otherwise release already handed this caller a permit, which it passes on below. */
        bool left = false;
        uv_mutex_lock(&pool.lock);
        waiter_remove(token, &left);
        uv_mutex_unlock(&pool.lock);
        granted = !left;
    }
    msrt_token_free(token);
    if ((got & MS_WAIT_CANCELLED) != 0) {
        if (granted) {
            ms_sched_pool_release();
        }
        *cancelled = true;
        return false;
    }
    return true;
}

void ms_sched_pool_release(void) {
    uv_mutex_lock(&pool.lock);
    Waiter *next = pool.waiters_head;
    if (next != NULL) {
        pool.waiters_head = next->next;
        if (pool.waiters_head == NULL) {
            pool.waiters_tail = NULL;
        }
    } else if (pool.permits > 0) {
        pool.permits--;
    }
    uv_mutex_unlock(&pool.lock);
    if (next != NULL) {
        msrt_token_post_remote(next->token, 1);
        free(next);
    }
}
