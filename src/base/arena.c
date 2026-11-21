/* Owns arena chunks and bump allocation (see arena.h). */
#include "base/arena.h"

#include "base/alloc.h"
#include "base/fatal.h"

#define MS_ARENA_MIN_CHUNK ((size_t)64 * 1024)
#define MS_ARENA_MAX_ALIGNMENT 16

struct MsArenaChunk {
  MsArenaChunk *next; /* owned: the older chunk */
  size_t capacity;
  _Alignas(MS_ARENA_MAX_ALIGNMENT) uint8_t bytes[]; /* capacity bytes */
};

static void start_chunk(MsArena *arena, size_t needed) {
  const size_t previous = arena->chunks != NULL ? arena->chunks->capacity : 0;
  size_t capacity = previous < MS_ARENA_MIN_CHUNK ? MS_ARENA_MIN_CHUNK : previous;
  size_t doubled = 0;
  if (ms_size_mul(capacity, 2, &doubled)) {
    capacity = doubled;
  }
  if (capacity < needed) {
    capacity = needed;
  }
  size_t total = 0;
  if (!ms_size_add(sizeof(MsArenaChunk), capacity, &total)) {
    ms_fatal(MS_FATAL_OVERFLOW, "arena size overflow");
  }
  MsArenaChunk *chunk = ms_alloc(total);
  chunk->next = arena->chunks;
  chunk->capacity = capacity;
  arena->chunks = chunk;
  arena->cursor = chunk->bytes;
  arena->end = chunk->bytes + capacity;
}

static uint8_t *take(MsArena *arena, size_t size, size_t alignment) {
  const uintptr_t start = (uintptr_t)arena->cursor;
  const uintptr_t aligned = (start + (alignment - 1)) & ~(uintptr_t)(alignment - 1);
  const size_t padding = (size_t)(aligned - start);
  if (arena->cursor == NULL || size > (size_t)(arena->end - arena->cursor) ||
      padding > (size_t)(arena->end - arena->cursor) - size) {
    return NULL;
  }
  uint8_t *block = arena->cursor + padding;
  arena->cursor = block + size;
  return block;
}

void *ms_arena_alloc(MsArena *arena, size_t size, size_t alignment) {
  if (alignment == 0 || alignment > MS_ARENA_MAX_ALIGNMENT || (alignment & (alignment - 1)) != 0) {
    ms_fatal(MS_FATAL_INVARIANT, "bad arena alignment");
  }
  uint8_t *block = take(arena, size, alignment);
  if (block == NULL) {
    size_t needed = 0;
    if (!ms_size_add(size, alignment, &needed)) {
      ms_fatal(MS_FATAL_OVERFLOW, "arena size overflow");
    }
    start_chunk(arena, needed);
    block = take(arena, size, alignment);
  }
  return block;
}

void *ms_arena_alloc_zeroed(MsArena *arena, size_t size, size_t alignment) {
  void *block = ms_arena_alloc(arena, size, alignment);
  __builtin_memset(block, 0, size);
  return block;
}

void *ms_arena_alloc_array(MsArena *arena, size_t element_size, size_t alignment, size_t count) {
  size_t bytes = 0;
  if (!ms_size_mul(element_size, count, &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "arena array size overflow");
  }
  return ms_arena_alloc_zeroed(arena, bytes, alignment);
}

MsSpan ms_arena_copy(MsArena *arena, MsSpan span) {
  uint8_t *copy = ms_arena_alloc(arena, span.len, 1);
  if (span.len != 0) {
    __builtin_memcpy(copy, span.ptr, span.len);
  }
  return ms_span_of(copy, span.len);
}

void ms_arena_reset(MsArena *arena) {
  MsArenaChunk *newest = arena->chunks;
  if (newest == NULL) {
    return;
  }
  MsArenaChunk *older = newest->next;
  newest->next = NULL;
  while (older != NULL) {
    MsArenaChunk *next = older->next;
    ms_free(older);
    older = next;
  }
  arena->cursor = newest->bytes;
  arena->end = newest->bytes + newest->capacity;
}

void ms_arena_free(MsArena *arena) {
  MsArenaChunk *chunk = arena->chunks;
  while (chunk != NULL) {
    MsArenaChunk *next = chunk->next;
    ms_free(chunk);
    chunk = next;
  }
  *arena = (MsArena){0};
}
