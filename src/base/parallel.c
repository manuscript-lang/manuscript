/* Runs the steps of a loop on every core (see parallel.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */
#include "base/parallel.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <uv.h>

typedef struct Loop {
  void (*step)(void *context, size_t worker, size_t index);
  void *context;
  size_t count;
  size_t batch;
  atomic_size_t next;
} Loop;

static void work(Loop *loop, size_t worker) {
  for (;;) {
    const size_t first = atomic_fetch_add(&loop->next, loop->batch);
    if (first >= loop->count) {
      return;
    }
    const size_t end = first + loop->batch < loop->count ? first + loop->batch : loop->count;
    for (size_t index = first; index < end; index++) {
      loop->step(loop->context, worker, index);
    }
  }
}

typedef struct Start {
  Loop *loop;
  size_t worker;
} Start;

static void thread_main(void *argument) {
  const Start *start = argument;
  work(start->loop, start->worker);
}

size_t ms_parallel_for(size_t count, size_t grain, void (*step)(void *context, size_t worker, size_t index), void *context) {
  size_t workers = uv_available_parallelism();
  workers = workers > MS_PARALLEL_MAX_WORKERS ? MS_PARALLEL_MAX_WORKERS : workers;
  grain = grain == 0 ? 1 : grain;
  const size_t useful = (count + grain - 1) / grain;
  workers = workers > useful ? useful : workers;
  Loop loop = {.step = step, .context = context, .count = count, .batch = grain};
  atomic_init(&loop.next, 0);
  if (workers <= 1) {
    work(&loop, 0);
    return 1;
  }
  uv_thread_t threads[MS_PARALLEL_MAX_WORKERS];
  Start starts[MS_PARALLEL_MAX_WORKERS];
  size_t started = 0;
  /* The caller is worker 0; a thread that cannot start only leaves its share to the others. */
  for (; started + 1 < workers; started++) {
    starts[started] = (Start){&loop, started + 1};
    if (uv_thread_create(&threads[started], thread_main, &starts[started]) != 0) {
      break;
    }
  }
  work(&loop, 0);
  for (size_t index = 0; index < started; index++) {
    (void)uv_thread_join(&threads[index]);
  }
  return started + 1;
}
