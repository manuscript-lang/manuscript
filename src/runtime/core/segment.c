/* Stack segments: a task that recurses past its slot continues on further slots, one per ms_task_grow. See
 * task.h.
 *
 * The cyclic functions of a program check the stack pointer against the limit in the region cell; below it, they
 * call ms_task_grow, which runs the function again on a fresh slot with the same parameters. The slot keeps
 * a chain cell at its top, [low, high, chain, 0] of the segment below it, which a frame walker follows when it
 * leaves the bounds of the running segment. A task keeps its segments until it ends, so a loop that crosses a
 * boundary on every iteration allocates nothing.
 */
#include "runtime/core/scheduler.h"

#include "base/alloc.h"

enum {
  CHAIN_CELL_WORDS = 4,
  CHAIN_CELL_BYTES = CHAIN_CELL_WORDS * sizeof(uintptr_t),
  /* A main task's region is the whole 256 MiB, the cap; a slot task adds up to the rest of a region's worth. */
  MAX_SEGMENTS = (int)(MS_STACK_REGION / MS_STACK_SLOT) - 1,
};

typedef struct SegmentBounds {
  uintptr_t low;   /* lowest usable address */
  uintptr_t high;  /* one past the highest */
  uintptr_t chain; /* the chain cell, or 0 on the home slot */
} SegmentBounds;

static SegmentBounds segment_bounds(const MsTask *task, uint32_t segment) {
  if (segment == 0) {
    const uintptr_t base = (uintptr_t)task->stack;
    return (SegmentBounds){.low = base + MS_STACK_GUARD,
                 .high = ms_stack_top(task->stack, task->stack_length),
                 .chain = 0};
  }
  const uintptr_t base = (uintptr_t)task->extra->segments.ptr[segment - 1];
  const uintptr_t top = base + MS_STACK_SLOT - CHAIN_CELL_BYTES;
  return (SegmentBounds){.low = base + MS_STACK_GUARD, .high = top, .chain = top};
}

static void set_segment_state(MsUnwind *unwind, SegmentBounds bounds) {
  unwind->stack_low = bounds.low;
  unwind->stack_high = bounds.high;
  unwind->stack_chain = bounds.chain;
}

uint32_t ms_task_segment(void) { return ms_task_running()->segment; }

void ms_task_publish_limit(void) {
  MsTask *const task = ms_task_running();
  if (task->stack == NULL) {
    return;
  }
  uint8_t *const base = task->segment == 0 ? task->stack : task->extra->segments.ptr[task->segment - 1];
  ms_stack_publish(base, &task->unwind.hdr, task->unwind.hdr.limit);
}

void ms_task_restore_segment(uint32_t segment) {
  MsTask *const task = ms_task_running();
  if (task->segment == segment) {
    return;
  }
  task->segment = segment;
  if (task->extra != NULL && task->extra->segment_teb.len > segment) {
    task->extra->segment_teb.len = segment;
  }
  set_segment_state(&task->unwind, segment_bounds(task, segment));
}

void ms_task_segment_teb(uint32_t segment, uintptr_t out[MS_CTX_TEB_WORDS]) {
  const MsTask *const task = ms_task_running();
  if (task->segment == segment || task->extra == NULL || segment >= task->extra->segment_teb.len) {
    ms_ctx_teb_stack(out);
  } else {
    __builtin_memcpy(out, task->extra->segment_teb.ptr[segment].words, sizeof task->extra->segment_teb.ptr[segment].words);
  }
}

static void free_block(uint8_t *block) { ms_free(block); }

/* Makes sure the task holds a slot for segment `k` (counted from 1). */
static bool ensure_segment(MsSched *sched, MsTask *task, uint32_t k) {
  if (task->extra == NULL) {
    task->extra = ms_alloc_zeroed(sizeof *task->extra);
  }
  MsTaskExtra *const extra = task->extra;
  if (extra->segments.len >= k) {
    return true;
  }
  uint8_t *base = NULL;
  if (!ms_stacks_acquire(&sched->stacks, MS_STACK_SLOT, &base)) {
    return false;
  }
  ms_segment_list_push(&extra->segments, base);
  return true;
}

