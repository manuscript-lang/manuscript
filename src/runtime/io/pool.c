/* pool.c: the blocking pool (see pool.h), on libuv's thread pool.
 *
 * A job is a uv_work_t on the submitting thread's reactor loop. The thread that runs it posts the waiter's token as
 * soon as the function returns, so a wake-up never waits for the loop to run. The record lives until libuv's
 * after-work callback, which only frees it: the callback runs inside the reactor and touches no task state.
 *
 * A wait that times out or is cancelled gives the job up. libuv cancels a job it has not started; the record is then
 * released at once. A running one is abandoned: the thread that finishes it posts nothing and the after-work callback
 * calls the job's release function.
 *
 * The size is libuv's: UV_THREADPOOL_SIZE (default 4), read when the pool first starts and shared with DNS lookups
 * and libuv's own file calls.
 *
 * Admission: a caller about to copy a large payload for a pool job first takes a permit; at most `threads` are out at
 * once and the others park on a token until one is returned. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/io/pool.h"

#include <stdatomic.h>
#include <uv.h>

#include "base/alloc.h"
#include "base/env.h"
#include "runtime/core/isolate.h"
#include "runtime/core/task.h"
#include "runtime/io/reactor_internal.h"

enum {
  DEFAULT_THREADS = 4, /* libuv's default */
  MAX_THREADS = 1024,  /* libuv's limit */
  ADMIT_BYTES = 64 * 1024,
};

typedef enum JobState { JOB_PENDING, JOB_DONE, JOB_ABANDONED } JobState;

typedef struct PoolJob {
  uv_work_t request;
  MsPoolJobFn run;
  MsPoolJobFn release; /* NULL for a shielded job, which is never abandoned */
  void *data;
  uint64_t token;
  _Atomic JobState state;
} PoolJob;

typedef struct Waiter {
  uint64_t token;
  struct Waiter *next;
} Waiter;

static struct {
  uv_once_t once;
  uv_mutex_t lock;                     /* guards the admission fields and the shielded wait */
  uv_cond_t finished;                  /* a job ended (a shielded wait that cannot park blocks on it) */
  Waiter *waiters_head, *waiters_tail; /* callers parked in admit, oldest first */
  size_t threads, permits;
  _Atomic size_t finish_waiters;
} pool = {.once = UV_ONCE_INIT};

static _Thread_local bool on_pool;

/* The thread count libuv will use: UV_THREADPOOL_SIZE read as libuv reads it. */
static size_t configured_threads(void) {
  uint64_t wanted = 0;
  MsString value;
  if (ms_env_get("UV_THREADPOOL_SIZE", &value)) {
    const MsSpan text = ms_string_span(&value);
    for (size_t i = 0; i < text.len && text.ptr[i] >= '0' && text.ptr[i] <= '9' && wanted <= MAX_THREADS; i++) {
      wanted = wanted * 10 + (uint64_t)(text.ptr[i] - '0');
    }
    ms_string_release(&value);
  }
  if (wanted > MAX_THREADS) {
    return MAX_THREADS;
  }
  return wanted > 0 ? (size_t)wanted : DEFAULT_THREADS;
}

static void pool_init(void) {
  pool.threads = configured_threads();
  (void)uv_mutex_init(&pool.lock);
  (void)uv_cond_init(&pool.finished);
}

static void pool_ready(void) { uv_once(&pool.once, pool_init); }

bool ms_pool_on_thread(void) { return on_pool; }

/* Whether the program has one task, so a blocking call can run inline instead of on the pool. */
static bool pool_alone(void) { return ms_task_count() <= 1 || ms_task_others_stalled(); }

/* ---- jobs ---- */

/* Runs on a libuv thread. */
static void on_work(uv_work_t *request) {
  PoolJob *job = request->data;
  on_pool = true;
  job->run(job->data);
  on_pool = false;
  JobState expected = JOB_PENDING;
  if (atomic_compare_exchange_strong(&job->state, &expected, JOB_DONE)) {
    ms_token_post_remote(job->token, 1);
  }
  if (atomic_load(&pool.finish_waiters) > 0) {
    uv_mutex_lock(&pool.lock);
    uv_cond_broadcast(&pool.finished);
    uv_mutex_unlock(&pool.lock);
  }
}

/* Runs inside the reactor loop, after the job ended or libuv cancelled it before it started. */
static void on_work_done(uv_work_t *request, int status) {
  PoolJob *job = request->data;
  if (status == 0 && atomic_load(&job->state) == JOB_ABANDONED) {
    job->release(job->data);
  }
  ms_free(job);
}

/* Starts `job` on libuv's pool; false when this thread has no reactor, and the caller runs it inline. */
static bool submit(PoolJob *job) {
  pool_ready();
  MsIoReactor *const reactor = ms_io_reactor_current();
  if (reactor == NULL) {
    return false;
  }
  job->request.data = job;
  return uv_queue_work(ms_io_reactor_loop(reactor), &job->request, on_work, on_work_done) == 0;
}

