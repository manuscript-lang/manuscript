/* base/arena.h: MsArena, bump allocation for compiler data (AST, types, HIR, MIR, checker tables).
 *
 * Everything allocated from an arena lives until ms_arena_reset or ms_arena_free, which release it in one
 * step; nothing is freed individually and nothing in it may own memory outside the arena. A failed parse or
 * check therefore leaves nothing to clean up. Blocks never move, so pointers into the arena stay valid.
 * Allocation failure reports through ms_fatal. The runtime does not use arenas. */
#ifndef MS_BASE_ARENA_H
#define MS_BASE_ARENA_H

#include "base/safe.h"

typedef struct MsArena {
  void *heap; /* owned: a mimalloc heap, made on first use; NULL while empty */
} MsArena;

static inline MsArena ms_arena_new(void) {
  return (MsArena){0};
}

/* `size` uninitialised bytes aligned to `alignment` (a power of two up to 16). */
MS_RETURNS_NONNULL void *ms_arena_alloc(MsArena *arena, size_t size, size_t alignment);

/* `size` zeroed bytes. */
MS_RETURNS_NONNULL void *ms_arena_alloc_zeroed(MsArena *arena, size_t size, size_t alignment);

/* A copy of `span` in the arena. */
MsSpan ms_arena_copy(MsArena *arena, MsSpan span);

/* Forgets everything; the arena is usable again (mimalloc keeps the pages for reuse). */
void ms_arena_reset(MsArena *arena);

void ms_arena_free(MsArena *arena);

#define MS_ARENA_NEW(arena, T) ((T *)ms_arena_alloc_zeroed((arena), sizeof(T), _Alignof(T)))

/* `count` zeroed elements; a count whose byte size overflows reports through ms_fatal. */
#define MS_ARENA_NEW_ARRAY(arena, T, count)                                                                  \
  ((T *)ms_arena_alloc_array((arena), sizeof(T), _Alignof(T), (count)))

MS_RETURNS_NONNULL void *ms_arena_alloc_array(MsArena *arena, size_t element_size, size_t alignment,
                                              size_t count);

#endif