/* The words ms_ctx_call_on_stack installs on Windows: the segment's stack bounds, then the caller's own for the
 * way back. Elsewhere they are ignored. */
static void teb_pair(const uint8_t *base, uintptr_t out[2 * MS_CTX_TEB_WORDS]) {
  const uintptr_t top = (uintptr_t)base + MS_STACK_SLOT;
  out[0] = top;
  out[1] = top - MS_STACK_INITIAL_COMMIT;
  out[2] = (uintptr_t)base;
  ms_ctx_teb_stack(&out[MS_CTX_TEB_WORDS]);
}

static void remember_teb(MsTask *task, const uintptr_t *teb) {
  MsTebWords words;
  __builtin_memcpy(words.words, &teb[MS_CTX_TEB_WORDS], sizeof words.words);
  ms_teb_list_push(&task->extra->segment_teb, words);
}

MsTaskStatus ms_task_grow(void (*shim)(void *), void *block) {
  MsSched *const sched = ms_sched();
  MsTask *const task = ms_task_running();
  MsUnwind *const unwind = &task->unwind;
  const uint32_t k = task->segment + 1;
  /* A cancellation or fault inside the shim leaves by a jump that skips the caller's free of `block`, so a
   * cleanup releases it; the normal return discards the cleanup. */
  const size_t release = ms_cleanup_push(free_block, block);
  if (task->stack == NULL || task->stack_length == MS_STACK_REGION || k > (uint32_t)MAX_SEGMENTS ||
    !ensure_segment(sched, task, k)) {
    return MS_TASK_STACK_OVERFLOW;
  }
  uint8_t *const base = task->extra->segments.ptr[k - 1];
  if (!ms_stack_commit_top(base, MS_STACK_SLOT)) {
    return MS_TASK_STACK_OVERFLOW;
  }
  const SegmentBounds bounds = segment_bounds(task, k);
  const SegmentBounds previous = {.low = unwind->stack_low, .high = unwind->stack_high, .chain = unwind->stack_chain};
  const uintptr_t chain_cell[CHAIN_CELL_WORDS] = {previous.low, previous.high, previous.chain, 0};
  __builtin_memcpy(base + MS_STACK_SLOT - CHAIN_CELL_BYTES, chain_cell, sizeof chain_cell);
  const uintptr_t outer_limit = unwind->hdr.limit;
  unwind->hdr.limit = ms_stack_limit(bounds.low, bounds.high);
  ms_stack_publish(base, &unwind->hdr, unwind->hdr.limit);
  set_segment_state(unwind, bounds);
  task->segment = k;
  uintptr_t teb[2 * MS_CTX_TEB_WORDS] = {0};
  teb_pair(base, teb);
  remember_teb(task, teb);
  uintptr_t left_at = 0; /* the stack pointer the call leaves this segment at; lives in this frame */
  ms_ctx_call_on_stack(bounds.high, shim, block, &left_at, teb);
  ms_cleanup_discard(release);
  task->segment = k - 1;
  task->extra->segment_teb.len = k - 1;
  unwind->hdr.limit = outer_limit;
  ms_task_publish_limit();
  set_segment_state(unwind, previous);
  return MS_TASK_OK;
}

enum { MS_STACK_NATIVE_ROOM = 64 * 1024 };

typedef struct StackCall {
  void (*fn)(void *);
  void *arg;
} StackCall;

static void run_stack_call(void *block) {
  const StackCall *call = block;
  call->fn(call->arg);
}

void ms_stack_call(void (*fn)(void *), void *arg) {
  const uintptr_t limit = ms_task_running()->unwind.hdr.limit;
  if (limit == 0 || (uintptr_t)__builtin_frame_address(0) - limit > MS_STACK_NATIVE_ROOM) {
    fn(arg);
    return;
  }
  StackCall *call = ms_alloc(sizeof *call);
  *call = (StackCall){.fn = fn, .arg = arg};
  if (ms_task_grow(run_stack_call, call) != MS_TASK_OK) {
    ms_fault_text(MS_FAULT_KIND_STACK_OVERFLOW, "stack overflow: recursion too deep or stack frames too large");
  }
  ms_free(call);
}
