/* Cancel switches. See cancel.h. */
#include "cancel.h"

#include <stdatomic.h>
#include <string.h>

#include "array.h"
#include "isolate.h"
#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"
#include "scheduler.h"

#define GENERATION_MASK 0xffffffu
#define ISOLATE_SHIFT 56

/* A switch belongs to the isolate that made it, which keeps its listeners. Every isolate reads and sets its fired
 * flag through the shared state table below; firing, listening, leaving and freeing from another isolate mail the
 * owner, which cancels its listeners (a listener on another isolate is cancelled by mail too). */
typedef struct Switch {
    uint32_t generation;
    bool live;
    bool notified;      /* the listeners were cancelled */
    uint32_t head;      /* row + 1 of the newest listener, 0 when none */
    MsPromise *remote;  /* listeners that belong to other isolates */
    size_t remote_count;
    size_t remote_capacity;
} Switch;

/* The shared state of every switch: `generation << 1 | fired`, 0 for a slot that holds none. The pages are made by the
 * owner and never freed (readers on other isolates may still look), so they are not heap blocks the leak checks count. */
#define PAGE_SLOTS 512u
#define MAX_PAGES 2048u
#define ISOLATE_SLOTS 64u

typedef struct Page {
    _Atomic uint32_t state[PAGE_SLOTS];
} Page;

static _Atomic(Page *) pages[ISOLATE_SLOTS][MAX_PAGES];

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

static uint32_t generation_of(int64_t id) { return (uint32_t)(((uint64_t)id >> 32) & GENERATION_MASK); }

static uint32_t isolate_of(int64_t id) { return (uint32_t)(((uint64_t)id >> ISOLATE_SHIFT) & 0x3fu); }

/* The shared state word of switch `id`, or NULL when its page does not exist. Any isolate may call this. */
static _Atomic uint32_t *state_of(int64_t id) {
    const uint64_t low = (uint64_t)id & 0xffffffffu;
    if (low == 0) {
        return NULL;
    }
    const size_t page = (size_t)((low - 1) / PAGE_SLOTS);
    if (page >= MAX_PAGES) {
        return NULL;
    }
    Page *const found = atomic_load_explicit(&pages[isolate_of(id)][page], memory_order_acquire);
    return found == NULL ? NULL : &found->state[(low - 1) % PAGE_SLOTS];
}

/* Publishes the state of the owner's slot `slot`, making its page first. */
static void publish(size_t slot, uint32_t state) {
    const size_t page = slot / PAGE_SLOTS;
    if (page >= MAX_PAGES) {
        ms_sched()->hooks.fault(MS_FAULT_KIND_FAULT, "cancel: too many switches");
    }
    _Atomic(Page *) *const cell = &pages[own_isolate()][page];
    Page *made = atomic_load_explicit(cell, memory_order_relaxed);
    if (made == NULL) {
        made = ms_sys_realloc(NULL, sizeof *made);
        if (made == NULL) {
            ms_sched()->hooks.fault(MS_FAULT_KIND_FAULT, "cancel: out of memory");
        }
        memset((void *)made, 0, sizeof *made);
        atomic_store_explicit(cell, made, memory_order_release);
    }
    atomic_store_explicit(&made->state[slot % PAGE_SLOTS], state, memory_order_release);
}

/* The owner's switch `id`, or NULL for one that is not the caller's, freed or stale. */
static Switch *find(int64_t id) {
    if (isolate_of(id) != own_isolate()) {
        return NULL;
    }
    const uint64_t low = (uint64_t)id & 0xffffffffu;
    if (low == 0 || low > switches.count) {
        return NULL;
    }
    Switch *const item = &switches.items[low - 1];
    return item->generation == generation_of(id) && item->live ? item : NULL;
}

static uint32_t slot_number(const Switch *item) { return (uint32_t)(item - switches.items) + 1; }

/* ---- mail to the owner ---- */

static void post_switch(uint32_t target, uint64_t sub, int64_t id, MsPromise promise) {
    MsMail *const mail = msrt_alloc(sizeof *mail);
    *mail = (MsMail){.kind = MS_MAIL_PROMISE, .a = MS_MAIL_SWITCH | sub << 8, .b = (uint64_t)id, .c = (uint64_t)promise};
    if (!ms_isolate_post(target, mail)) {
        msrt_free(mail); /* the owner ended: its switches went with it */
    }
}

/* Cancels a promise that belongs to another isolate, without waiting for it. */
static void post_cancel(MsPromise promise) {
    MsMail *const mail = msrt_alloc(sizeof *mail);
    *mail = (MsMail){.kind = MS_MAIL_PROMISE, .a = MS_MAIL_CANCEL_ID, .b = (uint64_t)promise};
    if (!ms_isolate_post((uint32_t)((uint64_t)promise >> ISOLATE_SHIFT), mail)) {
        msrt_free(mail);
    }
}

/* ---- the owner's side ---- */

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
    item->notified = false;
    item->head = 0;
    publish(slot, item->generation << 1);
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

static bool is_fired(int64_t id) {
    _Atomic uint32_t *const state = state_of(id);
    if (state == NULL) {
        return false;
    }
    const uint32_t value = atomic_load_explicit(state, memory_order_acquire);
    return (value >> 1) == generation_of(id) && (value & 1u) != 0;
}

static bool owns_promise(MsPromise promise) { return ((uint64_t)promise >> ISOLATE_SHIFT) == own_isolate(); }

