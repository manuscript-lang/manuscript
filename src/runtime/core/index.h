/* index.h: Manuscript's index rules, shared by lists and Bytes. An index may be negative and then counts from
 * the end; a slice has two such bounds. Each resolver returns false when the result is out of range and leaves
 * its outputs alone.
 */
#ifndef MS_INDEX_H
#define MS_INDEX_H

#include "ms_rt/base.h"
#include "ms_rt/safe.h"

/* Resolves `index` against `len` to a position below `len`. */
MS_NODISCARD MS_NONNULL static inline bool ms_resolve_index(size_t len, int64_t index, size_t *out) {
    const int64_t position = index < 0 ? (int64_t)len + index : index;
    if (position < 0 || (uint64_t)position >= len) {
        return false;
    }
    *out = (size_t)position;
    return true;
}

/* Resolves `index` against `len` to a position up to and including `len` (the place after the last element). */
MS_NODISCARD MS_NONNULL static inline bool ms_resolve_insert_index(size_t len, int64_t index, size_t *out) {
    const int64_t position = index < 0 ? (int64_t)len + index : index;
    if (position < 0 || (uint64_t)position > len) {
        return false;
    }
    *out = (size_t)position;
    return true;
}

/* Resolves the bounds start..end of a slice against `len`; both ends may be negative. */
MS_NODISCARD MS_NONNULL_ARGS(4, 5) static inline bool ms_resolve_bounds(size_t len, int64_t start, int64_t end, size_t *from,
                                                                       size_t *to) {
    const int64_t first = start < 0 ? (int64_t)len + start : start;
    const int64_t last = end < 0 ? (int64_t)len + end : end;
    if (first < 0 || last < first || (uint64_t)last > len) {
        return false;
    }
    *from = (size_t)first;
    *to = (size_t)last;
    return true;
}

#endif
