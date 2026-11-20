/* The promise table of a thread. See promise.h.
 *
 * Rows are split in two arrays: the hot one holds what a wait and a wake touch (state, flags, generation, the
 * waiter's token), the cold one everything else, so the scheduler's common paths read 16 bytes per promise. The
 * promises a task started form a doubly linked list threaded through the cold rows by index, with its head in the
 * task record, so a cancelled frame visits only its own promises and ending one is constant time.
 */
#include "promise.h"

#include <string.h>

#include "array.h"
#include "cancel.h"
#include "group.h"
#include "ms_rt/alloc.h"
#include "ms_rt/obj.h"
#include "scheduler.h"

enum PromiseState {
    STATE_FREE = 0,
    STATE_PENDING,
    STATE_OK,
    STATE_ERROR,
    STATE_FAILED,
    STATE_CANCELLED,
    STATE_TAKEN,
};

enum {
    FLAG_REMOTE_WAKE = 1, /* another thread completes this promise: a waiter's token must be remote */
    FLAG_HELD = 2,        /* the result is stored, but the promise stays pending until its work's task ended */
    FLAG_HELD_ERROR = 4,  /* the held result is the operation's own error */
    FLAG_DEFERRED = 8,    /* no task: the first waiter runs the work on its own stack */
    FLAG_TIMED_OUT = 16,  /* the limit passed and ended it: a wait reports a timeout, not a cancellation */
    FLAG_STOPPED = 32,    /* stop asked the work to cancel; without a result it reads as cancelled */
    FLAG_GROUPED = 64,    /* a wait group member: the group hears when it finishes */
};

#define GENERATION_MASK 0xffffffu /* 24 bits: an id is `isolate << 56 | generation << 32 | (row + 1)` */
#define ISOLATE_SHIFT 56
#define NO_TIME INT64_MAX

typedef struct Hot {
    uint8_t state;
    uint8_t flags;
    uint32_t generation;
    uint64_t token; /* the token a waiter parks on, or 0 */
} Hot;

typedef struct Cold {
    uint8_t *result;            /* heap block holding an owned value of `desc`, or NULL */
    const MsTypeDesc *desc;
    MsObj *closure;             /* the work while its task may still run (or the deferred work), else NULL */
    MsTaskHandle task;          /* the task running the work, else 0 */
    MsTaskHandle creator;       /* the task that started the work, else 0 */
    size_t started_at;          /* the creator's cleanup height when it started the work */
    int64_t deadline;           /* when a sleep ends, or NO_TIME */
    int64_t limit;              /* when the limit ends the promise, or NO_TIME */
    MsPromiseRetry retry;       /* the continuation of an I/O promise */
    uintptr_t retry_state;
    int64_t pipe;               /* the pipe a result block came from, for the unread hook */
    int32_t fd;                 /* the descriptor a readiness wait watches, or -1 */
    uint32_t events;            /* what that wait asks for */
    MsFaultText report;         /* the fault that ended the promise */
    int64_t cancel;             /* the cancel switch the promise listens to, or 0 */
    uint32_t next_started;      /* row + 1 of the creator's next older started promise, 0 ends the list */
    uint32_t prev_started;
} Cold;

typedef struct Table {
    Hot *hot;
    Cold *cold;
    size_t count;
    size_t capacity;
    uint32_t *free_rows;
    size_t free_count;
    size_t free_capacity;
} Table;

typedef struct MsClosure {
    MsObj header;
    void (*code)(struct MsClosure *);
} MsClosure;

static _Thread_local Table table; /* per-thread state, like the scheduler's */
static MsPromiseUnread unread_hook;

void ms_promise_set_unread(MsPromiseUnread unread) { unread_hook = unread; }

/* ---- rows ---- */

static void fail(const char *text) { ms_sched()->hooks.fault(MS_FAULT_KIND_FAULT, text); }

static void drop_closure(uint8_t *closure) { msrt_obj_drop((MsObj *)__builtin_assume_aligned(closure, _Alignof(MsObj))); }

static uint64_t own_isolate(void) { return (uint64_t)(ms_sched()->isolate & 0x3fu); }

static MsPromise make_id(size_t row) {
    return (MsPromise)(own_isolate() << ISOLATE_SHIFT | (uint64_t)table.hot[row].generation << 32 | (uint64_t)(row + 1));
}

/* Whether `id` belongs to another isolate's table. */
static bool is_foreign(MsPromise id) { return ((uint64_t)id >> ISOLATE_SHIFT) != own_isolate(); }

