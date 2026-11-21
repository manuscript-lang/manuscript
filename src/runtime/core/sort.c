/* runtime/core/sort.c: sorting lists by a comparator closure: a stable merge sort. A comparator is program
 * code and can fault or be cancelled, which leaves by a jump and skips this code. So the sort works on a copy
 * of the slots and writes them back only when it is done: a comparator that leaves early finds the list as it
 * was, and at worst the copy is not freed. */
#include "runtime/core/list.h"

#include "base/alloc.h"
#include "base/sort.h"
#include "runtime/core/list_support.h"

void msrt_list_sort_in_place(MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env) {
  if (v->len < 2) {
    return;
  }
  const size_t bytes = msrt_list_buffer_bytes(v->len, d->size);
  uint8_t *work = ms_alloc(bytes);
  __builtin_memcpy(work, v->ptr, bytes);
  ms_sort(work, v->len, d->size, cmp, env);
  __builtin_memcpy(v->ptr, work, bytes);
  ms_free(work);
}

void msrt_list_sorted(const MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env, MsList *out) {
  ms_list_clone_desc(v, d, out);
  msrt_list_sort_in_place(out, d, cmp, env);
}

/* Whether hi - lo overflows an Int for the extremes of the list: then some pair differs by more than an
 * Int holds, and the comparator must run as written. */
static bool differences_overflow(const MsList *list) {
  int64_t lowest = INT64_MAX;
  int64_t highest = INT64_MIN;
  for (size_t i = 0; i < list->len; i++) {
    int64_t value = 0;
    __builtin_memcpy(&value, list->ptr + i * sizeof value, sizeof value);
    lowest = value < lowest ? value : lowest;
    highest = value > highest ? value : highest;
  }
  int64_t spread = 0;
  return __builtin_sub_overflow(highest, lowest, &spread);
}

/* `sorted` over Ints by a comparator that returns `left - right` (or `right - left` when `desc` is not
 * zero). When no two elements differ by more than an Int holds, every difference has the sign of the integer
 * order, so this is the integer sort. Otherwise the comparator runs as written, faulting where a subtraction
 * overflows. */
void msrt_list_sorted_by_difference(const MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env,
                                    int64_t desc, MsList *out) {
  ms_list_clone_desc(v, d, out);
  if (out->len >= 2 && differences_overflow(out)) {
    msrt_list_sort_in_place(out, d, cmp, env);
  } else {
    msrt_list_sort_ints(out, desc);
  }
}
