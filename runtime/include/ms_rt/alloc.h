/* ms_rt/alloc.h: the allocator. msrt_alloc, msrt_alloc_zeroed, msrt_realloc and msrt_free are the program ABI;
 * the msrt_heap_* functions serve the rest of the runtime (heap claim per thread, sizes, figures). */
#ifndef MS_RT_ALLOC_H
#define MS_RT_ALLOC_H

#include "ms_rt/base.h"

void *msrt_alloc(size_t size);
void *msrt_alloc_zeroed(size_t size);
void *msrt_realloc(void *p, size_t size);
void msrt_free(void *p);
void msrt_heap_claim(void);
void msrt_heap_release(void);
uint8_t msrt_heap_has(void);
uint8_t msrt_heap_owns(const void *p);
size_t msrt_heap_usable_size(void *p);
void *msrt_heap_trim(void *p, size_t new_size);
void *msrt_heap_alloc_zeroed_cached(size_t size);
size_t msrt_heap_large_request(size_t size);
void *msrt_heap_shared_take(size_t size);
uint8_t msrt_heap_shared_put(void *p);
void msrt_heap_stats(int64_t *out);
void msrt_heap_requested(uint64_t *out);
void msrt_heap_sample_every(int64_t period, void *hook);


#endif
