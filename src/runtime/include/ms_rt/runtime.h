/* ms_rt/runtime.h: what natives written in C call in the runtime and what they hand back to it: allocation,
 * faults, status codes and the two entry points every runtime object starts with. The functions are defined in
 * the runtime (crates/ms-rt today, src/runtime/core when it moves); tests supply fakes. */
#ifndef MS_RT_RUNTIME_H
#define MS_RT_RUNTIME_H

#include "ms_rt/alloc.h"
#include "ms_rt/base.h"
#include "ms_rt/fault.h"
#include "ms_rt/safe.h"
#include "ms_rt/string.h"
#include "ms_rt/strbuild.h" /* msrt_fault: raises a fault with a message and never returns */

/* The FaultKind codes of ms-rt-abi that natives raise (the families are ms_rt/fault.h's). */
#define MS_FAULT_DIVISION_BY_ZERO MS_FAULT_KIND_DIVISION_BY_ZERO
#define MS_FAULT_OVERFLOW MS_FAULT_KIND_OVERFLOW
#define MS_FAULT_OUT_OF_MEMORY MS_FAULT_KIND_OUT_OF_MEMORY

/* A presence flag parameter (an `Optional` argument split in two): 0 or 1. */
typedef uint8_t HasRaw;

/* The fault message is bytes, so text literals go through ms_fault_text. */
static inline MS_NORETURN void ms_fault_text(const char *text, size_t length) {
    msrt_fault((const uint8_t *)text, length);
}
/* Raises a fault of a family (an MsFaultKind) with this message; never returns. */
MS_NORETURN void msfault_raise(uint8_t kind, const void *message, size_t length);

#endif
