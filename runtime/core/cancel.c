/* Cancel switches. See cancel.h. */
#include "cancel.h"

#include "array.h"
#include "ms_rt/alloc.h"
#include "scheduler.h"

#define GENERATION_MASK 0xffffffu
#define ISOLATE_SHIFT 56

typedef struct Switch {
    uint32_t generation;
    bool live;
    bool fired;
    uint32_t head; /* row + 1 of the newest listener, 0 when none */
} Switch;

/* Per promise row: the switch the promise listens to and its place in that switch's list. */
typedef struct Listener {
    MsPromise promise; /* the listening promise, 0 when the row listens to nothing */
    uint32_t next;     /* row + 1 */
    uint32_t prev;
} Listener;

typedef struct Switches {
    Switch *items;
    size_t count;
    size_t capacity;
    uint32_t *free_slots;
    size_t free_count;
    size_t free_capacity;
    Listener *listeners;
    size_t listener_rows;
    size_t listener_capacity;
} Switches;

static _Thread_local Switches switches; /* per-thread state, like the scheduler's */

static uint64_t own_isolate(void) { return (uint64_t)(ms_sched()->isolate & 0x3fu); }

static Switch *find(int64_t id, bool include_fired) {
    if (((uint64_t)id >> ISOLATE_SHIFT) != own_isolate()) {
        return NULL;
    }
    const uint64_t low = (uint64_t)id & 0xffffffffu;
    if (low == 0 || low > switches.count) {
        return NULL;
    }
    Switch *const item = &switches.items[low - 1];
    if (item->generation != (((uint64_t)id >> 32) & GENERATION_MASK)) {
        return NULL;
    }
    return item->live || (include_fired && item->fired) ? item : NULL;
}

static uint32_t slot_number(const Switch *item) { return (uint32_t)(item - switches.items) + 1; }

int64_t ms_cancel_new(void) {
    size_t slot = 0;
    if (switches.free_count != 0) {
        slot = switches.free_slots[--switches.free_count];
    } else {
        void *items = switches.items;
        if (!ms_array_reserve(&items, &switches.capacity, switches.count + 1, sizeof *switches.items)) {
            ms_sched()->hooks.fault(MS_FAULT_KIND_FAULT, "cancel: out of memory");
        }
        switches.items = items;
        slot = switches.count++;
        switches.items[slot] = (Switch){0};
    }
    Switch *const item = &switches.items[slot];
    item->generation = (item->generation + 1) & GENERATION_MASK;
    if (item->generation == 0) {
        item->generation = 1;
    }
    item->live = true;
    item->fired = false;
    item->head = 0;
    return (int64_t)(own_isolate() << ISOLATE_SHIFT | (uint64_t)item->generation << 32 | (uint64_t)(slot + 1));
}

static Listener *listener_row(MsPromise promise) {
    const size_t row = (size_t)((uint64_t)promise & 0xffffffffu) - 1;
    if (row >= switches.listener_rows) {
        void *rows = switches.listeners;
        const size_t before = switches.listener_capacity;
        if (!ms_array_reserve(&rows, &switches.listener_capacity, row + 1, sizeof *switches.listeners)) {
            ms_sched()->hooks.fault(MS_FAULT_KIND_FAULT, "cancel: out of memory");
        }
        switches.listeners = rows;
        for (size_t i = before; i < switches.listener_capacity; i++) {
            switches.listeners[i] = (Listener){0};
        }
        switches.listener_rows = row + 1;
    }
    return &switches.listeners[row];
}

bool ms_cancel_register(int64_t id, MsPromise promise) {
    Switch *const item = find(id, true);
    if (item == NULL) {
        return false;
    }
    if (item->fired) {
        return true;
    }
    Listener *const listener = listener_row(promise);
    const uint32_t row = (uint32_t)((uint64_t)promise & 0xffffffffu);
    *listener = (Listener){.promise = promise, .next = item->head, .prev = 0};
    if (item->head != 0) {
        switches.listeners[item->head - 1].prev = row;
    }
    item->head = row;
    return false;
}

void ms_cancel_unregister(int64_t id, MsPromise promise) {
    Switch *const item = find(id, false);
    Listener *const listener = listener_row(promise);
    if (item == NULL || listener->promise != promise) {
        return;
    }
    if (listener->prev != 0) {
        switches.listeners[listener->prev - 1].next = listener->next;
    } else {
        item->head = listener->next;
    }
    if (listener->next != 0) {
        switches.listeners[listener->next - 1].prev = listener->prev;
    }
    *listener = (Listener){0};
}

void ms_cancel_fire(int64_t id) {
    Switch *item = find(id, false);
    if (item == NULL || item->fired) {
        return;
    }
    item->fired = true;
    uint32_t row = item->head;
    item->head = 0;
    /* Detach every listener first: cancelling one may end promises and change the arrays. */
    MsPromise *firing = NULL;
    size_t count = 0;
    size_t capacity = 0;
    for (; row != 0; row = switches.listeners[row - 1].next) {
        void *list = firing;
        if (!ms_array_reserve(&list, &capacity, count + 1, sizeof *firing)) {
            break;
        }
        firing = list;
        firing[count++] = switches.listeners[row - 1].promise;
        switches.listeners[row - 1] = (Listener){.next = switches.listeners[row - 1].next};
    }
    for (size_t i = 0; i < count; i++) {
        ms_promise_cancel(firing[i]);
    }
    msrt_free(firing);
}

bool ms_cancel_fired(int64_t id) {
    const Switch *const item = find(id, true);
    return item != NULL && item->fired;
}

void ms_cancel_free(int64_t id) {
    Switch *const item = find(id, false);
    if (item == NULL) {
        return;
    }
    for (uint32_t row = item->head; row != 0;) {
        Listener *const listener = &switches.listeners[row - 1];
        const uint32_t next = listener->next;
        *listener = (Listener){0};
        row = next;
    }
    item->head = 0;
    item->live = false;
    if (item->fired) {
        return; /* stays readable as fired until its generation is reused: the slot is not recycled */
    }
    if (switches.free_count == switches.free_capacity) {
        void *slots = switches.free_slots;
        if (!ms_array_reserve(&slots, &switches.free_capacity, switches.free_count + 1, sizeof *switches.free_slots)) {
            return;
        }
        switches.free_slots = slots;
    }
    switches.free_slots[switches.free_count++] = slot_number(item) - 1;
}

void ms_cancel_teardown(void) {
    msrt_free(switches.items);
    msrt_free(switches.free_slots);
    msrt_free(switches.listeners);
    switches = (Switches){0};
}
