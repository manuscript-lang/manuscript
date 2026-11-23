/* runtime/core/stats.h: the counters of the counting runtime (`cmake --preset stats`, MS_STATS) behind the leak,
 * cancel and count gates (proposals/c-runtime-stats-variant.md). Every call is a no-op that compiles away in a build
 * without MS_STATS. */
#ifndef MS_RUNTIME_CORE_STATS_H
#define MS_RUNTIME_CORE_STATS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef MS_STATS

/* Counts one park of the running task; true when this is the park `MS_CANCEL_AT_PARK` names and the caller returns
 * MS_WAIT_CANCELLED. The cancel stays recorded on the task, so code that swallows it fails at its next park, as it
 * would under a real cancel. A task born shielded and a shielded park are never cancelled (the request stays pending). */
bool ms_stats_park(void);
/* The next park of this thread is the scheduler's own (a worker's root task waiting for work): not counted. */
void ms_stats_park_internal(bool on);
uint64_t ms_stats_parks(void);

/* One deep copy: kind 0 a list, kind 1 a string, `bytes` moved. */
void ms_stats_copy(int kind, size_t bytes);
/* The copies counted so far: list copies, list bytes, string clones, string bytes. */
void ms_stats_copies(uint64_t out[4]);

#else

static inline bool ms_stats_park(void) { return false; }
static inline void ms_stats_park_internal(bool on) { (void)on; }
static inline void ms_stats_copy(int kind, size_t bytes) { (void)kind; (void)bytes; }

#endif

#endif