/* The row of `id`, or -1 for a stale, closed or foreign id. */
static ptrdiff_t row_of(MsPromise id) {
    if (is_foreign(id)) {
        return -1;
    }
    const uint64_t low = (uint64_t)id & 0xffffffffu;
    if (low == 0 || low > table.count) {
        return -1;
    }
    const size_t row = (size_t)low - 1;
    if (table.hot[row].state == STATE_FREE || (uint64_t)table.hot[row].generation != (((uint64_t)id >> 32) & GENERATION_MASK)) {
        return -1;
    }
    return (ptrdiff_t)row;
}

static size_t row_or_fault(MsPromise id) {
    const ptrdiff_t row = row_of(id);
    if (row < 0) {
        fail("promise: no such promise");
    }
    return (size_t)row;
}

static void release_result(size_t row) {
    Cold *const cold = &table.cold[row];
    if (cold->result != NULL) {
        msrt_slot_drop(cold->desc, cold->result);
        msrt_free(cold->result);
    }
    cold->result = NULL;
    cold->desc = NULL;
}

static void reset_row(size_t row) {
    table.cold[row] = (Cold){.deadline = NO_TIME, .limit = NO_TIME, .fd = -1};
    Hot *const hot = &table.hot[row];
    hot->flags = 0;
    hot->token = 0;
}

static bool grow_table(void) {
    size_t capacity = table.capacity;
    void *hot = table.hot;
    if (!ms_array_reserve(&hot, &capacity, table.count + 1, sizeof *table.hot)) {
        return false;
    }
    table.hot = hot;
    capacity = table.capacity;
    void *cold = table.cold;
    if (!ms_array_reserve(&cold, &capacity, table.count + 1, sizeof *table.cold)) {
        return false;
    }
    table.cold = cold;
    table.capacity = capacity;
    return true;
}

MsPromise ms_promise_new(void) {
    size_t row = 0;
    if (table.free_count != 0) {
        row = table.free_rows[--table.free_count];
    } else {
        if (!grow_table()) {
            fail("promise: out of memory");
        }
        row = table.count++;
        table.hot[row] = (Hot){0};
    }
    Hot *const hot = &table.hot[row];
    hot->generation = (hot->generation + 1) & GENERATION_MASK;
    if (hot->generation == 0) {
        hot->generation = 1;
    }
    hot->state = STATE_PENDING;
    reset_row(row);
    return make_id(row);
}

static bool ended_without_value(uint8_t state) {
    return state == STATE_ERROR || state == STATE_FAILED || state == STATE_CANCELLED;
}

static void wake(size_t row) {
    Hot *const hot = &table.hot[row];
    if ((hot->flags & FLAG_GROUPED) != 0 && hot->state != STATE_PENDING) {
        hot->flags &= (uint8_t)~FLAG_GROUPED;
        ms_group_finished(make_id(row), ended_without_value(hot->state));
    }
    const uint64_t token = hot->token;
    hot->token = 0;
    if (token != 0) {
        ms_token_post(token, 1);
    }
}

/* ---- completion ---- */

static void drop_block(void *block, const MsTypeDesc *desc, int64_t pipe) {
    if (pipe != 0 && unread_hook != NULL) {
        unread_hook(pipe, block, desc);
        return;
    }
    msrt_slot_drop(desc, block);
    msrt_free(block);
}

/* Completes `row` with `block` unless it already finished; `block` is taken either way. */
static void complete(size_t row, void *block, const MsTypeDesc *desc, bool failed, int64_t pipe) {
    Hot *const hot = &table.hot[row];
    Cold *const cold = &table.cold[row];
    if (hot->state != STATE_PENDING || (hot->flags & FLAG_HELD) != 0) {
        if (block != NULL) {
            drop_block(block, desc, pipe);
        }
        return;
    }
    cold->result = block;
    cold->desc = desc;
    cold->pipe = pipe;
    cold->retry = NULL;
    if (cold->closure != NULL) {
        /* The work's task is still ending: its owned resources close first. */
        hot->flags |= (uint8_t)(FLAG_HELD | (failed ? FLAG_HELD_ERROR : 0));
        return;
    }
    hot->state = failed ? STATE_ERROR : STATE_OK;
    wake(row);
}

void ms_promise_put(MsPromise id, uint8_t *value, const MsTypeDesc *desc, bool failed) {
    const ptrdiff_t row = row_of(id);
    const size_t size = desc->size;
    uint8_t *const block = msrt_alloc(size > 0 ? size : 1);
    memcpy(block, value, size);
    if (row < 0) {
        drop_block(block, desc, 0);
        return;
    }
    complete((size_t)row, block, desc, failed, 0);
}

void ms_promise_io_done_block(MsPromise id, void *block, const MsTypeDesc *desc, int64_t pipe) {
    const ptrdiff_t row = row_of(id);
    if (row < 0) {
        drop_block(block, desc, pipe);
        return;
    }
    complete((size_t)row, block, desc, false, pipe);
}

