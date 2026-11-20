/* alloc.h: internal to runtime/core. The exported allocator functions are declared in ms_rt/alloc.h. */
#ifndef MS_ALLOC_H
#define MS_ALLOC_H

#include "ms_rt/alloc.h"

/* Called when the system cannot give a block: reports out-of-memory and does not return. Defined by
 * core/fault.c; a C test defines its own. */
void msalloc_oom(size_t bytes) __attribute__((noreturn));

/* Blocks the calling process holds. Defined only when alloc.c is built with -DMS_ALLOC_STATS (the counting runtime
 * and the unit tests). */
int64_t msalloc_live_blocks(void);

/* The calling thread's own requested counters, and putting them back: the runtime's bookkeeping after main returns
 * (stack pool, slot lists) is not the program's allocation and stays out of the counting report. */
void ms_heap_requested_thread(uint64_t *out);
void ms_heap_requested_restore(const uint64_t *saved);

#endif
