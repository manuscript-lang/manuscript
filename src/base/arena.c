/* Owns the mimalloc heap behind an arena (see arena.h). */
#include "base/arena.h"

#include <mimalloc.h>

#include "base/fatal.h"

#define MS_ARENA_MAX_ALIGNMENT 16

void *ms_arena_alloc(MsArena *arena, size_t size, size_t alignment) {
  if (alignment == 0 || alignment > MS_ARENA_MAX_ALIGNMENT || (alignment & (alignment - 1)) != 0) {
    ms_fatal(MS_FATAL_INVARIANT, "bad arena alignment");
  }
  if (arena->heap == NULL) {
    arena->heap = mi_heap_new();
  }
  void *block = arena->heap != NULL ? mi_heap_malloc_aligned(arena->heap, size, alignment) : NULL;
  if (block == NULL) {
    ms_fatal(MS_FATAL_OUT_OF_MEMORY, "out of memory");
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

void ms_arena_free(MsArena *arena) {
  if (arena->heap != NULL) {
    mi_heap_destroy(arena->heap);
  }
  *arena = (MsArena){0};
}

void ms_arena_reset(MsArena *arena) {
  ms_arena_free(arena);
}
