/* The idle connection pool. See idle.h.
 *
 * A row is one connection between requests. It is on one global list, guarded by a spin lock, with the thread (isolate)
 * that watches it. The watching is a registration (`Reg`): a task-free promise of that thread waiting for the
 * descriptor, whose callback `on_event` is the only code that serves, times out or closes a row. A row moved to another
 * thread (`take`) gets a new registration with a bumped `epoch`; the old registration finds its epoch stale when it
 * runs and only releases its own descriptor. The row's `state` moves from IDLE with a compare-and-swap, so exactly one of
 * a ready event, a timeout, a drain and a take decides it.
 */
#include "idle.h"

#include <stdatomic.h>
#include <string.h>

#include "isolate.h"
#include "ms_rt/alloc.h"
#include "ms_rt/array.h"
#include "ms_rt/desc.h"
#include "ms_rt/sys.h"
#include "promise.h"
#include "task.h"
#include "watch.h"

enum { IDLE = 0, RUNNING = 1, CLOSED = 2 };
enum { OP_TAKE = 1, OP_CLOSE = 3, OP_CANCEL = 4 };
enum { TAKE_BATCH = 64 };

typedef struct IdleGroup {
    atomic_size_t inflight;
} IdleGroup;

typedef struct IdleRow {
    struct IdleRow *prev, *next;
    atomic_uint refs;    /* the list, each registration, each mail in flight */
    atomic_uint state;
    atomic_bool closing; /* a drain asked for this row to end */
    /* Guarded by the list lock: */
    uint32_t owner;      /* the isolate whose reactor watches the row */
    uint32_t epoch;      /* bumped each time the row moves */
    int fd;              /* the connection's current descriptor */
    MsPromise watching;  /* the owner's registration promise, 0 until it exists */
    bool listed;
    /* Fixed after parking: */
    int64_t deadline_ns; /* on ms_sched_now's clock, or MS_NO_DEADLINE */
    IdleGroup *group;
    const MsIdleOps *ops;
    void *subject;       /* the connection handle, owned by the row until it starts or closes */
    MsObj *next_request; /* the closure to start, owned likewise */
} IdleRow;

/* One thread's registration of a row. Freed by on_event, which runs exactly once for it. */
typedef struct Reg {
    IdleRow *row;
    uint32_t epoch;
    int fd;
    MsPromise promise;
} Reg;

static atomic_flag list_lock = ATOMIC_FLAG_INIT;
static IdleRow *list_head;
static _Atomic uint32_t counts[MS_MAX_ISOLATES];
static atomic_bool hook_added;

static void lock(void) {
    while (atomic_flag_test_and_set_explicit(&list_lock, memory_order_acquire)) {
        ms_sys_yield();
    }
}
static void unlock(void) { atomic_flag_clear_explicit(&list_lock, memory_order_release); }

/* ---- what this thread must tidy later: promises to drop and descriptors to close ---- */

typedef struct TidyPromise {
    MsPromise id;
    IdleGroup *group; /* the group of a request promise, NULL for a registration */
} TidyPromise;

typedef struct Tidy {
    TidyPromise *promises;
    size_t promise_count, promise_capacity;
    int *fds;
    size_t fd_count, fd_capacity;
    const MsIdleOps *fd_ops;
} Tidy;
static _Thread_local Tidy tidy;

static void tidy_promise(MsPromise id, IdleGroup *group) {
    if (tidy.promise_count == tidy.promise_capacity) {
        void *grown = tidy.promises;
        size_t capacity = tidy.promise_capacity;
        if (!ms_array_reserve(&grown, &capacity, tidy.promise_count + 1, sizeof *tidy.promises)) {
            return; /* the promise stays allocated until the scheduler ends */
        }
        tidy.promises = grown;
        tidy.promise_capacity = capacity;
    }
    tidy.promises[tidy.promise_count++] = (TidyPromise){id, group};
}

static void tidy_fd(const MsIdleOps *ops, int fd) {
    if (tidy.fd_count == tidy.fd_capacity) {
        void *grown = tidy.fds;
        size_t capacity = tidy.fd_capacity;
        if (!ms_array_reserve(&grown, &capacity, tidy.fd_count + 1, sizeof *tidy.fds)) {
            ops->release(fd); /* closing now is a risk only for the reactor's one-shot bookkeeping */
            return;
        }
        tidy.fds = grown;
        tidy.fd_capacity = capacity;
    }
    tidy.fd_ops = ops;
    tidy.fds[tidy.fd_count++] = fd;
}

