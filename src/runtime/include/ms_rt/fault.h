/* ms_rt/fault.h: the families of fault, the statuses a process exits with, and the faults, cleanups, shields and
 * guards generated code calls (src/runtime/core/fault_abi.c; symbols in src/runtime/symbols/fault.txt). The numbers never
 * change: generated code and tools read them, and `ms-rt-abi` generates its `FaultKind` and `EXIT_*` constants from the
 * `MS_FAULT_KIND_*` and `MS_EXIT_*` lines below (crates/ms-rt-abi/build.rs), so keep one `NAME = number` per line.
 * Exit statuses are C-style: this is the one place that names them, no code writes a literal.
 */
#ifndef MS_RT_FAULT_H
#define MS_RT_FAULT_H

#include <stddef.h>
#include <stdint.h>

#include "ms_rt/base.h"
#include "ms_rt/safe.h"
#include "ms_rt/string.h"

typedef enum MsFaultKind {
    MS_FAULT_KIND_FAULT = 0, /* any fault without a more specific family */
    MS_FAULT_KIND_INCOMPLETE_CLEANUP = 1,
    MS_FAULT_KIND_STACK_OVERFLOW = 2,
    MS_FAULT_KIND_DEADLOCK = 3,
    MS_FAULT_KIND_DIVISION_BY_ZERO = 4,
    MS_FAULT_KIND_OVERFLOW = 5,
    MS_FAULT_KIND_INDEX_OUT_OF_RANGE = 6,
    MS_FAULT_KIND_TEST_FAILURE = 7, /* not a fault: the test returned an error */
    MS_FAULT_KIND_OUT_OF_MEMORY = 8,
} MsFaultKind;

enum {
    MS_EXIT_ABORT = 134,          /* a fault */
    MS_EXIT_STACK_OVERFLOW = 139, /* a stack overflow */
    MS_EXIT_NO_MEMORY = 139,      /* an allocation the system refused */
    MS_EXIT_INTERRUPT = 130,      /* SIGINT */
    MS_EXIT_TERMINATE = 143,      /* SIGTERM */
    MS_EXIT_TEST_FAILURE = 1,     /* a failed test */
};

/* The cleanups the faulting task runs on its way out: a function and its argument, kept on the task's stack. */
typedef void (*MsCleanupFn)(uint8_t *);
/* Code run guarded by msrt_guard_call. */
typedef void (*MsGuardFn)(uint8_t *);
/* The header block of a task (src/runtime/core/unwind.h). */
typedef struct MsTaskHdr MsTaskHdr;

/* ms-sig: msrt_fault(msg: *const u8, len: usize) -> ! */
MS_NORETURN void msrt_fault(const uint8_t *msg, size_t len);

/* ms-sig: msrt_fault_string(s: *const StrVal) -> ! @leaf */
MS_NORETURN void msrt_fault_string(const MsStr *message);

/* ms-sig: msrt_fault_depth() -> ! @leaf */
MS_NORETURN void msrt_fault_depth(void);

/* ms-sig: msrt_index_fault(index: i64, length: i64) -> ! @leaf */
MS_NORETURN void msrt_index_fault(int64_t index, int64_t length);

/* ms-sig: msrt_list_index_fault(operation: i64, index: i64, len: i64) -> ! @leaf */
MS_NORETURN void msrt_list_index_fault(int64_t operation, int64_t index, int64_t len);

/* ms-sig: msrt_fault_unwrap_none() -> ! @leaf */
MS_NORETURN void msrt_fault_unwrap_none(void);

/* ms-sig: msrt_fault_result_get() -> ! @leaf */
MS_NORETURN void msrt_fault_result_get(void);

/* ms-sig: msrt_fault_result_err() -> ! @leaf */
MS_NORETURN void msrt_fault_result_err(void);

/* ms-sig: msrt_fault_int_overflow() -> ! @leaf */
MS_NORETURN void msrt_fault_int_overflow(void);

/* ms-sig: msrt_fault_int_range() -> ! @leaf */
MS_NORETURN void msrt_fault_int_range(void);

/* ms-sig: msrt_fault_div_zero() -> ! @leaf */
MS_NORETURN void msrt_fault_div_zero(void);

/* ms-sig: msrt_fault_rem_zero() -> ! @leaf */
MS_NORETURN void msrt_fault_rem_zero(void);

/* ms-sig: msrt_fault_div_overflow(a: i64, b: i64) -> ! @leaf */
MS_NORETURN void msrt_fault_div_overflow(int64_t a, int64_t b);

/* ms-sig: msrt_cleanup_push(f: CleanupFn, arg: *mut u8) -> usize @leaf @retains */
size_t msrt_cleanup_push(MsCleanupFn run, uint8_t *arg);

/* ms-sig: msrt_cleanup_run(handle: usize) @leaf */
void msrt_cleanup_run(size_t handle);

/* ms-sig: msrt_cleanup_discard(handle: usize) @leaf */
void msrt_cleanup_discard(size_t handle);

/* ms-sig: msrt_cleanup_remove(handle: usize) @leaf */
void msrt_cleanup_remove(size_t handle);

/* ms-sig: msrt_cleanup_cancel(handle: usize) @leaf */
void msrt_cleanup_cancel(size_t handle);

/* ms-sig: msrt_cleanup_base() -> usize @domain=unwind @leaf */
size_t msrt_cleanup_base(void);

/* ms-sig: msrt_cleanup_unwind_to(base: usize) */
void msrt_cleanup_unwind_to(size_t base);

/* ms-sig: msrt_cleanup_truncate(base: usize) @domain=unwind @leaf */
void msrt_cleanup_truncate(size_t base);

/* ms-sig: msrt_unwind_drops() -> u8 @domain=unwind @leaf */
uint8_t msrt_unwind_drops(void);

/* ms-sig: msrt_rollback_needed() -> u8 @leaf */
uint8_t msrt_rollback_needed(void);

/* ms-sig: msrt_shield_enter() @leaf */
void msrt_shield_enter(void);

/* ms-sig: msrt_shield_exit() @leaf */
void msrt_shield_exit(void);

/* ms-sig: msrt_cancel_edges() @domain=unwind @leaf */
void msrt_cancel_edges(void);

/* ms-sig: msrt_unwinding_pause() @domain=unwind @leaf */
void msrt_unwinding_pause(void);

/* ms-sig: msrt_unwinding_resume() @domain=unwind @leaf */
void msrt_unwinding_resume(void);

/* ms-sig: msrt_unwinding() -> u8 @domain=unwind @leaf */
uint8_t msrt_unwinding(void);

/* ms-sig: msrt_cancelled() -> ! */
MS_NORETURN void msrt_cancelled(void);

/* ms-sig: msrt_isolate_hdr() -> *mut Hdr */
MsTaskHdr * msrt_isolate_hdr(void);

/* ms-sig: msrt_guard_call(code: unsafe extern "C-unwind" fn(*mut u8), data: *mut u8, msg_out: *mut StrVal) -> u8 @retains */
uint8_t msrt_guard_call(MsGuardFn code, uint8_t *data, MsStr *message);

#endif