void ms_promise_io_done(MsPromise id) {
    const ptrdiff_t row = row_of(id);
    if (row >= 0) {
        complete((size_t)row, NULL, NULL, false, 0);
    }
}

void ms_promise_io_done_int(MsPromise id, int64_t value) {
    int64_t *const block = msrt_alloc(sizeof value);
    *block = value;
    ms_promise_io_done_block(id, block, &msrt_desc_int, 0);
}

void ms_promise_io_done_unit(MsPromise id) { ms_promise_io_done_int(id, 0); }

bool ms_promise_take(MsPromise id, const MsTypeDesc *desc, uint8_t *out) {
    const ptrdiff_t row = row_of(id);
    if (row < 0 || table.cold[row].result == NULL) {
        return false;
    }
    Cold *const cold = &table.cold[row];
    memcpy(out, cold->result, desc->size);
    msrt_free(cold->result);
    cold->result = NULL;
    cold->desc = NULL;
    table.hot[row].state = STATE_TAKEN;
    return true;
}

void ms_promise_set_remote_wake(MsPromise id) {
    const ptrdiff_t row = row_of(id);
    if (row >= 0) {
        table.hot[row].flags |= FLAG_REMOTE_WAKE;
    }
}

void ms_promise_on_drop(MsPromise id, MsPromiseRetry cancel, uintptr_t state) {
    const ptrdiff_t row = row_of(id);
    if (row < 0 || table.hot[row].state != STATE_PENDING) {
        (void)cancel(id, state, MS_WAIT_CANCELLED);
        return;
    }
    table.cold[row].retry = cancel;
    table.cold[row].retry_state = state;
}

/* ---- the lists of started promises ---- */

static void link_started(size_t row) {
    Cold *const cold = &table.cold[row];
    const uint32_t old = ms_task_started_swap(cold->creator, (uint32_t)row + 1);
    cold->next_started = old;
    cold->prev_started = 0;
    if (old != 0) {
        table.cold[old - 1].prev_started = (uint32_t)row + 1;
    }
}

static void unlink_started(size_t row, MsTaskHandle creator) {
    Cold *const cold = &table.cold[row];
    const uint32_t prev = cold->prev_started;
    const uint32_t next = cold->next_started;
    if (prev != 0) {
        table.cold[prev - 1].next_started = next;
    } else if (ms_task_started_head(creator) == (uint32_t)row + 1) {
        (void)ms_task_started_swap(creator, next);
    }
    if (next != 0) {
        table.cold[next - 1].prev_started = prev;
    }
    cold->next_started = 0;
    cold->prev_started = 0;
}

/* ---- the work's task ---- */

static void run_closure(void *closure) { ((MsClosure *)closure)->code(closure); }

/* The task of promise `id` ended with `status` (a MsGuardStatus); records how, drops the closure and wakes. */
static void work_ended(MsPromise id, MsGuardStatus status, MsFaultText message) {
    const ptrdiff_t found = row_of(id);
    if (found < 0) {
        ms_fault_text_free(&message);
        return;
    }
    const size_t row = (size_t)found;
    Hot *const hot = &table.hot[row];
    Cold *const cold = &table.cold[row];
    MsObj *const closure = cold->closure;
    cold->closure = NULL;
    msrt_obj_drop(closure);
    if (cold->creator != 0) {
        unlink_started(row, cold->creator);
        cold->creator = 0;
    }
    cold->task = 0;
    const bool interrupted = (hot->flags & (FLAG_TIMED_OUT | FLAG_STOPPED)) != 0;
    if (hot->state == STATE_PENDING && (hot->flags & FLAG_HELD) != 0) {
        /* A promise whose limit passed or that was cancelled reports that, not the error its work returned on the
         * way out (a wait inside the work that finds its child cancelled returns an error before the work's own
         * cancellation is seen, so the outcome would otherwise depend on timing). */
        const bool error = (hot->flags & FLAG_HELD_ERROR) != 0;
        if (error && interrupted) {
            release_result(row);
        }
        hot->state = STATE_OK;
        if (error) {
            hot->state = interrupted ? STATE_CANCELLED : STATE_ERROR;
        }
        hot->flags &= (uint8_t) ~(FLAG_HELD | FLAG_HELD_ERROR);
    } else if (hot->state == STATE_PENDING) {
        if (status == MS_GUARD_FAULT) {
            cold->report = message;
            message = (MsFaultText){0};
            hot->state = STATE_FAILED;
        } else {
            hot->state = status == MS_GUARD_CANCELLED || interrupted ? STATE_CANCELLED : STATE_FAILED;
        }
        if (hot->state == STATE_FAILED && cold->report.bytes == NULL) {
            static const char text[] = "promise: the work ended without a result";
            cold->report.bytes = msrt_alloc(sizeof text - 1);
            memcpy(cold->report.bytes, text, sizeof text - 1);
            cold->report.length = sizeof text - 1;
        }
    }
    ms_fault_text_free(&message);
    wake(row);
}

