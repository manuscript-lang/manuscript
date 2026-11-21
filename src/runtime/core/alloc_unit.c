/* Unit test of core/alloc.h: blocks round-trip through the default (mimalloc) allocator. */
#include <stdio.h>

#include "base/alloc.h"
#include "runtime/core/alloc.h"

int main(void) {
  uint8_t *block = ms_alloc_zeroed(100);
  int failures = block[99] != 0;
  block[0] = 7;
  block = ms_realloc(block, 100000);
  failures += block[0] != 7;
  ms_free(block);
  ms_free(NULL);
  if (failures != 0) {
    (void)fprintf(stderr, "core_alloc: %d failures\n", failures);
  }
  return failures == 0 ? 0 : 1;
}
