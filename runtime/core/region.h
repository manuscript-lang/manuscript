/* region.h: regions, the second half of the allocator (M3 in the runtime plan).
 *
 * A region owns every block allocated from it. Allocation is a pointer bump inside a chunk, nothing is
 * freed one block at a time, and releasing the region frees all of it in one step. A region has a byte
 * budget: an allocation that would take it past the budget returns NULL and changes nothing, so the
 * caller reports the failure (a request that holds too much, a task over its limit) instead of the
 * process running out of memory. Values that outlive the region are moved out explicitly (copied into
 * the heap with msrt_alloc), which the one-owner rules already express.
 *
 * Chunks come from the heap (msrt_alloc), so a region may be released from any thread. A region is not
 * thread safe: one owner at a time. Not yet part of the program ABI (ms_rt.h); the runtime calls it.
 */
#ifndef MS_REGION_H
#define MS_REGION_H

#include "ms_rt.h"

typedef struct msregion msregion;

/* A region that holds at most `budget` bytes of chunks, headers included. NULL when the heap cannot give
 * the first chunk or the budget is smaller than the region's own header. */
msregion *msregion_new(size_t budget);
/* `size` bytes, 16-byte aligned and uninitialised, valid until reset or release; NULL over the budget. */
void *msregion_alloc(msregion *r, size_t size);
/* The same, zeroed. */
void *msregion_alloc_zeroed(msregion *r, size_t size);
/* Bytes handed out (rounded up to 16) since creation or the last reset. */
size_t msregion_used(const msregion *r);
/* Bytes of chunks held now; never above the budget. */
size_t msregion_held(const msregion *r);
size_t msregion_budget(const msregion *r);
/* Every block is dead; the first chunk stays for reuse and the rest go back to the heap. */
void msregion_reset(msregion *r);
/* Frees the region and everything allocated from it. NULL is ignored. */
void msregion_release(msregion *r);

#endif
