/* Owns the allocator hook and the mimalloc default (see alloc.h). */
#include "base/alloc.h"

#include <mimalloc.h>
#include <stdatomic.h>

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

/* The live bytes: the usable size of every mimalloc block handed out less those freed. The sum is striped over
 * cache-line padded counters, each thread adding to its own stripe, so threads do not contend; a block freed on
 * another thread than the one that made it leaves one stripe negative, and only the sum is meaningful. */
enum { LIVE_STRIPES = 64 };
typedef struct LiveStripe {
  _Alignas(64) _Atomic int64_t bytes;
} LiveStripe;
static LiveStripe live_stripes[LIVE_STRIPES];
static _Atomic unsigned next_stripe;
static _Thread_local LiveStripe *my_stripe = NULL;

static void live_add(int64_t delta) {
  if (installed != NULL) {
    return; /* a test allocator's blocks have no known size */
  }
  if (my_stripe == NULL) {
    my_stripe = &live_stripes[atomic_fetch_add_explicit(&next_stripe, 1, memory_order_relaxed) % LIVE_STRIPES];
  }
  atomic_fetch_add_explicit(&my_stripe->bytes, delta, memory_order_relaxed);
}

static int64_t usable(const void *block) {
  return block == NULL || installed != NULL ? 0 : (int64_t)mi_usable_size(block);
}

int64_t ms_alloc_live_bytes(void) {
  int64_t sum = 0;
  for (size_t i = 0; i < LIVE_STRIPES; i++) {
    sum += atomic_load_explicit(&live_stripes[i].bytes, memory_order_relaxed);
  }
  return sum;
}

void *ms_alloc(size_t size) {
  count(size);
  void *block = checked(current()->allocate(size));
  live_add(usable(block));
  return block;
}

void *ms_alloc_zeroed(size_t size) {
  void *block = ms_alloc(size);
  __builtin_memset(block, 0, size);
  return block;
}

void *ms_realloc(void *block, size_t size) {
  count(size);
  const int64_t before = usable(block);
  void *moved = checked(block == NULL ? current()->allocate(size) : current()->reallocate(block, size));
  live_add(usable(moved) - before);
  return moved;
}

void ms_free(void *block) {
  if (block != NULL) {
    live_add(-usable(block));
    current()->release(block);
  }
}
