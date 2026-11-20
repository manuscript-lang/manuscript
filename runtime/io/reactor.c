#define _GNU_SOURCE
#include "reactor.h"

#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>
#if defined(__linux__)
#include <poll.h>
#include <time.h>
#endif

#define RING 64

typedef struct row {
    uv_poll_t h;
    struct row *next_free;
    int fd;
    uint8_t started;
    uint8_t keep;
} row;

typedef struct {
    uv_loop_t loop;
    uv_async_t wake;
    uv_timer_t timer;
    row **rows; /* by descriptor */
    size_t rows_len;
    row *free_rows;
    msio_ready ring[RING];
    size_t ring_len;
    size_t open_handles; /* closing handles not yet finished */
    int woken;           /* a wake-up was consumed since the wait began */
} reactor;

static _Thread_local reactor *self;
static _Atomic(uv_async_t *) main_wake;

static void on_wake(uv_async_t *a) { (void)a; self->woken = 1; }
#if !defined(__linux__)
static void noop_timer(uv_timer_t *t) { (void)t; }
#endif

static void row_closed(uv_handle_t *h) {
    row *r = (row *)h;
    reactor *s = self;
    r->next_free = s->free_rows;
    s->free_rows = r;
    s->open_handles--;
}

static void stop_row(row *r) {
    if (r->started) {
        uv_poll_stop(&r->h);
        r->started = 0;
    }
}

/* Ends a row's handle; its memory returns to the free list from the close callback. */
static void drop_row(reactor *s, row *r) {
    stop_row(r);
    s->rows[r->fd] = NULL;
    s->open_handles++;
    uv_close((uv_handle_t *)&r->h, row_closed);
}

static void on_poll(uv_poll_t *h, int status, int events) {
    row *r = (row *)h;
    reactor *s = self;
    if (s->ring_len == RING) return; /* stays armed: level-triggered, reported next turn */
    uint32_t bits = 0;
    if (status < 0) {
        bits = MSIO_READ | MSIO_WRITE | MSIO_HUP;
    } else {
        if (events & UV_READABLE) bits |= MSIO_READ;
        if (events & UV_WRITABLE) bits |= MSIO_WRITE;
        if (events & UV_DISCONNECT) bits |= MSIO_READ;
    }
    stop_row(r);
    if (bits == 0) return;
    s->ring[s->ring_len].fd = (uintptr_t)r->fd;
    s->ring[s->ring_len].bits = bits;
    s->ring_len++;
}

void *msio_open(int is_main) {
    reactor *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    if (uv_loop_init(&s->loop) != 0) { free(s); return NULL; }
    if (uv_async_init(&s->loop, &s->wake, on_wake) != 0 ||
        uv_timer_init(&s->loop, &s->timer) != 0) {
        uv_loop_close(&s->loop);
        free(s);
        return NULL;
    }
    self = s;
    if (is_main) atomic_store(&main_wake, &s->wake);
    return &s->wake;
}

static void close_cb_noop(uv_handle_t *h) { (void)h; }

void msio_close(int is_main) {
    reactor *s = self;
    if (!s) return;
    if (is_main) atomic_store(&main_wake, NULL);
    for (size_t i = 0; i < s->rows_len; i++)
        if (s->rows[i]) drop_row(s, s->rows[i]);
    uv_close((uv_handle_t *)&s->wake, close_cb_noop);
    uv_close((uv_handle_t *)&s->timer, close_cb_noop);
    while (uv_loop_close(&s->loop) == UV_EBUSY) uv_run(&s->loop, UV_RUN_NOWAIT);
    for (row *r = s->free_rows; r;) { row *n = r->next_free; free(r); r = n; }
    free(s->rows);
    free(s);
    self = NULL;
}

void msio_wake(void *wake) { uv_async_send((uv_async_t *)wake); }

void msio_kick(void) {
    uv_async_t *a = atomic_load(&main_wake);
    if (a) uv_async_send(a);
}

