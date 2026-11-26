/* Owns the mappings of base/alloc_huge.h: a small table of live ones behind a spin lock (resizes past the threshold
 * are rare, and a lookup first checks a count and an address range, so a free of any other block costs two loads). */
#define _GNU_SOURCE 1
#include "base/alloc_huge.h"

#include <stdatomic.h>

#ifdef __linux__
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include <mimalloc.h>

/* A resize to at least this many bytes makes a mapping; one to less than half of it makes the block ordinary again. */
enum { HUGE_SLOTS = 256 };

typedef struct Mapping {
  uintptr_t address;
  size_t bytes;
} Mapping;

static Mapping table[HUGE_SLOTS];
static atomic_flag table_lock = ATOMIC_FLAG_INIT;
_Atomic size_t ms_huge_live;
_Atomic uintptr_t ms_huge_lowest = UINTPTR_MAX, ms_huge_highest;

static void lock(void) {
  while (atomic_flag_test_and_set_explicit(&table_lock, memory_order_acquire)) {
  }
}

static void unlock(void) { atomic_flag_clear_explicit(&table_lock, memory_order_release); }

/* The slot of `block`, or NULL. Call locked. */
static Mapping *find(const void *block) {
  for (size_t i = 0; i < HUGE_SLOTS; i++) {
    if (table[i].address == (uintptr_t)block) {
      return &table[i];
    }
  }
  return NULL;
}

static void note_range(uintptr_t address) {
  if (address < atomic_load_explicit(&ms_huge_lowest, memory_order_relaxed)) {
    atomic_store_explicit(&ms_huge_lowest, address, memory_order_relaxed);
  }
  if (address > atomic_load_explicit(&ms_huge_highest, memory_order_relaxed)) {
    atomic_store_explicit(&ms_huge_highest, address, memory_order_relaxed);
  }
}

bool ms_huge_owns(const void *block) {
  if (!ms_huge_maybe(block)) {
    return false;
  }
  lock();
  const bool found = find(block) != NULL;
  unlock();
  return found;
}

size_t ms_huge_usable(const void *block) {
  lock();
  const Mapping *slot = find(block);
  const size_t bytes = slot == NULL ? 0 : slot->bytes;
  unlock();
  return bytes;
}

static size_t round_up(size_t size) {
  static size_t page;
  if (page == 0) {
    page = (size_t)sysconf(_SC_PAGESIZE);
  }
  return (size + page - 1) / page * page;
}

/* Records a mapping; false when the table is full. */
static bool add(void *address, size_t bytes) {
  lock();
  Mapping *free_slot = find(NULL);
  if (free_slot != NULL) {
    *free_slot = (Mapping){(uintptr_t)address, bytes};
    note_range((uintptr_t)address);
    if (atomic_fetch_add_explicit(&ms_huge_live, 1, memory_order_relaxed) == 0) {
      ms_alloc_huge_flag(true);
    }
  }
  unlock();
  return free_slot != NULL;
}

static void remove_mapping(const void *address) {
  lock();
  Mapping *slot = find(address);
  if (slot != NULL) {
    slot->address = 0;
    if (atomic_fetch_sub_explicit(&ms_huge_live, 1, memory_order_relaxed) == 1) { /* none left: the range starts over */
      atomic_store_explicit(&ms_huge_lowest, UINTPTR_MAX, memory_order_relaxed);
      atomic_store_explicit(&ms_huge_highest, 0, memory_order_relaxed);
      ms_alloc_huge_flag(false);
    }
  }
  unlock();
}

void ms_huge_free(void *block) {
  const size_t bytes = ms_huge_usable(block);
  remove_mapping(block);
  (void)munmap(block, bytes);
}

bool ms_huge_realloc(void *block, size_t size, void **out) {
  const bool mapped = block != NULL && ms_huge_owns(block);
  if (!mapped && size < MS_HUGE_MIN) {
    return false;
  }
  if (mapped && size < MS_HUGE_MIN / 2) { /* back to an ordinary block */
    const size_t old = ms_huge_usable(block);
    void *small = mi_malloc(size);
    if (small != NULL) {
      memcpy(small, block, size < old ? size : old);
      ms_huge_free(block);
    }
    *out = small;
    return true;
  }
  const size_t bytes = round_up(size);
  if (mapped) {
    const size_t old = ms_huge_usable(block);
    void *moved = mremap(block, old, bytes, MREMAP_MAYMOVE);
    if (moved == MAP_FAILED) {
      *out = NULL;
      return true;
    }
    lock();
    Mapping *slot = find(block);
    slot->address = (uintptr_t)moved;
    slot->bytes = bytes;
    note_range((uintptr_t)moved);
    unlock();
    *out = moved;
    return true;
  }
  void *fresh = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (fresh == MAP_FAILED || !add(fresh, bytes)) {
    if (fresh != MAP_FAILED) {
      (void)munmap(fresh, bytes); /* the table is full: the block stays ordinary */
      return false;
    }
    *out = NULL;
    return true;
  }
  if (block != NULL) {
    const size_t old = mi_usable_size(block);
    memcpy(fresh, block, old < size ? old : size);
    mi_free(block);
  }
  *out = fresh;
  return true;
}

#else

_Atomic size_t ms_huge_live;
_Atomic uintptr_t ms_huge_lowest, ms_huge_highest;

bool ms_huge_owns(const void *block) {
  (void)block;
  return false;
}
size_t ms_huge_usable(const void *block) {
  (void)block;
  return 0;
}
void ms_huge_free(void *block) { (void)block; }
bool ms_huge_realloc(void *block, size_t size, void **out) {
  (void)block;
  (void)size;
  (void)out;
  return false;
}

#endif
