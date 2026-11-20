/* The scheduler of a thread: creation, hooks, the stop request, the clock and teardown. See scheduler.h. */
#include "scheduler.h"

#include "array.h"
#include "ms_rt/sys.h"

enum { MIN_TIMER_LIMIT = 1024 };

static _Thread_local MsSched *thread_sched; /* this thread's scheduler: per-thread state the design names */

MsSched *ms_sched_if_any(void) { return thread_sched; }

MsSched *ms_sched(void) {
    if (thread_sched == NULL) {
        MsSched *const created = msrt_alloc_zeroed(sizeof *created);
        created->timer_limit = MIN_TIMER_LIMIT;
        created->kill_limit = MIN_TIMER_LIMIT;
        created->external_limit = MIN_TIMER_LIMIT;
        thread_sched = created;
    }
    return thread_sched;
}

void ms_sched_set_hooks(const MsSchedHooks *hooks, const MsPollOps *poll) {
    MsSched *const sched = ms_sched();
    sched->hooks = *hooks;
    sched->poll = *poll;
}

uint32_t ms_sched_attach(MsWakeFn wake, void *argument) {
    MsSched *const sched = ms_sched();
    const uint32_t index = ms_isolate_register(wake, argument);
    if (index != MS_NO_ISOLATE) {
        sched->isolate = index;
    }
    return index;
}

int64_t ms_sched_now(void) { return ms_sys_monotonic_ns(); }

void ms_sched_post_completion(uint64_t id, int32_t result, uint32_t kind) {
    (void)kind;
    ms_token_post(id, (uint64_t)(int64_t)result); /* the result sign-extends; the taker casts it back to int32_t */
}

uint8_t ms_sched_stop_request(void) {
    return thread_sched == NULL ? 0 : atomic_load_explicit(&thread_sched->stop_request, memory_order_relaxed);
}

void ms_sched_stop(uint8_t signal) {
    atomic_store_explicit(&ms_sched()->stop_request, signal, memory_order_relaxed);
}

/* Frees a record and what hangs off it. The stack goes to the pool (or is dropped with the regions). */
void ms_task_destroy(MsSched *sched, MsTask *task) {
    if (task->stack != NULL) {
        ms_stacks_release(&sched->stacks, task->stack, task->stack_length);
    }
    if (task->extra != NULL) {
        for (size_t i = 0; i < task->extra->segment_count; i++) {
            ms_stacks_release(&sched->stacks, task->extra->segments[i], MS_STACK_SLOT);
        }
        msrt_free(task->extra->segments);
        msrt_free(task->extra->segment_teb);
        msrt_free(task->extra);
    }
    msrt_free(task->unwind.hdr.cleanups);
    msrt_free(task->unwind.guards);
    ms_fault_text_free(&task->message);
    msrt_free(task);
}

void ms_sched_teardown(void) {
    MsSched *const sched = thread_sched;
    if (sched == NULL) {
        return;
    }
    if (ms_isolate_self() != MS_NO_ISOLATE) {
        ms_isolate_unregister(ms_isolate_self());
    }
    if (sched->hooks.teardown != NULL) {
        sched->hooks.teardown();
    }
    for (size_t i = 0; i < sched->slot_count; i++) {
        if (sched->slots[i].task != NULL) {
            ms_task_destroy(sched, sched->slots[i].task);
        }
    }
    if (sched->zombie_stack != NULL) {
        ms_stacks_release(&sched->stacks, sched->zombie_stack, sched->zombie_stack_length);
    }
    ms_park_free(sched);
    ms_token_free_all(sched);
    ms_stacks_destroy(&sched->stacks);
    msrt_free(sched->slots);
    msrt_free(sched->free_slots);
    msrt_free(sched->ready);
    thread_sched = NULL;
    msrt_free(sched);
}
