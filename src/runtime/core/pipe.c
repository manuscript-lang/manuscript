/* Pipe[T]: an in-memory stream of whole values, any number of writers and one reader.
 *
 * A pipe is one of the few objects two threads touch at once, so it synchronizes itself. Each pipe lives in a cell of a
 * table that never moves, found from its id by two loads. Writers hand values over under the cell's spin lock; the
 * reader takes the whole shared queue per lock acquisition by swapping it with a queue only it touches. Each writer's
 * values arrive in the order it wrote them; values of different writers have no order between them. A reader or a
 * flush that must wait publishes itself under the lock, so a value or a wake is never lost. A value is a block of the
 * heap read by pointer, never copied deeper; a plain scalar of at most a word travels inside its queue entry and costs
 * no allocation. */
#include "runtime/core/pipe.h"

#include <stdalign.h>
#include <stdatomic.h>

#include "base/alloc.h"
#include "runtime/core/fault_abi.h"
#include "runtime/core/promise.h"
#include "runtime/core/scheduler.h"
#include "runtime/core/task.h"
#include "runtime/core/unwind.h"
#include "runtime/sys/spin.h"

/* ---- queue entries ---- */

/* A queued value: a heap block holding it, or, for a plain scalar of at most a word, the value itself in the entry,
 * which then costs no allocation and no cache line of its own to hand between threads. */
typedef struct PipeItem {
  union {
    void *block;
    uint64_t word;
  } value;
  const MsTypeDesc *desc;
} PipeItem;

static bool desc_fits_inline(const MsTypeDesc *desc) {
  const bool plain = desc->kind == MS_KIND_INT || desc->kind == MS_KIND_FLOAT || desc->kind == MS_KIND_BOOL ||
                     desc->kind == MS_KIND_POD;
  return plain && desc->size <= sizeof(uint64_t);
}

static bool item_is_inline(const PipeItem *item) { return desc_fits_inline(item->desc); }

/* The entry for the owned value at `value`, in a block unless it fits inline. */
static PipeItem item_new(const uint8_t *value, const MsTypeDesc *desc) {
  PipeItem item = {.value = {.word = 0}, .desc = desc};
  if (desc_fits_inline(desc)) {
    __builtin_memcpy(&item.value.word, value, desc->size);
    return item;
  }
  item.value.block = ms_alloc(desc->size > 0 ? desc->size : 1);
  __builtin_memcpy(item.value.block, value, desc->size);
  return item;
}

/* The value as a heap block, the form a promise result takes. */
static void *item_into_block(const PipeItem *item) {
  if (!item_is_inline(item)) {
    return item->value.block;
  }
  void *block = ms_alloc(item->desc->size > 0 ? item->desc->size : 1);
  __builtin_memcpy(block, &item->value.word, item->desc->size);
  return block;
}

/* Drops what an entry nobody took owns. */
static void item_free(const PipeItem *item) {
  if (!item_is_inline(item)) {
    ms_slot_drop(item->desc, item->value.block);
    ms_free(item->value.block);
  }
}

/* A ring of entries, its capacity zero or a power of two. */
typedef struct ItemRing {
  PipeItem *items;
  size_t head;
  size_t len;
  size_t cap;
} ItemRing;

static void ring_grow(ItemRing *ring) {
  const size_t cap = ring->cap == 0 ? 8 : ring->cap * 2;
  PipeItem *items = ms_alloc(cap * sizeof(PipeItem));
  for (size_t i = 0; i < ring->len; i++) {
    items[i] = ring->items[(ring->head + i) & (ring->cap - 1)];
  }
  ms_free(ring->items);
  ring->items = items;
  ring->head = 0;
  ring->cap = cap;
}

static void ring_push_back(ItemRing *ring, PipeItem item) {
  if (ring->len == ring->cap) {
    ring_grow(ring);
  }
  ring->items[(ring->head + ring->len) & (ring->cap - 1)] = item;
  ring->len++;
}

static void ring_push_front(ItemRing *ring, PipeItem item) {
  if (ring->len == ring->cap) {
    ring_grow(ring);
  }
  ring->head = (ring->head - 1) & (ring->cap - 1);
  ring->items[ring->head] = item;
  ring->len++;
}