/* Drops finished promises and closes descriptors set aside. `in_task` is true from a task, which may wait for a
 * promise's turn; from mail handling or the idle path the running task is parked and must not yield, so only what
 * already finished goes. */
static void tidy_run(bool in_task) {
    size_t kept = 0;
    for (size_t i = 0; i < tidy.promise_count; i++) {
        const MsPromise id = tidy.promises[i].id;
        if (in_task ? ms_promise_done(id) : ms_promise_finished(id)) {
            ms_promise_drop(tidy.promises[i].id);
        } else {
            tidy.promises[kept++] = tidy.promises[i];
        }
    }
    tidy.promise_count = kept;
    while (tidy.fd_count > 0) {
        tidy.fd_ops->release(tidy.fds[--tidy.fd_count]);
    }
}

/* ---- rows ---- */

static void row_unref(IdleRow *row) {
    if (atomic_fetch_sub(&row->refs, 1) != 1) {
        return;
    }
    msrt_free(row);
}

/* Takes `row` off the list and drops the list's reference. */
static void row_leave(IdleRow *row) {
    lock();
    if (row->listed) {
        row->listed = false;
        if (row->prev != NULL) {
            row->prev->next = row->next;
        } else {
            list_head = row->next;
        }
        if (row->next != NULL) {
            row->next->prev = row->prev;
        }
        atomic_fetch_sub(&counts[row->owner], 1);
        unlock();
        row_unref(row);
        return;
    }
    unlock();
}

/* The work of a request promise: runs the server's closure (a plain function value, which puts no result of its own),
 * then finishes the promise. The promise owns the wrapper, and the wrapper owns the closure. */
typedef struct Request {
    MsObj header;
    void (*code)(struct Request *);
    MsPromise id;
    MsObj *inner;
    IdleGroup *group;
} Request;

/* A function value with no arguments and no result, as the compiler lays it out. */
typedef struct Plain {
    MsObj header;
    void (*code)(struct Plain *);
} Plain;

static void request_run(Request *request) {
    Plain *const inner = (Plain *)request->inner;
    inner->code(inner);
    int64_t done = 0;
    ms_promise_put(request->id, (uint8_t *)&done, &msrt_desc_int, false);
}

static void request_drop(MsObj *object) {
    Request *const request = (Request *)object;
    msrt_obj_drop(request->inner);
    atomic_fetch_sub(&request->group->inflight, 1);
    msrt_free(request);
}

/* Starts the row's request on this thread and ends the row. */
static void row_start(IdleRow *row) {
    MsObj *const next = row->next_request;
    void *const subject = row->subject;
    row->next_request = NULL;
    row->subject = NULL;
    row_leave(row);
    const MsPromise id = ms_promise_new();
    Request *const request = msrt_alloc_zeroed(sizeof *request);
    request->header.drop = request_drop;
    request->code = request_run;
    request->id = id;
    request->inner = next;
    request->group = row->group;
    atomic_fetch_add(&row->group->inflight, 1);
    ms_promise_start_detached(id, &request->header);
    tidy_promise(id, row->group);
    msrt_obj_drop(subject); /* the closure holds its own handle on the connection */
}

/* Ends the row and its connection. */
static void row_close(IdleRow *row) {
    MsObj *const next = row->next_request;
    void *const subject = row->subject;
    const MsIdleOps *const ops = row->ops;
    row->next_request = NULL;
    row->subject = NULL;
    row_leave(row);
    ops->close(subject);
    msrt_obj_drop(subject);
    msrt_obj_drop(next);
}

/* Starting every ready row of one poll at once would turn them all into tasks of this thread, which then cannot move
 * when the first request holds the thread. So one request starts per turn of the scheduler and the other ready rows
 * wait here: still idle rows, which a resting thread can take. */
typedef struct Waiting {
    IdleRow *row; /* holds a reference */
    uint32_t epoch;
    int fd;       /* the descriptor this thread watched */
} Waiting;

static _Thread_local struct {
    Waiting *items;
    size_t count, capacity;
    bool started; /* a request started since the scheduler last looked for work */
} waiting;

/* A group is a handle that Manuscript holds as a number (`ms_idle_group_new`): the one place it becomes a pointer again. */
static IdleGroup *group_of(uintptr_t word) {
    return (IdleGroup *)word; // NOLINT(performance-no-int-to-ptr): the handle travels as a word through Manuscript
}

/* A registration's state word, as `ms_promise_io_on_ready` hands it back to the callback. */
static Reg *reg_of(uintptr_t word) {
    return (Reg *)word; // NOLINT(performance-no-int-to-ptr): the promise table stores the state as a word
}

static bool on_event(MsPromise id, uintptr_t state, uint32_t bits);

