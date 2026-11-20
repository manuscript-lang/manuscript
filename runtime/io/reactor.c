/* reactor.c: the scheduler's descriptor poller on libuv (see reactor.h).
 *
 * Owns one loop per scheduler thread. Each watched descriptor has a row: a uv_poll_t that exists only while the
 * descriptor is watched, or until ms_io_forget when it was watched with MS_IO_BIT_KEEP. A watch is one-shot and
 * level-like: libuv reports readiness at the next pass, and the row stops itself once it has reported.
 * Callbacks only push completion events (ring.h) naming the descriptor; ms_io_wait pops them after the pass and
 * folds the events of one descriptor into the (descriptor, bits) the scheduler waits on. A readable row is a
 * MS_IO_READ event, a writable one MS_IO_WRITE (result 0), and an error or hang-up a MS_IO_READ event whose
 * result is the negative libuv status.
 */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include "reactor.h"
#include "ring.h"

#include <stdatomic.h>
#include <uv.h>

#include "ms_sys.h"

enum {
    EVENT_CAPACITY = 128, /* two events per ready descriptor; a callback needs room for both */
    EVENTS_PER_CALLBACK = 2,
    FIRST_TABLE_LENGTH = 64,
    NANOSECONDS_PER_MILLISECOND = 1000000,
};

typedef struct MsIoRow MsIoRow;

struct MsIoRow {
    uv_poll_t handle;
    MsIoRow *next_free; /* owned; links the free list, meaningful only while the row is on it */
    int fd;
    bool started; /* the handle is polling */
    bool keep;    /* survives its event until ms_io_forget */
};

struct MsIoReactor {
    uv_loop_t loop;
    uv_async_t wake_handle;
    uv_timer_t timer; /* ends a blocking pass where the system cannot sleep with nanosecond resolution */
    bool wake_open;
    bool timer_open;
    MsIoRow **rows; /* owned; by descriptor, null where none */
    size_t rows_length;
    MsIoRow *free_rows; /* owned; closed rows ready for reuse */
    MsIoRing *ring; /* owned */
    bool woken; /* a wake-up was consumed since the wait began */
};

_Static_assert(sizeof(MsIoReady) == 16, "MsIoReady is shared with poller.rs");
_Static_assert(sizeof(MsIoWatch) == sizeof(int), "MsIoWatch crosses the ABI as an int");

/* The reactor of the calling scheduler thread. */
static _Thread_local MsIoReactor *thread_reactor;
/* The main thread's reactor, for signal handlers. */
static _Atomic(MsIoReactor *) main_reactor;

static MsIoReactor *reactor_of(const uv_handle_t *handle) {
    return uv_loop_get_data(uv_handle_get_loop(handle));
}

static void on_wake(uv_async_t *handle) {
    reactor_of((const uv_handle_t *)handle)->woken = true;
}

static void on_timer(uv_timer_t *handle) {
    (void)handle;
}

static void on_row_closed(uv_handle_t *handle) {
    MsIoRow *row = uv_handle_get_data(handle);
    MsIoReactor *reactor = reactor_of(handle);
    row->next_free = reactor->free_rows;
    reactor->free_rows = row;
}

static void row_stop(MsIoRow *row) {
    if (row->started) {
        (void)uv_poll_stop(&row->handle);
        row->started = false;
    }
}

/* Ends a row's handle. The row's memory joins the free list when libuv has finished closing it. */
static void row_discard(MsIoReactor *reactor, MsIoRow *row) {
    row_stop(row);
    reactor->rows[row->fd] = NULL;
    uv_close((uv_handle_t *)&row->handle, on_row_closed);
}

/* The MS_IO_* bits of what libuv reported. An error counts as everything, hang-up included. */
static uint32_t readiness_bits(int status, int events) {
    if (status < 0) {
        return MS_IO_BIT_READ | MS_IO_BIT_WRITE | MS_IO_BIT_HUP;
    }
    uint32_t bits = 0;
    if ((events & (UV_READABLE | UV_DISCONNECT)) != 0) {
        bits |= MS_IO_BIT_READ;
    }
    if ((events & UV_WRITABLE) != 0) {
        bits |= MS_IO_BIT_WRITE;
    }
    return bits;
}

/* Pushes the events for one report. Room for all of them was checked by the caller. */
static void push_report(MsIoReactor *reactor, const MsIoRow *row, int status, uint32_t bits) {
    const uint64_t id = (uint64_t)row->fd;
    if (status < 0) {
        (void)ms_io_ring_push(reactor->ring, (MsIoEvent){.id = id, .result = status, .kind = MS_IO_READ});
        return;
    }
    if ((bits & MS_IO_BIT_READ) != 0) {
        (void)ms_io_ring_push(reactor->ring, (MsIoEvent){.id = id, .result = 0, .kind = MS_IO_READ});
    }
    if ((bits & MS_IO_BIT_WRITE) != 0) {
        (void)ms_io_ring_push(reactor->ring, (MsIoEvent){.id = id, .result = 0, .kind = MS_IO_WRITE});
    }
}