static bool ring_pop_front(ItemRing *ring, PipeItem *out) {
  if (ring->len == 0) {
    return false;
  }
  *out = ring->items[ring->head];
  ring->head = (ring->head + 1) & (ring->cap - 1);
  ring->len--;
  return true;
}

/* Frees every entry still in the ring. */
static void ring_clear(ItemRing *ring) {
  PipeItem item;
  while (ring_pop_front(ring, &item)) {
    item_free(&item);
  }
}

/* ---- cells ---- */

/* Pipes per chunk and chunks in the table: the table holds up to 16M pipes at once. */
enum { PIPE_CHUNK = 256, PIPE_CHUNKS = 1 << 16, LINE = 128 };

/* Every 256th transfer on a thread passes a cancellation point. */
enum { CANCEL_POINT_MASK = 0xff };

/* A pipe's parts sit on cache lines of their own, so a writer never invalidates a line the reader works on and two busy
 * pipes never share one. */
// NOLINTNEXTLINE(clang-analyzer-optin.performance.Padding): the padding is the point, each group owns its cache line
typedef struct PipeCell {
  /* Guarded by `lock`. */
  MsSpin lock;
  size_t index; /* the cell's own position, to return it to the free list */
  uint32_t generation;
  bool live;
  bool reader_open;
  uint32_t writers;
  size_t capacity;
  ItemRing queue;     /* values writers handed over and the reader has not taken */
  MsPromise *flushes; /* flush promises waiting for the queue to fall to `capacity` */
  size_t flush_count;
  size_t flush_cap;

  /* Read by every writer, written rarely. */
  alignas(LINE) _Atomic uint32_t live_generation; /* of the live pipe, 0 when none */
  _Atomic MsPromise waiting;                      /* the read promise waiting for a value, 0 when none */
  atomic_bool flush_pending;                      /* some flush promise waits for the queue to fall */
  _Atomic uint32_t open_writers; /* mirror of `writers`: a writer queues before it closes, so a reader that sees 0
                                    (acquire) sees every value queued */

  /* Written by every write, so it sits apart from the flags the reader reads on every value. */
  alignas(LINE) atomic_size_t queue_len;

  /* The reader's own: it alone touches them, or the writer that has claimed the parked reader. */
  alignas(LINE) ItemRing front; /* values handed back by a dropped read: they come out first */
  ItemRing local;               /* values taken from the shared queue ahead of reading them */
} PipeCell;

/* The indexes of retired cells. Only creating and retiring a pipe take the lock. */
static struct {
  MsSpin lock;
  size_t count;
  uint32_t *free_list;
  size_t free_count;
  size_t free_cap;
} registry = {.lock = MS_SPIN_INIT};

static _Atomic(PipeCell *) pipe_table[PIPE_CHUNKS];

static PipeCell *cell_at(size_t index) {
  if (index / PIPE_CHUNK >= PIPE_CHUNKS) {
    return NULL;
  }
  PipeCell *chunk = atomic_load_explicit(&pipe_table[index / PIPE_CHUNK], memory_order_acquire);
  return chunk == NULL ? NULL : &chunk[index % PIPE_CHUNK];
}

static PipeCell *cell_of_index(int64_t id) {
  const int64_t position = (id & 0xffffffff) - 1;
  return position < 0 ? NULL : cell_at((size_t)position);
}

/* The cell of pipe `id`, when that pipe is live. */
static PipeCell *cell_for(int64_t id) {
  PipeCell *cell = cell_of_index(id);
  if (cell == NULL || (int64_t)atomic_load_explicit(&cell->live_generation, memory_order_acquire) != id >> 32) {
    return NULL;
  }
  return cell;
}

/* The cell of pipe `id` with its lock held, when that pipe is still live; release it with cell_unlock. */
static PipeCell *cell_lock(int64_t id) {
  PipeCell *cell = cell_of_index(id);
  if (cell == NULL) {
    return NULL;
  }
  ms_spin_lock(&cell->lock);
  if (!cell->live || (int64_t)cell->generation != id >> 32) {
    ms_spin_unlock(&cell->lock);
    return NULL;
  }
  return cell;
}

static void cell_unlock(PipeCell *cell) { ms_spin_unlock(&cell->lock); }

static void fault_text(const char *message) { msrt_fault((const uint8_t *)message, __builtin_strlen(message)); }

/* ---- the free list and the table ---- */

