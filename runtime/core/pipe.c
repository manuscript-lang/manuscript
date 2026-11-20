/* Pipe[T]: an in-memory stream of whole values, any number of writers and one reader.
 *
 * A pipe is one of the few objects two threads touch at once, so it synchronizes itself. Each pipe lives in a
 * cell of a table that never moves, found from its id by two loads. Writers hand values over under the cell's
 * spin lock; the reader takes the whole shared queue per lock acquisition by swapping it with a queue only it
 * touches. Each writer's values arrive in the order it wrote them; values of different writers have no order
 * between them. A reader or a flush that must wait publishes itself under the lock, so a value or a wake is
 * never lost. A value is a block of the heap read by pointer, never copied deeper; a plain scalar of at most a
 * word travels inside its queue entry and costs no allocation.
 *
 * Promises are completed through promise.h, which is owner-thread only until the multi-thread scheduler lands:
 * a pipe between two threads becomes live with that change (ms_promise_set_remote_wake marks the promises a
 * peer will finish).
 */
#include <stdalign.h>
#include <stdatomic.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/pipe.h"
#include "ms_rt/sys.h"
#include "promise.h"
#include "scheduler.h"
#include "spin.h"
#include "unwind.h"


/* ---- queue entries ---- */

/* A queued value: a heap block holding it, or, for a plain scalar of at most a word, the value itself in the entry,
 * which then costs no allocation and no cache line of its own to hand between threads. */
typedef struct PipeItem {
    union {
        void *block;   /* a heap block holding the value */
        uint64_t word; /* a plain scalar of at most a word (item_fits_inline): the value itself */
    } value;
    const MsTypeDesc *desc;
} PipeItem;

_Static_assert(sizeof(PipeItem) == 2 * sizeof(uintptr_t), "an entry is two words");

enum { WORD_BYTES = sizeof(uint64_t) };

static bool item_fits_inline(const MsTypeDesc *desc) {
    const bool plain = desc->kind == MS_KIND_INT || desc->kind == MS_KIND_FLOAT || desc->kind == MS_KIND_BOOL ||
                       desc->kind == MS_KIND_POD;
    return plain && desc->size <= WORD_BYTES;
}

static bool item_is_inline(const PipeItem *item) { return item_fits_inline(item->desc); }

static const MsTypeDesc *item_desc(const PipeItem *item) { return item->desc; }

/* The entry for the owned value at `value`, in a block unless it fits inline. */
static PipeItem item_new(const uint8_t *value, const MsTypeDesc *desc) {
    PipeItem item = {.value = {.word = 0}, .desc = desc};
    if (item_fits_inline(desc)) {
        memcpy(&item.value.word, value, desc->size);
        return item;
    }
    const size_t size = desc->size > 0 ? desc->size : 1;
    uint8_t *block = msrt_alloc(size);
    memcpy(block, value, desc->size);
    item.value.block = block;
    return item;
}

/* The value as a heap block, the form a promise result takes. */
static void *item_into_block(const PipeItem *item) {
    if (!item_is_inline(item)) {
        return item->value.block;
    }
    const MsTypeDesc *desc = item_desc(item);
    uint8_t *block = msrt_alloc(desc->size > 0 ? desc->size : 1);
    memcpy(block, &item->value.word, desc->size);
    return block;
}

/* Drops what an entry nobody took owns. */
static void item_free(const PipeItem *item) {
    if (item_is_inline(item)) {
        return;
    }
    msrt_slot_drop(item_desc(item), item->value.block);
    msrt_free(item->value.block);
}

/* A ring of entries, its capacity zero or a power of two. Allocated with the system allocator: any thread frees it. */
typedef struct ItemRing {
    PipeItem *items; /* owned */
    size_t head;
    size_t len;
    size_t cap;
} ItemRing;

static bool ring_grow(ItemRing *ring) {
    const size_t cap = ring->cap == 0 ? 8 : ring->cap * 2;
    size_t bytes = 0;
    if (!ms_size_mul(cap, sizeof(PipeItem), &bytes)) {
        return false;
    }
    PipeItem *items = ms_sys_malloc(bytes);
    if (items == NULL) {
        return false;
    }
    for (size_t i = 0; i < ring->len; i++) {
        items[i] = ring->items[(ring->head + i) & (ring->cap - 1)];
    }
    ms_sys_free(ring->items);
    ring->items = items;
    ring->head = 0;
    ring->cap = cap;
    return true;
}