static void on_poll(uv_poll_t *handle, int status, int events) {
    MsIoRow *row = uv_handle_get_data((uv_handle_t *)handle);
    MsIoReactor *reactor = reactor_of((const uv_handle_t *)handle);
    if (ms_io_ring_length(reactor->ring) + EVENTS_PER_CALLBACK > EVENT_CAPACITY) {
        return; /* still armed: level-triggered, so the next pass reports it again */
    }
    const uint32_t bits = readiness_bits(status, events);
    row_stop(row);
    push_report(reactor, row, status, bits);
}

static void reactor_destroy(MsIoReactor *reactor) {
    for (size_t index = 0; index < reactor->rows_length; index++) {
        if (reactor->rows[index] != NULL) {
            row_discard(reactor, reactor->rows[index]);
        }
    }
    if (reactor->wake_open) {
        uv_close((uv_handle_t *)&reactor->wake_handle, NULL);
    }
    if (reactor->timer_open) {
        uv_close((uv_handle_t *)&reactor->timer, NULL);
    }
    while (uv_loop_close(&reactor->loop) == UV_EBUSY) {
        (void)uv_run(&reactor->loop, UV_RUN_NOWAIT);
    }
    for (MsIoRow *row = reactor->free_rows; row != NULL;) {
        MsIoRow *next = row->next_free;
        mssys_free(row);
        row = next;
    }
    mssys_free(reactor->rows);
    ms_io_ring_free(reactor->ring);
    mssys_free(reactor);
}

bool ms_io_open(bool is_main, MsIoReactor **reactor_out) {
    MsIoReactor *reactor = mssys_malloc(sizeof *reactor);
    if (reactor == NULL) {
        return false;
    }
    *reactor = (MsIoReactor){0};
    reactor->ring = ms_io_ring_new(EVENT_CAPACITY);
    if (reactor->ring == NULL || uv_loop_init(&reactor->loop) != 0) {
        ms_io_ring_free(reactor->ring);
        mssys_free(reactor);
        return false;
    }
    uv_loop_set_data(&reactor->loop, reactor);
    reactor->wake_open = uv_async_init(&reactor->loop, &reactor->wake_handle, on_wake) == 0;
    reactor->timer_open = uv_timer_init(&reactor->loop, &reactor->timer) == 0;
    if (!reactor->wake_open || !reactor->timer_open) {
        reactor_destroy(reactor);
        return false;
    }
    thread_reactor = reactor;
    if (is_main) {
        atomic_store(&main_reactor, reactor);
    }
    *reactor_out = reactor;
    return true;
}

void ms_io_close(bool is_main) {
    MsIoReactor *reactor = thread_reactor;
    if (reactor == NULL) {
        return;
    }
    if (is_main) {
        atomic_store(&main_reactor, NULL);
    }
    thread_reactor = NULL;
    reactor_destroy(reactor);
}

void ms_io_wake(MsIoReactor *reactor) {
    (void)uv_async_send(&reactor->wake_handle);
}

void ms_io_kick(void) {
    MsIoReactor *reactor = atomic_load(&main_reactor);
    if (reactor != NULL) {
        ms_io_wake(reactor);
    }
}

/* Makes room in the row table for descriptor `fd`. */
MS_NODISCARD static bool table_reserve(MsIoReactor *reactor, int fd) {
    const size_t index = (size_t)fd;
    if (index < reactor->rows_length) {
        return true;
    }
    size_t length = reactor->rows_length == 0 ? FIRST_TABLE_LENGTH : reactor->rows_length;
    while (length <= index) {
        if (!ms_size_mul(length, 2, &length)) {
            return false;
        }
    }
    size_t bytes = 0;
    if (!ms_size_mul(length, sizeof(MsIoRow *), &bytes)) {
        return false;
    }
    MsIoRow **grown = mssys_realloc(reactor->rows, bytes);
    if (grown == NULL) {
        return false;
    }
    for (size_t slot = reactor->rows_length; slot < length; slot++) {
        grown[slot] = NULL;
    }
    reactor->rows = grown;
    reactor->rows_length = length;
    return true;
}

/* A row for `fd` with its handle initialised, taken from the free list when it can be. */
static MsIoWatch row_open(MsIoReactor *reactor, int fd, MsIoRow **row_out) {
    MsIoRow *row = reactor->free_rows;
    if (row != NULL) {
        reactor->free_rows = row->next_free;
    } else {
        row = mssys_malloc(sizeof *row);
        if (row == NULL) {
            return MS_IO_WATCH_FAILED;
        }
    }
    *row = (MsIoRow){.fd = fd};
    /* uv_poll_init makes the descriptor non-blocking; the owner's choice is restored. */
    bool was_nonblocking = true;
    const bool known = mssys_fd_get_nonblocking(fd, &was_nonblocking);
    const int error = uv_poll_init(&reactor->loop, &row->handle, fd);
    if (error != 0) {
        row->next_free = reactor->free_rows;
        reactor->free_rows = row;
        /* A regular file or device never blocks; only a closed descriptor is a failure. */
        return error == UV_EBADF ? MS_IO_WATCH_FAILED : MS_IO_WATCH_ALWAYS;
    }
    if (known && !was_nonblocking) {
        (void)mssys_fd_set_nonblocking(fd, false);
    }
    uv_handle_set_data((uv_handle_t *)&row->handle, row);
    *row_out = row;
    return MS_IO_WATCH_ARMED;
}