/* Returns the index of a retired cell to the free list; a cell whose generation ran out is never reused. */
static void registry_release(size_t index) {
  ms_spin_lock(&registry.lock);
  if (registry.free_count == registry.free_cap) {
    registry.free_cap = registry.free_cap == 0 ? 64 : registry.free_cap * 2;
    registry.free_list = ms_realloc(registry.free_list, registry.free_cap * sizeof(uint32_t));
  }
  registry.free_list[registry.free_count++] = (uint32_t)index;
  ms_spin_unlock(&registry.lock);
}

/* A chunk of zeroed cells. Chunks are never freed. */
static PipeCell *chunk_new(size_t first_index) {
  PipeCell *cells = ms_alloc_zeroed(PIPE_CHUNK * sizeof(PipeCell));
  for (size_t i = 0; i < PIPE_CHUNK; i++) {
    cells[i].index = first_index + i;
  }
  return cells;
}

/* The index of a cell no pipe uses: a retired one, or the next of the table. SIZE_MAX when the table is full. */
static size_t registry_take(void) {
  ms_spin_lock(&registry.lock);
  size_t index = SIZE_MAX;
  if (registry.free_count > 0) {
    index = registry.free_list[--registry.free_count];
  } else if (registry.count / PIPE_CHUNK < PIPE_CHUNKS) {
    if (registry.count % PIPE_CHUNK == 0) {
      atomic_store_explicit(&pipe_table[registry.count / PIPE_CHUNK], chunk_new(registry.count), memory_order_release);
    }
    index = registry.count++;
  }
  ms_spin_unlock(&registry.lock);
  return index;
}

/* Frees the tables of retired pipes (rings, chunks without a live pipe, the free list) that a process keeps for reuse, at
 * the end of one that balances its books; a live pipe keeps its chunk, so a leaked pipe is still counted. */
void ms_pipe_release_all(void) {
  bool kept_any = false;
  for (size_t chunk = 0; chunk < registry.count / PIPE_CHUNK + 1 && chunk < PIPE_CHUNKS; chunk++) {
    PipeCell *cells = atomic_load_explicit(&pipe_table[chunk], memory_order_acquire);
    if (cells == NULL) {
      continue;
    }
    bool live = false;
    for (size_t i = 0; i < PIPE_CHUNK; i++) {
      live = live || cells[i].live;
    }
    if (live) {
      kept_any = true; /* a leaked pipe keeps its chunk, and its blocks stay counted */
      continue;
    }
    for (size_t i = 0; i < PIPE_CHUNK; i++) {
      ms_free(cells[i].queue.items);
      ms_free(cells[i].front.items);
      ms_free(cells[i].local.items);
      ms_free(cells[i].flushes);
    }
    atomic_store_explicit(&pipe_table[chunk], NULL, memory_order_release);
    ms_free(cells);
  }
  if (!kept_any) {
    ms_free(registry.free_list);
    registry.free_list = NULL;
    registry.free_count = registry.free_cap = registry.count = 0;
  }
}

/* ---- the reader's side ---- */

static bool take_ready(PipeCell *cell, PipeItem *out) {
  return ring_pop_front(&cell->front, out) || ring_pop_front(&cell->local, out);
}

/* Takes over the read promise that waits, if any. */
static MsPromise claim_reader(PipeCell *cell) {
  if (atomic_load_explicit(&cell->waiting, memory_order_acquire) == 0) {
    return 0;
  }
  return atomic_exchange_explicit(&cell->waiting, 0, memory_order_acq_rel);
}

static size_t backlog(const PipeCell *cell) { return atomic_load_explicit(&cell->queue_len, memory_order_relaxed); }

static void publish_backlog(PipeCell *cell) {
  atomic_store_explicit(&cell->queue_len, cell->queue.len, memory_order_relaxed);
}

/* Frees the pipe when its last writer and its reader are gone. The lock is held. */
static void retire(PipeCell *cell) {
  if (cell->writers != 0 || cell->reader_open) {
    return;
  }
  ring_clear(&cell->queue);
  cell->live = false;
  atomic_store_explicit(&cell->live_generation, 0, memory_order_release);
  ring_clear(&cell->front);
  ring_clear(&cell->local);
  atomic_store_explicit(&cell->queue_len, 0, memory_order_relaxed);
  if (cell->generation < INT32_MAX) {
    registry_release(cell->index);
  }
}

