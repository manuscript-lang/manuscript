/* The per-isolate unstarted-work queues. See queue.h. */
#include "runtime/core/queue.h"

#include <stdatomic.h>

#include "abi/layout.h"
#include "base/alloc.h"
#include "runtime/sys/spin.h"

typedef struct Entry {
  _Atomic uint64_t id; /* 0: taken or removed, skipped. The owner removes with one compare-and-swap, without the lock */
  int64_t at;  /* when a looker first saw it; NOT_SEEN until one has */
  void *work;
} Entry;

static const int64_t NOT_SEEN = 0;
static const int64_t AGED = INT64_MIN; /* older than any beat */

/* A ring of entries indexed by sequence number: entry `sequence` sits at `sequence & (capacity - 1)`, and the
 * slots in use are `head` up to `tail`.
 *
 * The owner pushes without the lock: it writes the slot at `tail` and then publishes it by storing `tail`, which only
 * it writes. `head` moves only under `lock`, past entries that were taken or removed, so a slot is not written again
 * while a looker can reach it. The owner takes the lock only when the ring looks full, to move `head` itself or to
 * replace the ring. Only the owner changes `items` and `capacity` (under the lock), so it reads them without it. */
typedef struct Queue {
  MsSpin lock;
  Entry *items;
  size_t capacity;
  _Atomic uint64_t head; /* the oldest slot in use */
  _Atomic uint64_t tail; /* one past the newest */
} Queue;

static Queue queues[MS_MAX_ISOLATES];

static Queue *queue_of(uint32_t isolate) { return isolate < MS_MAX_ISOLATES ? &queues[isolate] : NULL; }

/* The capacity is a power of two (16, doubled), so a position wraps with a mask, not a division. */
static Entry *entry_at(const Queue *queue, uint64_t sequence) {
  return &queue->items[(size_t)sequence & (queue->capacity - 1)];
}

static uint64_t id_of(const Entry *entry) { return atomic_load_explicit(&entry->id, memory_order_relaxed); }
static uint64_t head_of(const Queue *queue) { return atomic_load_explicit(&queue->head, memory_order_relaxed); }
static uint64_t tail_of(const Queue *queue) { return atomic_load_explicit(&queue->tail, memory_order_acquire); }

/* Moves `head` past the entries that were taken or removed. Under the lock. Answers the new head. */
static uint64_t trim(Queue *queue, uint64_t tail) {
  uint64_t head = head_of(queue);
  while (head < tail && id_of(entry_at(queue, head)) == 0) {
    head++;
  }
  atomic_store_explicit(&queue->head, head, memory_order_relaxed);
  return head;
}

/* The owner found the ring full: under the lock, drops what was removed and doubles the ring if that freed nothing. */
static void make_room(Queue *queue, uint64_t tail) {
  ms_spin_lock(&queue->lock);
  const uint64_t head = trim(queue, tail);
  if (tail - head == queue->capacity) {
    const size_t capacity = queue->capacity == 0 ? 16 : queue->capacity * 2;
    Entry *const items = ms_alloc(capacity * sizeof *items);
    /* A slot nothing was copied to must read as empty: an owner removing an entry that a thief took earlier looks at its
     * old slot, and stale bytes of a freed ring there would hold the id of that very entry. */
    for (size_t at = 0; at < capacity; at++) {
      atomic_init(&items[at].id, 0);
    }
    for (uint64_t at = head; at < tail; at++) {
      const Entry *const from = entry_at(queue, at);
      Entry *const to = &items[(size_t)at & (capacity - 1)];
      atomic_init(&to->id, id_of(from));
      to->at = from->at;
      to->work = from->work;
    }
    ms_free(queue->items);
    queue->items = items;
    queue->capacity = capacity;
  }
  ms_spin_unlock(&queue->lock);
}

/* Dates the entries no looker has seen with `now_ns`. They are the newest ones, since every look dates all it finds,
 * so this stops at the first dated entry. */
static void date_unseen(Queue *queue, uint64_t head, uint64_t tail, int64_t now_ns) {
  for (uint64_t at = tail; at > head; at--) {
    Entry *const entry = entry_at(queue, at - 1);
    if (entry->at != NOT_SEEN) {
      return;
    }
    entry->at = now_ns;
  }
}

