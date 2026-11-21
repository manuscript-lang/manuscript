/* Owns the stable merge sort (see sort.h): insertion sort for short runs, then a two-ended merge. */
#include "base/sort.h"

#include "base/alloc.h"
#include "base/fatal.h"

/* Runs of at most this many slots are insertion sorted. */
enum { INSERTION_LIMIT = 12 };

typedef struct Comparator {
  MsSortCompare call;
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

void ms_sort(uint8_t *items, size_t count, size_t size, MsSortCompare compare, uint8_t *env) {
  if (count < 2) {
    return;
  }
  size_t bytes = 0;
  if (!ms_size_mul(count, size, &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "sort: size overflow");
  }
  uint8_t *scratch = ms_alloc(bytes);
  const Comparator comparator = {.call = compare, .env = env};
  merge_sort(items, scratch, count, size, &comparator);
  ms_free(scratch);
}
