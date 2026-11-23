/* base/alloc.h: the one allocation entry point of the value layer and the compiler.
 *
 * Every allocation in base goes through these functions, so a program chooses its allocator once: the
 * default is mimalloc, for the runtime, the compiler and the tools alike; the compiler's per-run data goes in an
 * arena (base/arena.h). A failed allocation never returns null; it calls ms_fatal(MS_FATAL_OUT_OF_MEMORY, ...).
 * Sizes are checked by the caller with ms_size_mul / ms_size_add before they get here.
 * Ownership: a block returned here belongs to the caller until it goes to ms_free or ms_realloc. */
#ifndef MS_BASE_ALLOC_H
#define MS_BASE_ALLOC_H

#include "base/safe.h"

typedef struct MsAllocator {
  void *(*allocate)(size_t size);
  void *(*reallocate)(void *block, size_t size);
  void (*release)(void *block);
} MsAllocator;

/* Replaces the allocator (a test hook); NULL restores mimalloc. Call before any block exists and before
 * any other thread starts: blocks must be freed by the allocator that made them. */
void ms_alloc_install(const MsAllocator *allocator);

/* A function called with the size of every allocation and resize, on the thread that makes it (the allocation profiler,
 * runtime/entry/profile.h); NULL, the default, makes none. Set before the first thread starts; the function must not
 * allocate through ms_alloc. */
typedef void (*MsAllocObserver)(size_t size);
void ms_alloc_observe(MsAllocObserver observer);

/* The allocations the calling thread has made and the bytes they asked for (a resize counts as one more). */
void ms_alloc_counts(int64_t *allocations, int64_t *bytes);

/* The bytes of all live blocks of every thread (usable sizes, so a little over what was asked for); 0 under a
 * test allocator. */
int64_t ms_alloc_live_bytes(void);
/* Starts counting live bytes (until then ms_alloc_live_bytes is 0): a program that reads the figure calls this before
 * main; the count excludes blocks made earlier. */
void ms_alloc_track_live(void);

#ifdef MS_STATS
/* The counting runtime (cmake --preset stats): the blocks live now, every thread, and a reset of the calling thread's
 * allocation counts (the program's main starts counting from zero). */
int64_t ms_alloc_live_blocks(void);
void ms_alloc_counts_reset(void);
/* With MS_STATS_TRACE set: one line per live block with its allocation site (addresses to resolve with addr2line). */
void ms_alloc_trace_report(void);
#endif

/* `size` bytes, uninitialised, aligned for any scalar. size 0 gives a valid block. */
MS_NODISCARD MS_RETURNS_NONNULL void *ms_alloc(size_t size);

/* `size` zeroed bytes. */
MS_NODISCARD MS_RETURNS_NONNULL void *ms_alloc_zeroed(size_t size);

/* Resizes a block from ms_alloc (NULL allocates). The old block is invalid afterwards. */
MS_NODISCARD MS_RETURNS_NONNULL void *ms_realloc(void *block, size_t size);

/* Frees a block from ms_alloc; NULL is allowed. */
void ms_free(void *block);

#endif