MS_NODISCARD static bool ring_push_back(ItemRing *ring, PipeItem item) {
    if (ring->len == ring->cap && !ring_grow(ring)) {
        return false;
    }
    ring->items[(ring->head + ring->len) & (ring->cap - 1)] = item;
    ring->len++;
    return true;
}

MS_NODISCARD static bool ring_push_front(ItemRing *ring, PipeItem item) {
    if (ring->len == ring->cap && !ring_grow(ring)) {
        return false;
    }
    ring->head = (ring->head - 1) & (ring->cap - 1);
    ring->items[ring->head] = item;
    ring->len++;
    return true;
}

MS_NODISCARD static bool ring_pop_front(ItemRing *ring, PipeItem *out) {
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

/* The gap in nanoseconds the reader leaves between looks at an empty queue; see msrt_pipe_brief_wait. */
enum { GAP_MIN = 100, GAP_MAX = 16000 };

/* A run of values at a look means the writer streams. */
enum { RUN_LENGTH = 4 };

/* Every 256th transfer on a thread passes a cancellation point. */
enum { CANCEL_POINT_MASK = 0xff };

/* A pipe's parts sit on cache lines of their own, so a writer never invalidates a line the reader works on and two
 * busy pipes never share one. */
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
    ItemRing queue; /* values writers handed over and the reader has not taken */
    MsPromise *flushes; /* owned: flush promises waiting for the queue to fall to `capacity` */
    size_t flush_count;
    size_t flush_cap;

    /* Read by every writer, written rarely. */
    alignas(LINE) _Atomic uint32_t live_generation; /* of the live pipe, 0 when none */
    _Atomic MsPromise waiting;                      /* the read promise waiting for a value, 0 when none */
    atomic_bool flush_pending;                      /* some flush promise waits for the queue to fall */
    _Atomic uint32_t open_writers;                  /* mirror of `writers`: a writer queues before it closes, so a
                                                       reader that sees 0 (acquire) sees every value queued */

    /* Written by every write, so it sits apart from the flags the reader reads on every value. */
    alignas(LINE) atomic_size_t queue_len;

    /* The reader's own: it alone touches them, or the writer that has claimed the parked reader. */
    alignas(LINE) ItemRing front; /* values handed back by a dropped read: they come out first */
    ItemRing local;               /* values taken from the shared queue ahead of reading them */
    atomic_int_fast64_t gap;
} PipeCell;

/* The cells of live and retired pipes, and the indexes of the retired ones. Only creating and retiring a pipe
 * take the lock. */
