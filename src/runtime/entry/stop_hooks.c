/* Stop hooks: what library code registers to be told of a stop request (see entry.h). A hook slot is a function (NULL
 * when free, FILLING while ms_on_stop_v1 fills it) and its argument. The stop thread reads them while another thread may
 * register one, so they are atomics written in order. */
#include <stdatomic.h>

#include "runtime/entry/entry.h"

enum { STOP_HOOKS_MAX = 32 };

typedef void (*StopFn)(void *argument);

typedef struct StopHook {
  _Atomic(StopFn) function;
  _Atomic(void *) argument;
} StopHook;

static void filling_marker(void *argument) { (void)argument; }
#define FILLING filling_marker

static StopHook stop_hooks[STOP_HOOKS_MAX];

void ms_stop_hooks_run(void) {
  for (size_t i = 0; i < STOP_HOOKS_MAX; i++) {
    const StopFn function = atomic_load_explicit(&stop_hooks[i].function, memory_order_acquire);
    if (function != NULL && function != FILLING) {
      function(atomic_load_explicit(&stop_hooks[i].argument, memory_order_relaxed));
    }
  }
}

void *ms_on_stop_v1(StopFn function, void *argument) {
  for (size_t i = 0; i < STOP_HOOKS_MAX; i++) {
    /* Claim a free slot with a placeholder, publish the argument, then the function. */
    StopFn expected = NULL;
    if (atomic_compare_exchange_strong_explicit(&stop_hooks[i].function, &expected, FILLING, memory_order_acquire,
                                                memory_order_relaxed)) {
      atomic_store_explicit(&stop_hooks[i].argument, argument, memory_order_relaxed);
      atomic_store_explicit(&stop_hooks[i].function, function, memory_order_release);
      return &stop_hooks[i];
    }
  }
  return NULL;
}

void ms_on_stop_remove_v1(void *hook) {
  for (size_t i = 0; i < STOP_HOOKS_MAX; i++) {
    if (hook == &stop_hooks[i]) {
      atomic_store_explicit(&stop_hooks[i].function, NULL, memory_order_release);
      return;
    }
  }
}
