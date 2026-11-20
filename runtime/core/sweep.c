/* sweep.c: the hooks of the cancellation sweep (`make cancel-sweep`), in the counting runtime only. MS_CANCEL_AT_PARK=n
 * makes the n-th park of the process report a cancellation, as if the parking task had been cancelled there, and
 * MS_PARK_COUNT=1 prints how many parks the run made (entry/start.c). Without MS_ALLOC_STATS the hooks are empty. */
#include "sweep.h"

#ifdef MS_ALLOC_STATS
#include <stdatomic.h>
#include <stdlib.h>

#include "scheduler.h"
#include "unwind.h"

static _Atomic uint64_t parks;
static _Atomic uint64_t target = UINT64_MAX;
static atomic_flag target_read = ATOMIC_FLAG_INIT;
static _Thread_local bool internal_next;

static uint64_t cancel_target(void) {
    if (!atomic_flag_test_and_set(&target_read)) {
        const char *const text = getenv("MS_CANCEL_AT_PARK");
        const unsigned long long value = text != NULL ? strtoull(text, NULL, 10) : 0;
        atomic_store(&target, value != 0 ? value : UINT64_MAX);
    }
    return atomic_load(&target);
}

void ms_sweep_internal(bool on) { internal_next = on; }

bool ms_sweep_cancel_here(void) {
    if (internal_next) {
        internal_next = false;
        return false;
    }
    const bool hit = atomic_fetch_add(&parks, 1) + 1 == cancel_target();
    MsTask *const task = ms_task_running();
    /* A task started under a shield is part of the shielded work, which no cancel reaches. */
    if (hit && (task->flags & MS_TASK_FLAG_BORN_SHIELDED) != 0) {
        return false;
    }
    if (hit) {
        ms_cancel_set_task(1); /* a real cancel stays recorded on the task, and survives shields */
    }
    /* A shielded park does not see a cancel: the request stays pending for the next unshielded park. */
    return hit && !ms_task_shielded(task);
}

uint64_t ms_sweep_parks(void) { return atomic_load(&parks); }

#else

void ms_sweep_internal(bool on) { (void)on; }
bool ms_sweep_cancel_here(void) { return false; }
uint64_t ms_sweep_parks(void) { return 0; }

#endif