/* The next value for the reader from the shared queue, with everything queued behind it moved into the reader's own
 * ring by swapping the two, so the lock is held for a few pointer moves and the following reads need none. The
 * reader's ring is empty here (take_ready found nothing). The lock is held. */
static bool take_batch(PipeCell *cell, PipeItem *out) {
  if (cell->queue.len == 0) {
    return false;
  }
  const ItemRing shared = cell->queue;
  cell->queue = cell->local;
  cell->local = shared;
  publish_backlog(cell);
  return ring_pop_front(&cell->local, out);
}

/* ---- flushes ---- */

/* The flush promises that no longer wait, moved into a new array the caller frees; NULL (count 0) when the queues are
 * still above the capacity or no flush waits. The lock is held. */
static MsPromise *take_flushes(PipeCell *cell, size_t *count) {
  *count = 0;
  if (backlog(cell) > cell->capacity || cell->flush_count == 0) {
    return NULL;
  }
  MsPromise *ids = cell->flushes;
  *count = cell->flush_count;
  cell->flushes = NULL;
  cell->flush_count = 0;
  cell->flush_cap = 0;
  atomic_store(&cell->flush_pending, false);
  return ids;
}

static void complete_flushes(MsPromise *ids, size_t count) {
  for (size_t i = 0; i < count; i++) {
    ms_promise_io_done_unit(ids[i]);
  }
  ms_free(ids);
}

static void flushes_add(PipeCell *cell, MsPromise id) {
  if (cell->flush_count == cell->flush_cap) {
    cell->flush_cap = cell->flush_cap == 0 ? 4 : cell->flush_cap * 2;
    cell->flushes = ms_realloc(cell->flushes, cell->flush_cap * sizeof(MsPromise));
  }
  cell->flushes[cell->flush_count++] = id;
  atomic_store(&cell->flush_pending, true);
}

static void flushes_remove(PipeCell *cell, MsPromise id) {
  for (size_t i = 0; i < cell->flush_count; i++) {
    if (cell->flushes[i] == id) {
      cell->flush_count--;
      for (size_t j = i; j < cell->flush_count; j++) {
        cell->flushes[j] = cell->flushes[j + 1];
      }
      break;
    }
  }
  if (cell->flush_count == 0) {
    atomic_store(&cell->flush_pending, false);
  }
}

/* After the reader took a value: lets the flushes that now fit go. */
static void after_consume(PipeCell *cell) {
  atomic_thread_fence(memory_order_seq_cst);
  if (!atomic_load_explicit(&cell->flush_pending, memory_order_relaxed)) {
    return;
  }
  ms_spin_lock(&cell->lock);
  size_t count = 0;
  MsPromise *released = take_flushes(cell, &count);
  ms_spin_unlock(&cell->lock);
  complete_flushes(released, count);
}

/* ---- cancellation points ---- */

/* Every 256th transfer on a thread passes a scheduler point and a cancellation check, so a task that always finds work
 * still sees timers, time limits and cancellation. True when a cancel is pending: the entry that holds nothing ends its
 * call with ms_sched_cancel_return. */
static bool cancellation_point(void) {
  static _Thread_local uint32_t operations; /* per scheduler thread */
  operations++;
  if ((operations & CANCEL_POINT_MASK) != 0) {
    return false;
  }
  ms_task_yield();
  return ms_cancel_flag() != 0;
}

/* ---- the program ABI ---- */

/* A value read but never taken (its promise ended first) goes back to the front of its pipe. */
static void pipe_unread(int64_t pipe, void *block, const MsTypeDesc *desc) {
  const PipeItem item = {.value = {.block = block}, .desc = desc};
  PipeCell *cell = cell_lock(pipe);
  if (cell == NULL) {
    item_free(&item);
    return;
  }
  if (cell->reader_open) {
    ring_push_front(&cell->front, item);
  } else {
    item_free(&item);
  }
  cell_unlock(cell);
}

