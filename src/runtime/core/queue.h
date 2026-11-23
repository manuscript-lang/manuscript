/* The per-isolate list of promises whose work has not started.
 *
 * promise(fn) puts the promise here instead of starting a task: the waiter usually runs the work inline on its own
 * stack (cheaper than a task), and an idle isolate takes the oldest entry once it is older than a short beat. The
 * owner pushes and removes at the newest end; thieves take from the oldest end. A spin lock guards the few
 * instructions of each operation. An entry is a promise id and the work (an opaque pointer the thief runs); the
 * queue knows nothing else. */
#ifndef MS_CORE_QUEUE_H
#define MS_CORE_QUEUE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "base/safe.h"

/* Appends `id` (nonzero) with its `work`, queued at `now_ns`, to the queue of `isolate`; false for an id or an
 * isolate out of range. */
MS_NODISCARD bool ms_queue_push(uint32_t isolate, uint64_t id, void *work, int64_t now_ns, uint64_t *sequence)
    MS_NONNULL_ARGS(5);
/* Removes `id`, pushed with `sequence`, from `isolate`'s queue; true when it was there (it is the caller's to run),
 * false when a thief took it. Constant time: the sequence gives the entry's place. */
MS_NODISCARD bool ms_queue_remove(uint32_t isolate, uint64_t id, uint64_t sequence);
/* Takes the oldest entry of `isolate` queued at or before `not_after_ns` into `*id` and `*work`. */
MS_NODISCARD bool ms_queue_steal(uint32_t isolate, int64_t not_after_ns, uint64_t *id, void **work)
    MS_NONNULL_ARGS(3, 4);
/* How many entries wait on `isolate`. */
size_t ms_queue_length(uint32_t isolate);
/* The time the oldest entry was queued (INT64_MAX when none). */
int64_t ms_queue_oldest(uint32_t isolate);
/* Frees the queue of `isolate` (its owner is gone); each entry still queued goes to `drop` (may be NULL). */
void ms_queue_release(uint32_t isolate, void (*drop)(void *work));

#endif
