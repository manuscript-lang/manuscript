/* Task stacks: regions, slots, the pool of finished stacks, and the cell generated code reads (see stack.h).
 */
#include "runtime/core/stack.h"

#include "runtime/sys/sys.h"

enum { STACK_RESERVE_MIN = 64 << 10, STACK_RESERVE_MAX = 1 << 20, STACK_RECURSION_MAX = 256 << 20 };

/* ---- the cell ---- */

void ms_stack_publish(uint8_t *inside, void *header, uintptr_t limit) {
  uint8_t *const region_end = inside + (MS_STACK_REGION - ((uintptr_t)inside & (MS_STACK_REGION - 1)));
  __builtin_memcpy(region_end - MS_STACK_CELL_HDR, &header, sizeof header);
  __builtin_memcpy(region_end - MS_STACK_CELL_LIMIT, &limit, sizeof limit);
}

uintptr_t ms_stack_limit(uintptr_t low, uintptr_t high) {
  if (low == 0 || high <= low) {
    return 0;
  }
  uintptr_t start = low;
  if (high - low > STACK_RECURSION_MAX) {
    start = high - STACK_RECURSION_MAX;
  }
  uintptr_t reserve = (high - start) / 8;
  if (reserve < STACK_RESERVE_MIN) {
    reserve = STACK_RESERVE_MIN;
  }
  if (reserve > STACK_RESERVE_MAX) {
    reserve = STACK_RESERVE_MAX;
  }
  return start + reserve;
}

uintptr_t ms_stack_top(const uint8_t *base, size_t length) {
  const uintptr_t start = (uintptr_t)base;
  return length == MS_STACK_REGION ? start + MS_STACK_REGION - MS_STACK_PAGE : start + length;
}

/* ---- regions and slots ---- */

/* Maps an aligned region with its cell page usable and records it for teardown; NULL when address space is
 * used up. */
static uint8_t *map_region(MsStacks *stacks) {
  uint8_t *const base = ms_sys_map_region(MS_STACK_REGION);
  if (base == NULL) {
    return NULL;
  }
  if (!ms_sys_commit(base + MS_STACK_REGION - MS_STACK_PAGE, MS_STACK_PAGE)) {
    ms_sys_unmap(base, MS_STACK_REGION);
    return NULL;
  }
  ms_region_list_push(&stacks->regions, base);
  return base;
}

/* The next slot: the next unused one of the newest region, else the first of a fresh region. */
static uint8_t *take_slot(MsStacks *stacks) {
  if (stacks->carve == stacks->carve_end) {
    uint8_t *const region = map_region(stacks);
    if (region == NULL) {
      return NULL;
    }
    stacks->carve = region;
    stacks->carve_end = region + MS_STACK_SLOTS_PER_REGION * MS_STACK_SLOT;
  }
  uint8_t *const slot = stacks->carve;
  stacks->carve += MS_STACK_SLOT;
  return slot;
}

/* A fresh stack of `length` bytes with its guard installed; NULL when none is left. A refused guard fails the
 * stack: running unguarded would let an overflow corrupt the neighbouring stack. The address space stays
 * reserved for the region's other slots. */
static uint8_t *create_stack(MsStacks *stacks, size_t length) {
  uint8_t *const base = length == MS_STACK_REGION ? map_region(stacks) : take_slot(stacks);
  if (base == NULL || !ms_sys_guard(base, MS_STACK_GUARD)) {
    return NULL;
  }
  return base;
}

bool ms_stacks_acquire(MsStacks *stacks, size_t length, uint8_t **base) {
  for (size_t at = stacks->pool.len; at > 0; at--) {
    const size_t index = at - 1;
    if (stacks->pool.ptr[index].length != length) {
      continue;
    }
    *base = stacks->pool.ptr[index].base;
    /* The newest entry moves into the hole and may still hold pages. */
    stacks->pool.ptr[index] = stacks->pool.ptr[--stacks->pool.len];
    if (stacks->pool_clean > index) {
      stacks->pool_clean = index;
    }
    return true;
  }
  uint8_t *const fresh = create_stack(stacks, length);
  if (fresh == NULL) {
    return false;
  }
  *base = fresh;
  return true;
}

void ms_stacks_release(MsStacks *stacks, uint8_t *base, size_t length) {
  ms_stack_pool_push(&stacks->pool, (MsStackEntry){.base = base, .length = length});
}

void ms_stacks_trim(MsStacks *stacks, size_t warm) {
  const size_t end = stacks->pool.len > warm ? stacks->pool.len - warm : 0;
  for (size_t at = stacks->pool_clean; at < end; at++) {
    const MsStackEntry entry = stacks->pool.ptr[at];
    /* A pooled stack is unused; its guard stays and the stack stays mapped. */
    const size_t used = (size_t)(ms_stack_top(entry.base, entry.length) - (uintptr_t)entry.base);
    ms_sys_release(entry.base + MS_STACK_GUARD, used - MS_STACK_GUARD);
  }
  if (stacks->pool_clean < end) {
    stacks->pool_clean = end;
  }
}

void ms_stacks_destroy(MsStacks *stacks) {
  for (size_t i = 0; i < stacks->regions.len; i++) {
    ms_sys_unmap(stacks->regions.ptr[i], MS_STACK_REGION);
  }
  ms_region_list_free(&stacks->regions);
  ms_stack_pool_free(&stacks->pool);
  *stacks = (MsStacks){0};
}

/* The highest usable address of the stack at `base`, as a pointer into the same reservation. */
static uint8_t *top_pointer(uint8_t *base, size_t length) {
  return base + (length == MS_STACK_REGION ? MS_STACK_REGION - MS_STACK_PAGE : length);
}

bool ms_stack_commit_top(uint8_t *base, size_t length) {
  uint8_t *const top = top_pointer(base, length);
  /* The top of the stack is reserved address space: Unix commits pages on first touch, Windows needs the
   * first pages committed and a guard page below them. */
  return ms_sys_commit(top - MS_STACK_INITIAL_COMMIT, MS_STACK_INITIAL_COMMIT) &&
         ms_sys_commit_guard(top - MS_STACK_INITIAL_COMMIT - MS_STACK_PAGE);
}

bool ms_stack_prepare(uint8_t *base, size_t length, MsCtxEntry entry, MsStackBounds *bounds) {
  if (!ms_stack_commit_top(base, length)) {
    return false;
  }
  uint8_t *const top = top_pointer(base, length);
  bounds->low = (uintptr_t)base + MS_STACK_GUARD;
  bounds->high = (uintptr_t)top;
  bounds->sp = ms_ctx_initial_sp(top, entry);
  return true;
}