/* libuv's interest for the bits of `events`; waiting on nothing watches for readability. */
static int interest_of(uint32_t events) {
    const bool writes = (events & MS_IO_BIT_WRITE) != 0;
    const bool reads = (events & MS_IO_BIT_READ) != 0 || !writes;
    return (reads ? UV_READABLE | UV_DISCONNECT : 0) | (writes ? UV_WRITABLE : 0);
}

MsIoWatch ms_io_watch(int fd, uint32_t events) {
    MsIoReactor *reactor = thread_reactor;
    if (reactor == NULL || fd < 0 || !table_reserve(reactor, fd)) {
        return MS_IO_WATCH_FAILED;
    }
    MsIoRow *row = reactor->rows[fd];
    if (row == NULL) {
        const MsIoWatch opened = row_open(reactor, fd, &row);
        if (opened != MS_IO_WATCH_ARMED) {
            return opened;
        }
        reactor->rows[fd] = row;
    }
    row->keep = (events & MS_IO_BIT_KEEP) != 0;
    if (uv_poll_start(&row->handle, interest_of(events), on_poll) != 0) {
        row_discard(reactor, row);
        return MS_IO_WATCH_FAILED;
    }
    row->started = true;
    return MS_IO_WATCH_ARMED;
}

static MsIoRow *row_find(const MsIoReactor *reactor, int fd) {
    if (fd < 0 || (size_t)fd >= reactor->rows_length) {
        return NULL;
    }
    return reactor->rows[fd];
}

void ms_io_unwatch(int fd) {
    MsIoReactor *reactor = thread_reactor;
    MsIoRow *row = reactor == NULL ? NULL : row_find(reactor, fd);
    if (row == NULL) {
        return;
    }
    if (row->keep) {
        row_stop(row);
    } else {
        row_discard(reactor, row);
    }
}

void ms_io_forget(int fd) {
    MsIoReactor *reactor = thread_reactor;
    MsIoRow *row = reactor == NULL ? NULL : row_find(reactor, fd);
    if (row != NULL) {
        row_discard(reactor, row);
    }
}

/* Blocks for at most `timeout_ns`, ending early for readiness or a wake-up. */
static void run_bounded(MsIoReactor *reactor, int64_t timeout_ns) {
    /* libuv adds new descriptors to the system poller only inside uv_run, so a pass that does not block comes
     * first: it registers them and collects what is already ready. */
    (void)uv_run(&reactor->loop, UV_RUN_NOWAIT);
    if (ms_io_ring_length(reactor->ring) > 0 || reactor->woken) {
        return;
    }
    if (mssys_fd_wait_readable(uv_backend_fd(&reactor->loop), timeout_ns)) {
        (void)uv_run(&reactor->loop, UV_RUN_NOWAIT);
        return;
    }
    const int64_t millis = (timeout_ns + NANOSECONDS_PER_MILLISECOND - 1) / NANOSECONDS_PER_MILLISECOND;
    (void)uv_timer_start(&reactor->timer, on_timer, (uint64_t)millis, 0);
    (void)uv_run(&reactor->loop, UV_RUN_ONCE);
    (void)uv_timer_stop(&reactor->timer);
}

/* Moves queued events into `out`, one entry per descriptor: the events a callback pushes for one descriptor are
 * adjacent, so each is folded into the previous entry when it names the same descriptor. */
static size_t drain_events(MsIoReactor *reactor, MsIoReady *out, size_t capacity) {
    size_t count = 0;
    MsIoEvent event;
    while (count < capacity && ms_io_ring_pop(reactor->ring, &event)) {
        uint32_t bits = MS_IO_BIT_READ;
        if (event.result < 0) {
            bits = MS_IO_BIT_READ | MS_IO_BIT_WRITE | MS_IO_BIT_HUP;
        } else if (event.kind == MS_IO_WRITE) {
            bits = MS_IO_BIT_WRITE;
        }
        if (count > 0 && out[count - 1].fd == (uintptr_t)event.id) {
            out[count - 1].bits |= bits;
            continue;
        }
        out[count] = (MsIoReady){.fd = (uintptr_t)event.id, .bits = bits};
        count++;
    }
    return count;
}

bool ms_io_wait(int64_t timeout_ns, MsIoReady *out, size_t capacity, size_t *count) {
    MsIoReactor *reactor = thread_reactor;
    if (reactor == NULL) {
        return false;
    }
    reactor->woken = false;
    if (timeout_ns == 0 || ms_io_ring_length(reactor->ring) > 0) {
        (void)uv_run(&reactor->loop, UV_RUN_NOWAIT); /* events left from an earlier wait are ready now */
    } else if (timeout_ns > 0) {
        run_bounded(reactor, timeout_ns);
    } else {
        (void)uv_run(&reactor->loop, UV_RUN_ONCE);
    }
    *count = drain_events(reactor, out, capacity);
    return true;
}
