/* runtime/core/index_fault.h: the faults of a bad index, posted (they return; the caller leaves), shared by the string, list and bytes natives. */
#ifndef MS_RUNTIME_CORE_INDEX_FAULT_H
#define MS_RUNTIME_CORE_INDEX_FAULT_H

#include "base/safe.h"

/* "index N out of range for length L; use get_or(index, default) to avoid the fault". */
/* ms-sig: msrt_post_index(index: i64, length: i64) -> void @end */
void msrt_post_index(int64_t index, int64_t length);

/* A bad index of a list mutator over `length` elements; `operation` names the mutator for the message. */
/* ms-sig: msrt_post_list_index(operation: i64, index: i64, len: i64) -> void @end */
void msrt_post_list_index(int64_t operation, int64_t index, int64_t length);

/* "<operation>: index must be between -L and L-1 (negative indexes count from the end), found N", or the
 * empty-collection spelling when `length` is 0. */
void msrt_post_collection_index(const char *operation, int64_t length, int64_t index);

#endif