static void work_entry(void *argument) {
    const MsPromise id = (MsPromise)(uintptr_t)argument; // NOLINT(performance-no-int-to-ptr): the id travels as the argument word
    const ptrdiff_t row = row_of(id);
    if (row < 0 || table.cold[row].closure == NULL) {
        return;
    }
    MsFaultText message = {0};
    const MsGuardStatus status = ms_guard_call(run_closure, table.cold[row].closure, &message);
    /* Ending drops the closure, which closes what it captured: like any implicit close it runs shielded, since a
     * cancelled task would otherwise be cancelled again at its first park. */
    ms_shield_enter();
    work_ended(id, status, message);
    ms_shield_exit();
}

static void start_task(MsPromise id, MsObj *closure) {
    const size_t row = row_or_fault(id);
    Cold *const cold = &table.cold[row];
    if (cold->closure != NULL || (table.hot[row].flags & FLAG_DEFERRED) != 0) {
        fail("promise: already started");
    }
    cold->closure = closure;
    cold->creator = ms_task_current();
    cold->started_at = ms_cleanup_base();
    link_started(row);
    MsTaskStatus status = MS_TASK_OK;
    void *const argument = (void *)(uintptr_t)id; // NOLINT(performance-no-int-to-ptr): the id travels as the argument word
    const MsTaskHandle task = ms_task_spawn(work_entry, argument, MS_SPAWN_DETACHED, 0, &status);
    if (task == 0) {
        unlink_started(row, cold->creator);
        cold->closure = NULL;
        cold->creator = 0;
        msrt_obj_drop(closure);
        fail("promise: cannot start the work: out of stacks");
    }
    table.cold[row].task = task;
}

void ms_promise_start(MsPromise id, MsObj *closure) { start_task(id, closure); }

void ms_promise_start_spread(MsPromise id, MsObj *closure) { start_task(id, closure); }

void ms_promise_defer(MsPromise id, MsObj *closure) {
    const size_t row = row_or_fault(id);
    table.hot[row].flags |= FLAG_DEFERRED;
    table.cold[row].closure = closure;
}

void ms_promise_start_idle(MsPromise id, MsObj *closure) {
    if (ms_task_count() <= 1) {
        ms_promise_defer(id, closure);
    } else {
        start_task(id, closure);
    }
}

/* Records how a guarded inline run ended. */
static void end_guarded_run(MsPromise id, MsGuardStatus status, MsFaultText message) {
    const ptrdiff_t row = row_of(id);
    if (row < 0 || status == MS_GUARD_OK || table.hot[row].state != STATE_PENDING) {
        ms_fault_text_free(&message);
        return;
    }
    if (status == MS_GUARD_FAULT) {
        table.cold[row].report = message;
        table.hot[row].state = STATE_FAILED;
    } else {
        ms_fault_text_free(&message);
        table.hot[row].state = STATE_CANCELLED;
    }
    wake((size_t)row);
}

/* Runs the deferred work of `id` on the caller's stack, ending by `deadline` (NO_TIME: no limit). With `guarded`, a
 * fault or a cancel inside the work ends the promise as failed or cancelled instead of unwinding the caller (the
 * run of a wait group, which a failing member interrupts). */
static bool run_deferred(MsPromise id, int64_t deadline, bool guarded) {
    const ptrdiff_t found = row_of(id);
    if (found < 0 || (table.hot[found].flags & FLAG_DEFERRED) == 0) {
        return false;
    }
    const size_t row = (size_t)found;
    table.hot[row].flags &= (uint8_t)~FLAG_DEFERRED;
    MsObj *const closure = table.cold[row].closure;
    table.cold[row].closure = NULL;
    int64_t until = deadline;
    if (table.cold[row].limit < until) {
        until = table.cold[row].limit;
    }
    const int64_t inherited = ms_task_defer_deadline();
    if (inherited < until) {
        until = inherited;
    }
    const int64_t earlier = ms_task_set_defer_deadline(until);
    const size_t handle = ms_cleanup_push(drop_closure, (uint8_t *)closure);
    MsFaultText message = {0};
    MsGuardStatus status = MS_GUARD_OK;
    if (guarded) {
        status = ms_guard_call(run_closure, closure, &message);
    } else {
        run_closure(closure);
    }
    ms_cleanup_discard(handle);
    msrt_obj_drop(closure);
    (void)ms_task_set_defer_deadline(earlier);
    end_guarded_run(id, status, message);
    return true;
}

