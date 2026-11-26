/* base/alloc_huge.h: blocks that grew past a few MiB are mapped pages the kernel can move, not mimalloc blocks.
 *
 * A list or string that doubles from a few KiB to tens of MiB copies its whole content at every step into pages never
 * touched before, so every byte is faulted in twice (about 2 us a page on a VM); `mremap` moves the pages without
 * copying or faulting them again, as the system allocator does. Only a resize (ms_realloc) makes such a block, and
 * only on Linux; elsewhere every function here declines and the block stays in mimalloc. */
#ifndef MS_BASE_ALLOC_HUGE_H
#define MS_BASE_ALLOC_HUGE_H

#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* The smallest size a resize maps (a smaller block is mimalloc's), and how many mappings are live. */
enum { MS_HUGE_MIN = 4 << 20 };
extern _Atomic size_t ms_huge_live;
extern _Atomic uintptr_t ms_huge_lowest, ms_huge_highest;

/* Whether `block` may be one of these mappings: two loads and a compare when none is live or it lies outside the range
 * of the live ones, which settles nearly every free and resize of an ordinary block. */
static inline bool ms_huge_maybe(const void *block) {
  const uintptr_t at = (uintptr_t)block;
  return atomic_load_explicit(&ms_huge_live, memory_order_relaxed) != 0 &&
         at >= atomic_load_explicit(&ms_huge_lowest, memory_order_relaxed) &&
         at <= atomic_load_explicit(&ms_huge_highest, memory_order_relaxed);
}

/* Told by alloc.c's owner of the free path whether any mapping is live (set under the table lock). */
void ms_alloc_huge_flag(bool live);

/* Whether `block` is one of these mappings. */
bool ms_huge_owns(const void *block);

/* Resizes `block` (NULL, a mimalloc block or a mapping) to `size` bytes when the result is or was a mapping; false when
 * the caller's allocator should do it. On true `*out` is the
 * new block, NULL when the system is out of memory. */
bool ms_huge_realloc(void *block, size_t size, void **out);

/* Unmaps `block`, which ms_huge_owns accepted. */
void ms_huge_free(void *block);

/* The mapped size of a block ms_huge_owns accepted. */
size_t ms_huge_usable(const void *block);

#endif
