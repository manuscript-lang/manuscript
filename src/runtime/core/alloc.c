/* Owns the heap statistics of the mimalloc allocator that base/alloc.c uses (see core/alloc.h). */
#include "runtime/core/alloc.h"

#include <mimalloc.h>
#include <stdatomic.h>

#include "base/alloc.h"

void ms_core_heap_stats(int64_t *used, int64_t *committed) {
  size_t current_commit = 0;
  mi_process_info(NULL, NULL, NULL, NULL, NULL, &current_commit, NULL, NULL);
  *used = (int64_t)current_commit;
  *committed = (int64_t)current_commit;
}

void *msrt_alloc(size_t size) {
  return ms_alloc(size);
}

void *msrt_alloc_zeroed(size_t size) {
  return ms_alloc_zeroed(size);
}

void *msrt_realloc(void *block, size_t size) {
  return ms_realloc(block, size);
}

void msrt_free(void *block) {
  ms_free(block);
}

static _Atomic int64_t operations;

void msrt_ops_add(int64_t count) {
  atomic_fetch_add_explicit(&operations, count, memory_order_relaxed);
}

int64_t ms_core_operations(void) {
  return atomic_load_explicit(&operations, memory_order_relaxed);
}
