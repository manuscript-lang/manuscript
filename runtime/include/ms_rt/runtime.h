/* ms_rt/runtime.h: what natives written in C call in the runtime and what they hand back to it: allocation,
 * faults, status codes and the two entry points every runtime object starts with. The functions are defined in
 * the runtime (crates/ms-rt today, runtime/core when it moves); tests supply fakes. */
#ifndef MS_RT_RUNTIME_H
#define MS_RT_RUNTIME_H

#include "ms_rt/alloc.h"
#include "ms_rt/base.h"
#include "ms_rt/safe.h"
#include "ms_rt/string.h"

/* The status code of invalid data (base.h has the others). */
enum { MS_STATUS_INVALID_DATA = 4 };

/* The FaultKind codes of ms-rt-abi that natives raise. */
typedef enum MsFaultKind {
    MS_FAULT_DIVISION_BY_ZERO = 4,
    MS_FAULT_OVERFLOW = 5,
} MsFaultKind;

/* A presence flag parameter (an `Optional` argument split in two): 0 or 1. */
typedef uint8_t HasRaw;

/* Raises a fault with this message; never returns. */
MS_NORETURN void msrt_fault(const void *message, size_t length);
/* The same for a fault of a family (an MsFaultKind). */
MS_NORETURN void msfault_raise(uint8_t kind, const void *message, size_t length);

#endif
