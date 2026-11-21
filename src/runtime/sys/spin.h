/* A lock for critical sections of a few loads and stores that never allocate or sleep: a waiter spins on a relaxed
 * load, then gives its core back. A contended mutex costs a futex wait and wake per hand-over, which made a pipe
 * between threads 5 to 10 times slower than one between tasks of a thread. */
#ifndef MS_SYS_SPIN_H
#define MS_SYS_SPIN_H

#include <stdatomic.h>

#include "runtime/sys/sys.h"

typedef struct MsSpin {
  atomic_bool held;
} MsSpin;

#define MS_SPIN_INIT {false}
enum { MS_SPIN_BUSY_LOOPS = 256 };

static inline void ms_spin_lock(MsSpin *lock) {
  unsigned spins = 0;
  while (atomic_exchange_explicit(&lock->held, true, memory_order_acquire)) {
    while (atomic_load_explicit(&lock->held, memory_order_relaxed)) {
      if (++spins >= MS_SPIN_BUSY_LOOPS) {
        ms_sys_yield(); /* the holder may have been descheduled */
      }
    }
  }
}

static inline void ms_spin_unlock(MsSpin *lock) {
  atomic_store_explicit(&lock->held, false, memory_order_release);
}

#endif
