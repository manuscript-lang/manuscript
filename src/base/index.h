/* base/index.h: Manuscript's index rules, shared by lists, bytes and strings. An index may be negative and
 * then counts from the end; a slice has two such bounds. Each resolver returns false when the result is out
 * of range and leaves its outputs alone. */
#ifndef MS_BASE_INDEX_H
#define MS_BASE_INDEX_H

#include "base/safe.h"

/* Resolves `index` against `length` to a position below `length`. */
MS_NODISCARD MS_NONNULL static inline bool ms_resolve_index(size_t length, int64_t index, size_t *out) {
  const int64_t position = index < 0 ? (int64_t)length + index : index;
  if (position < 0 || (uint64_t)position >= length) {
    return false;
  }
  *out = (size_t)position;
  return true;
}

/* Resolves `index` to a position up to and including `length` (the place after the last element). */
MS_NODISCARD MS_NONNULL static inline bool ms_resolve_insert_index(size_t length, int64_t index,
                                                                   size_t *out) {
  const int64_t position = index < 0 ? (int64_t)length + index : index;
  if (position < 0 || (uint64_t)position > length) {
    return false;
  }
  *out = (size_t)position;
  return true;
}

/* Resolves the bounds start..end of a slice against `length`; both may be negative. */
MS_NODISCARD MS_NONNULL static inline bool ms_resolve_bounds(size_t length, int64_t start, int64_t end,
                                                             size_t *from, size_t *to) {
  const int64_t first = start < 0 ? (int64_t)length + start : start;
  const int64_t last = end < 0 ? (int64_t)length + end : end;
  if (first < 0 || last < first || (uint64_t)last > length) {
    return false;
  }
  *from = (size_t)first;
  *to = (size_t)last;
  return true;
}

#endif
