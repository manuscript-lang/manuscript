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

  /* A block that grows past a few MiB is a mapping that moves with its content, and an ordinary block beside it still
   * frees; one that shrinks again is ordinary. */
  uint8_t *ordinary = ms_alloc(64);
  uint8_t *grown = ms_alloc(100);
  for (size_t i = 0; i < 100; i++) {
    grown[i] = (uint8_t)(i * 7);
  }
  for (size_t size = 1u << 10; size <= (96u << 20); size *= 4) {
    grown = ms_realloc(grown, size);
    CHECK(ms_alloc_live_bytes() >= live_before + (int64_t)size);
    CHECK(grown[99] == (uint8_t)(99 * 7) && grown[0] == 0);
    grown[size - 1] = 1; /* the whole block is writable */
  }
  ms_free(ordinary);
  uint8_t *second = ms_realloc(NULL, 8u << 20);
  second[(8u << 20) - 1] = 2;
  ms_free(grown);
  second = ms_realloc(second, 100);
  CHECK(second != NULL);
  ms_free(second);
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
