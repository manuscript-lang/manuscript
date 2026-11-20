/* alloc.h: internal to runtime/core. The exported allocator functions are declared in ms_rt/alloc.h; this
 * header holds what the allocator, its tests and regions share. */
#ifndef MS_ALLOC_H
#define MS_ALLOC_H

#include "ms_rt/alloc.h"

/* Size classes: sixteen-byte steps up to 128, then four per doubling to MSALLOC_MAX_SMALL. */
#define MSALLOC_MAX_SMALL 2048
#define MSALLOC_NUM_CLASSES 24
/* Large blocks go to the system allocator and are cached in classes of 4, 5, 6, 7 times 1 KiB, then doubling. */
#define MSALLOC_LARGE_MIN_SHIFT 12
#define MSALLOC_NUM_LARGE 49
#define MSALLOC_LARGE_MAX ((size_t)16 << 20)

extern const uint16_t msalloc_class_size[MSALLOC_NUM_CLASSES];
size_t msalloc_large_size(size_t large_class);

/* What a heap reservation is: small-block pages, their owner/class table, and the growth chunks. */
typedef struct msalloc_region {
    void *pages;
    size_t pages_len;
    void *table;
    void *grow;
    size_t grow_len;
    size_t grow_bits;
} msalloc_region;

/* Reserves the pages, their table and the growth chunks with `map`. When the system refuses the full
 * size (ulimit -v, a container, valgrind) the reservation is halved until it fits, and the heap keeps
 * a quarter of what fit so later stacks and system maps still find space. False when even the
 * smallest is refused. Exposed so a test can refuse maps. */
bool msalloc_reserve(void *(*map)(size_t), void (*unmap)(void *, size_t), msalloc_region *out);

/* Called when the system cannot give a block: reports out-of-memory and does not return. Defined by
 * the Rust runtime (crates/ms-rt/src/alloc.rs); a C test defines its own. */
void msalloc_rust_oom(size_t bytes) __attribute__((noreturn));

/* Blocks the calling thread holds. Defined only when alloc.c is built with -DMS_ALLOC_STATS (the unit tests),
 * which also scribbles over freed blocks so a use after free shows up. */
int64_t msalloc_live_blocks(void);

#endif
