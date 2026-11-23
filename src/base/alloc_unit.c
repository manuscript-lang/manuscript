/* Unit test of base/alloc.h and base/fatal.h: the allocator and fatal hooks. */
#include <setjmp.h>
#include <stdio.h>

#include "base/alloc.h"
#include "base/fatal.h"

static int failures = 0;
static int allocations = 0;
static int releases = 0;
static jmp_buf escape;
static MsFatalKind seen_kind = MS_FATAL_INVARIANT;

#define CHECK(condition)                                                                                     \
  do {                                                                                                       \
    if (!(condition)) {                                                                                      \
      (void)fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);                                  \
      failures++;                                                                                            \
    }                                                                                                        \
  } while (0)

static void *counting_allocate(size_t size) {
  allocations++;
  return size > 1024 ? NULL : __builtin_malloc(size == 0 ? 1 : size);
}
static void *counting_reallocate(void *block, size_t size) {
  return __builtin_realloc(block, size);
}
static void counting_release(void *block) {
  releases++;
  __builtin_free(block);
}

static void escaping_handler(MsFatalKind kind, MsSpan message) {
  (void)message;
  seen_kind = kind;
  longjmp(escape, 1);
}

int main(void) {
  const MsAllocator counting = {counting_allocate, counting_reallocate, counting_release};
  ms_alloc_track_live();
  const int64_t live_before = ms_alloc_live_bytes();
  uint8_t *block = ms_alloc_zeroed(8);
  CHECK(block[7] == 0);
  CHECK(ms_alloc_live_bytes() >= live_before + 8);
  block = ms_realloc(block, 4096);
  CHECK(ms_alloc_live_bytes() >= live_before + 4096);
  ms_free(block);
  ms_free(NULL);
  CHECK(ms_alloc_live_bytes() == live_before);

  ms_alloc_install(&counting);
  block = ms_alloc(16);
  ms_free(block);
  CHECK(allocations == 1 && releases == 1);

  ms_fatal_install(escaping_handler);
  if (setjmp(escape) == 0) {
    block = ms_alloc(4096);
    CHECK(false);
  }
  CHECK(seen_kind == MS_FATAL_OUT_OF_MEMORY);
  ms_fatal_install(NULL);
  ms_alloc_install(NULL);
  return failures == 0 ? 0 : 1;
}
