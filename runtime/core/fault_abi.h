/* fault_abi.h: the faults, cleanups, guards and shields generated code and the natives call by exported name
 * (`msrt_fault` and friends, declared in ms_rt/fault.h), over the C fault path in runtime/core (fault.h) and the
 * task's unwind state (unwind.h).
 *
 * What the startup code calls (all in runtime/core):
 *  - ms_frames_install(tables) once at start, with the tables the compiled program passes;
 *  - ms_fault(kind, message) and ms_fault_fatal(kind, message) for a fault or a broken invariant; ms_fault_hook
 *    below is the scheduler's `hooks.fault`;
 *  - ms_fault_exit(&text) to report a fault that left a guarded task and end the process;
 *  - ms_fault_record_write(...) for a failed test;
 *  - ms_cancel_set_task / ms_cancelled (unwind.h) for a stop request; the signal handler only records it in
 *    MsSched.stop_request.
 */
#ifndef MS_CORE_FAULT_ABI_H
#define MS_CORE_FAULT_ABI_H

#include <stddef.h>
#include <stdint.h>

#include "fault.h"
#include "rt_calls.h"
#include "unwind.h"
#include "ms_rt/fault.h"

/* The scheduler's fault hook: raises a fault of `kind` with a NUL-terminated message. */
MS_NORETURN void ms_fault_hook(MsFaultKind kind, const char *message);

/* Ends a native's call that a cancel interrupted (ms_sched_cancel_return): with cancel edges the task is marked
 * unwinding and the native returns zero; without them it leaves by msrt_cancelled. */
void ms_sched_cancel_return(void);

#endif
