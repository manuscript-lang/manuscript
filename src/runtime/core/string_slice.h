/* The checked slice the string modules share: a range the callers' arithmetic keeps in bounds, whose failure can only
 * be a runtime bug, so it faults and names the module. */
#ifndef MS_CORE_STRING_SLICE_H
#define MS_CORE_STRING_SLICE_H

#include "ms_rt/safe.h"
#include "rt_calls.h"

MS_NORETURN static inline void ms_string_internal_fault(void) {
    static const uint8_t message[] = "string: internal bounds error";
    msrt_fault(message, sizeof message - 1);
}

/* bytes[start..end]; a bad range is a runtime bug. */
static inline MS_ALWAYS_INLINE MsBytes ms_string_slice(MsBytes bytes, size_t start, size_t end) {
    MsBytes part = {0};
    if (!ms_bytes_slice(bytes, start, end, &part)) {
        ms_string_internal_fault();
    }
    return part;
}

#endif
