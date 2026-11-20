/* reactor.c: the scheduler's descriptor poller on libuv (see reactor.h).
 *
 * Owns one loop per scheduler thread. Each watched descriptor has a row: a uv_poll_t that exists only while the
 * descriptor is watched, or until ms_io_forget when it was watched with MS_IO_KEEP. A watch is one-shot and
 * level-like: libuv reports readiness at the next pass, and the row stops itself once it has reported.
 * Callbacks only fill the ready ring; ms_io_wait hands the ring to the scheduler after the pass.
 */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include "reactor.h"

#include <stdatomic.h>
#include <uv.h>

#include "ms_sys.h"

enum {
    READY_RING_CAPACITY = 64,
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
    MsIoReady ring[READY_RING_CAPACITY];
    size_t ring_length;
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
        return MS_IO_READ | MS_IO_WRITE | MS_IO_HUP;
    }
    uint32_t bits = 0;
    if ((events & (UV_READABLE | UV_DISCONNECT)) != 0) {
        bits |= MS_IO_READ;
    }
    if ((events & UV_WRITABLE) != 0) {
        bits |= MS_IO_WRITE;
    }
    return bits;
}

static void on_poll(uv_poll_t *handle, int status, int events) {
    MsIoRow *row = uv_handle_get_data((uv_handle_t *)handle);
    MsIoReactor *reactor = reactor_of((const uv_handle_t *)handle);
    if (reactor->ring_length == READY_RING_CAPACITY) {
        return; /* still armed: level-triggered, so the next pass reports it again */
    }
    const uint32_t bits = readiness_bits(status, events);
    row_stop(row);
    if (bits != 0) {
        reactor->ring[reactor->ring_length] = (MsIoReady){.fd = (uintptr_t)row->fd, .bits = bits};
        reactor->ring_length++;
    }
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
    mssys_free(reactor);
}

bool ms_io_open(bool is_main, MsIoReactor **reactor_out) {
    MsIoReactor *reactor = mssys_malloc(sizeof *reactor);
    if (reactor == NULL) {
        return false;
    }
    *reactor = (MsIoReactor){0};
    if (uv_loop_init(&reactor->loop) != 0) {
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
    const bool writes = (events & MS_IO_WRITE) != 0;
    const bool reads = (events & MS_IO_READ) != 0 || !writes;
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
    row->keep = (events & MS_IO_KEEP) != 0;
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
    if (reactor->ring_length > 0 || reactor->woken) {
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

bool ms_io_wait(int64_t timeout_ns, MsIoReady *out, size_t capacity, size_t *count) {
    MsIoReactor *reactor = thread_reactor;
    if (reactor == NULL) {
        return false;
    }
    reactor->ring_length = 0;
    reactor->woken = false;
    if (timeout_ns == 0) {
        (void)uv_run(&reactor->loop, UV_RUN_NOWAIT);
    } else if (timeout_ns > 0) {
        run_bounded(reactor, timeout_ns);
    } else {
        (void)uv_run(&reactor->loop, UV_RUN_ONCE);
    }
    const size_t ready = reactor->ring_length < capacity ? reactor->ring_length : capacity;
    for (size_t index = 0; index < ready; index++) {
        out[index] = reactor->ring[index];
    }
    reactor->ring_length = 0;
    *count = ready;
    return true;
}