/* Adds `promise` to the listeners of the owner's switch `item`. */
static void add_listener(Switch *item, MsPromise promise) {
    if (!owns_promise(promise)) {
        if (item->remote_count == item->remote_capacity) {
            void *list = item->remote;
            if (!ms_array_reserve(&list, &item->remote_capacity, item->remote_count + 1, sizeof *item->remote)) {
                ms_sched()->hooks.fault(MS_FAULT_KIND_FAULT, "cancel: out of memory");
            }
            item->remote = list;
        }
        item->remote[item->remote_count++] = promise;
        return;
    }
    Listener *const listener = listener_row(promise);
    const uint32_t row = (uint32_t)((uint64_t)promise & 0xffffffffu);
    *listener = (Listener){.promise = promise, .next = item->head, .prev = 0};
    if (item->head != 0) {
        switches.listeners[item->head - 1].prev = row;
    }
    item->head = row;
}

static void remove_listener(Switch *item, MsPromise promise) {
    if (!owns_promise(promise)) {
        for (size_t i = 0; i < item->remote_count; i++) {
            if (item->remote[i] == promise) {
                item->remote[i] = item->remote[--item->remote_count];
                return;
            }
        }
        return;
    }
    Listener *const listener = listener_row(promise);
    if (listener->promise != promise) {
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

/* The owner cancels the listeners of a fired switch, once. */
static void notify(int64_t id) {
    Switch *const item = find(id);
    if (item == NULL || item->notified) {
        return;
    }
    item->notified = true;
    /* Detach every listener first: cancelling one may end promises and change the arrays. */
    MsPromise *firing = NULL;
    size_t count = 0;
    size_t capacity = 0;
    void *list = NULL;
    for (uint32_t row = item->head; row != 0;) {
        list = firing;
        if (!ms_array_reserve(&list, &capacity, count + 1, sizeof *firing)) {
            break;
        }
        firing = list;
        firing[count++] = switches.listeners[row - 1].promise;
        const uint32_t next = switches.listeners[row - 1].next;
        switches.listeners[row - 1] = (Listener){0};
        row = next;
    }
    item->head = 0;
    for (size_t i = 0; i < item->remote_count; i++) {
        post_cancel(item->remote[i]);
    }
    item->remote_count = 0;
    for (size_t i = 0; i < count; i++) {
        ms_promise_cancel(firing[i]);
    }
    msrt_free(firing);
}

static void release(int64_t id) {
    Switch *const item = find(id);
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
    item->remote_count = 0;
    item->live = false;
    if (is_fired(id)) {
        return; /* stays readable as fired until its generation is reused: the slot is not recycled */
    }
    _Atomic uint32_t *const state = state_of(id);
    if (state != NULL) {
        atomic_store_explicit(state, 0, memory_order_release); /* a freed switch that never fired reads as not fired */
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

/* ---- any isolate ---- */

bool ms_cancel_register(int64_t id, MsPromise promise) {
    if (isolate_of(id) != own_isolate()) {
        if (is_fired(id)) {
            return true;
        }
        post_switch(isolate_of(id), SWITCH_REGISTER, id, promise);
        return false;
    }
    Switch *const item = find(id);
    if (item == NULL) {
        return is_fired(id);
    }
    if (is_fired(id)) {
        return true;
    }
    add_listener(item, promise);
    return false;
}

void ms_cancel_unregister(int64_t id, MsPromise promise) {
    if (isolate_of(id) != own_isolate()) {
        post_switch(isolate_of(id), SWITCH_UNREGISTER, id, promise);
        return;
    }
    Switch *const item = find(id);
    if (item != NULL) {
        remove_listener(item, promise);
    }
}

void ms_cancel_fire(int64_t id) {
    _Atomic uint32_t *const state = state_of(id);
    if (state == NULL) {
        return;
    }
    uint32_t value = atomic_load_explicit(state, memory_order_acquire);
    do {
        if ((value >> 1) != generation_of(id) || (value & 1u) != 0) {
            return; /* stale, freed or already fired */
        }
    } while (!atomic_compare_exchange_weak_explicit(state, &value, value | 1u, memory_order_acq_rel, memory_order_acquire));
    if (isolate_of(id) == own_isolate()) {
        notify(id);
    } else {
        post_switch(isolate_of(id), SWITCH_FIRE, id, 0);
    }
}

bool ms_cancel_fired(int64_t id) { return is_fired(id); }

void ms_cancel_free(int64_t id) {
    if (isolate_of(id) != own_isolate()) {
        post_switch(isolate_of(id), SWITCH_FREE, id, 0);
        return;
    }
    release(id);
}

void ms_cancel_serve(MsMail *mail) {
    const int64_t id = (int64_t)mail->b;
    const MsPromise promise = (MsPromise)mail->c;
    switch ((mail->a >> 8) & 0xffu) {
    case SWITCH_FIRE:
        notify(id);
        break;
    case SWITCH_REGISTER:
        if (is_fired(id)) {
            if (owns_promise(promise)) {
                ms_promise_cancel(promise);
            } else {
                post_cancel(promise);
            }
        } else {
            Switch *const item = find(id);
            if (item != NULL) {
                add_listener(item, promise);
            }
        }
        break;
    case SWITCH_UNREGISTER: {
        Switch *const item = find(id);
        if (item != NULL) {
            remove_listener(item, promise);
        }
        break;
    }
    case SWITCH_FREE:
        release(id);
        break;
    default:
        break;
    }
    msrt_free(mail);
}

void ms_cancel_teardown(void) {
    for (size_t page = 0; page < MAX_PAGES; page++) {
        Page *const found = atomic_load_explicit(&pages[own_isolate()][page], memory_order_relaxed);
        if (found == NULL) {
            break;
        }
        memset((void *)found, 0, sizeof *found); /* a stale id of this isolate reads as not fired */
    }
    for (size_t i = 0; i < switches.count; i++) {
        msrt_free(switches.items[i].remote);
    }
    msrt_free(switches.items);
    msrt_free(switches.free_slots);
    msrt_free(switches.listeners);
    switches = (Switches){0};
}
