/* rt_calls.h: what runtime/core calls by its exported name and the Rust runtime still defines: faults, objects,
 * strings and the cleanup stack. Each moves to its own C module in turn; the declarations here follow it
 * and the unit tests link runtime/tests/support/rt_stubs.c in place of them.
 *
 * The allocator is C already (ms_rt/alloc.h). Faults do not return: they leave by the runtime's jump.
 */
#ifndef MS_RT_CALLS_H
#define MS_RT_CALLS_H

#include "ms_rt/base.h"
#include "ms_rt/safe.h"
#include "ms_rt/desc.h"
#include "ms_rt/fault.h"
#include "ms_rt/map.h"
#include "ms_rt/obj.h"
#include "ms_rt/string.h"

/* The families of fault are ms_rt/fault.h's; core files that predate it keep their spellings. */
#define MS_FAULT_GENERIC MS_FAULT_KIND_FAULT
#define MS_FAULT_OVERFLOW MS_FAULT_KIND_OVERFLOW
#define MS_FAULT_INDEX_OUT_OF_RANGE MS_FAULT_KIND_INDEX_OUT_OF_RANGE

/* Raises a fault of `kind` with the message `msg[0..len]`. */
MS_NORETURN void msfault_raise(uint8_t kind, const uint8_t *msg, size_t len);
/* Division and remainder by zero (a fault of the division family). */
MS_NORETURN void msrt_fault_div_zero(void);
MS_NORETURN void msrt_fault_rem_zero(void);
#ifndef MS_RT_STRBUILD_H /* ms_rt/strbuild.h declares the same two */
/* Raises a generic fault. */
MS_NORETURN void msrt_fault(const uint8_t *msg, size_t len);
/* "index N out of range for length L; pass a default". */
MS_NORETURN void msrt_index_fault(int64_t index, int64_t length);
#endif
/* The fault of a list mutator given a bad index: operation 0 insert, 1 remove, 2 set, 3 swap, 4 replace. */
MS_NORETURN void msrt_list_index_fault(int64_t operation, int64_t index, int64_t len);

/* A cleanup runs when a fault or cancellation leaves the code between push and discard by a jump. */
typedef void (*MsCleanupFn)(uint8_t *arg);
size_t msrt_cleanup_push(MsCleanupFn run, uint8_t *arg);
void msrt_cleanup_discard(size_t handle);
/* Non-zero when a callback may leave through a guard or a registered cleanup (fault.rs). */
uint8_t msrt_rollback_needed(void);

/* Runs `shim(block)` on the running task's next stack segment (the task module). */
void msrt_task_grow(void (*shim)(uint8_t *), uint8_t *block);

#endif
