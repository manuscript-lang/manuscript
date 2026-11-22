/* Freeing deeply nested data in bounded stack. The drop glue of a type that can contain itself (a tree, a JSON
 * value) enters here: below LIMIT nested drops it runs as usual; at the limit it parks the value in a heap block on
 * a worklist and returns, and the drop that started the nest drains the worklist when it finishes. Each drained
 * value starts a fresh nest, so the stack never holds more than LIMIT levels however deep the data is. Only data
 * deeper than LIMIT is reordered: its deepest parts are freed after their siblings. */
#include "base/alloc.h"
#include "runtime/core/alloc.h"
#include "runtime/core/drop_queue.h"
#include "runtime/core/task_abi.h"

/* Nested drops that run recursively before the next one is deferred. */
enum { LIMIT = 256 };

typedef struct Parked {
  void (*run)(uint8_t *block);
  uint8_t *block;
} Parked;

typedef struct DropState {
  uint32_t depth;
  bool draining;
  Parked *pending;
  size_t count;
  size_t capacity;
} DropState;

static _Thread_local DropState state; /* per-thread, like the stack it protects */

int64_t msrt_drop_enter(void) {
  if (state.depth >= LIMIT) {
    return 1;
  }
  state.depth++;
  return 0;
}

void msrt_drop_defer(void (*run)(uint8_t *block), uint8_t *block) {
  if (state.count == state.capacity) {
    state.capacity = state.capacity == 0 ? 16 : state.capacity * 2;
    state.pending = ms_realloc(state.pending, state.capacity * sizeof(Parked));
  }
  state.pending[state.count++] = (Parked){run, block};
}

void msrt_drop_leave(void) {
  state.depth = state.depth > 0 ? state.depth - 1 : 0;
  if (state.depth != 0 || state.draining) {
    return;
  }
  state.draining = true;
  while (state.count > 0) {
    const Parked parked = state.pending[--state.count];
    parked.run(parked.block);
    ms_free(parked.block);
  }
  state.draining = false;
}

/* The three words a grown copy needs: the copy function, its source and its destination. */
typedef void (*CopyFn)(const uint8_t *src, uint8_t *dst);

typedef struct GrownCopy {
  CopyFn copy;
  const uint8_t *src;
  uint8_t *dst;
} GrownCopy;

static void run_copy(void *block) {
  const GrownCopy *grown = (const GrownCopy *)block;
  grown->copy(grown->src, grown->dst);
}

void msrt_slot_copy_grown(void (*copy)(const uint8_t *src, uint8_t *dst), const uint8_t *src, uint8_t *dst) {
  GrownCopy *block = ms_alloc(sizeof *block);
  *block = (GrownCopy){copy, src, dst};
  msrt_task_grow(run_copy, block);
  ms_free(block);
}
