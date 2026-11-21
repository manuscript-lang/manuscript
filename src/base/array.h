/* base/array.h: growth of a plain array an owner declares as `T *items; size_t length; size_t capacity;`, for
 * tables whose items are not MsList elements (a struct that already owns three such arrays). The helper only
 * grows the storage; the owner frees `items` with ms_free. A request whose byte size overflows reports false. */
#ifndef MS_BASE_ARRAY_H
#define MS_BASE_ARRAY_H

#include "base/alloc.h"
#include "base/safe.h"

enum { MS_ARRAY_MIN_CAPACITY = 16 };

/* Makes room for `needed` items of `item_size` bytes at `*items`, doubling the capacity so repeated pushes cost
 * amortised constant time. New items are uninitialised. */
MS_NODISCARD MS_NONNULL static inline bool ms_array_reserve(void **items, size_t *capacity, size_t needed,
                                                            size_t item_size) {
  if (needed <= *capacity) {
    return true;
  }
  size_t grown = *capacity < MS_ARRAY_MIN_CAPACITY ? MS_ARRAY_MIN_CAPACITY : *capacity;
  while (grown < needed) {
    if (!ms_size_mul(grown, 2, &grown)) {
      return false;
    }
  }
  size_t bytes = 0;
  if (!ms_size_mul(grown, item_size, &bytes)) {
    return false;
  }
  *items = ms_realloc(*items, bytes);
  *capacity = grown;
  return true;
}

#endif
