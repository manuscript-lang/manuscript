/* runtime/core/alloc.h: the runtime allocator, mimalloc behind the base/alloc hook. */
#ifndef MS_CORE_ALLOC_H
#define MS_CORE_ALLOC_H

#include "base/alloc.h"

/* The mimalloc allocator for ms_alloc_install; same contract (call before any block exists). */
const MsAllocator *ms_core_allocator(void);

#endif
