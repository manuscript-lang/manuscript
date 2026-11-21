/* abi/fault.h: the families of fault and the statuses a process exits with. The numbers never change:
 * generated code, tools and the CLI read them. Exit statuses are C-style, the same on every platform; this is
 * the one place that names them, and no code writes a literal. */
#ifndef MS_ABI_FAULT_H
#define MS_ABI_FAULT_H

#include "base/fatal.h"

typedef enum MsFaultKind {
  MS_FAULT_KIND_FAULT = 0, /* any fault without a more specific family */
  MS_FAULT_KIND_INCOMPLETE_CLEANUP = 1,
  MS_FAULT_KIND_STACK_OVERFLOW = 2,
  MS_FAULT_KIND_DEADLOCK = 3,
  MS_FAULT_KIND_DIVISION_BY_ZERO = 4,
  MS_FAULT_KIND_OVERFLOW = 5,
  MS_FAULT_KIND_INDEX_OUT_OF_RANGE = 6,
  MS_FAULT_KIND_TEST_FAILURE = 7, /* not a fault: the test returned an error */
  MS_FAULT_KIND_OUT_OF_MEMORY = 8
} MsFaultKind;

enum {
  MS_EXIT_ABORT = 134,          /* a fault */
  MS_EXIT_STACK_OVERFLOW = 139, /* a stack overflow */
  MS_EXIT_NO_MEMORY = 139,      /* an allocation the system refused */
  MS_EXIT_INTERRUPT = 130,      /* SIGINT */
  MS_EXIT_TERMINATE = 143,      /* SIGTERM */
  MS_EXIT_TEST_FAILURE = 1      /* a failed test */
};

/* base reports its own unrecoverable conditions with the same statuses. */
_Static_assert(MS_EXIT_ABORT == MS_EXIT_FAULT && MS_EXIT_NO_MEMORY == MS_EXIT_RESOURCE,
               "base and abi agree on the fault statuses");

/* The status a process ends with after a fault of `kind`. */
static inline int ms_fault_exit_status(MsFaultKind kind) {
  switch (kind) {
  case MS_FAULT_KIND_TEST_FAILURE:
    return MS_EXIT_TEST_FAILURE;
  case MS_FAULT_KIND_STACK_OVERFLOW:
    return MS_EXIT_STACK_OVERFLOW;
  case MS_FAULT_KIND_OUT_OF_MEMORY:
    return MS_EXIT_NO_MEMORY;
  case MS_FAULT_KIND_FAULT:
  case MS_FAULT_KIND_INCOMPLETE_CLEANUP:
  case MS_FAULT_KIND_DEADLOCK:
  case MS_FAULT_KIND_DIVISION_BY_ZERO:
  case MS_FAULT_KIND_OVERFLOW:
  case MS_FAULT_KIND_INDEX_OUT_OF_RANGE:
    return MS_EXIT_ABORT;
  }
  return MS_EXIT_ABORT;
}

/* The family a base fatal condition belongs to. */
static inline MsFaultKind ms_fault_kind_of_fatal(MsFatalKind kind) {
  switch (kind) {
  case MS_FATAL_OUT_OF_MEMORY:
    return MS_FAULT_KIND_OUT_OF_MEMORY;
  case MS_FATAL_OVERFLOW:
    return MS_FAULT_KIND_OVERFLOW;
  case MS_FATAL_OUT_OF_RANGE:
    return MS_FAULT_KIND_INDEX_OUT_OF_RANGE;
  case MS_FATAL_INVARIANT:
    return MS_FAULT_KIND_FAULT;
  }
  return MS_FAULT_KIND_FAULT;
}

#endif
