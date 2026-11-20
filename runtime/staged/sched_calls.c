/* The two calls runtime/std/pool.c makes that runtime/core does not define yet. Staged with sched_shims.c; the flip
 * moves them into runtime/core (task_abi.c) and lists them in runtime/symbols.
 *
 * msrt_token_post_remote is the program ABI over ms_token_post_remote, the post any thread may make to a token of an
 * isolate; the scheduler takes it from the isolate's mail. The pool's job threads call it, so it allocates the mail on
 * the calling thread; the isolate that receives it frees it.
 *
 * ms_sched_task_pin lends the running task's stack to a pool job. The Rust scheduler freezes the stack of a parked
 * task to save memory ("hibernation"), so a job that reads a caller's frame needs the task pinned. The C scheduler
 * never freezes a stack, so there is nothing to hold off and the call is empty; it must start counting if the C
 * scheduler ever reclaims the stack of a parked task. */
#include "ms_sched.h"
#include "isolate.h"

void msrt_token_post_remote(uint64_t token, uint64_t value) { ms_token_post_remote(token, value); }

void ms_sched_task_pin(bool lend) { (void)lend; }