/* Watches the row on this thread with a fresh registration. False when the descriptor cannot be watched. */
static bool row_watch(IdleRow *row) {
    lock();
    const uint32_t epoch = row->epoch;
    const int fd = row->fd;
    unlock();
    Reg *const reg = msrt_alloc(sizeof *reg);
    *reg = (Reg){.row = row, .epoch = epoch, .fd = fd};
    atomic_fetch_add(&row->refs, 1);
    int64_t timeout_ns = -1;
    if (row->deadline_ns != MS_NO_DEADLINE) {
        const int64_t left = row->deadline_ns - ms_sched_now();
        timeout_ns = left > 0 ? left : 0;
    }
    const MsPromise id = ms_promise_new();
    reg->promise = id;
    lock();
    row->watching = id; /* before the wait begins: a take that follows must find it */
    unlock();
    if (!ms_promise_io_on_ready(id, fd, MS_WAIT_READ, timeout_ns, on_event, (uintptr_t)reg)) {
        ms_promise_drop(id);
        msrt_free(reg);
        row_unref(row);
        return false;
    }
    return true; /* `reg` may be gone already: a descriptor that is ready at once ran on_event inside the call */
}

/* What a thread that learned a row's event does with it. */
typedef enum { CLAIM_MOVED, CLAIM_START, CLAIM_CLOSE, CLAIM_LOST } Claim;

/* Decides, under the list lock so that no take comes between the look and the change, what this thread does with `row`
 * whose registration of epoch `epoch` fired: start it, close it, or leave it (moved to another thread, or taken). */
static Claim claim_row(IdleRow *row, uint32_t epoch, bool serve) {
    lock();
    Claim claim = CLAIM_MOVED;
    if (row->owner == ms_isolate_self() && row->epoch == epoch) {
        unsigned expected = IDLE;
        const bool serving = serve && !atomic_load(&row->closing);
        if (atomic_compare_exchange_strong(&row->state, &expected, serving ? RUNNING : CLOSED)) {
            claim = serving ? CLAIM_START : CLAIM_CLOSE;
        } else {
            claim = CLAIM_LOST;
        }
    }
    unlock();
    return claim;
}

/* Keeps `row` idle until a turn can start it. False when there is no room to remember it. */
static bool wait_for_turn(IdleRow *row, const Reg *reg) {
    if (waiting.count == waiting.capacity) {
        void *grown = waiting.items;
        size_t capacity = waiting.capacity;
        if (!ms_array_reserve(&grown, &capacity, waiting.count + 1, sizeof *waiting.items)) {
            return false;
        }
        waiting.items = grown;
        waiting.capacity = capacity;
    }
    atomic_fetch_add(&row->refs, 1);
    waiting.items[waiting.count++] = (Waiting){row, reg->epoch, reg->fd};
    return true;
}

/* Settles one waiting entry: starts its row, closes it, or finds it gone or moved. True when a request started. */
static bool settle(Waiting entry) {
    IdleRow *const row = entry.row;
    const Claim claim = claim_row(row, entry.epoch, true);
    bool started = false;
    if (claim == CLAIM_MOVED) {
        tidy_fd(row->ops, entry.fd); /* the row moved: this thread's descriptor is only a duplicate now */
    } else if (claim == CLAIM_START) {
        row_start(row);
        started = true;
    } else if (claim == CLAIM_CLOSE) {
        row_close(row);
    }
    row_unref(row);
    return started;
}

bool ms_idle_turn(void) {
    waiting.started = false;
    while (waiting.count > 0) {
        /* the oldest first */
        const Waiting entry = waiting.items[0];
        memmove(waiting.items, waiting.items + 1, --waiting.count * sizeof *waiting.items);
        if (settle(entry)) {
            waiting.started = true;
            return true;
        }
    }
    return false;
}

/* The registration's callback, once: READ or HUP when the descriptor is readable, TIMEOUT, or CANCELLED. */
static bool on_event(MsPromise id, uintptr_t state, uint32_t bits) {
    Reg *const reg = reg_of(state);
    IdleRow *const row = reg->row;
    lock();
    if (row->watching == id) {
        row->watching = 0; /* this registration is over: a drain must not cancel an id that may name another promise */
    }
    unlock();
    const bool serve = (bits & (MS_WAIT_READ | MS_WAIT_HUP)) != 0;
    if (serve && waiting.started && wait_for_turn(row, reg)) {
        /* kept idle until the scheduler looks for work */
    } else {
        const Claim claim = claim_row(row, reg->epoch, serve);
        if (claim == CLAIM_MOVED) {
            tidy_fd(row->ops, reg->fd); /* the row moved: this thread's descriptor is only a duplicate now */
        } else if (claim == CLAIM_START) {
            waiting.started = true;
            row_start(row);
        } else if (claim == CLAIM_CLOSE) {
            row_close(row);
        }
    }
    if (bits != MS_WAIT_CANCELLED) {
        ms_promise_io_done_unit(id);
        tidy_promise(id, NULL);
    }
    msrt_free(reg);
    row_unref(row);
    return true;
}

