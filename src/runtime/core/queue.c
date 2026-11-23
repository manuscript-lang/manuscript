/* The per-isolate unstarted-work queues. See queue.h. */
#include "runtime/core/queue.h"

#include <stdatomic.h>

#include "abi/layout.h"
#include "base/alloc.h"
#include "runtime/sys/spin.h"

typedef struct Entry {
  uint64_t id; /* 0: removed from the middle, skipped */
  int64_t at;
  void *work;
} Entry;

/* A ring of entries, `head` the oldest. Every field but `live` is guarded by `lock`. */
typedef struct Queue {
  MsSpin lock;
  Entry *items;
  size_t capacity;
  size_t head;
  size_t length;       /* slots in use, removed ones included */
  uint64_t head_sequence; /* the sequence number of the entry at `head`: entry `sequence` is at `sequence - head_sequence` */
  _Atomic size_t live; /* entries still wanting to run; thieves read it without the lock to skip an empty queue */
} Queue;

static Queue queues[MS_MAX_ISOLATES];

static Queue *queue_of(uint32_t isolate) { return isolate < MS_MAX_ISOLATES ? &queues[isolate] : NULL; }

static size_t slot(const Queue *queue, size_t index) { return (queue->head + index) % queue->capacity; }

/* Drops removed entries at both ends. */
static void trim(Queue *queue) {
  while (queue->length > 0 && queue->items[queue->head].id == 0) {
    queue->head = (queue->head + 1) % queue->capacity;
    queue->length--;
    queue->head_sequence++;
  }
  while (queue->length > 0 && queue->items[slot(queue, queue->length - 1)].id == 0) {
    queue->length--;
  }
}

static void grow(Queue *queue) {
  const size_t capacity = queue->capacity == 0 ? 16 : queue->capacity * 2;
  Entry *const items = ms_alloc(capacity * sizeof *items);
  for (size_t i = 0; i < queue->length; i++) {
    items[i] = queue->items[slot(queue, i)];
  }
  ms_free(queue->items);
  queue->items = items;
  queue->capacity = capacity;
  queue->head = 0;
}

bool ms_queue_push(uint32_t isolate, uint64_t id, void *work, int64_t now_ns, uint64_t *sequence) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL || id == 0) {
    return false;
  }
  ms_spin_lock(&queue->lock);
  if (queue->length == queue->capacity) {
    grow(queue);
  }
  queue->items[slot(queue, queue->length)] = (Entry){id, now_ns, work};
  *sequence = queue->head_sequence + queue->length;
  queue->length++;
  atomic_fetch_add(&queue->live, 1); /* ordered against a looker's last look (ms_workers_nudge) */
  ms_spin_unlock(&queue->lock);
  return true;
}

bool ms_queue_remove(uint32_t isolate, uint64_t id, uint64_t sequence) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL) {
    return false;
  }
  bool found = false;
  ms_spin_lock(&queue->lock);
  const uint64_t offset = sequence - queue->head_sequence; /* wraps to a huge value for an entry already trimmed */
  if (offset < queue->length) {
    Entry *const entry = &queue->items[slot(queue, (size_t)offset)];
    if (entry->id == id) {
      entry->id = 0;
      atomic_fetch_sub_explicit(&queue->live, 1, memory_order_relaxed);
      found = true;
      trim(queue);
    }
  }
  ms_spin_unlock(&queue->lock);
  return found;
}

bool ms_queue_steal(uint32_t isolate, int64_t not_after_ns, uint64_t *id, void **work) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL || atomic_load_explicit(&queue->live, memory_order_relaxed) == 0) {
    return false; /* a stale read only delays a steal */
  }
  bool taken = false;
  ms_spin_lock(&queue->lock);
  trim(queue);
  if (queue->length > 0 && queue->items[queue->head].at <= not_after_ns) {
    Entry *const oldest = &queue->items[queue->head];
    *id = oldest->id;
    *work = oldest->work;
    oldest->id = 0;
    atomic_fetch_sub_explicit(&queue->live, 1, memory_order_relaxed);
    trim(queue);
    taken = true;
  }
  ms_spin_unlock(&queue->lock);
  return taken;
}

size_t ms_queue_length(uint32_t isolate) {
  const Queue *const queue = queue_of(isolate);
  return queue == NULL ? 0 : atomic_load(&queue->live);
}

int64_t ms_queue_oldest(uint32_t isolate) {
  Queue *const queue = queue_of(isolate);
  if (queue == NULL) {
    return INT64_MAX;
  }
  ms_spin_lock(&queue->lock);
  trim(queue);
  const int64_t oldest = queue->length > 0 ? queue->items[queue->head].at : INT64_MAX;
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
    if (entry->id != 0) {
      drop(entry->work);
    }
  }
  ms_free(queue->items);
  queue->items = NULL;
  queue->capacity = 0;
  queue->head = 0;
  queue->head_sequence += queue->length;
  queue->length = 0;
  atomic_store_explicit(&queue->live, 0, memory_order_relaxed);
  ms_spin_unlock(&queue->lock);
}