static row *new_row(reactor *s, int fd) {
    if ((size_t)fd >= s->rows_len) {
        size_t n = s->rows_len ? s->rows_len : 64;
        while (n <= (size_t)fd) n *= 2;
        row **grown = realloc(s->rows, n * sizeof *grown);
        if (!grown) return NULL;
        memset(grown + s->rows_len, 0, (n - s->rows_len) * sizeof *grown);
        s->rows = grown;
        s->rows_len = n;
    }
    row *r = s->free_rows;
    if (r) s->free_rows = r->next_free; else r = malloc(sizeof *r);
    if (!r) return NULL;
    memset(r, 0, sizeof *r);
    r->fd = fd;
    return r;
}

int msio_watch(int fd, uint32_t events) {
    reactor *s = self;
    if (!s || fd < 0) return MSIO_FAILED;
    int want = 0;
    if (events & MSIO_READ) want |= UV_READABLE;
    if (events & MSIO_WRITE) want |= UV_WRITABLE;
    if (!(events & MSIO_WRITE)) want |= UV_READABLE;
    if (want & UV_READABLE) want |= UV_DISCONNECT;
    row *r = (size_t)fd < s->rows_len ? s->rows[fd] : NULL;
    if (!r) {
        r = new_row(s, fd);
        if (!r) return MSIO_FAILED;
        /* uv_poll_init makes the descriptor non-blocking; restore what the owner chose. */
        int flags = fcntl(fd, F_GETFL);
        int err = uv_poll_init(&s->loop, &r->h, fd);
        if (err == 0 && flags >= 0 && !(flags & O_NONBLOCK)) fcntl(fd, F_SETFL, flags);
        if (err != 0) {
            r->next_free = s->free_rows;
            s->free_rows = r;
            if (err == UV_EBADF) return MSIO_FAILED;
            return MSIO_ALWAYS; /* a regular file or device never blocks */
        }
        s->rows[fd] = r;
    }
    r->keep = (events & MSIO_KEEP) != 0;
    int err = uv_poll_start(&r->h, want, on_poll);
    if (err != 0) {
        drop_row(s, r);
        return err == UV_EBADF ? MSIO_FAILED : MSIO_ALWAYS;
    }
    r->started = 1;
    return MSIO_ARMED;
}

void msio_unwatch(int fd) {
    reactor *s = self;
    if (!s || (size_t)fd >= s->rows_len) return;
    row *r = s->rows[fd];
    if (!r) return;
    if (r->keep) stop_row(r); else drop_row(s, r);
}

void msio_forget(int fd) {
    reactor *s = self;
    if (!s || (size_t)fd >= s->rows_len) return;
    row *r = s->rows[fd];
    if (r) drop_row(s, r);
}

long msio_wait(int64_t timeout_ns, msio_ready *out, size_t cap) {
    reactor *s = self;
    if (!s) return -1;
    s->ring_len = 0;
    s->woken = 0;
    uv_run_mode mode = UV_RUN_ONCE;
    if (timeout_ns == 0) {
        mode = UV_RUN_NOWAIT;
    } else if (timeout_ns > 0) {
#if defined(__linux__)
        /* libuv adds new descriptors to epoll inside uv_run, so a pass without blocking registers them and
         * collects what is ready; only then may the sleep watch the epoll descriptor, which takes a
         * timespec where epoll_wait rounds up to whole milliseconds. */
        uv_run(&s->loop, UV_RUN_NOWAIT);
        /* A consumed wake-up ends the wait too: the scheduler must look for mail again before sleeping. */
        if (s->ring_len == 0 && !s->woken) {
            struct pollfd p = {.fd = uv_backend_fd(&s->loop), .events = POLLIN};
            struct timespec ts = {.tv_sec = timeout_ns / 1000000000, .tv_nsec = timeout_ns % 1000000000};
            ppoll(&p, 1, &ts, NULL);
            uv_run(&s->loop, UV_RUN_NOWAIT);
        }
        mode = UV_RUN_DEFAULT; /* unused */
        goto done;
#else
        uv_timer_start(&s->timer, noop_timer, (timeout_ns + 999999) / 1000000, 0);
#endif
    }
    uv_run(&s->loop, mode);
#if !defined(__linux__)
    if (timeout_ns > 0) uv_timer_stop(&s->timer);
#endif
#if defined(__linux__)
done:;
#endif
    size_t n = s->ring_len < cap ? s->ring_len : cap;
    memcpy(out, s->ring, n * sizeof *out);
    s->ring_len = 0;
    return (long)n;
}
