/* Owns the heap statistics of the mimalloc allocator that base/alloc.c uses (see core/alloc.h). */
#include "runtime/core/alloc.h"

#include <mimalloc.h>

void ms_core_heap_stats(int64_t *used, int64_t *committed) {
  size_t current_commit = 0;
  mi_process_info(NULL, NULL, NULL, NULL, NULL, &current_commit, NULL, NULL);
  *used = (int64_t)current_commit;
  *committed = (int64_t)current_commit;
}