/* ---- stopping and ending ---- */

/* Asks the work of `id` to stop at its next cancellation point. */
static void request_cancel(size_t row) {
    const Cold *const cold = &table.cold[row];
    if (cold->closure != NULL && cold->task != 0) {
        ms_task_cancel(cold->task);
    }
}

/* Ends the descriptor wait of a pending promise. */
static void leave_fd(MsPromise id, size_t row) {
    Cold *const cold = &table.cold[row];
    if (cold->fd >= 0) {
        ms_sched_fd_wait_end((uint64_t)id, cold->fd);
        cold->fd = -1;
    }
}

static void stop(MsPromise id) {
    const ptrdiff_t found = row_of(id);
    if (found < 0 || table.hot[found].state != STATE_PENDING) {
        return;
    }
    const size_t row = (size_t)found;
    Hot *const hot = &table.hot[row];
    Cold *const cold = &table.cold[row];
    if (cold->closure != NULL && (hot->flags & FLAG_DEFERRED) == 0) {
        hot->flags |= FLAG_STOPPED;
        request_cancel(row);
        return;
    }
    if ((hot->flags & FLAG_DEFERRED) != 0) {
        hot->flags &= (uint8_t)~FLAG_DEFERRED;
        MsObj *const closure = cold->closure;
        cold->closure = NULL;
        msrt_obj_drop(closure);
    }
    leave_fd(id, row);
    MsPromiseRetry retry = cold->retry;
    cold->retry = NULL;
    if (retry != NULL) {
        (void)retry(id, cold->retry_state, MS_WAIT_CANCELLED);
    }
    const ptrdiff_t again = row_of(id);
    if (again >= 0 && table.hot[again].state == STATE_PENDING) {
        table.hot[again].state = STATE_CANCELLED;
        wake((size_t)again);
    }
}

void ms_promise_cancel(MsPromise id) { stop(id); }

void ms_promise_on_cancel(MsPromise id, int64_t cancel) {
    const ptrdiff_t row = row_of(id);
    if (row < 0) {
        return;
    }
    const int64_t previous = table.cold[row].cancel;
    table.cold[row].cancel = cancel;
    if (previous != 0) {
        ms_cancel_unregister(previous, id);
    }
    if (ms_cancel_register(cancel, id)) {
        stop(id);
    }
}

void ms_promise_limit(MsPromise id, int64_t timeout_ns) {
    const ptrdiff_t row = row_of(id);
    if (row < 0) {
        return;
    }
    const int64_t at = ms_sched_now() + (timeout_ns > 0 ? timeout_ns : 0);
    table.cold[row].limit = at;
    ms_sched_arm((uint64_t)id, at);
}

/* Parks the caller until `id` wakes it, `at_ns` passes (negative: never) or a cancel arrives; returns the wake
 * result (0 posted, MS_WAIT_TIMEOUT, MS_WAIT_CANCELLED). */
static uint32_t park_on(MsPromise id, int64_t at_ns) {
    const ptrdiff_t row = row_of(id);
    if (row < 0) {
        return 0;
    }
    const bool remote = (table.hot[row].flags & FLAG_REMOTE_WAKE) != 0;
    const uint64_t token = ms_token_new(remote ? MS_TOKEN_REMOTE : 0);
    if (token == 0) {
        fail("promise: out of wait tokens");
    }
    table.hot[row].token = token;
    uint64_t value = 0;
    uint32_t result = 0;
    const MsTokenStatus status = ms_token_park_at(token, at_ns, &value, &result);
    const ptrdiff_t after = row_of(id);
    if (after >= 0 && table.hot[after].token == token) {
        table.hot[after].token = 0;
    }
    (void)ms_token_free(token);
    return status == MS_TOKEN_OK ? result : 0;
}

bool ms_promise_end(MsPromise id) {
    ptrdiff_t found = row_of(id);
    if (found < 0) {
        return false;
    }
    Hot *hot = &table.hot[found];
    Cold *const cold = &table.cold[found];
    if (cold->cancel != 0) {
        ms_cancel_unregister(cold->cancel, id);
        cold->cancel = 0;
    }
    if ((hot->flags & FLAG_DEFERRED) != 0) {
        hot->flags &= (uint8_t)~FLAG_DEFERRED;
        MsObj *const closure = cold->closure;
        cold->closure = NULL;
        msrt_obj_drop(closure);
    }
    if (hot->state == STATE_PENDING) {
        leave_fd(id, (size_t)found);
    }
    if (hot->state == STATE_PENDING && cold->retry != NULL) {
        MsPromiseRetry retry = cold->retry;
        cold->retry = NULL;
        (void)retry(id, cold->retry_state, MS_WAIT_CANCELLED);
    }
    if (table.cold[found].closure != NULL) {
        if (table.hot[found].state == STATE_PENDING) {
            request_cancel((size_t)found);
        }
        ms_shield_enter();
        while ((found = row_of(id)) >= 0 && table.cold[found].closure != NULL) {
            (void)park_on(id, -1);
        }
        ms_shield_exit();
    }
    found = row_of(id);
    return found >= 0 && table.hot[found].state == STATE_OK && table.cold[found].result != NULL;
}