static void install(void);

uintptr_t ms_idle_group_new(void) { return (uintptr_t)msrt_alloc_zeroed(sizeof(IdleGroup)); }

bool ms_idle_park(const MsIdleOps *ops, void *subject, int fd, MsObj *next, uintptr_t group, int64_t timeout_ns) {
    install();
    tidy_run(true);
    IdleRow *const row = msrt_alloc_zeroed(sizeof *row);
    atomic_init(&row->refs, 1);
    atomic_init(&row->state, IDLE);
    atomic_init(&row->closing, false);
    row->owner = ms_isolate_self();
    row->fd = fd;
    row->deadline_ns = timeout_ns < 0 ? MS_NO_DEADLINE : ms_sched_now() + timeout_ns;
    row->group = group_of(group);
    row->ops = ops;
    row->subject = subject;
    row->next_request = next;
    if (row->owner >= MS_MAX_ISOLATES) {
        msrt_free(row);
        return false;
    }
    if (ops->buffered(subject)) {
        atomic_store(&row->state, RUNNING);
        row->listed = false;
        row_start(row);
        row_unref(row);
        return true;
    }
    lock();
    row->listed = true;
    row->next = list_head;
    if (list_head != NULL) {
        list_head->prev = row;
    }
    list_head = row;
    atomic_fetch_add(&counts[row->owner], 1);
    unlock();
    if (!row_watch(row)) {
        row->next_request = NULL;
        row->subject = NULL;
        row_leave(row); /* drops the creation reference */
        return false;
    }
    return true;
}

/* ---- taking, draining, tearing down ---- */

static void post(uint32_t target, uint64_t operation, uint64_t value, IdleRow *row) {
    MsMail *const mail = msrt_alloc(sizeof *mail);
    *mail = (MsMail){.kind = MS_MAIL_IDLE, .from = ms_isolate_self(), .a = operation, .b = value, .p = row};
    if (!ms_isolate_post(target, mail)) {
        msrt_free(mail);
        if (row != NULL) {
            row_unref(row);
        }
    }
}

/* This thread takes `row`, which another thread watches: a duplicate descriptor and a registration of its own. The
 * old registration ends by itself: it closes its descriptor when the peer acts or the idle time passes. Holds the mail's reference on `row` and drops it. */
static void take(IdleRow *row) {
    const uint32_t self = ms_isolate_self();
    lock();
    const bool open = row->listed && row->owner != self && atomic_load(&row->state) == IDLE && !atomic_load(&row->closing);
    const uint32_t from = row->owner;
    const uint32_t epoch = row->epoch;
    const int old_fd = row->fd;
    unlock();
    const int copy = open ? row->ops->duplicate(old_fd) : -1;
    if (copy < 0) {
        row_unref(row);
        return;
    }
    lock();
    const bool taken = row->listed && row->epoch == epoch && atomic_load(&row->state) == IDLE &&
                       !atomic_load(&row->closing);
    if (taken) {
        row->owner = self;
        row->epoch++;
        row->fd = copy;
        row->watching = 0;
        atomic_fetch_sub(&counts[from], 1);
        atomic_fetch_add(&counts[self], 1);
        row->ops->moved(row->subject, copy);
    }
    unlock();
    if (!taken) {
        row->ops->release(copy);
        row_unref(row);
        return;
    }
    unsigned expected = IDLE;
    if (!row_watch(row) && atomic_compare_exchange_strong(&row->state, &expected, CLOSED)) {
        row_close(row);
    }
    row_unref(row);
}

/* Ends the registration `id` of this thread now (an idle row being drained, or a registration that a take made
 * stale): its callback closes the row or releases the old descriptor. */
static void cancel_registration(MsPromise id) {
    if (id != 0) {
        ms_promise_cancel(id);
        tidy_promise(id, NULL);
    }
}

