/* fault.h: the kinds of fault and the statuses a process exits with. Internal to runtime/core.
 *
 * The numbers are the ones `ms-rt-abi` records (crates/ms-rt-abi/src/record.rs) and generated code and tools
 * read, so they never change. Exit statuses are C-style: one place names them, no code writes a literal.
 */
#ifndef MS_CORE_FAULT_H
#define MS_CORE_FAULT_H

#include <stdint.h>

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

/* Outcome of a guarded call (ms_guard_call in unwind.h). */
typedef enum MsGuardStatus {
    MS_GUARD_OK = 0,
    MS_GUARD_FAULT = 1,
    MS_GUARD_CANCELLED = 2,
} MsGuardStatus;

#endif