void ms_promise_drop(MsPromise id) {
    (void)ms_promise_end(id);
    const ptrdiff_t found = row_of(id);
    if (found < 0) {
        return;
    }
    const size_t row = (size_t)found;
    release_result(row);
    ms_fault_text_free(&table.cold[row].report);
    table.hot[row].state = STATE_FREE;
    if (table.free_count == table.free_capacity) {
        size_t capacity = table.free_capacity;
        void *rows = table.free_rows;
        if (!ms_array_reserve(&rows, &capacity, table.free_count + 1, sizeof *table.free_rows)) {
            return;
        }
        table.free_rows = rows;
        table.free_capacity = capacity;
    }
    table.free_rows[table.free_count++] = (uint32_t)row;
}

MsFaultText ms_promise_fault_report(MsPromise id) {
    const ptrdiff_t row = row_of(id);
    if (row < 0 || table.cold[row].report.bytes == NULL) {
        return (MsFaultText){0};
    }
    return ms_fault_text_clone(&table.cold[row].report);
}

/* A cancelled frame ends the promises it started at or above its cleanup height `base`, newest first: the work
 * borrows the frame's values, so it must end before they do. Work on this task's own stack (a deferred promise)
 * ends with it, and joining it would wait on itself. */
static ptrdiff_t next_to_end(MsTaskHandle me, size_t base) {
    for (uint32_t at = ms_task_started_head(me); at != 0; at = table.cold[at - 1].next_started) {
        const Cold *const cold = &table.cold[at - 1];
        if (cold->closure != NULL && cold->task != 0 && cold->task != me && cold->started_at >= base) {
            return (ptrdiff_t)at - 1;
        }
    }
    return -1;
}

static void end_started(size_t base) {
    const MsTaskHandle me = ms_task_current();
    ptrdiff_t row = 0;
    while ((row = next_to_end(me, base)) >= 0) {
        (void)ms_promise_end(make_id((size_t)row));
    }
}

/* ---- waiting ---- */

static int64_t outcome(size_t row) {
    const Hot *const hot = &table.hot[row];
    switch (hot->state) {
    case STATE_OK:
        return MS_PROMISE_OK;
    case STATE_ERROR:
        return MS_PROMISE_ERROR;
    case STATE_FAILED:
        return MS_PROMISE_FAILED;
    case STATE_CANCELLED:
        return (hot->flags & FLAG_TIMED_OUT) != 0 ? MS_PROMISE_TIMEOUT : MS_PROMISE_CANCELLED;
    case STATE_TAKEN:
        return MS_PROMISE_CLOSED;
    default:
        return -1;
    }
}

static int64_t earliest(int64_t a, int64_t b) { return a < b ? a : b; }

int64_t ms_promise_wait(MsPromise id, int64_t timeout_ns) {
    const size_t first = row_or_fault(id);
    int64_t deadline = timeout_ns >= 0 ? ms_sched_now() + timeout_ns : NO_TIME;
    deadline = earliest(deadline, earliest(table.cold[first].limit, ms_task_defer_deadline()));
    (void)run_deferred(id, deadline, false);
    for (;;) {
        const ptrdiff_t row = row_of(id);
        if (row < 0) {
            return MS_PROMISE_CLOSED;
        }
        const int64_t code = outcome((size_t)row);
        if (code >= 0) {
            return code;
        }
        const uint32_t woke = park_on(id, deadline == NO_TIME ? -1 : deadline);
        if (woke == MS_WAIT_CANCELLED) {
            (void)ms_promise_end(id);
            ms_cancelled();
        }
        const ptrdiff_t after = row_of(id);
        if (after < 0) {
            return MS_PROMISE_CLOSED;
        }
        const int64_t done = outcome((size_t)after);
        if (done >= 0) {
            return done;
        }
        if (woke == MS_WAIT_TIMEOUT) {
            request_cancel((size_t)after);
            return MS_PROMISE_TIMEOUT;
        }
    }
}

