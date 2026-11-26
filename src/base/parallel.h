/* base/parallel.h: run the steps of one loop on every core. */
#ifndef MS_BASE_PARALLEL_H
#define MS_BASE_PARALLEL_H

#include "base/safe.h"

/* The most workers a loop uses. */
enum { MS_PARALLEL_MAX_WORKERS = 16 };

/* Runs `step(context, worker, index)` once for each index below `count`, on up to as many threads as there are cores
 * (the caller is one of them), at most one per `grain` indexes. `worker` is the same on one thread for the whole call
 * and below MS_PARALLEL_MAX_WORKERS, so a step may keep its scratch state per worker. Indexes are handed out in
 * ascending batches, in no fixed assignment: steps must not depend on which thread runs them or on their order.
 * Returns when every step is done. Returns the number of workers used (1 means the loop ran on the caller alone). */
size_t ms_parallel_for(size_t count, size_t grain, void (*step)(void *context, size_t worker, size_t index), void *context);

#endif