static struct {
    MsSpin lock;
    size_t count;
    uint32_t *free_list; /* owned */
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

static bool index_of(int64_t id, size_t *index) {
    const int64_t position = (id & 0xffffffff) - 1;
    if (position < 0) {
        return false;
    }
    *index = (size_t)position;
    return true;
}

/* The cell of pipe `id`, when that pipe is live. */
static PipeCell *cell_for(int64_t id) {
    size_t index = 0;
    if (!index_of(id, &index)) {
        return NULL;
    }
    PipeCell *cell = cell_at(index);
    if (cell == NULL || (int64_t)atomic_load_explicit(&cell->live_generation, memory_order_acquire) != id >> 32) {
        return NULL;
    }
    return cell;
}

/* The cell of pipe `id` with its lock held, when that pipe is still live; release it with cell_unlock. */
static PipeCell *cell_lock(int64_t id) {
    size_t index = 0;
    PipeCell *cell = index_of(id, &index) ? cell_at(index) : NULL;
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

/* Ends the operation the lock is held in with the out-of-memory fault (the lock is released first). */
MS_NORETURN static void fault_no_memory(PipeCell *held) {
    if (held != NULL) {
        cell_unlock(held);
    }
    static const char message[] = "pipe: out of memory";
    msrt_fault((const uint8_t *)message, sizeof message - 1);
}

/* ---- the free list and the table ---- */

/* Returns the index of a retired cell to the free list; a cell whose generation ran out is never reused. */
static void registry_release(size_t index) {
    ms_spin_lock(&registry.lock);
    if (registry.free_count == registry.free_cap) {
        const size_t cap = registry.free_cap == 0 ? 64 : registry.free_cap * 2;
        size_t bytes = 0;
        uint32_t *grown = ms_size_mul(cap, sizeof(uint32_t), &bytes) ? ms_sys_realloc(registry.free_list, bytes) : NULL;
        if (grown == NULL) { /* the index is lost: a leaked cell, never an invalid one */
            ms_spin_unlock(&registry.lock);
            return;
        }
        registry.free_list = grown;
        registry.free_cap = cap;
    }
    registry.free_list[registry.free_count++] = (uint32_t)index;
    ms_spin_unlock(&registry.lock);
}

/* A chunk of zeroed cells aligned to a cache line. Chunks are never freed. */
static PipeCell *chunk_new(size_t first_index) {
    const size_t bytes = PIPE_CHUNK * sizeof(PipeCell) + LINE;
    uint8_t *raw = ms_sys_malloc(bytes);
    if (raw == NULL) {
        return NULL;
    }
    memset(raw, 0, bytes);
    const size_t skew = (size_t)((uintptr_t)raw & (LINE - 1));
    void *const aligned = raw + (skew == 0 ? 0 : LINE - skew);
    PipeCell *const cells = aligned;
    for (size_t i = 0; i < PIPE_CHUNK; i++) {
        cells[i].index = first_index + i;
    }
    return cells;
}

/* The index of a cell no pipe uses: a retired one, or the next of the table. SIZE_MAX when the table is full or
 * memory ran out. */
static size_t registry_take(void) {
    ms_spin_lock(&registry.lock);
    size_t index = SIZE_MAX;
    if (registry.free_count > 0) {
        index = registry.free_list[--registry.free_count];
    } else if (registry.count / PIPE_CHUNK < PIPE_CHUNKS) {
        const size_t next = registry.count;
        if (next % PIPE_CHUNK != 0 || cell_at(next) != NULL) {
            index = registry.count++;
        } else {
            PipeCell *chunk = chunk_new(next);
            if (chunk != NULL) {
                atomic_store_explicit(&pipe_table[next / PIPE_CHUNK], chunk, memory_order_release);
                index = registry.count++;
            }
        }
    }
    ms_spin_unlock(&registry.lock);
    return index;
}

/* ---- the reader's side ---- */

static bool take_ready(PipeCell *cell, PipeItem *out) { return ring_pop_front(&cell->front, out) || ring_pop_front(&cell->local, out); }

/* Takes over the read promise that waits, if any. */
static MsPromise claim_reader(PipeCell *cell) {
    if (atomic_load_explicit(&cell->waiting, memory_order_acquire) == 0) {
        return 0;
    }
    return atomic_exchange_explicit(&cell->waiting, 0, memory_order_acq_rel);
}

static size_t backlog(const PipeCell *cell) { return atomic_load_explicit(&cell->queue_len, memory_order_relaxed); }

static void publish_backlog(PipeCell *cell) { atomic_store_explicit(&cell->queue_len, cell->queue.len, memory_order_relaxed); }

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

static int_fast64_t int_min(int_fast64_t a, int_fast64_t b) { return a < b ? a : b; }

static int_fast64_t int_max(int_fast64_t a, int_fast64_t b) { return a > b ? a : b; }

/* The next value for the reader from the shared queue, with everything queued behind it moved into the reader's own
 * ring by swapping the two, so the lock is held for a few pointer moves and the following reads need none. The
 * reader's ring is empty here (take_ready found nothing), and writers wait above the capacity. The lock is held. */
static bool take_batch(PipeCell *cell, PipeItem *out) {
    if (cell->queue.len == 0) {
        return false;
    }
    const ItemRing shared = cell->queue;
    cell->queue = cell->local;
    cell->local = shared;
    /* A run of values means the writer streams: look less often, so it queues longer runs between looks. A lone
     * value means a request and a reply: look soon. */
    int_fast64_t gap = atomic_load_explicit(&cell->gap, memory_order_relaxed);
    gap = cell->local.len >= RUN_LENGTH ? int_min(gap * 2, GAP_MAX) : int_max(gap / 2, GAP_MIN);
    atomic_store_explicit(&cell->gap, gap, memory_order_relaxed);
    publish_backlog(cell);
    return ring_pop_front(&cell->local, out);
}

/* ---- flushes ---- */

/* The flush promises that no longer wait, moved into a new array the caller frees with ms_sys_free; NULL (count 0)
 * when the queues are still above the capacity or no flush waits. The lock is held. */
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
    ms_sys_free(ids);
}

MS_NODISCARD static bool flushes_add(PipeCell *cell, MsPromise id) {
    if (cell->flush_count == cell->flush_cap) {
        const size_t cap = cell->flush_cap == 0 ? 4 : cell->flush_cap * 2;
        size_t bytes = 0;
        MsPromise *grown = ms_size_mul(cap, sizeof(MsPromise), &bytes) ? ms_sys_realloc(cell->flushes, bytes) : NULL;
        if (grown == NULL) {
            return false;
        }
        cell->flushes = grown;
        cell->flush_cap = cap;
    }
    cell->flushes[cell->flush_count++] = id;
    atomic_store(&cell->flush_pending, true);
    return true;
}

static void flushes_remove(PipeCell *cell, MsPromise id) {
    for (size_t i = 0; i < cell->flush_count; i++) {
        if (cell->flushes[i] == id) {
            memmove(&cell->flushes[i], &cell->flushes[i + 1], (cell->flush_count - i - 1) * sizeof(MsPromise));
            cell->flush_count--;
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

/* Every 256th transfer on a thread passes a scheduler point and a cancellation check, so a task that always finds
 * work still sees timers, time limits and cancellation. Call it where the operation holds nothing; true means the
 * caller returns its zero result now. */
static bool cancellation_point(void) {
    static _Thread_local uint32_t operations; /* per scheduler thread */
    operations++;
    if ((operations & CANCEL_POINT_MASK) != 0) {
        return false;
    }
    ms_task_yield();
    if (ms_cancel_flag() == 0) {
        return false;
    }
    if (ms_sched()->cancel_edges) {
        ms_cancel_deliver(); /* the caller's compiled code leaves on the `unwinding` byte */
    } else {
        ms_cancelled(); /* a program without cancel edges is left by a jump */
    }
    return true;
}

/* ---- the program ABI ---- */

/* A value read but never taken (its promise ended first) goes back to the front of its pipe. */
static void pipe_unread(int64_t pipe, void *block, const MsTypeDesc *desc) {
    const PipeItem item = {.value = {.block = block}, .desc = desc};
    PipeCell *cell = cell_lock(pipe);
    if (cell == NULL || !cell->reader_open) {
        if (cell != NULL) {
            cell_unlock(cell);
        }
        item_free(&item);
        return;
    }
    const bool queued = ring_push_front(&cell->front, item);
    cell_unlock(cell);
    if (!queued) {
        item_free(&item);
    }
}

int64_t msrt_pipe_new(int64_t capacity) {
    static atomic_bool hook_set;
    if (!atomic_exchange(&hook_set, true)) {
        ms_promise_set_unread(pipe_unread);
    }
    const size_t index = registry_take();
    PipeCell *cell = index == SIZE_MAX ? NULL : cell_at(index);
    if (cell == NULL) {
        static const char message[] = "pipe: too many pipes are open at once";
        msrt_fault((const uint8_t *)message, sizeof message - 1);
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
    atomic_store(&cell->gap, GAP_MIN);
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
    ms_promise_io_done_block(reader, item_into_block(item), item_desc(item), pipe);
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
    if (!ring_push_back(&cell->queue, item)) {
        item_free(&item);
        fault_no_memory(cell);
    }
    publish_backlog(cell);
    const MsPromise reader = claim_reader(cell);
    if (reader == 0) {
        const int64_t status = backlog(cell) > cell->capacity ? MS_PIPE_FULL : MS_PIPE_WRITTEN;
        cell_unlock(cell);
        (void)cancellation_point();
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
        static const char message[] = "pipe: a read is already waiting";
        msrt_fault((const uint8_t *)message, sizeof message - 1);
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
        if (atomic_load_explicit(&cell->queue_len, memory_order_relaxed) == 0) {
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
        memcpy(out, &item.value.word, desc->size);
    } else {
        memcpy(out, item.value.block, desc->size);
        msrt_free(item.value.block);
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

/* No other thread can complete a pipe yet (see the file comment), so a reader never spins for a peer: it parks.
 * The look-and-spin of the Rust runtime returns with the multi-thread scheduler. */
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
        if (!flushes_add(cell, id)) {
            fault_no_memory(cell);
        }
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
    size_t count = 0;
    atomic_store(&cell->flush_pending, false);
    MsPromise *flushes = cell->flushes;
    count = cell->flush_count;
    cell->flushes = NULL;
    cell->flush_count = 0;
    cell->flush_cap = 0;
    retire(cell);
    cell_unlock(cell);
    complete_flushes(flushes, count);
}
