/* Unit test of core/alloc.h: blocks round-trip through mimalloc via the base hook. */
#include <stdio.h>

#include "runtime/core/alloc.h"

int main(void) {
  ms_alloc_install(ms_core_allocator());
  uint8_t *block = ms_alloc_zeroed(100);
  int failures = block[99] != 0;
  block[0] = 7;
  block = ms_realloc(block, 100000);
  failures += block[0] != 7;
  ms_free(block);
  ms_free(NULL);
  ms_alloc_install(NULL);
  if (failures != 0) {
    (void)fprintf(stderr, "core_alloc: %d failures\n", failures);
  }
  return failures == 0 ? 0 : 1;
}