int64_t msrt_pipe_new(int64_t capacity) {
  static atomic_bool hook_set;
  if (!atomic_exchange(&hook_set, true)) {
    ms_promise_set_unread(pipe_unread);
  }
  const size_t index = registry_take();
  PipeCell *cell = index == SIZE_MAX ? NULL : cell_at(index);
  if (cell == NULL) {
    fault_text("pipe: too many pipes are open at once");
  }
  ms_spin_lock(&cell->lock);
  cell->generation++;
  cell->live = true;
  cell->capacity = capacity > 0 ? (size_t)capacity : 0;
  cell->writers = 1;
  cell->reader_open = true;
  cell->flush_count = 0;
  atomic_store(&cell->waiting, 0);
  atomic_store(&cell->flush_pending, false);
  atomic_store(&cell->open_writers, 1);
  atomic_store_explicit(&cell->live_generation, cell->generation, memory_order_release);
  const int64_t id = (int64_t)cell->generation << 32 | (int64_t)(index + 1);
  ms_spin_unlock(&cell->lock);
  return id;
}

void msrt_pipe_add_writer(int64_t pipe) {
  PipeCell *cell = cell_lock(pipe);
  if (cell == NULL) {
    return;
  }
  cell->writers++;
  atomic_store_explicit(&cell->open_writers, cell->writers, memory_order_release);
  cell_unlock(cell);
}

/* Hands the value to the parked reader whose promise `reader` is. */
static void finish_read(MsPromise reader, const PipeItem *item, int64_t pipe) {
  ms_promise_io_done_block(reader, item_into_block(item), item->desc, pipe);
}

int64_t msrt_pipe_write(int64_t pipe, uint8_t *value, const MsTypeDesc *desc) {
  const PipeItem item = item_new(value, desc);
  PipeCell *cell = cell_lock(pipe);
  if (cell == NULL || !cell->reader_open) {
    if (cell != NULL) {
      cell_unlock(cell);
    }
    item_free(&item);
    return MS_PIPE_CLOSED;
  }
  ring_push_back(&cell->queue, item);
  publish_backlog(cell);
  const MsPromise reader = claim_reader(cell);
  if (reader == 0) {
    const int64_t status = backlog(cell) > cell->capacity ? MS_PIPE_FULL : MS_PIPE_WRITTEN;
    cell_unlock(cell);
    if (cancellation_point()) {
      ms_sched_cancel_return();
    }
    return status;
  }
  /* The reader was parked, so the queue held nothing else. */
  PipeItem first = {.value = {.word = 0}, .desc = NULL};
  const bool popped = ring_pop_front(&cell->queue, &first);
  publish_backlog(cell);
  cell_unlock(cell);
  if (popped) {
    finish_read(reader, &first, pipe);
  }
  return MS_PIPE_WRITTEN;
}

/* The read promise's cancel hook: the reader leaves the pipe's wait. */
static bool reader_cancelled(MsPromise id, uintptr_t pipe, uint32_t bits) {
  (void)bits;
  PipeCell *cell = cell_for((int64_t)pipe);
  if (cell != NULL) {
    MsPromise expected = id;
    (void)atomic_compare_exchange_strong(&cell->waiting, &expected, 0);
  }
  return false;
}

int64_t msrt_pipe_read(int64_t pipe) {
  const MsPromise id = ms_promise_new();
  PipeCell *cell = cell_for(pipe);
  if (cell == NULL) {
    ms_promise_io_done(id);
    return id;
  }
  PipeItem item;
  if (take_ready(cell, &item)) {
    after_consume(cell);
    finish_read(id, &item, pipe);
    return id;
  }
  cell = cell_lock(pipe);
  if (cell == NULL) {
    ms_promise_io_done(id);
    return id;
  }
  if (atomic_load_explicit(&cell->waiting, memory_order_acquire) != 0) {
    cell_unlock(cell);
    fault_text("pipe: a read is already waiting");
  }
  if (!take_batch(cell, &item)) {
    const bool ended = cell->writers == 0;
    if (!ended) {
      ms_promise_set_remote_wake(id);
      atomic_store(&cell->waiting, id);
    }
    cell_unlock(cell);
    if (ended) {
      ms_promise_io_done(id);
    } else {
      ms_promise_on_drop(id, reader_cancelled, (uintptr_t)pipe);
    }
    return id;
  }
  size_t count = 0;
  MsPromise *released = take_flushes(cell, &count);
  cell_unlock(cell);
  complete_flushes(released, count);
  finish_read(id, &item, pipe);
  return id;
}

