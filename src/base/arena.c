/* Owns the chunks behind an arena (see arena.h). */
#include "base/arena.h"

#include <mimalloc.h>

#include "base/fatal.h"

#define MS_ARENA_MAX_ALIGNMENT 16
/* The first chunk, and the growth cap: each chunk of a growing arena is twice the last up to the cap. A request of
 * more than a quarter of the next chunk gets a chunk of its own, so the free range of the current one is not lost. */
#define MS_ARENA_FIRST_CHUNK 4096u
#define MS_ARENA_MAX_CHUNK (1024u * 1024u)

struct MsArenaChunk {
  MsArenaChunk *next;
  size_t size; /* bytes after the header */
  size_t pad[2];
};

_Static_assert(sizeof(MsArenaChunk) % MS_ARENA_MAX_ALIGNMENT == 0, "chunk header keeps 16-byte alignment");

static uint8_t *chunk_data(MsArenaChunk *chunk) {
  return (uint8_t *)(void *)(chunk + 1);
}

static MsArenaChunk *chunk_new(size_t size) {
  MsArenaChunk *chunk = mi_malloc_aligned(sizeof *chunk + size, MS_ARENA_MAX_ALIGNMENT);
  if (chunk == NULL) {
    ms_fatal(MS_FATAL_OUT_OF_MEMORY, "out of memory");
  }
  chunk->next = NULL;
  chunk->size = size;
  return chunk;
}

static void *bump(MsArena *arena, size_t size, size_t alignment) {
  uintptr_t at = ((uintptr_t)arena->cursor + (alignment - 1)) & ~(uintptr_t)(alignment - 1);
  if (arena->head == NULL || at > (uintptr_t)arena->limit || size > (size_t)((uintptr_t)arena->limit - at)) {
    return NULL;
  }
  arena->cursor = (uint8_t *)at + size;
  return (void *)at;
}

void *ms_arena_alloc_slow(MsArena *arena, size_t size, size_t alignment) {
  if (alignment == 0 || alignment > MS_ARENA_MAX_ALIGNMENT || (alignment & (alignment - 1)) != 0) {
    ms_fatal(MS_FATAL_INVARIANT, "bad arena alignment");
  }
  void *block = bump(arena, size, alignment);
  if (block != NULL) {
    return block;
  }
  size_t next = arena->head == NULL ? MS_ARENA_FIRST_CHUNK : arena->head->size * 2;
  next = next > MS_ARENA_MAX_CHUNK ? MS_ARENA_MAX_CHUNK : next;
  if (size > next / 4) {
    /* A chunk of its own, behind the current one. */
    MsArenaChunk *own = chunk_new(size);
    if (arena->head == NULL) {
      arena->head = own;
      arena->cursor = arena->limit = chunk_data(own) + size;
    } else {
      own->next = arena->head->next;
      arena->head->next = own;
    }
    return chunk_data(own);
  }
  MsArenaChunk *chunk = chunk_new(next);
  chunk->next = arena->head;
  arena->head = chunk;
  arena->cursor = chunk_data(chunk);
  arena->limit = chunk_data(chunk) + next;
  return bump(arena, size, alignment);
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

void *ms_arena_alloc_array_uninit(MsArena *arena, size_t element_size, size_t alignment, size_t count) {
  size_t bytes = 0;
  if (!ms_size_mul(element_size, count, &bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "arena array size overflow");
  }
  return ms_arena_alloc(arena, bytes, alignment);
}

MsSpan ms_arena_copy(MsArena *arena, MsSpan span) {
  uint8_t *copy = ms_arena_alloc(arena, span.len, 1);
  if (span.len != 0) {
    __builtin_memcpy(copy, span.ptr, span.len);
  }
  return ms_span_of(copy, span.len);
}

static void release(MsArenaChunk *chunk) {
  while (chunk != NULL) {
    MsArenaChunk *next = chunk->next;
    mi_free(chunk);
    chunk = next;
  }
}

void ms_arena_free(MsArena *arena) {
  release(arena->head);
  *arena = (MsArena){0};
}

void ms_arena_reset(MsArena *arena) {
  if (arena->head == NULL) {
    return;
  }
  /* The head is the newest and largest regular chunk, or a chunk made for one large request. */
  release(arena->head->next);
  arena->head->next = NULL;
  arena->cursor = chunk_data(arena->head);
  arena->limit = arena->cursor + arena->head->size;
}

void ms_arena_absorb(MsArena *into, MsArena *from) {
  if (from->head == NULL) {
    return;
  }
  if (into->head == NULL) {
    *into = *from;
  } else {
    MsArenaChunk *tail = into->head;
    while (tail->next != NULL) {
      tail = tail->next;
    }
    tail->next = from->head;
  }
  *from = (MsArena){0};
}
