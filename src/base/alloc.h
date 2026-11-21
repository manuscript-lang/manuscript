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

/* `size` bytes, uninitialised, aligned for any scalar. size 0 gives a valid block. */
MS_NODISCARD MS_RETURNS_NONNULL void *ms_alloc(size_t size);

/* `size` zeroed bytes. */
MS_NODISCARD MS_RETURNS_NONNULL void *ms_alloc_zeroed(size_t size);

/* Resizes a block from ms_alloc (NULL allocates). The old block is invalid afterwards. */
MS_NODISCARD MS_RETURNS_NONNULL void *ms_realloc(void *block, size_t size);

/* Frees a block from ms_alloc; NULL is allowed. */
void ms_free(void *block);

#endif
