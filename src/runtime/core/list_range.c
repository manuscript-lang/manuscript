/* runtime/core/list_range.c: list natives that generate Int lists, and the set made from a list. */
#include "runtime/core/list.h"

#include "base/alloc.h"
#include "runtime/core/fault.h"
#include "runtime/core/list_support.h"
#include "runtime/core/scratch.h"

static const MsList empty_list = {0};

/* The list of `count` Ints, the first `first` and each `step` after the last, wrapping like two's
 * complement. */
static MsList int_list(size_t count, int64_t first, int64_t step) {
  MsList list = msrt_list_with_slots(&ms_desc_int, count, count);
  if (list.len != count) {
    return list; /* too large: a fault was posted */
  }
  uint64_t value = (uint64_t)first;
  for (size_t i = 0; i < count; i++) {
    __builtin_memcpy(list.ptr + i * sizeof value, &value, sizeof value);
    value += (uint64_t)step;
  }
  return list;
}

/* `keys()`: 0, 1, ..., len-1. */
void msrt_list_keys(const MsList *v, MsList *out) {
  *out = v->len == 0 ? empty_list : int_list(v->len, 0, 1);
}

void msrt_list_range(int64_t start, int64_t end, MsList *out) {
  if (end <= start) {
    *out = empty_list;
    return;
  }
  const uint64_t count = (uint64_t)end - (uint64_t)start; /* exact: the difference of two Ints fits */
  if (count > MSRT_LIST_MAX_ITEMS) {
    ms_fault_post_text(MS_FAULT_KIND_FAULT,
                       "range: more than 268435456 items; iterate with 'for index in start..end' directly or "
                       "bound the list with range_by(max_items:)");
    return;
  }
  *out = int_list((size_t)count, start, 1);
}

/* The distance covered and the step size of a range_by, or false when it covers nothing. */
static bool range_extent(int64_t start, int64_t end, int64_t step, uint64_t *span, uint64_t *size) {
  if (step > 0 && start < end) {
    *span = (uint64_t)end - (uint64_t)start;
    *size = (uint64_t)step;
    return true;
  }
  if (step < 0 && start > end) {
    *span = (uint64_t)start - (uint64_t)end;
    *size = (uint64_t)0 - (uint64_t)step;
    return true;
  }
  return false;
}

uint8_t msrt_list_range_by(int64_t start, int64_t end, int64_t step, uint8_t has_max, int64_t max,
                           MsList *out) {
  const int64_t requested = has_max != 0 ? max : INT64_MAX;
  if (step == 0 || requested < 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  const uint64_t limit =
      (uint64_t)requested < MSRT_LIST_MAX_ITEMS ? (uint64_t)requested : MSRT_LIST_MAX_ITEMS;
  uint64_t span = 0;
  uint64_t size = 1;
  if (!range_extent(start, end, step, &span, &size)) {
    *out = empty_list;
    return MS_STATUS_OK;
  }
  const uint64_t count = (span - 1) / size + 1;
  if (count > limit) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  *out = int_list((size_t)count, start, step);
  return MS_STATUS_OK;
}

/* `to_set`: a set of copies of the elements. */
void msrt_list_to_set(const MsList *v, const MsTypeDesc *d, MsMap *out) {
  MsMap set = {0};
  MsrtScratch copy;
  msrt_scratch_open(&copy, d->size);
  for (size_t i = 0; i < v->len; i++) {
    ms_slot_copy(d, ms_list_slot(v, d, i), copy.ptr);
    ms_map_insert(&set, d, NULL, copy.ptr, NULL);
  }
  msrt_scratch_close(&copy);
  *out = set;
}
