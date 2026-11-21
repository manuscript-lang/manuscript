/* The per-isolate unstarted-work queues. See queue.h. */
#include "queue.h"

#include <stdatomic.h>

#include "isolate.h"
#include "ms_rt/alloc.h"

typedef struct Entry {
    uint64_t id; /* 0: removed from the middle, skipped */
    int64_t at;
    void *work;
} Entry;

/* A ring of entries, `head` the oldest. Every field is guarded by `lock`. */
typedef struct Queue {
    atomic_flag lock;
    Entry *items;
    size_t capacity;
    size_t head;
    size_t length; /* slots in use, removed ones included */
    _Atomic size_t live; /* entries still wanting to run; thieves read it without the lock to skip an empty queue */
} Queue;

static Queue queues[MS_MAX_ISOLATES];

static void lock(Queue *queue) {
    while (atomic_flag_test_and_set_explicit(&queue->lock, memory_order_acquire)) {
        /* the critical sections are a few instructions: spin */
    }
}

static void unlock(Queue *queue) { atomic_flag_clear_explicit(&queue->lock, memory_order_release); }

static Queue *queue_of(uint32_t isolate) { return isolate < MS_MAX_ISOLATES ? &queues[isolate] : NULL; }

static size_t slot(const Queue *queue, size_t index) { return (queue->head + index) % queue->capacity; }

/* Drops removed entries at both ends. */
static void trim(Queue *queue) {
    while (queue->length > 0 && queue->items[queue->head].id == 0) {
        queue->head = (queue->head + 1) % queue->capacity;
        queue->length--;
    }
    while (queue->length > 0 && queue->items[slot(queue, queue->length - 1)].id == 0) {
        queue->length--;
    }
}

static bool grow(Queue *queue) {
    const size_t capacity = queue->capacity == 0 ? 16 : queue->capacity * 2;
    Entry *const items = msrt_alloc(capacity * sizeof *items);
    if (items == NULL) {
        return false;
    }
    for (size_t i = 0; i < queue->length; i++) {
        items[i] = queue->items[slot(queue, i)];
    }
    msrt_free(queue->items);
    queue->items = items;
    queue->capacity = capacity;
    queue->head = 0;
    return true;
}

bool ms_queue_push(uint32_t isolate, uint64_t id, void *work, int64_t now_ns) {
    Queue *const queue = queue_of(isolate);
    if (queue == NULL || id == 0) {
        return false;
    }
    lock(queue);
    if (queue->length == queue->capacity && !grow(queue)) {
        unlock(queue);
        return false;
    }
    queue->items[slot(queue, queue->length)] = (Entry){id, now_ns, work};
    queue->length++;
    atomic_fetch_add_explicit(&queue->live, 1, memory_order_relaxed);
    unlock(queue);
    return true;
}

bool ms_queue_remove(uint32_t isolate, uint64_t id) {
    Queue *const queue = queue_of(isolate);
    if (queue == NULL) {
        return false;
    }
    bool found = false;
    lock(queue);
    /* Waiters mostly want the newest promise: search from that end. */
    for (size_t i = queue->length; i > 0 && !found; i--) {
        Entry *const entry = &queue->items[slot(queue, i - 1)];
        if (entry->id == id) {
            entry->id = 0;
            atomic_fetch_sub_explicit(&queue->live, 1, memory_order_relaxed);
            found = true;
        }
    }
    if (found) {
        trim(queue);
    }
    unlock(queue);
    return found;
}

bool ms_queue_steal(uint32_t isolate, int64_t not_after_ns, uint64_t *id, void **work) {
    Queue *const queue = queue_of(isolate);
    if (queue == NULL) {
        return false;
    }
    bool taken = false;
    if (atomic_load_explicit(&queue->live, memory_order_relaxed) == 0) { /* a stale read only delays a steal */
        return false;
    }
    lock(queue);
    trim(queue);
    if (queue->length > 0 && queue->items[queue->head].at <= not_after_ns) {
        *id = queue->items[queue->head].id;
        *work = queue->items[queue->head].work;
        queue->items[queue->head].id = 0;
        atomic_fetch_sub_explicit(&queue->live, 1, memory_order_relaxed);
        trim(queue);
        taken = true;
    }
    unlock(queue);
    return taken;
}

size_t ms_queue_length(uint32_t isolate) {
    Queue *const queue = queue_of(isolate);
    if (queue == NULL) {
        return 0;
    }
    lock(queue);
    const size_t live = atomic_load_explicit(&queue->live, memory_order_relaxed);
    unlock(queue);
    return live;
}

int64_t ms_queue_oldest(uint32_t isolate) {
    Queue *const queue = queue_of(isolate);
    int64_t oldest = INT64_MAX;
    if (queue == NULL) {
        return oldest;
    }
    lock(queue);
    trim(queue);
    if (queue->length > 0) {
        oldest = queue->items[queue->head].at;
    }
    unlock(queue);
    return oldest;
}

void ms_queue_release(uint32_t isolate, void (*drop)(void *work)) {
    Queue *const queue = queue_of(isolate);
    if (queue == NULL) {
        return;
    }
    lock(queue);
    for (size_t i = 0; drop != NULL && i < queue->length; i++) {
        const Entry *const entry = &queue->items[(queue->head + i) % queue->capacity];
        if (entry->id != 0) {
            drop(entry->work);
        }
    }
    msrt_free(queue->items);
    queue->items = NULL;
    queue->capacity = 0;
    queue->head = 0;
    queue->length = 0;
    atomic_store_explicit(&queue->live, 0, memory_order_relaxed);
    unlock(queue);
}
