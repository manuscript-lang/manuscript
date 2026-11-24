/* The worker isolates. See worker.h. */
#include "runtime/core/worker.h"

#include <stdatomic.h>

#include "base/alloc.h"
#include "runtime/core/isolate.h"
#include "runtime/core/release.h"
#include "runtime/core/scheduler.h"
#include "runtime/core/stats.h"
#include "runtime/sys/sys.h"

enum { WORKER_STACK = 0, SPREAD_WEIGHT = 1024 }; /* a spread start outweighs any number of tasks */

typedef struct Worker {
  MsSysThread *thread;
  _Atomic uint32_t isolate; /* MS_NO_ISOLATE until its thread registered */
  _Atomic uint32_t failed;  /* the thread ended without registering */
} Worker;

/* Process-wide: written by the main isolate (configure, start, shutdown), read by threads only through `limit`. */
static MsWorkerEnv config;
static _Atomic uint32_t limit_cache = 1;
static _Atomic bool stress_on;
static Worker workers[MS_MAX_ISOLATES];
static _Atomic uint32_t started;
static _Atomic uint32_t spawning;

void ms_workers_configure(const MsWorkerEnv *env) {
  config = *env;
  config.hooks.service = true;
  atomic_store(&stress_on, env->stress);
  ms_workers_set_limit(env->limit);
}

bool ms_workers_stress(void) { return atomic_load_explicit(&stress_on, memory_order_relaxed); }

int64_t ms_workers_own_beat(void) {
  return ms_workers_stress() ? MS_WORKER_STRESS_OWN_BEAT_NS : MS_WORKER_OWN_BEAT_NS;
}

void ms_workers_set_limit(uint32_t limit) {
  uint32_t bounded = limit > MS_MAX_ISOLATES ? MS_MAX_ISOLATES : limit;
  const uint32_t floor = ms_workers_stress() ? 2 : 1; /* stress mode needs a thread to take the work */
  if (bounded < floor) {
    bounded = floor;
  }
  atomic_store(&limit_cache, bounded);
}

uint32_t ms_workers_limit(void) { return atomic_load_explicit(&limit_cache, memory_order_relaxed); }

/* The worker's only task: it waits for the stop request while the scheduler's idle hook runs promises. */
static void root_entry(void *argument) {
  (void)argument;
  const uint64_t token = ms_token_new(0);
  uint64_t value = 0;
  uint32_t result = 0;
  for (;;) {
    ms_stats_park_internal(true); /* no program awaits this park */
    const MsTokenStatus status = token != 0 ? ms_token_park(token, -1, &value, &result) : MS_TOKEN_NO_SUCH_TOKEN;
    if (status != MS_TOKEN_OK || result == MS_WAIT_CANCELLED) {
      break;
    }
    ms_stats_park_internal(false);
    /* woken by nothing: wait again */
  }
}

static void worker_main(void *argument) {
  Worker *const self = argument;
  MsPollOps poll = {0};
  MsWakeFn wake = NULL;
  void *wake_argument = NULL;
  if (!config.setup(&poll, &wake, &wake_argument)) {
    atomic_store(&self->failed, 1);
    return;
  }
  ms_sched_set_hooks(&config.hooks, &poll);
  const uint32_t index = ms_sched_attach(wake, wake_argument);
  if (index == MS_NO_ISOLATE) {
    atomic_store(&self->failed, 1);
    ms_sched_teardown();
    return;
  }
  atomic_store_explicit(&self->isolate, index, memory_order_release);
  uint8_t outcome = 0;
  MsFaultText message = {0};
  (void)ms_task_run_main(root_entry, NULL, 0, &outcome, &message);
  ms_fault_text_free(&message);
  ms_sched_teardown();
  ms_quiesce_run();
  if (config.finish != NULL) {
    config.finish();
  }
}

static _Atomic uint32_t assigned[MS_MAX_ISOLATES]; /* spread starts placed on each isolate: long-lived work, so never taken back */