bool ms_promise_done(MsPromise id) {
    const ptrdiff_t row = row_of(id);
    if (row < 0) {
        return true;
    }
    if (table.hot[row].state == STATE_PENDING && table.cold[row].closure != NULL) {
        /* A task that has not run yet gets its turn, so polling done makes progress. */
        ms_task_yield();
    }
    const ptrdiff_t after = row_of(id);
    return after < 0 || table.hot[after].state != STATE_PENDING;
}

MsPromiseProbe ms_promise_probe(MsPromise id) {
    const ptrdiff_t row = row_of(id);
    if (row < 0) {
        return MS_PROMISE_GONE;
    }
    const uint8_t state = table.hot[row].state;
    if (state == STATE_PENDING) {
        return MS_PROMISE_PENDING;
    }
    return ended_without_value(state) ? MS_PROMISE_FAILED_PROBE : MS_PROMISE_DONE_PROBE;
}

void ms_promise_set_grouped(MsPromise id, bool grouped) {
    const ptrdiff_t row = row_of(id);
    if (row < 0) {
        return;
    }
    if (grouped) {
        table.hot[row].flags |= FLAG_GROUPED;
    } else {
        table.hot[row].flags &= (uint8_t)~FLAG_GROUPED;
    }
}

bool ms_promise_run_inline(MsPromise id) {
    const ptrdiff_t row = row_of(id);
    if (row < 0 || table.hot[row].state != STATE_PENDING || (table.hot[row].flags & FLAG_DEFERRED) == 0) {
        return false;
    }
    (void)run_deferred(id, NO_TIME, true);
    return true;
}

/* ---- waiting for any ---- */

static ptrdiff_t first_done(const MsPromise *ids, size_t count) {
    for (size_t at = 0; at < count; at++) {
        const ptrdiff_t row = row_of(ids[at]);
        if (row < 0 || table.hot[row].state != STATE_PENDING) {
            return (ptrdiff_t)at;
        }
    }
    return -1;
}

static void set_tokens(const MsPromise *ids, size_t count, uint64_t from, uint64_t to) {
    for (size_t at = 0; at < count; at++) {
        const ptrdiff_t row = row_of(ids[at]);
        if (row < 0) {
            continue;
        }
        if (to != 0 && table.hot[row].token != 0) {
            fail("promise: another task is already waiting on this promise");
        }
        if (to != 0 || table.hot[row].token == from) {
            table.hot[row].token = to;
        }
    }
}

int64_t ms_promise_wait_any(const MsPromise *ids, size_t count, int64_t timeout_ns) {
    int64_t deadline = timeout_ns >= 0 ? ms_sched_now() + timeout_ns : NO_TIME;
    deadline = earliest(deadline, ms_task_defer_deadline());
    if (first_done(ids, count) < 0) {
        for (size_t at = 0; at < count && run_deferred(ids[at], deadline, false) && first_done(ids, count) < 0; at++) {
        }
    }
    for (;;) {
        const ptrdiff_t done = first_done(ids, count);
        if (done >= 0) {
            return done;
        }
        const uint64_t token = ms_token_new(0);
        if (token == 0) {
            fail("promise: out of wait tokens");
        }
        set_tokens(ids, count, 0, token);
        uint64_t value = 0;
        uint32_t result = 0;
        (void)ms_token_park_at(token, deadline == NO_TIME ? -1 : deadline, &value, &result);
        set_tokens(ids, count, token, 0);
        (void)ms_token_free(token);
        if (result == MS_WAIT_CANCELLED) {
            ms_cancelled();
        }
        const ptrdiff_t after = first_done(ids, count);
        if (after >= 0) {
            return after;
        }
        if (result == MS_WAIT_TIMEOUT) {
            return -1;
        }
    }
}

/* ---- sleeps and limits ---- */

MsPromise ms_promise_sleep(int64_t ns) {
    const MsPromise id = ms_promise_new();
    const size_t row = row_or_fault(id);
    const int64_t at = ms_sched_now() + (ns > 0 ? ns : 0);
    table.cold[row].deadline = at;
    ms_sched_arm((uint64_t)id, at);
    return id;
}

/* The wait of a readiness promise ran out: the continuation completes it, or it reads as MS_WAIT_TIMEOUT. */
static void readiness_timed_out(MsPromise id, size_t row) {
    leave_fd(id, row);
    MsPromiseRetry retry = table.cold[row].retry;
    table.cold[row].retry = NULL;
    if (retry != NULL) {
        (void)retry(id, table.cold[row].retry_state, MS_WAIT_TIMEOUT);
    }
    const ptrdiff_t again = row_of(id);
    if (again >= 0 && table.hot[again].state == STATE_PENDING) {
        ms_promise_io_done_int(id, MS_WAIT_TIMEOUT);
    }
}

