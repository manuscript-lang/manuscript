/* The per-isolate list of promises whose work has not started.
 *
 * promise(fn) puts the promise here instead of starting a task: the waiter usually runs the work inline on its own
 * stack (cheaper than a task), and an idle isolate takes the oldest entry once it has seen it wait a short beat. An
 * entry's age counts from the first look that finds it, by any isolate, so a start reads no clock. The
 * owner pushes and removes without a lock; thieves and looks take a spin lock for their few instructions. An entry is a promise id and the work (an opaque pointer the thief runs); the
 * queue knows nothing else. */
#ifndef MS_CORE_QUEUE_H
#define MS_CORE_QUEUE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "base/safe.h"

/* Appends `id` (nonzero) with its `work` to the queue of `isolate`; false for an id or an isolate out of range.
 * `aged`: it may be taken at the first look. */
MS_NODISCARD bool ms_queue_push(uint32_t isolate, uint64_t id, void *work, bool aged, uint64_t *sequence)
    MS_NONNULL_ARGS(5);
/* Removes `id`, pushed with `sequence`, from `isolate`'s queue; true when it was there (it is the caller's to run),
 * false when a thief took it. Constant time: the sequence gives the entry's place. */
MS_NODISCARD bool ms_queue_remove(uint32_t isolate, uint64_t id, uint64_t sequence);
/* A look at `now_ns`: dates the entries no look has seen, then takes the oldest entry of `isolate` into `*id` and
 * `*work` if it was first seen `beat_ns` ago or earlier. A negative `beat_ns` takes the oldest whatever its age. */
MS_NODISCARD bool ms_queue_steal(uint32_t isolate, int64_t now_ns, int64_t beat_ns, uint64_t *id, void **work)
    MS_NONNULL_ARGS(4, 5);
/* At least how many entries wait on `isolate`: one the owner removed is counted until the next look passes it. */
size_t ms_queue_length(uint32_t isolate);
/* A look at `now_ns`: dates the entries no look has seen and answers when the oldest was first seen (INT64_MAX when
 * none). */
int64_t ms_queue_oldest(uint32_t isolate, int64_t now_ns);
/* Frees the queue of `isolate` (its owner is gone); each entry still queued goes to `drop` (may be NULL). */
void ms_queue_release(uint32_t isolate, void (*drop)(void *work));

#endif
