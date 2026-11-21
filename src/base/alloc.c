/* Owns the allocator hook and the system default (see alloc.h). */
#include "base/alloc.h"

#include <stdlib.h>

#include "base/fatal.h"

/* The one other mutable global of base besides the fatal handler: set once before threads. */
static const MsAllocator *installed = NULL;

static void *system_allocate(size_t size) {
  return malloc(size == 0 ? 1 : size);
}
static void *system_reallocate(void *block, size_t size) {
  return realloc(block, size == 0 ? 1 : size);
}
static void system_release(void *block) {
  free(block);
}

static const MsAllocator system_allocator = {system_allocate, system_reallocate, system_release};

static const MsAllocator *current(void) {
  return installed != NULL ? installed : &system_allocator;
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

void *ms_alloc(size_t size) {
  return checked(current()->allocate(size));
}

void *ms_alloc_zeroed(size_t size) {
  void *block = ms_alloc(size);
  __builtin_memset(block, 0, size);
  return block;
}

void *ms_realloc(void *block, size_t size) {
  return checked(block == NULL ? current()->allocate(size) : current()->reallocate(block, size));
}

void ms_free(void *block) {
  if (block != NULL) {
    current()->release(block);
  }
}
