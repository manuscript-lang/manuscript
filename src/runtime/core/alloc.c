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

void ms_core_heap_stats(int64_t *used, int64_t *committed) {
  size_t current_commit = 0;
  mi_process_info(NULL, NULL, NULL, NULL, NULL, &current_commit, NULL, NULL);
  *used = (int64_t)current_commit;
  *committed = (int64_t)current_commit;
}