uint8_t msrt_pipe_try(int64_t pipe, const MsTypeDesc *desc, uint8_t *out) {
  if (cancellation_point()) {
    ms_sched_cancel_return();
    return 0;
  }
  PipeCell *cell = cell_for(pipe);
  if (cell == NULL) {
    return 0;
  }
  PipeItem item;
  if (take_ready(cell, &item)) {
    after_consume(cell);
  } else {
    /* Nothing queued: a reader that has caught up must not fight the writers for the lock. */
    if (backlog(cell) == 0) {
      return 0;
    }
    cell = cell_lock(pipe);
    if (cell == NULL) {
      return 0;
    }
    if (!take_batch(cell, &item)) {
      cell_unlock(cell);
      return 0;
    }
    size_t count = 0;
    MsPromise *released = take_flushes(cell, &count);
    cell_unlock(cell);
    complete_flushes(released, count);
  }
  if (item_is_inline(&item)) {
    __builtin_memcpy(out, &item.value.word, desc->size);
  } else {
    __builtin_memcpy(out, item.value.block, desc->size);
    ms_free(item.value.block);
  }
  return 1;
}

int64_t msrt_pipe_ended(int64_t pipe) {
  PipeCell *cell = cell_for(pipe);
  if (cell == NULL) {
    return 1;
  }
  /* The writers first: they queue before they close, so no value can appear after this sees 0. */
  if (atomic_load_explicit(&cell->open_writers, memory_order_acquire) != 0) {
    return 0;
  }
  const bool held = cell->front.len != 0 || cell->local.len != 0;
  return backlog(cell) == 0 && !held;
}

int64_t msrt_pipe_brief_wait(int64_t pipe) {
  PipeCell *cell = cell_for(pipe);
  if (cell == NULL) {
    return 1;
  }
  return backlog(cell) != 0 || atomic_load_explicit(&cell->open_writers, memory_order_acquire) == 0;
}

/* The flush promise's cancel hook: it leaves the pipe's list. */
static bool flush_cancelled(MsPromise id, uintptr_t pipe, uint32_t bits) {
  (void)bits;
  PipeCell *cell = cell_lock((int64_t)pipe);
  if (cell != NULL) {
    flushes_remove(cell, id);
    cell_unlock(cell);
  }
  return false;
}

int64_t msrt_pipe_flush(int64_t pipe) {
  const MsPromise id = ms_promise_new();
  PipeCell *cell = cell_lock(pipe);
  bool waits = false;
  if (cell != NULL && cell->reader_open && backlog(cell) > cell->capacity) {
    flushes_add(cell, id);
    atomic_thread_fence(memory_order_seq_cst);
    waits = backlog(cell) > cell->capacity;
    if (!waits) { /* the reader caught up while this flush registered */
      flushes_remove(cell, id);
    }
  }
  if (waits) {
    ms_promise_set_remote_wake(id);
  }
  if (cell != NULL) {
    cell_unlock(cell);
  }
  if (waits) {
    ms_promise_on_drop(id, flush_cancelled, (uintptr_t)pipe);
  } else {
    ms_promise_io_done_unit(id);
  }
  return id;
}

void msrt_pipe_close_writer(int64_t pipe) {
  PipeCell *cell = cell_lock(pipe);
  if (cell == NULL) {
    return;
  }
  if (cell->writers > 0) {
    cell->writers--;
  }
  atomic_store_explicit(&cell->open_writers, cell->writers, memory_order_release);
  /* A parked reader means the queue was empty when it parked, and a write since would have claimed it. */
  const MsPromise reader = cell->writers == 0 && cell->queue.len == 0 ? claim_reader(cell) : 0;
  retire(cell);
  cell_unlock(cell);
  if (reader != 0) {
    ms_promise_io_done(reader);
  }
}

void msrt_pipe_close_reader(int64_t pipe) {
  PipeCell *cell = cell_lock(pipe);
  if (cell == NULL) {
    return;
  }
  cell->reader_open = false;
  atomic_store(&cell->waiting, 0);
  ring_clear(&cell->queue);
  ring_clear(&cell->front);
  ring_clear(&cell->local);
  atomic_store_explicit(&cell->queue_len, 0, memory_order_relaxed);
  atomic_store(&cell->flush_pending, false);
  MsPromise *flushes = cell->flushes;
  const size_t count = cell->flush_count;
  cell->flushes = NULL;
  cell->flush_count = 0;
  cell->flush_cap = 0;
  retire(cell);
  cell_unlock(cell);
  complete_flushes(flushes, count);
}
