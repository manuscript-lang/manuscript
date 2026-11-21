/* runtime/core/alloc.h: the runtime allocator, mimalloc behind the base/alloc hook. */
#ifndef MS_CORE_ALLOC_H
#define MS_CORE_ALLOC_H

#include <stdint.h>

#include "base/alloc.h"

/* The mimalloc allocator for ms_alloc_install; same contract (call before any block exists). */
const MsAllocator *ms_core_allocator(void);

/* The bytes of the heap in use and the bytes it has committed from the system, as the allocator counts them. */
void ms_core_heap_stats(int64_t *used, int64_t *committed);

#endif
