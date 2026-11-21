/* runtime/core/alloc.h: statistics of the allocator (mimalloc, behind base/alloc). */
#ifndef MS_CORE_ALLOC_H
#define MS_CORE_ALLOC_H

#include <stdint.h>

/* The bytes of the heap in use and the bytes it has committed from the system, as the allocator counts them. */
void ms_core_heap_stats(int64_t *used, int64_t *committed);

#endif