static bool timer_live(uint64_t id, int64_t deadline) {
    const ptrdiff_t row = row_of((MsPromise)id);
    return row >= 0 && table.hot[row].state == STATE_PENDING &&
           (table.cold[row].deadline == deadline || table.cold[row].limit == deadline);
}

static void timer_fire(uint64_t id, int64_t deadline) {
    const MsPromise promise = (MsPromise)id;
    ptrdiff_t row = row_of(promise);
    if (row >= 0 && table.cold[row].limit == deadline) {
        table.hot[row].flags |= FLAG_TIMED_OUT;
        table.cold[row].limit = NO_TIME;
        stop(promise);
        row = row_of(promise);
    }
    if (row >= 0 && table.hot[row].state == STATE_PENDING && table.cold[row].deadline == deadline) {
        table.cold[row].deadline = NO_TIME;
        if (table.cold[row].fd >= 0) {
            readiness_timed_out(promise, (size_t)row);
        } else {
            ms_promise_io_done_unit(promise);
        }
    }
}

/* ---- descriptor readiness ---- */

static void arm_timeout(MsPromise id, size_t row, int64_t timeout_ns) {
    if (timeout_ns >= 0) {
        const int64_t at = ms_sched_now() + timeout_ns;
        table.cold[row].deadline = at;
        ms_sched_arm((uint64_t)id, at);
    }
}

MsPromise ms_promise_ready(int fd, uint32_t events, int64_t timeout_ns) {
    const MsPromise id = ms_promise_new();
    const int armed = ms_sched_fd_wait_begin((uint64_t)id, fd, events);
    if (armed == MS_POLL_FAILED) {
        ms_promise_drop(id);
        return -1;
    }
    if (armed == MS_POLL_ALWAYS) {
        ms_promise_io_done_int(id, events & (MS_WAIT_READ | MS_WAIT_WRITE));
        return id;
    }
    const size_t row = row_or_fault(id);
    table.cold[row].fd = fd;
    table.cold[row].events = events;
    arm_timeout(id, row, timeout_ns);
    return id;
}

bool ms_promise_io_on_ready(MsPromise id, int fd, uint32_t events, int64_t timeout_ns, MsPromiseRetry retry,
                            uintptr_t state) {
    const ptrdiff_t found = row_of(id);
    if (found < 0) {
        return false;
    }
    const int armed = ms_sched_fd_wait_begin((uint64_t)id, fd, events);
    if (armed == MS_POLL_FAILED) {
        return false;
    }
    if (armed == MS_POLL_ALWAYS) {
        (void)retry(id, state, events & (MS_WAIT_READ | MS_WAIT_WRITE));
        return true;
    }
    Cold *const cold = &table.cold[found];
    cold->fd = fd;
    cold->events = events;
    cold->retry = retry;
    cold->retry_state = state;
    arm_timeout(id, (size_t)found, timeout_ns);
    return true;
}

/* The poller reports `bits` for the descriptor `id` waits on: true when the promise is done with it. */
static bool fd_ready(uint64_t id, uint32_t bits) {
    const MsPromise promise = (MsPromise)id;
    ptrdiff_t found = row_of(promise);
    if (found < 0 || table.hot[found].state != STATE_PENDING) {
        return true;
    }
    const uint32_t wanted = bits & (table.cold[found].events | MS_WAIT_HUP);
    if (wanted == 0) {
        return false;
    }
    const MsPromiseRetry retry = table.cold[found].retry;
    if (retry != NULL && !retry(promise, table.cold[found].retry_state, wanted)) {
        return false;
    }
    found = row_of(promise);
    if (found >= 0) {
        table.cold[found].fd = -1; /* the scheduler removes the wait now */
        table.cold[found].retry = NULL;
    }
    if (retry == NULL) {
        ms_promise_io_done_int(promise, wanted);
    }
    return true;
}

void ms_promises_teardown(void) {
    ms_groups_teardown();
    ms_cancel_teardown();
    for (size_t row = 0; row < table.count; row++) {
        if (table.hot[row].state != STATE_FREE) {
            release_result(row);
            ms_fault_text_free(&table.cold[row].report);
        }
    }
    msrt_free(table.hot);
    msrt_free(table.cold);
    msrt_free(table.free_rows);
    table = (Table){0};
}

void ms_promise_hooks(MsSchedHooks *hooks) {
    hooks->end_started = end_started;
    hooks->timer_live = timer_live;
    hooks->timer_fire = timer_fire;
    hooks->fd_ready = fd_ready;
    ms_group_hooks(hooks);
    hooks->teardown = ms_promises_teardown;
}
