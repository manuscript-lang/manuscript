/* Owns the worker threads behind ms_parallel_for (see parallel.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */
#include "base/parallel.h"

#include <stdatomic.h>

#include <uv.h>

/* LLVM-sized recursion is not expected here, but a pass recurses on a deep function: a stack as large as the main
 * thread's, not the system's default (which is 512 KiB on macOS). */
enum { PARALLEL_STACK_BYTES = 8 << 20, PARALLEL_BATCH = 4 };

typedef struct Shared {
  atomic_size_t next;
  size_t count;
  MsParallelFn fn;
  void *context;
} Shared;

typedef struct Worker {
  Shared *shared;
  uint32_t id;
} Worker;

static void work(Worker *worker) {
  Shared *shared = worker->shared;
  for (;;) {
    const size_t first = atomic_fetch_add_explicit(&shared->next, PARALLEL_BATCH, memory_order_relaxed);
    if (first >= shared->count) {
      return;
    }
    const size_t end = first + PARALLEL_BATCH < shared->count ? first + PARALLEL_BATCH : shared->count;
    for (size_t item = first; item < end; item++) {
      shared->fn(shared->context, item, worker->id);
    }
  }
}

static void thread_main(void *argument) {
  work(argument);
}

uint32_t ms_parallel_threads(size_t count, size_t grain) {
  const unsigned cores = uv_available_parallelism();
  const size_t wanted = grain == 0 ? count : count / grain;
  const size_t threads = wanted < cores ? wanted : cores;
  return threads < 1 ? 1 : (uint32_t)threads;
}

void ms_parallel_for(uint32_t threads, size_t count, MsParallelFn fn, void *context) {
  enum { MAX_THREADS = 64 };
  threads = threads < 1 ? 1 : threads > MAX_THREADS ? MAX_THREADS : threads;
  Shared shared = {.count = count, .fn = fn, .context = context};
  atomic_init(&shared.next, 0);
  Worker workers[MAX_THREADS];
  uv_thread_t handles[MAX_THREADS];
  bool started[MAX_THREADS] = {false};
  const uv_thread_options_t stack = {.flags = UV_THREAD_HAS_STACK_SIZE, .stack_size = PARALLEL_STACK_BYTES};
  for (uint32_t id = 1; id < threads; id++) {
    workers[id] = (Worker){.shared = &shared, .id = id};
    started[id] = uv_thread_create_ex(&handles[id], &stack, thread_main, &workers[id]) == 0;
  }
  workers[0] = (Worker){.shared = &shared, .id = 0};
  work(&workers[0]);
  for (uint32_t id = 1; id < threads; id++) {
    if (started[id]) {
      (void)uv_thread_join(&handles[id]);
    }
  }
}