static void idle_mail(MsMail *mail) {
    const uint64_t operation = mail->a & 0xffu;
    IdleRow *const row = mail->p;
    const uint32_t self = ms_isolate_self();
    if (operation == OP_TAKE) {
        take(row);
    } else if (operation == OP_CANCEL) {
        for (size_t i = 0; i < tidy.promise_count; i++) {
            if (tidy.promises[i].group == group_of(mail->b)) {
                ms_promise_cancel(tidy.promises[i].id);
            }
        }
    } else if (operation == OP_CLOSE) {
        lock();
        const MsPromise id = row->owner == self ? row->watching : 0;
        unlock();
        cancel_registration(id);
        row_unref(row);
    }
    msrt_free(mail);
    tidy_run(false);
}

static void idle_discard(MsMail *mail) {
    if (mail->p != NULL) {
        row_unref(mail->p);
    }
}

/* The rows of `owner` that can move, referenced, up to `limit`; with `group` set the rows of that group on any thread. */
static size_t collect(IdleRow **out, size_t limit, uint32_t owner, bool by_group, uintptr_t group, bool mark_closing) {
    size_t count = 0;
    lock();
    for (IdleRow *row = list_head; row != NULL && count < limit; row = row->next) {
        const bool wanted = by_group ? row->group == group_of(group) : row->owner == owner;
        if (!wanted || atomic_load(&row->state) != IDLE || (!mark_closing && atomic_load(&row->closing))) {
            continue;
        }
        if (mark_closing) {
            atomic_store(&row->closing, true);
        }
        atomic_fetch_add(&row->refs, 1);
        out[count++] = row;
    }
    unlock();
    return count;
}

/* The watcher's hook: the idle rows of a held-up thread go to a resting one. Looks often while a thread is held up. */
static bool idle_hook(MsWatchLook look, uint64_t resting) {
    uint64_t live = 0;
    (void)ms_isolate_resting(&live);
    bool held = false;
    for (uint32_t from = 0; from < MS_MAX_ISOLATES; from++) {
        if (atomic_load(&counts[from]) == 0 || !ms_watch_held_up(look, resting, from)) {
            continue;
        }
        held = true;
        const uint64_t takers = resting & live & ~(UINT64_C(1) << from);
        if (takers == 0) {
            continue;
        }
        uint32_t to = (from + 1) % MS_MAX_ISOLATES;
        while ((takers >> to & 1) == 0) {
            to = (to + 1) % MS_MAX_ISOLATES;
        }
        IdleRow *rows[TAKE_BATCH];
        const size_t count = collect(rows, TAKE_BATCH, from, false, 0, false);
        for (size_t i = 0; i < count; i++) {
            post(to, OP_TAKE, 0, rows[i]);
        }
    }
    return held;
}

void ms_idle_drain(uintptr_t group) {
    for (;;) {
        IdleRow *rows[TAKE_BATCH];
        const size_t count = collect(rows, TAKE_BATCH, 0, true, group, true);
        for (size_t i = 0; i < count; i++) {
            uint32_t owner = 0;
            lock();
            owner = rows[i]->owner;
            unlock();
            post(owner, OP_CLOSE, 0, rows[i]);
        }
        if (count < TAKE_BATCH) {
            return;
        }
    }
}

size_t ms_idle_inflight(uintptr_t group) { return atomic_load(&(group_of(group))->inflight); }

void ms_idle_cancel(uintptr_t group) {
    uint64_t live = 0;
    (void)ms_isolate_resting(&live);
    for (uint32_t isolate = 0; isolate < MS_MAX_ISOLATES; isolate++) {
        if ((live >> isolate & 1) != 0) {
            post(isolate, OP_CANCEL, group, NULL);
        }
    }
}

void ms_idle_teardown(void) {
    const uint32_t self = ms_isolate_self();
    for (;;) {
        IdleRow *rows[TAKE_BATCH];
        const size_t count = collect(rows, TAKE_BATCH, self, false, 0, true);
        for (size_t i = 0; i < count; i++) {
            unsigned expected = IDLE;
            if (atomic_compare_exchange_strong(&rows[i]->state, &expected, CLOSED)) {
                row_close(rows[i]);
            }
            row_unref(rows[i]);
        }
        if (count < TAKE_BATCH) {
            break;
        }
    }
    while (waiting.count > 0) {
        row_unref(waiting.items[--waiting.count].row);
    }
    tidy_run(false);
}

uint32_t ms_idle_count(uint32_t isolate) { return isolate < MS_MAX_ISOLATES ? atomic_load(&counts[isolate]) : 0; }

static void install(void) {
    static const MsMailKindOps ops = {.handle = idle_mail, .discard = idle_discard};
    if (!atomic_exchange(&hook_added, true)) {
        ms_isolate_set_mail_kind(MS_MAIL_IDLE, &ops);
        (void)ms_watch_add_hook(idle_hook);
    }
}
