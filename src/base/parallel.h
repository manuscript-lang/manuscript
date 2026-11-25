/* base/parallel.h: ms_parallel_for, run independent items on several threads of the process.
 *
 * The items are claimed from one shared counter, so a slow item does not hold up the others. Nothing is shared by the
 * threads except what `context` points at: an item reads what it likes and writes only into its own slot. Threads that
 * cannot be started are not an error; the caller's thread takes their items. Built on libuv threads, so it behaves the
 * same on Linux, macOS and Windows. */
#ifndef MS_BASE_PARALLEL_H
#define MS_BASE_PARALLEL_H

#include "base/safe.h"

/* How many threads (the caller's included) a run of `count` items should use: one per core, and none at all where an
 * item is too few to pay for the thread, `grain` items to a thread at least. Always at least 1. */
uint32_t ms_parallel_threads(size_t count, size_t grain);

/* Calls `fn(context, item, worker)` once for every item below `count`, on `threads` threads (see ms_parallel_threads;
 * worker 0 is the caller's thread, the others number up from 1 below `threads`) and returns when every item is done. */
typedef void (*MsParallelFn)(void *context, size_t item, uint32_t worker);
void ms_parallel_for(uint32_t threads, size_t count, MsParallelFn fn, void *context);

#endif
