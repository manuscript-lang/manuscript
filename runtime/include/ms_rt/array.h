/* ms_rt/array.h: growable arrays of plain items: the scheduler's tables and the buffers of the std natives.
 *
 * An array is three fields the owner declares: `T *items; size_t length; size_t capacity;`. These helpers
 * only grow the storage; they never move or free an item, and the owner frees `items` with msrt_free.
 * Allocation does not fail (the allocator reports out of memory itself); false means the byte size of the
 * request overflows, which a table of this runtime cannot reach.
 */
#ifndef MS_RT_ARRAY_H
#define MS_RT_ARRAY_H

#include <stdlib.h>

#include "ms_rt/alloc.h"
#include "ms_rt/safe.h"

enum { MS_ARRAY_MIN_CAPACITY = 16 };

/* Makes room for `needed` items of `item_size` bytes at `*items`, doubling the capacity so repeated pushes
 * cost amortised constant time. New items are uninitialised. */
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
    void *const moved = msrt_realloc(*items, bytes);
    if (moved == NULL) {
        return false;
    }
    *items = moved;
    *capacity = grown;
    return true;
}

/* The same on the system allocator, for a table that belongs to the runtime and not to the program (a task's cleanup
 * stack, guards and equality pairs): the counting runtime reports the program's blocks, and the owner frees `items`
 * with free. */
MS_NODISCARD MS_NONNULL static inline bool ms_array_reserve_system(void **items, size_t *capacity, size_t needed,
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
    void *const moved = realloc(*items, bytes);
    if (moved == NULL) {
        return false;
    }
    *items = moved;
    *capacity = grown;
    return true;
}

#endif
