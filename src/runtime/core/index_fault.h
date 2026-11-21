/* runtime/core/index_fault.h: the faults of a bad index, shared by the string, list and bytes natives. */
#ifndef MS_RUNTIME_CORE_INDEX_FAULT_H
#define MS_RUNTIME_CORE_INDEX_FAULT_H

#include "base/safe.h"

/* "index N out of range for length L; pass a default: get(index:, default: ...)". */
/* ms-sig: msrt_index_fault(index: i64, length: i64) -> ! @leaf */
MS_NORETURN void msrt_index_fault(int64_t index, int64_t length);

/* A bad index of a list mutator over `length` elements; `operation` names the mutator for the message. */
/* ms-sig: msrt_list_index_fault(operation: i64, index: i64, len: i64) -> ! @leaf */
MS_NORETURN void msrt_list_index_fault(int64_t operation, int64_t index, int64_t length);

/* "<operation>: index must be between -L and L-1 (negative indexes count from the end), found N", or the
 * empty-collection spelling when `length` is 0. */
MS_NORETURN void msrt_collection_index_fault(const char *operation, int64_t length, int64_t index);

#endif
