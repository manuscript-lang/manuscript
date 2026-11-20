/* ms_rt/runtime.h: what natives written in C call in the runtime and what they hand back to it: allocation,
 * faults, status codes and the two entry points every runtime object starts with. The functions are defined in
 * the runtime (crates/ms-rt today, runtime/core when it moves); tests supply fakes. */
#ifndef MS_RT_RUNTIME_H
#define MS_RT_RUNTIME_H

#include "ms_rt/base.h"
#include "ms_rt/safe.h"

/* The STATUS_* codes of ms-rt-abi that natives return. */
typedef enum MsStatus {
    MS_STATUS_OK = 0,
    MS_STATUS_INVALID_INPUT = 1,
    MS_STATUS_OUT_OF_RANGE = 2,
    MS_STATUS_LIMIT_EXCEEDED = 3,
    MS_STATUS_INVALID_DATA = 4,
} MsStatus;

/* The FaultKind codes of ms-rt-abi that natives raise. */
typedef enum MsFaultKind {
    MS_FAULT_DIVISION_BY_ZERO = 4,
    MS_FAULT_OVERFLOW = 5,
} MsFaultKind;

/* A presence flag parameter (an `Optional` argument split in two): 0 or 1. */
typedef uint8_t HasRaw;

/* A runtime object starts with these two entry points: clone returns an independent copy (NULL when the value
 * has one owner and cannot be copied) and drop releases the object itself. */
typedef struct MsObject {
    struct MsObject *(*clone)(struct MsObject *object);
    void (*drop)(struct MsObject *object);
} MsObject;

/* Memory from the runtime allocator; it faults when memory is exhausted, so the result is never null. */
MS_RETURNS_NONNULL void *msrt_alloc(size_t size);
void msrt_free(void *pointer);
/* Raises a fault with this message; never returns. */
MS_NORETURN void msrt_fault(const void *message, size_t length);
/* The same for a fault of a family (an MsFaultKind). */
MS_NORETURN void msrt_fault_kind(uint8_t kind, const void *message, size_t length);
/* Writes a new owned string holding a copy of the bytes (an ms_str, ms_rt/string.h) to *out. */
void msrt_string_from_bytes(const uint8_t *bytes, size_t length, void *out);

#endif
