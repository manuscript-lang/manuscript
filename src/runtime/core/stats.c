/* Owns the park and copy counters of the counting runtime (see stats.h). */
#include "runtime/core/stats.h"

#ifdef MS_STATS

#include <stdatomic.h>
#include <stdlib.h>

#include "runtime/core/scheduler.h"
#include "runtime/core/unwind.h"

static _Atomic uint64_t parks;
static _Atomic uint64_t copies[4];
static _Thread_local bool internal_park;

/* `MS_CANCEL_AT_PARK`, read once: the park to cancel, or UINT64_MAX for none. */
static uint64_t target(void) {
  static _Atomic uint64_t value = 0; /* 0: not read yet */
  uint64_t known = atomic_load_explicit(&value, memory_order_relaxed);
  if (known == 0) {
    const char *text = getenv("MS_CANCEL_AT_PARK");
    known = text != NULL ? strtoull(text, NULL, 10) : 0;
    known = known == 0 ? UINT64_MAX : known;
    atomic_store_explicit(&value, known, memory_order_relaxed);
  }
  return known;
}

void ms_stats_park_internal(bool on) { internal_park = on; }

bool ms_stats_park(void) {
  if (internal_park) {
    internal_park = false;
    return false;
  }
  const bool hit = atomic_fetch_add_explicit(&parks, 1, memory_order_relaxed) + 1 == target();
  if (!hit || (ms_task_running()->flags & MS_TASK_FLAG_BORN_SHIELDED) != 0) {
    return false;
  }
  ms_cancel_set_task(1);
  return !ms_shielded();
}

uint64_t ms_stats_parks(void) { return atomic_load_explicit(&parks, memory_order_relaxed); }

void ms_stats_copy(int kind, size_t bytes) {
  atomic_fetch_add_explicit(&copies[kind * 2], 1, memory_order_relaxed);
  atomic_fetch_add_explicit(&copies[kind * 2 + 1], bytes, memory_order_relaxed);
}

void ms_stats_copies(uint64_t out[4]) {
  for (int i = 0; i < 4; i++) {
    out[i] = atomic_load_explicit(&copies[i], memory_order_relaxed);
  }
}

#endif