static PoolJob *job_new(MsPoolJobFn run, MsPoolJobFn release, void *data) {
  PoolJob *job = ms_alloc_zeroed(sizeof *job);
  job->token = ms_token_new(MS_TOKEN_REMOTE);
  job->run = run;
  job->release = release;
  job->data = data;
  return job;
}

/* Ends the wait for an unfinished job: libuv drops one it has not started, a running one is abandoned. False when the
 * job finished meanwhile and the caller takes it. */
static bool give_up(PoolJob *job) {
  if (uv_cancel((uv_req_t *)&job->request) == 0) {
    (void)ms_token_free(job->token);
    job->release(job->data); /* on_work_done frees the record */
    return true;
  }
  JobState expected = JOB_PENDING;
  if (!atomic_compare_exchange_strong(&job->state, &expected, JOB_ABANDONED)) {
    return false;
  }
  (void)ms_token_free(job->token);
  return true;
}

MsPoolWait ms_pool_run(MsPoolJobFn run, MsPoolJobFn release, void *data, int64_t timeout_ns) {
  PoolJob *job = job_new(run, release, data);
  if (!submit(job)) {
    (void)ms_token_free(job->token);
    ms_free(job);
    run(data);
    return MS_POOL_DONE;
  }
  uint64_t value = 0;
  uint32_t got = 0;
  (void)ms_token_park(job->token, timeout_ns, &value, &got);
  if ((got & (MS_WAIT_TIMEOUT | MS_WAIT_CANCELLED)) != 0 && give_up(job)) {
    return (got & MS_WAIT_CANCELLED) != 0 ? MS_POOL_CANCELLED : MS_POOL_TIMED_OUT;
  }
  (void)ms_token_free(job->token);
  if ((got & MS_WAIT_CANCELLED) != 0) {
    release(data); /* the cancelled caller does not take the data back */
    return MS_POOL_CANCELLED;
  }
  return MS_POOL_DONE;
}

MsPoolWait ms_pool_run_shielded(MsPoolJobFn run, void *data) {
  PoolJob *job = job_new(run, NULL, data);
  if (!submit(job)) {
    (void)ms_token_free(job->token);
    ms_free(job);
    run(data);
    return MS_POOL_DONE;
  }
  uint64_t value = 0;
  uint32_t got = 0;
  (void)ms_token_park(job->token, -1, &value, &got);
  if ((got & MS_WAIT_CANCELLED) != 0) {
    /* A pending stop ends every park at once: block the thread until the job is done. */
    uv_mutex_lock(&pool.lock);
    atomic_fetch_add(&pool.finish_waiters, 1);
    while (atomic_load(&job->state) != JOB_DONE) {
      uv_cond_wait(&pool.finished, &pool.lock);
    }
    atomic_fetch_sub(&pool.finish_waiters, 1);
    uv_mutex_unlock(&pool.lock);
  }
  (void)ms_token_free(job->token);
  return (got & MS_WAIT_CANCELLED) != 0 ? MS_POOL_CANCELLED : MS_POOL_DONE;
}

/* ---- admission ---- */

static bool waiter_remove(uint64_t token) {
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
    ms_free(at);
    return true;
  }
  return false;
}

bool ms_pool_admit(size_t bytes, bool *cancelled) {
  *cancelled = false;
  if (bytes < ADMIT_BYTES || ms_pool_on_thread() || pool_alone()) {
    return false;
  }
  pool_ready();
  uv_mutex_lock(&pool.lock);
  if (pool.permits < pool.threads) {
    pool.permits++;
    uv_mutex_unlock(&pool.lock);
    return true;
  }
  Waiter *waiter = ms_alloc_zeroed(sizeof *waiter);
  const uint64_t token = ms_token_new(MS_TOKEN_REMOTE);
  waiter->token = token;
  if (pool.waiters_tail != NULL) {
    pool.waiters_tail->next = waiter;
  } else {
    pool.waiters_head = waiter;
  }
  pool.waiters_tail = waiter;
  uv_mutex_unlock(&pool.lock);

  uint64_t value = 0;
  uint32_t got = 0;
  (void)ms_token_park(token, -1, &value, &got);
  const bool was_cancelled = (got & MS_WAIT_CANCELLED) != 0;
  bool granted = true;
  if (was_cancelled) {
    /* Still queued: leave. Otherwise release already handed this caller a permit, which it passes on below. */
    uv_mutex_lock(&pool.lock);
    granted = !waiter_remove(token);
    uv_mutex_unlock(&pool.lock);
  }
  (void)ms_token_free(token);
  if (was_cancelled) {
    if (granted) {
      ms_pool_release();
    }
    *cancelled = true;
    return false;
  }
  return true;
}

void ms_pool_release(void) {
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
    ms_token_post_remote(next->token, 1);
    ms_free(next);
  }
}
