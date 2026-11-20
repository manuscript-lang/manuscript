/* The scheduler queries C natives call through ms_sched.h, over the C scheduler (runtime/core). Staged with
 * fault_abi.c: nothing builds this directory into the archive until the flip replaces
 * crates/ms-rt/src/glue/c_sched.rs.
 *
 * The blocking pool of ms_sched.h is runtime/std/pool.c (libuv threads, every platform). It calls msrt_token_*,
 * msrt_task_count and msrt_task_others_stalled from runtime/core/task_abi.c, and msrt_token_post_remote and
 * ms_sched_task_pin from sched_calls.c (staged_sched_pool tests the whole). Standard output is stdout.c; the Windows pipe and waitable-object calls are not here. */
#include "ms_sched.h"
#include "task.h"
#include "unwind.h"

bool ms_sched_cancel_pending(void) { return ms_cancel_flag() != 0; }

void ms_sched_stop_hold(void) { ms_stop_shield_enter(); }

void ms_sched_stop_release(void) { ms_stop_shield_exit(); }

bool ms_sched_read_limit_passed(void) { return ms_task_read_limit_passed(); }
