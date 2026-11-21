/* watch.h: the watcher, one thread that looks at the scheduler threads from outside. Internal to src/runtime/core.
 *
 * A task is not interrupted, so a thread that runs one task for a long time does none of its other duties meanwhile.
 * The watcher keeps a clock in ticks and runs the hooks other modules register, which do for a held-up thread what
 * cannot wait: the HTTP server's hook sends a resting thread to take the waiting connections of a held-up one.
 *
 * It looks every two milliseconds, or every tick for a tenth of a second after a hook asked for that, and sleeps when
 * every isolate has rested for a while; an isolate that leaves its rest wakes it. It reads atomics only and never
 * touches a task.
 */
#ifndef MS_CORE_WATCH_H
#define MS_CORE_WATCH_H

#include <stdbool.h>
#include <stdint.h>

#define MS_WATCH_TICK_NS 100000 /* the clock's unit and the shortest wait between looks */

/* The clock at one look, in ticks: `now`, and `last` at the look before. An isolate that copies the clock at each turn
 * of its loop has not turned since before the last look when its copy is below `last`. */
typedef struct MsWatchLook {
    uint64_t now;
    uint64_t last;
} MsWatchLook;

/* Called at every look with the clock and the resting isolates (bit `i` for isolate `i`, see ms_isolate_resting).
 * Answers whether the watcher should look often for a while. */
typedef bool (*MsWatchHook)(MsWatchLook look, uint64_t resting);

/* The clock as of the last look. */
uint64_t ms_watch_epoch(void);
/* Adds `hook` (once) and starts the watcher. False when the hook table is full or the thread cannot start. */
bool ms_watch_add_hook(MsWatchHook hook);
/* The calling isolate finished a turn of its reactor: it is not held up. One relaxed store. */
void ms_watch_turn(void);
/* The calling isolate leaves its rest: notes the clock and wakes a sleeping watcher. */
void ms_watch_stir(void);
/* The clock when `isolate` last left its rest. */
uint64_t ms_watch_stirred(uint32_t isolate);
/* Whether `isolate`, found busy at `look`, has neither turned nor left its rest since before the previous look. */
bool ms_watch_held_up(MsWatchLook look, uint64_t resting, uint32_t isolate);
/* Whether the watcher sleeps until an isolate leaves its rest (for tests and diagnostics). */
bool ms_watch_asleep(void);
/* Ends the watcher and waits for it; a later add_hook starts a new one. */
void ms_watch_stop(void);

#endif
