/* Owns the allocator hook and the mimalloc default (see alloc.h). */
#include "base/alloc.h"

#include <mimalloc.h>

#include "base/fatal.h"

/* The one other mutable global of base besides the fatal handler: set once before threads. */
static const MsAllocator *installed = NULL;

static void *mimalloc_allocate(size_t size) {
  return mi_malloc(size);
}
static void *mimalloc_reallocate(void *block, size_t size) {
  return mi_realloc(block, size);
}
static void mimalloc_release(void *block) {
  mi_free(block);
}

static const MsAllocator mimalloc_allocator = {mimalloc_allocate, mimalloc_reallocate, mimalloc_release};

static const MsAllocator *current(void) {
  return installed != NULL ? installed : &mimalloc_allocator;
}

static void *checked(void *block) {
  if (block == NULL) {
    ms_fatal(MS_FATAL_OUT_OF_MEMORY, "out of memory");
  }
  return block;
}

void ms_alloc_install(const MsAllocator *allocator) {
  installed = allocator;
}

static _Thread_local int64_t counted_allocations, counted_bytes;

void ms_alloc_counts(int64_t *allocations, int64_t *bytes) {
  *allocations = counted_allocations;
  *bytes = counted_bytes;
}

static void count(size_t size) {
  counted_allocations++;
  counted_bytes += (int64_t)size;
}

void *ms_alloc(size_t size) {
  count(size);
  return checked(current()->allocate(size));
}

void *ms_alloc_zeroed(size_t size) {
  void *block = ms_alloc(size);
  __builtin_memset(block, 0, size);
  return block;
}

void *ms_realloc(void *block, size_t size) {
  count(size);
  return checked(block == NULL ? current()->allocate(size) : current()->reallocate(block, size));
}

void ms_free(void *block) {
  if (block != NULL) {
    current()->release(block);
  }
}
