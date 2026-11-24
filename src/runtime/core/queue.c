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
 * entries in use are `head_sequence` up to `head_sequence + length`. `lock` guards every field but `live` and an
 * entry's `id`. Only the owner pushes, so only the owner changes `items` and `capacity`, and it may read them
 * without the lock. */
typedef struct Queue {
  MsSpin lock;
  Entry *items;
  size_t capacity;
  size_t length;          /* slots in use, removed ones included */
  uint64_t head_sequence; /* the sequence number of the oldest slot in use */
  /* At least the entries still wanting to run (a removal by the owner is counted off at the next push or look);
   * thieves read it without the lock to skip an empty queue. */
  _Atomic size_t live;
} Queue;

static Queue queues[MS_MAX_ISOLATES];

static Queue *queue_of(uint32_t isolate) { return isolate < MS_MAX_ISOLATES ? &queues[isolate] : NULL; }

/* The capacity is a power of two (16, doubled), so a position wraps with a mask, not a division. */
static size_t slot(const Queue *queue, size_t index) {
  return (size_t)(queue->head_sequence + index) & (queue->capacity - 1);
}

static uint64_t id_of(const Entry *entry) { return atomic_load_explicit(&entry->id, memory_order_relaxed); }

/* Drops removed entries at both ends. */
static void trim(Queue *queue) {
  while (queue->length > 0 && id_of(&queue->items[slot(queue, 0)]) == 0) {
    queue->length--;
    queue->head_sequence++;
  }
  while (queue->length > 0 && id_of(&queue->items[slot(queue, queue->length - 1)]) == 0) {
    queue->length--;
  }
}

static void grow(Queue *queue) {
  const size_t capacity = queue->capacity == 0 ? 16 : queue->capacity * 2;
  Entry *const items = ms_alloc(capacity * sizeof *items);
  for (size_t i = 0; i < queue->length; i++) {
    const Entry *const from = &queue->items[slot(queue, i)];
    Entry *const to = &items[(size_t)(queue->head_sequence + i) & (capacity - 1)];
    atomic_init(&to->id, id_of(from));
    to->at = from->at;
    to->work = from->work;
  }
  ms_free(queue->items);
  queue->items = items;
  queue->capacity = capacity;
}

/* Dates the entries no looker has seen with `now_ns`. They are the newest ones, since every look dates all it finds,
 * so this stops at the first dated entry. */
static void date_unseen(Queue *queue, int64_t now_ns) {
  for (size_t index = queue->length; index > 0; index--) {
    Entry *const entry = &queue->items[slot(queue, index - 1)];
    if (entry->at != NOT_SEEN) {
      return;
    }
    entry->at = now_ns;
  }
}

bool ms_queue_push(uint32_t isolate, uint64_t id, void *work, bool aged, uint64_t *sequence) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL || id == 0) {
    return false;
  }
  ms_spin_lock(&queue->lock);
  trim(queue); /* what the owner removed since its last push */
  if (queue->length == queue->capacity) {
    grow(queue);
  }
  Entry *const entry = &queue->items[slot(queue, queue->length)];
  entry->at = aged ? AGED : NOT_SEEN;
  entry->work = work;
  atomic_store_explicit(&entry->id, id, memory_order_relaxed);
  *sequence = queue->head_sequence + queue->length;
  queue->length++;
  atomic_store(&queue->live, queue->length); /* ordered against a looker's last look (ms_workers_nudge) */
  ms_spin_unlock(&queue->lock);
  return true;
}

bool ms_queue_remove(uint32_t isolate, uint64_t id, uint64_t sequence) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL || queue->capacity == 0) {
    return false;
  }
  /* The owner's own entry: its slot holds `id` until a thief takes it, and no other entry can hold `id` there (a
   * later push to the slot carries another promise's id). One compare-and-swap decides between owner and thief. */
  uint64_t expected = id;
  return atomic_compare_exchange_strong_explicit(&queue->items[(size_t)sequence & (queue->capacity - 1)].id, &expected, 0,
                                                 memory_order_acq_rel, memory_order_relaxed);
}

bool ms_queue_steal(uint32_t isolate, int64_t now_ns, int64_t beat_ns, uint64_t *id, void **work) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL || atomic_load_explicit(&queue->live, memory_order_relaxed) == 0) {
    return false; /* a stale read only delays a steal */
  }
  bool taken = false;
  ms_spin_lock(&queue->lock);
  trim(queue);
  if (beat_ns >= 0) {
    date_unseen(queue, now_ns);
  }
  while (queue->length > 0 && (beat_ns < 0 || queue->items[slot(queue, 0)].at <= now_ns - beat_ns)) {
    Entry *const oldest = &queue->items[slot(queue, 0)];
    uint64_t found = id_of(oldest);
    taken = found != 0 && atomic_compare_exchange_strong_explicit(&oldest->id, &found, 0, memory_order_acq_rel,
                                                                  memory_order_relaxed);
    if (taken) {
      *id = found;
      *work = oldest->work;
    }
    trim(queue); /* the entry is gone either way: taken here, or removed by its owner a moment ago */
    if (taken) {
      break;
    }
  }
  atomic_store_explicit(&queue->live, queue->length, memory_order_relaxed);
  ms_spin_unlock(&queue->lock);
  return taken;
}

size_t ms_queue_length(uint32_t isolate) {
  const Queue *const queue = queue_of(isolate);
  return queue == NULL ? 0 : atomic_load(&queue->live);
}

int64_t ms_queue_oldest(uint32_t isolate, int64_t now_ns) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL) {
    return INT64_MAX;
  }
  ms_spin_lock(&queue->lock);
  trim(queue);
  date_unseen(queue, now_ns);
  const int64_t oldest = queue->length > 0 ? queue->items[slot(queue, 0)].at : INT64_MAX;
  atomic_store_explicit(&queue->live, queue->length, memory_order_relaxed);
  ms_spin_unlock(&queue->lock);
  return oldest;
}

void ms_queue_release(uint32_t isolate, void (*drop)(void *work)) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL) {
    return;
  }
  ms_spin_lock(&queue->lock);
  for (size_t i = 0; drop != NULL && i < queue->length; i++) {
    const Entry *const entry = &queue->items[slot(queue, i)];
    if (id_of(entry) != 0) {
      drop(entry->work);
    }
  }
  ms_free(queue->items);
  queue->items = NULL;
  queue->capacity = 0;
  queue->head_sequence += queue->length;
  queue->length = 0;
  atomic_store_explicit(&queue->live, 0, memory_order_relaxed);
  ms_spin_unlock(&queue->lock);
}
