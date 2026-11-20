/* The scheduler queries C natives call through ms_sched.h, over the C scheduler (runtime/core). Staged with
 * fault_abi.c: nothing builds this directory into the archive until the flip replaces
 * crates/ms-rt/src/glue/c_sched.rs.
 *
 * The blocking pool of ms_sched.h is runtime/std/pool.c (libuv threads, every platform). It calls the program-ABI
 * msrt_token_new / msrt_token_park / msrt_token_free / msrt_token_post_remote, msrt_task_count,
 * msrt_task_others_stalled and ms_sched_task_pin, which the flip defines over ms_token_* / ms_task_* (the Rust
 * glue defines them today). Standard output is stdout.c; the Windows pipe and waitable-object calls are not here. */
#include "ms_sched.h"
#include "task.h"
#include "unwind.h"

bool ms_sched_cancel_pending(void) { return ms_cancel_flag() != 0; }

bool ms_sched_read_limit_passed(void) { return ms_task_read_limit_passed(); }
