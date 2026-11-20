/* The worker isolates. See worker.h. */
#include "worker.h"

#include <stdatomic.h>

#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"
#include "scheduler.h"
#include "sweep.h"

enum { WORKER_STACK = 0 };

typedef struct Worker {
    MsSysThread *thread;
    _Atomic uint32_t isolate; /* MS_NO_ISOLATE until its thread registered */
    _Atomic uint32_t failed;  /* the thread ended without registering */
} Worker;

/* Process-wide: written by the main isolate (configure, start, shutdown), read by threads only through `limit`. */
static MsWorkerEnv config;
static _Atomic uint32_t limit_cache = 1;
static Worker workers[MS_MAX_ISOLATES];
static _Atomic uint32_t started;
static _Atomic uint32_t spawning;

void ms_workers_configure(const MsWorkerEnv *env) {
    config = *env;
    config.hooks.service = true;
    atomic_store(&limit_cache, env->limit < 1 ? 1 : env->limit);
}

void ms_workers_set_limit(uint32_t limit) {
    uint32_t bounded = limit > MS_MAX_ISOLATES ? MS_MAX_ISOLATES : limit;
    if (bounded < 1) {
        bounded = 1;
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
        ms_sweep_internal(true); /* the scheduler's own wait, not an await point of the program */
        const MsTokenStatus status = token != 0 ? ms_token_park(token, -1, &value, &result) : MS_TOKEN_NO_SUCH_TOKEN;
        ms_sweep_internal(false);
        if (status != MS_TOKEN_OK || result == MS_WAIT_CANCELLED) {
            break;
        }
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
    msrt_free(message.bytes);
    ms_sched_teardown();
    if (config.finish != NULL) {
        config.finish();
    }
}

void ms_workers_nudge(void) {
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
        MsMail *const mail = msrt_alloc(sizeof *mail);
        *mail = (MsMail){.kind = MS_MAIL_STOP, .a = 15};
        if (index == MS_NO_ISOLATE || !ms_isolate_post(index, mail)) {
            msrt_free(mail);
        }
    }
    for (uint32_t i = 0; i < count; i++) {
        ms_sys_thread_join(workers[i].thread);
    }
    atomic_store(&started, 0);
}
