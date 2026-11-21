/* runtime/core/sort.c: sorting lists by a comparator closure: a stable merge sort. A comparator is program
 * code and can fault or be cancelled, which leaves by a jump and skips this code. So the sort works on a copy
 * of the slots and writes them back only when it is done: a comparator that leaves early finds the list as it
 * was, and at worst the scratch memory is not freed. */
#include "runtime/core/list.h"

#include "base/alloc.h"
#include "runtime/core/list_support.h"

/* Runs of at most this many slots are insertion sorted. */
#define INSERTION_LIMIT 12

typedef struct Comparator {
  MsCompareFn call;
  uint8_t *env;
} Comparator;

static bool less(const Comparator *cmp, const uint8_t *a, const uint8_t *b) {
  return cmp->call(cmp->env, a, b) < 0;
}

/* Stable insertion sort of `count` slots, holding the slot being placed in `spare`. */
static void insertion_sort(uint8_t *items, uint8_t *spare, size_t count, size_t size, const Comparator *cmp) {
  for (size_t i = 1; i < count; i++) {
    __builtin_memcpy(spare, items + i * size, size);
    size_t j = i;
    while (j > 0 && less(cmp, spare, items + (j - 1) * size)) {
      __builtin_memcpy(items + j * size, items + (j - 1) * size, size);
      j--;
    }
    __builtin_memcpy(items + j * size, spare, size);
  }
}

/* The two ends of a merge: the unmerged runs of `buf` from the left and from the right. */
typedef struct MergeRuns {
  size_t left;
  size_t left_end;
  size_t right;
  size_t right_end;
} MergeRuns;

/* Merges the sorted halves items[0..mid) and items[mid..count) from both ends at once: two independent
 * chains hide the load-to-compare latency of a single merge. Every slot is consumed exactly once whatever
 * the comparator answers (each step takes from a cursor range that is still non-empty), so a comparator
 * that is not a total order only gives a poor order. `buf` holds `count` slots. */
static void merge_halves(uint8_t *items, uint8_t *buf, size_t count, size_t mid, size_t size,
                         const Comparator *cmp) {
  __builtin_memcpy(buf, items, count * size);
  MergeRuns runs = {.left = 0, .left_end = mid, .right = mid, .right_end = count};
  for (size_t k = 0; k < count / 2; k++) {
    const bool take_right =
        runs.left == runs.left_end ||
        (runs.right < runs.right_end && less(cmp, buf + runs.right * size, buf + runs.left * size));
    __builtin_memcpy(items + k * size, buf + (take_right ? runs.right : runs.left) * size, size);
    runs.right += take_right;
    runs.left += !take_right;
    const bool take_left = runs.right_end == runs.right ||
                           (runs.left < runs.left_end &&
                            less(cmp, buf + (runs.right_end - 1) * size, buf + (runs.left_end - 1) * size));
    __builtin_memcpy(items + (count - 1 - k) * size,
                     buf + (take_left ? runs.left_end - 1 : runs.right_end - 1) * size, size);
    runs.left_end -= take_left;
    runs.right_end -= !take_left;
  }
  if (count % 2 == 1) {
    __builtin_memcpy(items + (count / 2) * size,
                     buf + (runs.left < runs.left_end ? runs.left : runs.right) * size, size);
  }
}

static void merge_sort(uint8_t *items, uint8_t *buf, size_t count, size_t size, const Comparator *cmp) {
  if (count <= INSERTION_LIMIT) {
    insertion_sort(items, buf, count, size, cmp);
    return;
  }
  const size_t mid = count / 2;
  merge_sort(items, buf, mid, size, cmp);
  merge_sort(items + mid * size, buf + mid * size, count - mid, size, cmp);
  if (!less(cmp, items + mid * size, items + (mid - 1) * size)) { /* already in order */
    return;
  }
  merge_halves(items, buf, count, mid, size, cmp);
}

void msrt_list_sort_in_place(MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env) {
  if (v->len < 2) {
    return;
  }
  const size_t bytes = msrt_list_buffer_bytes(v->len, d->size);
  size_t storage = 0;
  if (!ms_size_mul(bytes, 2, &storage)) {
    msrt_list_overflow_fault();
  }
  uint8_t *work = ms_alloc(storage);
  __builtin_memcpy(work, v->ptr, bytes);
  const Comparator comparator = {.call = cmp, .env = env};
  merge_sort(work, work + bytes, v->len, d->size, &comparator);
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
