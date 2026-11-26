/* base/arena.h: MsArena, bump allocation for compiler data (AST, types, HIR, MIR, checker tables).
 *
 * Everything allocated from an arena lives until ms_arena_reset or ms_arena_free, which release it in one
 * step; nothing is freed individually and nothing in it may own memory outside the arena. A failed parse or
 * check therefore leaves nothing to clean up. Blocks never move, so pointers into the arena stay valid.
 * Allocation failure reports through ms_fatal. The runtime does not use arenas. */
#ifndef MS_BASE_ARENA_H
#define MS_BASE_ARENA_H

#include "base/safe.h"

typedef struct MsArenaChunk MsArenaChunk;

/* A chain of chunks the arena bumps through. `head` is the chunk allocation continues in; `cursor` and `limit`
 * are its free range. An empty arena has no chunk. */
typedef struct MsArena {
  MsArenaChunk *head;
  uint8_t *cursor;
  uint8_t *limit;
} MsArena;

static inline MsArena ms_arena_new(void) {
  return (MsArena){0};
}

/* The allocation that starts a new chunk, or validates the alignment: `ms_arena_alloc` takes this path only when the
 * current chunk has no room. */
MS_RETURNS_NONNULL void *ms_arena_alloc_slow(MsArena *arena, size_t size, size_t alignment);

/* `size` uninitialised bytes aligned to `alignment` (a power of two up to 16). The bump inside the current chunk
 * is inline: most allocations of a pass are a handful of bytes. */
MS_RETURNS_NONNULL static inline void *ms_arena_alloc(MsArena *arena, size_t size, size_t alignment) {
  if (alignment != 0 && alignment <= 16 && (alignment & (alignment - 1)) == 0 && arena->head != NULL) {
    const uintptr_t at = ((uintptr_t)arena->cursor + (alignment - 1)) & ~(uintptr_t)(alignment - 1);
    if (at <= (uintptr_t)arena->limit && size <= (size_t)((uintptr_t)arena->limit - at)) {
      arena->cursor = (uint8_t *)at + size;
      return (void *)at;
    }
  }
  return ms_arena_alloc_slow(arena, size, alignment);
}

/* `size` zeroed bytes. */
MS_RETURNS_NONNULL void *ms_arena_alloc_zeroed(MsArena *arena, size_t size, size_t alignment);

/* A copy of `span` in the arena. */
MsSpan ms_arena_copy(MsArena *arena, MsSpan span);

/* Moves every chunk of `from` into `into`, which owns them from now on: what `from` handed out stays valid for as long
 * as `into` lives. `into` keeps bumping in its own current chunk. `from` is empty afterwards. */
void ms_arena_absorb(MsArena *into, MsArena *from);

/* Forgets everything; the arena is usable again and keeps its newest chunk, so a scratch arena reset between
 * queries allocates nothing once it has grown to the size of its largest query. */
void ms_arena_reset(MsArena *arena);

void ms_arena_free(MsArena *arena);

#define MS_ARENA_NEW(arena, T) ((T *)ms_arena_alloc_zeroed((arena), sizeof(T), _Alignof(T)))

/* `count` zeroed elements; a count whose byte size overflows reports through ms_fatal. */
#define MS_ARENA_NEW_ARRAY(arena, T, count)                                                                  \
  ((T *)ms_arena_alloc_array((arena), sizeof(T), _Alignof(T), (count)))

MS_RETURNS_NONNULL void *ms_arena_alloc_array(MsArena *arena, size_t element_size, size_t alignment,
                                              size_t count);

/* `count` elements left as they were in the chunk (not cleared): for an array whose entries are written before
 * they are read, so a large one costs only what is used. */
#define MS_ARENA_NEW_ARRAY_UNINIT(arena, T, count)                                                           \
  ((T *)ms_arena_alloc_array_uninit((arena), sizeof(T), _Alignof(T), (count)))

MS_RETURNS_NONNULL void *ms_arena_alloc_array_uninit(MsArena *arena, size_t element_size, size_t alignment,
                                                     size_t count);

#endif
