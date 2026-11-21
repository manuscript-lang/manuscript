/* The watcher. See watch.h. */
#include "runtime/core/watch.h"

#include <stdatomic.h>

#include "base/safe.h"
#include "runtime/core/isolate.h"
#include "runtime/sys/sys.h"

enum {
  SLOW_TICKS = 20,        /* ticks between looks otherwise (two milliseconds) */
  OFTEN_FOR_TICKS = 1000, /* ticks it keeps looking often after a hook last asked for it (a tenth of a second) */
  QUIET_LOOKS = 20,       /* looks with every isolate resting after which it sleeps (40 ms): long enough that
                 steady traffic does not wake it, short enough that a quiet server wakes nothing */
  MAX_HOOKS = 8,
};

static _Atomic uint64_t epoch;
static _Atomic bool asleep;
static _Atomic bool stopping;
static _Atomic uint32_t starting; /* 0 not started, 1 starting, 2 running */
static _Atomic(MsWatchHook) hooks[MAX_HOOKS];
static _Atomic uint64_t seen[MS_MAX_ISOLATES];    /* the clock at each isolate's last turn of its reactor */
static _Atomic uint64_t stirred[MS_MAX_ISOLATES]; /* the clock when each isolate last left its rest */
static MsSysSignal *signal_to_watcher;
static MsSysThread *watcher;

uint64_t ms_watch_epoch(void) { return atomic_load_explicit(&epoch, memory_order_relaxed); }

void ms_watch_turn(void) {
  const uint32_t self = ms_isolate_self();
  if (self < MS_MAX_ISOLATES) {
    atomic_store_explicit(&seen[self], ms_watch_epoch(), memory_order_relaxed);
  }
}

static void wake(void) {
  if (atomic_exchange(&asleep, false)) {
    ms_sys_signal_send(signal_to_watcher);
  }
}

/* The clock when `isolate` last left its rest (0 for an index out of range). */
uint64_t ms_watch_stirred(uint32_t isolate) {
  return isolate < MS_MAX_ISOLATES ? atomic_load_explicit(&stirred[isolate], memory_order_relaxed) : 0;
}

void ms_watch_stir(void) {
  const uint32_t self = ms_isolate_self();
  if (self >= MS_MAX_ISOLATES) {
    return;
  }
  atomic_store_explicit(&stirred[self], ms_watch_epoch(), memory_order_relaxed);
  if (atomic_load(&asleep)) {
    wake();
  }
}

bool ms_watch_asleep(void) { return atomic_load(&asleep); }

bool ms_watch_held_up(MsWatchLook look, uint64_t resting, uint32_t isolate) {
  if (isolate >= MS_MAX_ISOLATES || (resting >> isolate & 1) != 0) {
    return false;
  }
  const uint64_t turned = atomic_load_explicit(&seen[isolate], memory_order_relaxed);
  const uint64_t left = atomic_load_explicit(&stirred[isolate], memory_order_relaxed);
  return (turned > left ? turned : left) < look.last;
}

static bool all_rest(uint64_t resting, uint64_t live) { return (resting & live) == live; }

static void watch_main(void *argument) {
  (void)argument;
  uint32_t quiet = 0;
  uint64_t often_until = 0;
  while (!atomic_load(&stopping)) {
    if (atomic_load_explicit(&asleep, memory_order_acquire)) {
      (void)ms_sys_signal_wait(signal_to_watcher, -1);
      continue;
    }
    const uint64_t last = ms_watch_epoch();
    const uint64_t step = last < often_until ? 1 : SLOW_TICKS;
    if (ms_sys_signal_wait(signal_to_watcher, (int64_t)(step * MS_WATCH_TICK_NS))) {
      continue; /* cut short: a stop request, or a wake that came after the watcher chose not to sleep */
    }
    const MsWatchLook look = {.now = last + step, .last = last};
    atomic_store_explicit(&epoch, look.now, memory_order_relaxed);
    uint64_t live = 0;
    const uint64_t resting = ms_isolate_resting(&live);
    for (size_t i = 0; i < MS_COUNT_OF(hooks); i++) {
      const MsWatchHook hook = atomic_load(&hooks[i]);
      if (hook != NULL && hook(look, resting)) {
        often_until = look.now + OFTEN_FOR_TICKS;
      }
    }
    quiet = all_rest(resting, live) ? quiet + 1 : 0;
    if (quiet >= QUIET_LOOKS) {
      quiet = 0;
      atomic_store(&asleep, true);
      /* An isolate that left its rest just before the store saw the watcher awake and did not wake it. */
      uint64_t live_now = 0;
      const uint64_t resting_now = ms_isolate_resting(&live_now);
      if (!all_rest(resting_now, live_now)) {
        atomic_store(&asleep, false);
      }
    }
  }
}

static bool start(void) {
  uint32_t expected = 0;
  if (!atomic_compare_exchange_strong(&starting, &expected, 1)) {
    while (atomic_load(&starting) == 1) {
      ms_sys_yield();
    }
    return atomic_load(&starting) == 2;
  }
  atomic_store(&stopping, false);
  atomic_store(&asleep, false);
  signal_to_watcher = ms_sys_signal_new();
  if (signal_to_watcher != NULL) {
    watcher = ms_sys_thread_spawn(0, watch_main, NULL);
  }
  if (watcher == NULL) {
    if (signal_to_watcher != NULL) {
      ms_sys_signal_free(signal_to_watcher);
      signal_to_watcher = NULL;
    }
    atomic_store(&starting, 0);
    return false;
  }
  atomic_store(&starting, 2);
  return true;
}

/* Whether `hook` is in the table afterwards. */
static bool place_hook(MsWatchHook hook) {
  for (size_t i = 0; i < MS_COUNT_OF(hooks); i++) {
    MsWatchHook current = atomic_load(&hooks[i]);
    if (current == NULL && atomic_compare_exchange_strong(&hooks[i], &current, hook)) {
      return true;
    }
    if (current == hook) {
      return true;
    }
  }
  return false;
}

bool ms_watch_add_hook(MsWatchHook hook) { return place_hook(hook) && start(); }

void ms_watch_stop(void) {
  if (atomic_load(&starting) != 2) {
    return;
  }
  atomic_store(&stopping, true);
  ms_sys_signal_send(signal_to_watcher);
  ms_sys_thread_join(watcher);
  ms_sys_signal_free(signal_to_watcher);
  watcher = NULL;
  signal_to_watcher = NULL;
  for (size_t i = 0; i < MS_COUNT_OF(hooks); i++) {
    atomic_store(&hooks[i], NULL);
  }
  atomic_store(&starting, 0);
}
