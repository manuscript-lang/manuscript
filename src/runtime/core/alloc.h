/* runtime/core/alloc.h: statistics of the allocator (mimalloc, behind base/alloc). */
#ifndef MS_CORE_ALLOC_H
#define MS_CORE_ALLOC_H

#include <stddef.h>
#include <stdint.h>

/* The bytes of live blocks (base/alloc counts them) and the bytes the heap has committed from the system. */
void ms_core_heap_stats(int64_t *used, int64_t *committed);

/* The heap of compiled programs: blocks of the allocator base/alloc uses (mimalloc). Out of memory is a fault, so
 * a returned block is never null; `msrt_free(NULL)` is allowed. */

/* ms-sig: msrt_alloc(size: usize) -> *mut u8 */
void *msrt_alloc(size_t size);

/* ms-sig: msrt_alloc_zeroed(size: usize) -> *mut u8 */
void *msrt_alloc_zeroed(size_t size);

/* ms-sig: msrt_realloc(p: *mut u8, size: usize) -> *mut u8 */
void *msrt_realloc(void *block, size_t size);

/* ms-sig: msrt_free(p: *mut u8) */
void msrt_free(void *block);

/* Operations executed, as the counting calls of an `ms bench --ops` build add them (a block's instruction count). */

/* ms-sig: msrt_ops_add(n: i64) @end */
void msrt_ops_add(int64_t count);

/* The operations counted so far. */
int64_t ms_core_operations(void);

#endif
