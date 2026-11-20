/* The calls of ms_sched.h that need the scheduler of this thread, for the natives of runtime/std and runtime/net:
 * whether a stop request or a read limit is pending, the pin of a task's stack lent to a pool job, and the post any
 * thread may make to a token (msrt_token_post_remote, the program ABI over ms_token_post_remote). The blocking
 * pool itself is runtime/std/pool.c; standard output is stdout.c; the Windows pipes are runtime/io/windows/sched.c. */
#include <stdatomic.h>

#include "ms_sched.h"
#include "scheduler.h"
#include "isolate.h"
#include "task.h"
#include "unwind.h"

bool ms_sched_cancel_pending(void) { return ms_cancel_flag() != 0; }

void ms_sched_stop_hold(void) { ms_stop_shield_enter(); }

void ms_sched_stop_release(void) { ms_stop_shield_exit(); }

int64_t ms_sched_defer_deadline(void) { return ms_task_defer_deadline(); }

bool ms_sched_read_limit_passed(void) { return ms_task_read_limit_passed(); }

/* The Rust scheduler freezes the stack of a parked task to save memory, so a pool job that reads a caller's frame
 * needs the task pinned. This scheduler never freezes a stack, so there is nothing to hold off; count here if it ever
 * reclaims the stack of a parked task. */
void ms_sched_task_pin(bool lend) { (void)lend; }

/* Native state that one thread alone may touch (the Rust session of a network stream, the terminal): promises started
 * on a thread holding some run there, never on another isolate's. Streams count themselves on the thread that
 * last used them; main-only state pins the main thread for good. Goes away with the Rust natives (ms-std-net). */
static _Atomic int32_t pinned_streams[MS_MAX_ISOLATES];
static atomic_bool main_affine;

uint32_t ms_sched_thread(void) { return ms_isolate_self(); }

bool ms_sched_is_worker(void) {
    const uint32_t self = ms_isolate_self();
    return self != MS_NO_ISOLATE && self != 0;
}

void ms_sched_pin_adjust(uint32_t thread, int32_t delta) {
    if (thread < MS_MAX_ISOLATES) {
        atomic_fetch_add_explicit(&pinned_streams[thread], delta, memory_order_relaxed);
    }
}

void ms_sched_pin_main(void) { atomic_store_explicit(&main_affine, true, memory_order_relaxed); }

bool ms_sched_pinned_here(void) {
    const uint32_t self = ms_isolate_self();
    if (self >= MS_MAX_ISOLATES) {
        return false;
    }
    return atomic_load_explicit(&pinned_streams[self], memory_order_relaxed) > 0 ||
           (self == 0 && atomic_load_explicit(&main_affine, memory_order_relaxed));
}

void msrt_token_post_remote(uint64_t token, uint64_t value) { ms_token_post_remote(token, value); }
