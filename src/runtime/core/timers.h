/* A min-heap of (deadline, handle) pairs for the scheduler's timeouts and time limits.
 *
 * Entries are never removed when the thing they time ends (a task woken by its descriptor leaves its entry
 * behind): the scheduler ignores an entry whose owner no longer waits on that deadline, and compacts the heap
 * when it passes a limit, so a loop of short waits with long timeouts does not grow it without bound. */
#ifndef MS_CORE_TIMERS_H
#define MS_CORE_TIMERS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "base/list.h"
#include "base/safe.h"

typedef struct MsTimer {
  int64_t deadline;
  uint64_t handle;
} MsTimer;

MS_LIST_DEFINE(MsTimerList, ms_timer_list, MsTimer)

/* Zero-initialise; ms_timers_free releases the storage. A binary heap, earliest deadline first. */
typedef struct MsTimers {
  MsTimerList heap;
} MsTimers;

void ms_timers_push(MsTimers *timers, MsTimer timer) MS_NONNULL;
/* The earliest entry, or false when empty. */
bool ms_timers_peek(const MsTimers *timers, MsTimer *out) MS_NONNULL;
/* Removes the earliest entry; no-op when empty. */
void ms_timers_pop(MsTimers *timers) MS_NONNULL;
/* Keeps the entries `keep(context, entry)` accepts, restoring heap order. */
void ms_timers_retain(MsTimers *timers, bool (*keep)(void *context, MsTimer timer), void *context)
    MS_NONNULL_ARGS(1, 2);
void ms_timers_free(MsTimers *timers) MS_NONNULL;

#endif
