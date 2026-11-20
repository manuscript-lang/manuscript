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
#include "ms_rt/map.h"
#include "ms_rt/string.h"

/* The family of a fault, which the structured fault record names (crates/ms-rt-abi FaultKind). */
typedef enum MsFaultKind {
    MS_FAULT_GENERIC = 0,
    MS_FAULT_OVERFLOW = 5,
    MS_FAULT_INDEX_OUT_OF_RANGE = 6
} MsFaultKind;

/* Raises a fault of `kind` with the message `msg[0..len]`. */
MS_NORETURN void msfault_raise(uint8_t kind, const uint8_t *msg, size_t len);
/* Raises a generic fault. */
MS_NORETURN void msrt_fault(const uint8_t *msg, size_t len);
/* "index N out of range for length L; pass a default". */
MS_NORETURN void msrt_index_fault(int64_t index, int64_t length);
/* The fault of a list mutator given a bad index: operation 0 insert, 1 remove, 2 set, 3 swap, 4 replace. */
MS_NORETURN void msrt_list_index_fault(int64_t operation, int64_t index, int64_t len);

/* A cleanup runs when a fault or cancellation leaves the code between push and discard by a jump. */
typedef void (*MsCleanupFn)(uint8_t *arg);
size_t msrt_cleanup_push(MsCleanupFn run, uint8_t *arg);
void msrt_cleanup_discard(size_t handle);

/* Objects with a header (closures, handles). Null stays null. */

/* Runs `shim(block)` on the running task's next stack segment (the task module). */
void msrt_task_grow(void (*shim)(uint8_t *), uint8_t *block);

MsObj *msrt_obj_clone(MsObj *object);
void msrt_obj_drop(MsObj *object);

#endif
