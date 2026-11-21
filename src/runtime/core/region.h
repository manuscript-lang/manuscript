/* region.h: regions, the second half of the allocator.
 *
 * A region owns every block allocated from it. Allocation bumps a pointer inside a chunk, nothing is freed one
 * block at a time, and releasing the region frees all of it in one step. A region has a byte budget: an
 * allocation that would take it past the budget fails and changes nothing, so the caller reports the failure
 * (a request that holds too much, a task over its limit) instead of the process running out of memory. Values
 * that outlive the region are moved out explicitly: copied into the heap with msrt_alloc.
 *
 * Chunks come from the heap, so a region may be released from any thread. A region is not thread safe: one
 * owner at a time. Not yet part of the program ABI; the runtime calls it.
 */
#ifndef MS_REGION_H
#define MS_REGION_H

#include "ms_rt/alloc.h"
#include "ms_rt/safe.h"

typedef struct MsRegion MsRegion;

/* Creates a region that holds at most `budget` bytes of chunks, headers included. The caller owns it and
 * frees it with ms_region_release. False, leaving *out untouched, when the budget is smaller than the region's
 * own header or the heap cannot give the first chunk. */
MS_NODISCARD MS_NONNULL bool ms_region_new(size_t budget, MsRegion **out);

/* Allocates `size` bytes, 16-byte aligned and uninitialised, valid until the region is reset or released.
 * False, changing nothing, when the budget would be exceeded. */
MS_NODISCARD MS_NONNULL bool ms_region_alloc(MsRegion *region, size_t size, void **out);

/* The same, zeroed. */
MS_NODISCARD MS_NONNULL bool ms_region_alloc_zeroed(MsRegion *region, size_t size, void **out);

/* Bytes handed out (rounded up to 16) since creation or the last reset. */
MS_NONNULL size_t ms_region_used(const MsRegion *region);

/* Bytes of chunks held now; never above the budget. */
MS_NONNULL size_t ms_region_held(const MsRegion *region);

MS_NONNULL size_t ms_region_budget(const MsRegion *region);

/* Every block is dead; the first chunk stays for reuse and the rest go back to the heap. */
MS_NONNULL void ms_region_reset(MsRegion *region);

/* Frees the region and everything allocated from it. A null region is ignored. */
void ms_region_release(MsRegion *region);

#endif
