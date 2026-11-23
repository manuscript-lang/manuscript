/* worker.h: the isolates that run queued promises beside the main one.
 *
 * A program starts as one isolate. promise(fn) queues its work (queue.h); when nobody is idle to take it, a worker
 * isolate starts, up to the limit (the core count, or MS_THREADS). A worker is an OS thread with its own
 * scheduler, promise table and poller; its only task of its own waits for the stop request, and its scheduler's
 * idle hook takes the oldest queued promise of another isolate once it is older than the beat.
 */
#ifndef MS_RUNTIME_CORE_WORKER_H
#define MS_RUNTIME_CORE_WORKER_H

#include <stdbool.h>
#include <stdint.h>

#include "runtime/core/isolate.h"
#include "runtime/core/task.h"

/* How long a promise waits in its creator's queue before another isolate may take it: its creator's waiter usually
 * runs it first, and a task start costs more than waiting this long. */
#define MS_WORKER_BEAT_NS 20000
/* How long an isolate that has nothing else to do lets its own queued promise wait for a thief before running it. */
#define MS_WORKER_OWN_BEAT_NS (50 * MS_WORKER_BEAT_NS)

/* Stress mode (MS_SCHED_STRESS=1): a promise never runs inline on the isolate that made it. Its start is queued
 * already aged, so the first idle isolate takes it, and its own isolate waits this long for a thief before it runs
 * the start itself. At least two isolates exist, so a thief always can. Placement is a rule, so a failure reproduces. */
#define MS_WORKER_STRESS_OWN_BEAT_NS (500 * MS_WORKER_BEAT_NS)

/* What a worker needs from the layer above, supplied before the first promise is queued. */
typedef struct MsWorkerEnv {
  bool stress;         /* stress mode, see MS_WORKER_STRESS_OWN_BEAT_NS */
  uint32_t limit;      /* isolates in all, the main one included; 1 runs everything on the main isolate */
  MsSchedHooks hooks;  /* the hooks of a worker's scheduler (ms_promise_hooks fills the promise ones) */
  /* Runs on the worker's thread: opens its poller and says how to wake it. False when it cannot. */
  bool (*setup)(MsPollOps *poll, MsWakeFn *wake, void **wake_argument);
  /* Runs on the worker's thread after its scheduler ended. May be NULL. */
  void (*finish)(void);
} MsWorkerEnv;

void ms_workers_configure(const MsWorkerEnv *env) MS_NONNULL;
/* Sets the most isolates the program starts (at least 1, at most MS_MAX_ISOLATES); those started keep running. */
void ms_workers_set_limit(uint32_t limit);
/* Whether stress mode is on. */
bool ms_workers_stress(void);
/* How long an isolate lets its own queued promise wait for a thief. */
int64_t ms_workers_own_beat(void);
/* Isolates the program may use (1 until configured). */
uint32_t ms_workers_limit(void);
/* The isolate a spread start runs on: the least loaded one, after starting a thread when fewer than the limit run;
 * MS_NO_ISOLATE when only one thread is allowed. */
uint32_t ms_workers_spread_pick(void);
/* Work was queued: unless an isolate is already looking for work, wakes a sleeping isolate, or starts a worker when
 * none sleeps and the limit allows. */
void ms_workers_nudge(void);
/* An isolate took queued work and more is waiting: gets the next isolate looking, as ms_workers_nudge does when
 * nobody looks. */
void ms_workers_nudge_next(void);

/* The longest a looking isolate rests between looks, and the looks it makes with every queue empty before it
 * sleeps for good. A look that takes nothing doubles the rest from the beat up to this. */
#define MS_WORKER_LOOK_MAX_NS (10 * MS_WORKER_BEAT_NS)
#define MS_WORKER_EMPTY_LOOKS 20
/* Ends every worker and waits for them. Call from the main isolate before it ends. */
void ms_workers_shutdown(void);

#endif
