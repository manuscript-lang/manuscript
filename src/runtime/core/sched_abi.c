/* The calls of ms_sched.h that need the scheduler of this thread, for the natives of src/runtime/std and src/runtime/net:
 * whether a stop request or a read limit is pending, the pin of a task's stack lent to a pool job, and the post any
 * thread may make to a token (msrt_token_post_remote, the program ABI over ms_token_post_remote). The blocking
 * pool itself is src/runtime/std/pool.c; standard output is stdout.c; the Windows pipes are src/runtime/io/windows/sched.c. */
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

void msrt_token_post_remote(uint64_t token, uint64_t value) { ms_token_post_remote(token, value); }
