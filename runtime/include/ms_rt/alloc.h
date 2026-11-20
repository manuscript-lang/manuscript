/* ms_rt/alloc.h: the allocator, a thin layer over mimalloc (runtime/core/alloc.c). msrt_alloc, msrt_alloc_zeroed, msrt_realloc and msrt_free are the program ABI;
 * the msrt_heap_* functions serve the rest of the runtime (heap claim per thread, sizes, figures). */
#ifndef MS_RT_ALLOC_H
#define MS_RT_ALLOC_H

#include "ms_rt/base.h"

/* ms-sig: msrt_alloc(size: usize) -> *mut u8 @leaf */
void *msrt_alloc(size_t size);
/* ms-sig: msrt_alloc_zeroed(size: usize) -> *mut u8 @leaf */
void *msrt_alloc_zeroed(size_t size);
/* ms-sig: msrt_realloc(p: *mut u8, size: usize) -> *mut u8 */
void *msrt_realloc(void *p, size_t size);
/* ms-sig: msrt_free(p: *mut u8) */
void msrt_free(void *p);
/* ms-sig: msrt_heap_claim() */
void msrt_heap_claim(void);
/* ms-sig: msrt_heap_release() */
void msrt_heap_release(void);
/* ms-sig: msrt_heap_has() -> u8 */
uint8_t msrt_heap_has(void);
/* ms-sig: msrt_heap_usable_size(p: *mut u8) -> usize */
size_t msrt_heap_usable_size(void *p);
/* ms-sig: msrt_heap_trim(p: *mut u8, new_size: usize) -> *mut u8 */
void *msrt_heap_trim(void *p, size_t new_size);
/* ms-sig: msrt_heap_stats(out: *mut i64) */
void msrt_heap_stats(int64_t *out);
/* ms-sig: msrt_heap_requested(out: *mut u64) */
void msrt_heap_requested(uint64_t *out);
/* Starts the requested counters over (the program's main begins). */
/* ms-sig: msrt_heap_requested_reset() */
void msrt_heap_requested_reset(void);
/* The counting runtime (built with MS_ALLOC_STATS; zero otherwise): live blocks of the whole process, and the
 * nonzero counts by block size class (a power of two, 16 and up); the second returns how many
 * entries it wrote. */
/* ms-sig: msrt_heap_live_total() -> i64 */
int64_t msrt_heap_live_total(void);
/* ms-sig: msrt_heap_live_by_size(sizes: *mut usize, counts: *mut i64, capacity: usize) -> usize */
size_t msrt_heap_live_by_size(size_t *sizes, int64_t *counts, size_t capacity);
/* ms-sig: msrt_heap_sample_every(period: i64, hook: *mut u8) */
void msrt_heap_sample_every(int64_t period, void *hook);

#endif
