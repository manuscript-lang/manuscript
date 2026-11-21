/* runtime/core/sort_ints.c: the sort of Int lists: insertion sort when short, radix sort when long. Equal
 * Ints are indistinguishable, so an unstable sort gives the same list as a stable one. */
#include "runtime/core/list.h"

#include "base/alloc.h"

/* Int lists up to this long are insertion sorted; longer ones are radix sorted. */
#define RADIX_THRESHOLD 64
/* The digit of a counting pass is a byte. */
#define RADIX_BITS 8U
#define RADIX_BUCKETS ((size_t)1 << RADIX_BITS)

static int64_t load_int(const uint8_t *items, size_t index) {
  int64_t value = 0;
  __builtin_memcpy(&value, items + index * sizeof value, sizeof value);
  return value;
}

static void store_int(uint8_t *items, size_t index, int64_t value) {
  __builtin_memcpy(items + index * sizeof value, &value, sizeof value);
}

static void insertion_sort_ints(uint8_t *items, size_t count) {
  for (size_t i = 1; i < count; i++) {
    const int64_t held = load_int(items, i);
    size_t j = i;
    while (j > 0 && load_int(items, j - 1) > held) {
      store_int(items, j, load_int(items, j - 1));
      j--;
    }
    store_int(items, j, held);
  }
}

/* The key whose unsigned order is the signed order of `value`. */
static uint64_t order_key(int64_t value) {
  return (uint64_t)value ^ ((uint64_t)1 << 63);
}

/* Sorts the first `count` Ints of the 8-aligned `items` by their order keys' bits `low` to `high` (the other
 * bits are equal in all of them), by one stable counting pass per byte of those bits, from `items` to `spare`
 * and back. Returns whichever of the two holds the result. A byte that is the same in every key costs only
 * its count. */
static int64_t *lsd_sort(int64_t *items, int64_t *spare, size_t count, unsigned low, unsigned high) {
  int64_t *from = items;
  int64_t *to = spare;
  for (unsigned shift = low; shift <= high; shift += RADIX_BITS) {
    const unsigned width = high - shift + 1 < RADIX_BITS ? high - shift + 1 : RADIX_BITS;
    const uint64_t mask = ((uint64_t)1 << width) - 1;
    size_t offsets[RADIX_BUCKETS] = {0};
    for (size_t i = 0; i < count; i++) {
      offsets[(order_key(from[i]) >> shift) & mask]++;
    }
    size_t running = 0;
    bool varies = true;
    for (size_t bucket = 0; bucket <= mask; bucket++) {
      varies = varies && offsets[bucket] != count;
      const size_t bucket_size = offsets[bucket];
      offsets[bucket] = running;
      running += bucket_size;
    }
    if (!varies) {
      continue;
    }
    for (size_t i = 0; i < count; i++) {
      const int64_t value = from[i];
      to[offsets[(order_key(value) >> shift) & mask]++] = value;
    }
    int64_t *swap = from;
    from = to;
    to = swap;
  }
  return from;
}

/* The bits in which the order keys of the Ints differ: the lowest and highest. False when they are all equal.
 */
static bool varying_bits(const int64_t *items, size_t count, unsigned *low, unsigned *high) {
  uint64_t any = 0;
  uint64_t all = ~(uint64_t)0;
  for (size_t i = 0; i < count; i++) {
    const uint64_t key = order_key(items[i]);
    any |= key;
    all &= key;
  }
  const uint64_t differ = any ^ all;
  if (differ == 0) {
    return false;
  }
  *low = (unsigned)__builtin_ctzll(differ);
  *high = 63U - (unsigned)__builtin_clzll(differ);
  return true;
}

/* Ints that sort without a heap buffer (16 KiB of stack). */
#define STACK_SPARE_ITEMS ((size_t)2048)
#define PARTITION_MIN ((size_t)1 << 13)

/* Sorts a long list by one partition on its top byte, then each part (a few thousand Ints, which stay in
 * cache) by counting passes on the bits below: one pass over memory instead of a pass per byte. */
static void partition_sort_ints(int64_t *items, int64_t *spare, size_t count, unsigned low, unsigned high) {
  const unsigned shift = high - (RADIX_BITS - 1);
  size_t starts[RADIX_BUCKETS + 1] = {0};
  for (size_t i = 0; i < count; i++) {
    starts[((order_key(items[i]) >> shift) & (RADIX_BUCKETS - 1)) + 1]++;
  }
  for (size_t bucket = 0; bucket < RADIX_BUCKETS; bucket++) {
    starts[bucket + 1] += starts[bucket];
  }
  size_t next[RADIX_BUCKETS];
  __builtin_memcpy(next, starts, sizeof next);
  for (size_t i = 0; i < count; i++) {
    const int64_t value = items[i];
    spare[next[(order_key(value) >> shift) & (RADIX_BUCKETS - 1)]++] = value;
  }
  for (size_t bucket = 0; bucket < RADIX_BUCKETS; bucket++) {
    const size_t start = starts[bucket];
    const size_t size = starts[bucket + 1] - start;
    int64_t *sorted = spare + start;
    if (size > 1 && shift > low) {
      sorted = lsd_sort(spare + start, items + start, size, low, shift - 1);
    }
    if (sorted != items + start) {
      __builtin_memcpy(items + start, sorted, size * sizeof(int64_t));
    }
  }
}

static void radix_sort_ints(MsList *list) {
  int64_t *items = (int64_t *)__builtin_assume_aligned(list->ptr, _Alignof(int64_t));
  unsigned low = 0;
  unsigned high = 0;
  if (!varying_bits(items, list->len, &low, &high)) {
    return;
  }
  /* A short list sorts in a stack buffer: no allocation, and nothing to unwind if the run is cancelled. */
  int64_t stack_spare[STACK_SPARE_ITEMS];
  const bool on_stack = list->len <= STACK_SPARE_ITEMS;
  int64_t *spare = on_stack ? stack_spare
                            : (int64_t *)__builtin_assume_aligned(ms_alloc(list->len * sizeof(int64_t)),
                                                                  _Alignof(int64_t));
  if (list->len >= PARTITION_MIN && high - low >= RADIX_BITS * 2) {
    partition_sort_ints(items, spare, list->len, low, high);
  } else {
    int64_t *sorted = lsd_sort(items, spare, list->len, low, high);
    if (sorted != items) {
      __builtin_memcpy(items, sorted, list->len * sizeof(int64_t));
    }
  }
  if (!on_stack) {
    ms_free(spare);
  }
}

static void reverse_ints(MsList *list) {
  for (size_t front = 0, back = list->len; front + 1 < back; front++) {
    back--;
    const int64_t held = load_int(list->ptr, front);
    store_int(list->ptr, front, load_int(list->ptr, back));
    store_int(list->ptr, back, held);
  }
}

/* Sorts a list of Ints in place, ascending or (when `desc` is not zero) descending. Equal Ints are
 * indistinguishable, so an unstable sort gives the same list as a stable one. */
void msrt_list_sort_ints(MsList *v, int64_t desc) {
  if (v->len < 2) {
    return;
  }
  if (v->len <= RADIX_THRESHOLD) {
    insertion_sort_ints(v->ptr, v->len);
  } else {
    radix_sort_ints(v);
  }
  if (desc != 0) {
    reverse_ints(v);
  }
}
