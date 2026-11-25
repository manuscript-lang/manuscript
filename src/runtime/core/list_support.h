/* runtime/core/list_support.h: what the list natives share: element addresses, checked sizes and the faults
 * of a bad range. A zero-sized element still takes one byte of buffer, so a buffer is never zero bytes. */
#ifndef MS_RUNTIME_CORE_LIST_SUPPORT_H
#define MS_RUNTIME_CORE_LIST_SUPPORT_H

#include "base/desc.h"

#define MSRT_LIST_MAX_ITEMS ((size_t)1 << 28) /* the largest list a range or a repeat builds */

/* Raises the fault "list size overflow". */
void msrt_post_list_overflow(void);

/* a + b, faulting on overflow. */
bool msrt_list_checked_add(size_t a, size_t b, size_t *sum);

/* A borrowed list over `count` elements of `list` from `start`. */
static inline MsList msrt_list_view_of(const MsList *list, const MsTypeDesc *d, size_t start, size_t count) {
  return (MsList){.ptr = count == 0 ? NULL : ms_list_slot(list, d, start), .len = count, .cap = count};
}

/* Copies `count` borrowed slots into the disjoint, uninitialised slots at `dst`, in order. */
void msrt_list_copy_range(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst, size_t count);

/* A list owning a new buffer of `count` slots, all counted in `len`; the caller fills the slots. */
MsList msrt_list_with_slots(const MsTypeDesc *d, size_t count, size_t capacity);

/* "List.splice: <what> must be between 0 and <high>, found <found>". */
void msrt_post_splice(const char *what, int64_t found, size_t high);

/* Faults unless 0 <= start <= end <= length. */
bool msrt_check_bounds(const char *operation, size_t length, int64_t start, int64_t end);

/* "List.copy_within: target must be between 0 and <length>, found <target>". */
void msrt_post_copy_target(size_t length, int64_t target);

/* The error text of a list slice whose bounds are out of range. */
MsString msrt_list_slice_error(int64_t start, int64_t end, size_t length);

#endif