MS_ALWAYS_INLINE bool ms_queue_push(uint32_t isolate, uint64_t id, void *work, bool aged, uint64_t *sequence) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL || id == 0) {
    return false;
  }
  const uint64_t tail = atomic_load_explicit(&queue->tail, memory_order_relaxed);
  if (tail - head_of(queue) >= queue->capacity) { /* a stale head only sends the owner to the lock early */
    make_room(queue, tail);
  }
  Entry *const entry = entry_at(queue, tail);
  entry->at = aged ? AGED : NOT_SEEN;
  entry->work = work;
  atomic_store_explicit(&entry->id, id, memory_order_relaxed);
  *sequence = tail;
  atomic_store(&queue->tail, tail + 1); /* publishes the slot; ordered against a looker's last look (ms_workers_nudge) */
  return true;
}

MS_ALWAYS_INLINE bool ms_queue_remove(uint32_t isolate, uint64_t id, uint64_t sequence) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL || queue->capacity == 0) {
    return false;
  }
  /* The owner's own entry: its slot holds `id` until a thief takes it, and no other entry can hold `id` there (a
   * later push to the slot carries another promise's id). One compare-and-swap decides between owner and thief. */
  uint64_t expected = id;
  return atomic_compare_exchange_strong_explicit(&entry_at(queue, sequence)->id, &expected, 0, memory_order_acq_rel,
                                                 memory_order_relaxed);
}

bool ms_queue_steal(uint32_t isolate, int64_t now_ns, int64_t beat_ns, uint64_t *id, void **work) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL || ms_queue_length(isolate) == 0) {
    return false; /* a stale read only delays a steal */
  }
  bool taken = false;
  ms_spin_lock(&queue->lock);
  const uint64_t tail = tail_of(queue);
  uint64_t head = trim(queue, tail);
  if (beat_ns >= 0) {
    date_unseen(queue, head, tail, now_ns);
  }
  while (!taken && head < tail && (beat_ns < 0 || entry_at(queue, head)->at <= now_ns - beat_ns)) {
    Entry *const oldest = entry_at(queue, head);
    uint64_t found = id_of(oldest);
    taken = found != 0 && atomic_compare_exchange_strong_explicit(&oldest->id, &found, 0, memory_order_acq_rel,
                                                                  memory_order_relaxed);
    if (taken) {
      /* The slot is not written again before `head` passes it, which needs this lock. */
      *id = found;
      *work = oldest->work;
    }
    head = trim(queue, tail); /* the entry is gone either way: taken here, or removed by its owner a moment ago */
  }
  ms_spin_unlock(&queue->lock);
  return taken;
}

size_t ms_queue_length(uint32_t isolate) {
  const Queue *const queue = queue_of(isolate);
  if (queue == NULL) {
    return 0;
  }
  const uint64_t tail = atomic_load(&queue->tail);
  const uint64_t head = head_of(queue);
  return tail > head ? (size_t)(tail - head) : 0;
}

int64_t ms_queue_oldest(uint32_t isolate, int64_t now_ns) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL) {
    return INT64_MAX;
  }
  ms_spin_lock(&queue->lock);
  const uint64_t tail = tail_of(queue);
  const uint64_t head = trim(queue, tail);
  date_unseen(queue, head, tail, now_ns);
  const int64_t oldest = head < tail ? entry_at(queue, head)->at : INT64_MAX;
  ms_spin_unlock(&queue->lock);
  return oldest;
}

void ms_queue_release(uint32_t isolate, void (*drop)(void *work)) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL) {
    return;
  }
  ms_spin_lock(&queue->lock);
  const uint64_t tail = tail_of(queue);
  for (uint64_t at = head_of(queue); drop != NULL && at < tail; at++) {
    const Entry *const entry = entry_at(queue, at);
    if (id_of(entry) != 0) {
      drop(entry->work);
    }
  }
  ms_free(queue->items);
  queue->items = NULL;
  queue->capacity = 0;
  atomic_store_explicit(&queue->head, tail, memory_order_relaxed);
  ms_spin_unlock(&queue->lock);
}
