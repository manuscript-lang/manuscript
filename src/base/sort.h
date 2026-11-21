/* base/sort.h: a stable merge sort of fixed-size elements by a comparator with an environment. */
#ifndef MS_BASE_SORT_H
#define MS_BASE_SORT_H

#include "base/safe.h"

/* Compares two elements: negative when `a` sorts first. `env` is the caller's context. */
typedef int64_t (*MsSortCompare)(uint8_t *env, const uint8_t *a, const uint8_t *b);

/* Sorts `count` elements of `size` bytes at `items`, keeping equal elements in order. Uses `count * size`
 * bytes of scratch from the allocator, which a comparator that leaves by a jump does not free. A comparator
 * that is not a total order only gives a poor order; every element is kept exactly once. */
void ms_sort(uint8_t *items, size_t count, size_t size, MsSortCompare compare, uint8_t *env);

#endif
