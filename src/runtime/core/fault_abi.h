/* The faults, cleanups, shields and guards generated code calls by exported name, over the C fault path
 * (fault.h) and the running task's unwind state (unwind.h). */
#ifndef MS_RUNTIME_CORE_FAULT_ABI_H
#define MS_RUNTIME_CORE_FAULT_ABI_H

#include <stddef.h>
#include <stdint.h>

#include "base/string.h"
#include "runtime/core/unwind.h"

/* ---- raising ---- */

/* ms-sig: msrt_fault(msg: *const u8, len: usize) -> ! */
MS_NORETURN void msrt_fault(const uint8_t *msg, size_t len);
/* ms-sig: msrt_fault_string(s: *const StrVal) -> ! @end */
MS_NORETURN void msrt_fault_string(const MsString *message);
/* ms-sig: msrt_panic(message: *const StrVal) -> ! @end */
MS_NORETURN void msrt_panic(const MsString *message);
/* ms-sig: msrt_fault_depth() -> ! @end */
MS_NORETURN void msrt_fault_depth(void);
/* ms-sig: msrt_fault_unwrap_none() -> ! @end */
MS_NORETURN void msrt_fault_unwrap_none(void);
/* ms-sig: msrt_fault_result_get() -> ! @end */
MS_NORETURN void msrt_fault_result_get(void);
/* ms-sig: msrt_fault_result_err() -> ! @end */
MS_NORETURN void msrt_fault_result_err(void);
/* ms-sig: msrt_fault_int_overflow() -> ! @end */
MS_NORETURN void msrt_fault_int_overflow(void);
/* ms-sig: msrt_fault_int_range() -> ! @end */
MS_NORETURN void msrt_fault_int_range(void);
/* ms-sig: msrt_fault_div_zero() -> ! @end */
MS_NORETURN void msrt_fault_div_zero(void);
/* ms-sig: msrt_fault_rem_zero() -> ! @end */
MS_NORETURN void msrt_fault_rem_zero(void);
/* ms-sig: msrt_fault_div_overflow(a: i64, b: i64) -> ! @end */
MS_NORETURN void msrt_fault_div_overflow(int64_t a, int64_t b);

/* ---- cleanups ---- */

/* ms-sig: msrt_cleanup_push(f: CleanupFn, arg: *mut u8) -> usize @end */
size_t msrt_cleanup_push(MsCleanupFn run, uint8_t *arg);
/* ms-sig: msrt_cleanup_run(handle: usize) @end */
void msrt_cleanup_run(size_t handle);
/* ms-sig: msrt_cleanup_discard(handle: usize) @end */
void msrt_cleanup_discard(size_t handle);
/* ms-sig: msrt_cleanup_remove(handle: usize) @end */
void msrt_cleanup_remove(size_t handle);
/* ms-sig: msrt_cleanup_cancel(handle: usize) @end */
void msrt_cleanup_cancel(size_t handle);
/* ms-sig: msrt_cleanup_base() -> usize @domain=unwind @end */
size_t msrt_cleanup_base(void);
/* ms-sig: msrt_cleanup_unwind_to(base: usize) */
void msrt_cleanup_unwind_to(size_t base);
/* ms-sig: msrt_cleanup_truncate(base: usize) @domain=unwind @end */
void msrt_cleanup_truncate(size_t base);
/* ms-sig: msrt_unwind_drops() -> u8 @domain=unwind @end */
uint8_t msrt_unwind_drops(void);

/* ---- shields and cancellation ---- */

/* ms-sig: msrt_shield_enter() @end */
void msrt_shield_enter(void);
/* ms-sig: msrt_shield_exit() @end */
void msrt_shield_exit(void);
/* The program's modules branch on `unwinding` after a call that can park. */
/* ms-sig: msrt_cancel_edges() @domain=unwind @end */
void msrt_cancel_edges(void);
/* ms-sig: msrt_unwinding_pause() @domain=unwind @end */
void msrt_unwinding_pause(void);
/* ms-sig: msrt_unwinding_resume() @domain=unwind @end */
void msrt_unwinding_resume(void);
/* ms-sig: msrt_unwinding() -> u8 @domain=unwind @end */
uint8_t msrt_unwinding(void);
/* Where compiled code receives a native's failing `status`: ends the call as cancelled (ms_sched_cancel_return) when
 * the status is MS_STATUS_CANCELLED or the task has a stop pending, so a layer that turned the cancel into another
 * failure does not hide it. Otherwise it does nothing. */
/* ms-sig: msrt_native_failed(status: u8) @domain=unwind @end */
void msrt_native_failed(uint8_t status);
/* ms-sig: msrt_cancelled() -> ! */
MS_NORETURN void msrt_cancelled(void);
/* ms-sig: msrt_isolate_hdr() -> *mut Hdr */
MsTaskHdr *msrt_isolate_hdr(void);

/* Ends a native's call that a cancel interrupted: with cancel edges the task is marked unwinding and the native
 * returns zero; without them it leaves by msrt_cancelled. */
void ms_sched_cancel_return(void);

/* ---- guards ---- */

/* ms-sig: msrt_guard_call(code: unsafe extern "C-unwind" fn(*mut u8), data: *mut u8, msg_out: *mut StrVal) -> u8 @end */
uint8_t msrt_guard_call(void (*code)(uint8_t *), uint8_t *data, MsString *message);

#endif
