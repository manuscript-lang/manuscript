/* queue.h: the per-isolate list of promises whose work has not started. Internal to runtime/core.
 *
 * promise(fn) puts the promise here instead of starting a task: the waiter usually runs the work inline on its own
 * stack (cheaper than a task), and an idle isolate takes the oldest entry once it is older than a short beat. The
 * owner pushes and removes at the newest end; thieves take from the oldest end. A spinlock guards the few
 * instructions of each operation. Entries are promise ids; the queue knows nothing else about them.
 */
#ifndef MS_CORE_QUEUE_H
#define MS_CORE_QUEUE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ms_rt/safe.h"

/* Appends `id` (queued at `now_ns`) to the calling isolate's queue; false when memory ran out. */
MS_NODISCARD bool ms_queue_push(uint32_t isolate, uint64_t id, int64_t now_ns);
/* Removes `id` from `isolate`'s queue; true when it was there (it is the caller's to run), false when a thief took it. */
MS_NODISCARD bool ms_queue_remove(uint32_t isolate, uint64_t id);
/* Takes the oldest entry of `isolate` queued at or before `not_after_ns` into `*id`. */
MS_NODISCARD bool ms_queue_steal(uint32_t isolate, int64_t not_after_ns, uint64_t *id);
/* How many entries wait on `isolate`, and the time the oldest was queued (INT64_MAX when none). */
size_t ms_queue_length(uint32_t isolate);
int64_t ms_queue_oldest(uint32_t isolate);
/* Frees the queue of `isolate` (its owner is gone); entries are dropped. */
void ms_queue_release(uint32_t isolate);

#endif
