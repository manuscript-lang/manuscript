/* pool.c: the blocking pool (see pool.h).
 *
 * A wait that times out or is cancelled gives the job up. A queued job is removed and released at once. A running one
 * is abandoned: its token is freed, and the thread that finishes it hands it back on a list the submitting thread
 * empties at the next submit, calling the job's release function there.
 *
 * Admission: a caller about to copy a large payload for a pool job first takes a permit; at most `threads` are out at
 * once and the others park on a token until one is returned. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/io/pool.h"

#include <uv.h>

#include "base/alloc.h"
#include "base/env.h"
#include "runtime/core/isolate.h"
#include "runtime/core/task.h"

enum {
  DEFAULT_THREADS = 4,
  MAX_THREADS = 64,
  STACK_BYTES = 512 * 1024,
  ADMIT_BYTES = 64 * 1024,
};

typedef enum JobState { JOB_QUEUED, JOB_RUNNING, JOB_DONE } JobState;

typedef struct PoolJob {
  MsPoolJobFn run;
  MsPoolJobFn release; /* NULL for a shielded job, which is never abandoned */
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
  uv_cond_t wake;                      /* a job is queued */
  uv_cond_t finished;                  /* a job ended (a shielded wait that cannot park blocks on it) */
  PoolJob *head, *tail;                /* the queue */
  PoolJob *done;                       /* abandoned jobs that ended, for the submitting thread to release */
  Waiter *waiters_head, *waiters_tail; /* callers parked in admit, oldest first */
  size_t threads, started, idle, finish_waiters, permits;
} pool = {.once = UV_ONCE_INIT};

static _Thread_local bool on_pool;

static void pool_init(void) {
  uint64_t wanted = 0;
  MsString value;
  if (ms_env_get("MS_POOL_THREADS", &value)) {
    const MsSpan text = ms_string_span(&value);
    for (size_t i = 0; i < text.len && text.ptr[i] >= '0' && text.ptr[i] <= '9' && wanted <= MAX_THREADS; i++) {
      wanted = wanted * 10 + (uint64_t)(text.ptr[i] - '0');
    }
    ms_string_release(&value);
  }
  if (wanted > MAX_THREADS) {
    wanted = MAX_THREADS;
  }
  pool.threads = wanted > 0 ? (size_t)wanted : DEFAULT_THREADS;
  (void)uv_mutex_init(&pool.lock);
  (void)uv_cond_init(&pool.wake);
  (void)uv_cond_init(&pool.finished);
}

static void pool_ready(void) { uv_once(&pool.once, pool_init); }

bool ms_pool_on_thread(void) { return on_pool; }

/* Whether the program has one task, so a blocking call can run inline instead of on the pool. */
static bool pool_alone(void) { return ms_task_count() <= 1 || ms_task_others_stalled(); }

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
      ms_token_post_remote(job->token, 1);
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

/* Releases the data of abandoned jobs that ended. Runs on the submitting thread. */
static void reap(void) {
  uv_mutex_lock(&pool.lock);
  PoolJob *ended = pool.done;
  pool.done = NULL;
  uv_mutex_unlock(&pool.lock);
  while (ended != NULL) {
    PoolJob *next = ended->next;
    ended->release(ended->data);
    ms_free(ended);
    ended = next;
  }
}

static PoolJob *submit(MsPoolJobFn run, MsPoolJobFn release, void *data) {
  pool_ready();
  reap();
  PoolJob *job = ms_alloc_zeroed(sizeof *job);
  job->token = ms_token_new(MS_TOKEN_REMOTE);
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

/* Removes `job` from the queue; false when it is not there (running or done). Called with the lock held. */
static bool dequeue(PoolJob *job) {
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
    return true;
  }
  return false;
}

/* Ends the wait for an unfinished job: a queued one is removed and released, a running one is abandoned. False when the
 * job finished meanwhile and the caller takes it. */
static bool give_up(PoolJob *job) {
  uv_mutex_lock(&pool.lock);
  if (job->state == JOB_DONE) {
    uv_mutex_unlock(&pool.lock);
    return false;
  }
  const bool queued = job->state == JOB_QUEUED && dequeue(job);
  job->abandoned = !queued;
  uv_mutex_unlock(&pool.lock);
  (void)ms_token_free(job->token);
  if (queued) {
    job->release(job->data);
    ms_free(job);
  }
  return true;
}

static void job_end(PoolJob *job) {
  (void)ms_token_free(job->token);
  ms_free(job);
}

MsPoolWait ms_pool_run(MsPoolJobFn run, MsPoolJobFn release, void *data, int64_t timeout_ns) {
  PoolJob *job = submit(run, release, data);
  uint64_t value = 0;
  uint32_t got = 0;
  (void)ms_token_park(job->token, timeout_ns, &value, &got);
  if ((got & (MS_WAIT_TIMEOUT | MS_WAIT_CANCELLED)) != 0 && give_up(job)) {
    return (got & MS_WAIT_CANCELLED) != 0 ? MS_POOL_CANCELLED : MS_POOL_TIMED_OUT;
  }
  job_end(job);
  if ((got & MS_WAIT_CANCELLED) != 0) {
    release(data); /* the cancelled caller does not take the data back */
    return MS_POOL_CANCELLED;
  }
  return MS_POOL_DONE;
}

MsPoolWait ms_pool_run_shielded(MsPoolJobFn run, void *data) {
  PoolJob *job = submit(run, NULL, data);
  uint64_t value = 0;
  uint32_t got = 0;
  (void)ms_token_park(job->token, -1, &value, &got);
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
  job_end(job);
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
