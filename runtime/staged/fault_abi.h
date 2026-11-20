/* fault_abi.h: the faults, cleanups, guards and shields generated code and the natives call by exported name
 * (`msrt_fault` and friends), over the C fault path in runtime/core (fault.h) and the task's unwind state
 * (unwind.h). Staged: nothing builds this directory into the runtime archive, so it can sit on main beside the
 * Rust definitions it will replace. The joint flip with the Rust task layer moves `fault_abi.c` to runtime/core,
 * lists the symbols in runtime/symbols/fault.txt, records their signatures here with `ms-sig`, and deletes
 * crates/ms-rt/src/fault.rs.
 *
 * What the startup code calls (all in runtime/core):
 *  - ms_frames_install(tables) once at start, with the tables the compiled program passes;
 *  - ms_fault(kind, message) and ms_fault_fatal(kind, message) for a fault or a broken invariant; ms_fault_hook
 *    below is the scheduler's `hooks.fault`;
 *  - ms_fault_exit(&text) to report a fault that left a guarded task and end the process;
 *  - ms_fault_record_write(...) for a failed test;
 *  - ms_cancel_set_task / ms_cancelled (unwind.h) for a stop request; the signal handler only records it in
 *    MsSched.stop_request.
 *
 * Open item for the flip: the guard frame of the Rust runtime also restores the equality-cycle guard's pair
 * stack (`desc::eq_truncate`); that state is still Rust, so it needs a hook in ms_guard_call or a C home first.
 */
#ifndef MS_STAGED_FAULT_ABI_H
#define MS_STAGED_FAULT_ABI_H

#include <stddef.h>
#include <stdint.h>

#include "fault.h"
#include "rt_calls.h"
#include "unwind.h"
#include "ms_rt/string.h"

/* The scheduler's fault hook: raises a fault of `kind` with a NUL-terminated message. */
MS_NORETURN void ms_fault_hook(MsFaultKind kind, const char *message);

/* ---- raising ---- */
MS_NORETURN void msfault_raise(uint8_t kind, const uint8_t *msg, size_t len);
MS_NORETURN void msrt_fault(const uint8_t *msg, size_t len);
MS_NORETURN void msrt_fault_string(const MsStr *message);
MS_NORETURN void msrt_fault_depth(void);
MS_NORETURN void msrt_index_fault(int64_t index, int64_t length);
MS_NORETURN void msrt_list_index_fault(int64_t operation, int64_t index, int64_t len);
MS_NORETURN void msrt_fault_unwrap_none(void);
MS_NORETURN void msrt_fault_result_get(void);
MS_NORETURN void msrt_fault_result_err(void);
MS_NORETURN void msrt_fault_int_overflow(void);
MS_NORETURN void msrt_fault_int_range(void);
MS_NORETURN void msrt_fault_div_zero(void);
MS_NORETURN void msrt_fault_rem_zero(void);
MS_NORETURN void msrt_fault_div_overflow(int64_t a, int64_t b);

/* ---- cleanups ---- */
size_t msrt_cleanup_push(MsCleanupFn run, uint8_t *arg);
void msrt_cleanup_run(size_t handle);
void msrt_cleanup_discard(size_t handle);
void msrt_cleanup_remove(size_t handle);
void msrt_cleanup_cancel(size_t handle);
size_t msrt_cleanup_base(void);
void msrt_cleanup_unwind_to(size_t base);
void msrt_cleanup_truncate(size_t base);
uint8_t msrt_unwind_drops(void);
uint8_t msrt_rollback_needed(void);

/* ---- shields, cancellation, guards ---- */
void msrt_shield_enter(void);
void msrt_shield_exit(void);
void msrt_cancel_edges(void);
void msrt_unwinding_pause(void);
void msrt_unwinding_resume(void);
uint8_t msrt_unwinding(void);
MS_NORETURN void msrt_cancelled(void);
/* Ends a native's call that a cancel interrupted (ms_sched_cancel_return): with cancel edges the task is marked
 * unwinding and the native returns zero; without them it leaves by msrt_cancelled. */
void ms_sched_cancel_return(void);
/* Runs code(data) guarded: 0 returned, 1 faulted (report in *message, owned by the caller), 2 cancelled. */
uint8_t msrt_guard_call(void (*code)(uint8_t *), uint8_t *data, MsStr *message);
/* The header block of the running task, for targets whose generated code cannot find it by the stack pointer. */
MsTaskHdr *msrt_isolate_hdr(void);

#endif