/* Starts one thread and waits until its isolate is registered, so the caller can send it work. */
static void start_one_blocking(void) {
  if (atomic_exchange(&spawning, 1) != 0) {
    return;
  }
  const uint32_t count = atomic_load(&started);
  if (count + 1 < ms_workers_limit() && count < MS_MAX_ISOLATES) {
    Worker *const worker = &workers[count];
    atomic_store(&worker->isolate, MS_NO_ISOLATE);
    atomic_store(&worker->failed, 0);
    worker->thread = ms_sys_thread_spawn(WORKER_STACK, worker_main, worker);
    if (worker->thread != NULL) {
      atomic_fetch_add(&started, 1);
      while (atomic_load_explicit(&worker->isolate, memory_order_acquire) == MS_NO_ISOLATE &&
             atomic_load(&worker->failed) == 0) {
        ms_sys_yield();
      }
    }
  }
  atomic_store(&spawning, 0);
}

/* Waits until every thread started so far (by this pick or by an earlier, non-blocking nudge) has registered its
 * isolate: a pick that scored only the registered ones would put several spread starts on the main thread. */
static void await_started(void) {
  const uint32_t count = atomic_load(&started);
  for (uint32_t i = 0; i < count && i < MS_MAX_ISOLATES; i++) {
    while (atomic_load_explicit(&workers[i].isolate, memory_order_acquire) == MS_NO_ISOLATE &&
           atomic_load(&workers[i].failed) == 0) {
      ms_sys_yield();
    }
  }
}

uint32_t ms_workers_spread_pick(void) {
  if (ms_workers_limit() <= 1) {
    return MS_NO_ISOLATE;
  }
  if (ms_isolate_count() < ms_workers_limit()) {
    start_one_blocking();
  }
  await_started();
  uint32_t best = MS_NO_ISOLATE;
  uint32_t best_score = UINT32_MAX;
  for (uint32_t i = 0; i < MS_MAX_ISOLATES; i++) {
    if (!ms_isolate_live(i)) {
      continue;
    }
    const uint32_t score = atomic_load(&assigned[i]) * SPREAD_WEIGHT + ms_isolate_load(i);
    if (score < best_score) {
      best = i;
      best_score = score;
    }
  }
  if (best != MS_NO_ISOLATE) {
    atomic_fetch_add(&assigned[best], 1);
  }
  return best;
}

void ms_workers_nudge(void) {
  /* The queue push before this call and a looker's last look after it stops looking are sequentially consistent
   * (the queue's count and the looking count): the push sees the looker, or the looker sees the push. */
  if (!ms_isolate_any_looking()) {
    ms_workers_nudge_next();
  }
}

void ms_workers_nudge_next(void) {
  if (ms_workers_limit() <= 1 || ms_isolate_wake_one(ms_isolate_self())) {
    return;
  }
  const uint32_t count = atomic_load(&started);
  if (count + 1 >= ms_workers_limit() || atomic_exchange(&spawning, 1) != 0) {
    return;
  }
  if (count < MS_MAX_ISOLATES) {
    Worker *const worker = &workers[count];
    atomic_store(&worker->isolate, MS_NO_ISOLATE);
    atomic_store(&worker->failed, 0);
    worker->thread = ms_sys_thread_spawn(WORKER_STACK, worker_main, worker);
    if (worker->thread != NULL) {
      atomic_fetch_add(&started, 1);
    }
  }
  atomic_store(&spawning, 0);
}

void ms_workers_shutdown(void) {
  const uint32_t count = atomic_load(&started);
  for (uint32_t i = 0; i < count; i++) {
    /* The worker may not have registered yet: wait for it, then stop it by mail. */
    uint32_t index = MS_NO_ISOLATE;
    while ((index = atomic_load_explicit(&workers[i].isolate, memory_order_acquire)) == MS_NO_ISOLATE &&
         atomic_load(&workers[i].failed) == 0) {
      ms_sys_yield();
    }
    MsMail *const mail = ms_alloc(sizeof *mail);
    *mail = (MsMail){.kind = MS_MAIL_STOP, .a = 15};
    if (index == MS_NO_ISOLATE || !ms_isolate_post(index, mail)) {
      ms_free(mail);
    }
  }
  for (uint32_t i = 0; i < count; i++) {
    ms_sys_thread_join(workers[i].thread);
  }
  atomic_store(&started, 0);
}
