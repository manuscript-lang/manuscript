/* Owns the mimalloc binding of the base allocator hook (see core/alloc.h). */
#include "runtime/core/alloc.h"

#include <mimalloc.h>

static void *mimalloc_allocate(size_t size) {
  return mi_malloc(size);
}
static void *mimalloc_reallocate(void *block, size_t size) {
  return mi_realloc(block, size);
}
static void mimalloc_release(void *block) {
  mi_free(block);
}

static const MsAllocator allocator = {mimalloc_allocate, mimalloc_reallocate, mimalloc_release};

const MsAllocator *ms_core_allocator(void) {
  return &allocator;
}
