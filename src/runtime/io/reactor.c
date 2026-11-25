/* reactor.c: the scheduler's descriptor poller on libuv (see reactor.h).
 *
 * Owns one loop per scheduler thread. Each watched descriptor has a row: a uv_poll_t that exists only while the
 * descriptor is watched, or until ms_io_forget when it was watched with MS_IO_BIT_KEEP. A watch is one-shot and
 * level-like: libuv reports readiness at the next pass, and the row stops itself once it has reported. Callbacks
 * only push events (ring.h) naming the descriptor; ms_io_wait pops them after the pass and folds the events of one
 * descriptor into the (descriptor, bits) the scheduler waits on. A readable row is a MS_IO_READ event, a writable
 * one MS_IO_WRITE (result 0), and an error or hang-up a MS_IO_READ event whose result is the negative libuv status.
 */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <stdatomic.h>

#include "runtime/io/reactor.h"

#include "base/alloc.h"
#include "base/list.h"
#include "runtime/io/edge.h"
#include "runtime/io/reactor_internal.h"
#include "runtime/io/refused.h"
#include "runtime/sys/sys.h"

enum {
  EVENT_CAPACITY = 128, /* two events per ready descriptor; a callback needs room for both */
  EVENTS_PER_CALLBACK = 2,
  FIRST_TABLE_LENGTH = 64,
  NANOSECONDS_PER_MILLISECOND = 1000000,
};

typedef struct MsIoRow MsIoRow;

struct MsIoRow {
  uv_poll_t handle;   /* unused when `polled` */
  bool polled;        /* libuv refused the descriptor (a FIFO on macOS): the refused-descriptor thread watches it */
  bool writes;        /* what that thread waits for */
  MsIoRow *next_free; /* links the free list, meaningful only while the row is on it */
  int fd;
  bool started; /* the handle is polling */
  bool keep;    /* survives its event until ms_io_forget */
};

MS_LIST_DEFINE(RowTable, row_table, MsIoRow *)

struct MsIoReactor {
  uv_loop_t loop;
  uv_async_t wake_handle;
  MsIoRefused *refused; /* watches the descriptors libuv refuses, started with the first */
  uv_timer_t timer;     /* ends a blocking pass where the system cannot sleep with nanosecond resolution */
  bool wake_open;
  bool timer_open;
  RowTable rows;        /* by descriptor, NULL where none */
  MsIoRow *free_rows;   /* closed rows ready for reuse */
  MsIoRing *ring;        /* readiness of watched descriptors */
  MsIoRing *completions; /* finished work and resolutions */
  uint32_t pending;      /* submitted completions not yet pushed */
  MsIoCompletionSink sink; /* receives completions in ms_io_wait, or NULL */
  bool woken;            /* a wake-up was consumed since the wait began */
  void *platform;        /* owned by the platform file, NULL when it keeps none */
  MsEdge *edge;          /* edge-triggered registrations, opened with the first */
  uint32_t edge_turns;   /* passes that took edges since the loop last ran */
};

_Static_assert(sizeof(MsIoWatch) == sizeof(int), "MsIoWatch crosses the ABI as an int");

/* The reactor of the calling scheduler thread. */
static _Thread_local MsIoReactor *thread_reactor;
/* The main thread's reactor, for signal handlers. */
static _Atomic(MsIoReactor *) main_reactor;

uv_loop_t *ms_io_reactor_loop(MsIoReactor *reactor) { return &reactor->loop; }

uv_async_t *ms_io_reactor_wake_handle(MsIoReactor *reactor) { return &reactor->wake_handle; }

bool ms_io_reactor_push(MsIoReactor *reactor, MsIoEvent event) { return ms_io_ring_push(reactor->ring, event); }

bool ms_io_reactor_pending(const MsIoReactor *reactor) {
  return ms_io_ring_length(reactor->ring) > 0 || reactor->woken;
}

MsIoReactor *ms_io_reactor_current(void) { return thread_reactor; }

void *ms_io_reactor_platform(const MsIoReactor *reactor) { return reactor->platform; }

void ms_io_reactor_set_platform(MsIoReactor *reactor, void *platform) { reactor->platform = platform; }

static MsIoReactor *reactor_of(const uv_handle_t *handle) { return uv_loop_get_data(uv_handle_get_loop(handle)); }

static void on_wake(uv_async_t *handle) { reactor_of((const uv_handle_t *)handle)->woken = true; }

static void on_timer(uv_timer_t *handle) { (void)handle; }

static void on_row_closed(uv_handle_t *handle) {
  MsIoRow *row = uv_handle_get_data(handle);
  MsIoReactor *reactor = reactor_of(handle);
  row->next_free = reactor->free_rows;
  reactor->free_rows = row;
}

static void row_stop(MsIoReactor *reactor, MsIoRow *row) {
  if (!row->started) {
    return;
  }
  if (row->polled) {
    ms_io_refused_remove(reactor->refused, row->fd);
  } else {
    (void)uv_poll_stop(&row->handle);
  }
  row->started = false;
}

/* Ends a row's handle. The row's memory joins the free list when libuv has finished closing it; a row without a
 * handle joins it now. */
static void row_discard(MsIoReactor *reactor, MsIoRow *row) {
  row_stop(reactor, row);
  reactor->rows.ptr[row->fd] = NULL;
  if (row->polled) {
    row->next_free = reactor->free_rows;
    reactor->free_rows = row;
    return;
  }
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

static MsIoRow *row_find(const MsIoReactor *reactor, int fd) {
  if (fd < 0 || (size_t)fd >= reactor->rows.len) {
    return NULL;
  }
  return reactor->rows.ptr[fd];
}

/* The refused-descriptor thread found `fd` ready. A watch ended or replaced since then is stale and dropped. */
static bool on_refused_ready(void *context, int fd) {
  MsIoReactor *reactor = context;
  MsIoRow *row = row_find(reactor, fd);
  if (row == NULL || !row->polled || !row->started) {
    return true;
  }
  if (ms_io_ring_length(reactor->ring) + EVENTS_PER_CALLBACK > EVENT_CAPACITY) {
    return false;
  }
  bool ready = true;
  if (ms_sys_fd_ready(fd, row->writes, &ready) && !ready) {
    ms_io_refused_add(reactor->refused, fd, row->writes);
    return true; /* the descriptor was drained by someone else since: wait again */
  }
  row->started = false; /* the thread dropped the watch when it reported */
  push_report(reactor, row, 0, row->writes ? MS_IO_BIT_WRITE : MS_IO_BIT_READ);
  return true;
}

static void on_poll(uv_poll_t *handle, int status, int events) {
  MsIoRow *row = uv_handle_get_data((uv_handle_t *)handle);
  MsIoReactor *reactor = reactor_of((const uv_handle_t *)handle);
  if (ms_io_ring_length(reactor->ring) + EVENTS_PER_CALLBACK > EVENT_CAPACITY) {
    return; /* still armed: level-triggered, so the next pass reports it again */
  }
  const uint32_t bits = readiness_bits(status, events);
  row_stop(reactor, row);
  push_report(reactor, row, status, bits);
}

static void reactor_destroy(MsIoReactor *reactor) {
  ms_io_platform_close(reactor);
  if (reactor->edge != NULL) {
    ms_edge_close(reactor->edge);
  }
  for (size_t index = 0; index < reactor->rows.len; index++) {
    if (reactor->rows.ptr[index] != NULL) {
      row_discard(reactor, reactor->rows.ptr[index]);
    }
  }
  if (reactor->refused != NULL) {
    ms_io_refused_close(reactor->refused);
  }
  if (reactor->wake_open) {
    uv_close((uv_handle_t *)&reactor->wake_handle, NULL);
  }
  if (reactor->timer_open) {
    uv_close((uv_handle_t *)&reactor->timer, NULL);
  }
  while (uv_loop_close(&reactor->loop) == UV_EBUSY) {
    (void)uv_run(&reactor->loop, UV_RUN_DEFAULT); /* waits for work still on the thread pool */
  }
  for (MsIoRow *row = reactor->free_rows; row != NULL;) {
    MsIoRow *next = row->next_free;
    ms_free(row);
    row = next;
  }
  row_table_free(&reactor->rows);
  ms_io_ring_free(reactor->ring);
  ms_io_ring_free(reactor->completions);
  ms_free(reactor);
}

bool ms_io_open(bool is_main, MsIoReactor **reactor_out) {
  MsIoReactor *reactor = ms_alloc_zeroed(sizeof *reactor);
  reactor->ring = ms_io_ring_new(EVENT_CAPACITY);
  reactor->completions = ms_io_ring_new(MS_IO_MAX_COMPLETIONS);
  if (uv_loop_init(&reactor->loop) != 0) {
    ms_io_ring_free(reactor->ring);
    ms_io_ring_free(reactor->completions);
    ms_free(reactor);
    return false;
  }
  uv_loop_set_data(&reactor->loop, reactor);
  reactor->wake_open = uv_async_init(&reactor->loop, &reactor->wake_handle, on_wake) == 0;
  reactor->timer_open = uv_timer_init(&reactor->loop, &reactor->timer) == 0;
  if (!reactor->wake_open || !reactor->timer_open || !ms_io_platform_open(reactor)) {
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

void ms_io_wake(MsIoReactor *reactor) { (void)uv_async_send(&reactor->wake_handle); }

void ms_io_kick(void) {
  MsIoReactor *reactor = atomic_load(&main_reactor);
  if (reactor != NULL) {
    ms_io_wake(reactor);
  }
}

/* Makes room in the row table for descriptor `fd`. */
static void table_reserve(MsIoReactor *reactor, int fd) {
  const size_t index = (size_t)fd;
  size_t length = reactor->rows.len;
  if (index < length) {
    return;
  }
  if (length == 0) {
    length = FIRST_TABLE_LENGTH;
  }
  while (length <= index) {
    length *= 2;
  }
  const size_t added = length - reactor->rows.len;
  MsIoRow **fresh = row_table_extend(&reactor->rows, added);
  for (size_t slot = 0; slot < added; slot++) {
    fresh[slot] = NULL;
  }
}

/* Memory for a row, from the free list when it can be. */
static MsIoRow *row_take(MsIoReactor *reactor) {
  MsIoRow *row = reactor->free_rows;
  if (row != NULL) {
    reactor->free_rows = row->next_free;
    return row;
  }
  return ms_alloc(sizeof *row);
}

/* A row for `fd` with its handle initialised, taken from the free list when it can be. */
static MsIoWatch row_open(MsIoReactor *reactor, int fd, MsIoRow **row_out) {
  MsIoRow *row = row_take(reactor);
  *row = (MsIoRow){.fd = fd};
  /* uv_poll_init makes the descriptor non-blocking; the owner's choice is restored. */
  bool was_nonblocking = true;
  const bool known = ms_sys_fd_get_nonblocking(fd, &was_nonblocking);
  const int error = ms_io_platform_poll_init(&reactor->loop, &row->handle, fd);
  if (error != 0) {
    row->next_free = reactor->free_rows;
    reactor->free_rows = row;
    return error == UV_EBADF ? MS_IO_WATCH_FAILED : MS_IO_WATCH_ALWAYS; /* refused; see watch_refused */
  }
  if (known && !was_nonblocking) {
    (void)ms_sys_fd_set_nonblocking(fd, false);
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

/* A descriptor libuv refuses is a file, directory or device, which never blocks, or a named pipe, which kqueue cannot
 * watch reliably. Only a named pipe can wait: ready now (or unanswerable) is ready at once, anything else goes to the
 * refused-descriptor thread (refused.c), which blocks in poll(2) until it is. */
static MsIoWatch watch_refused(MsIoReactor *reactor, int fd, uint32_t events) {
  if (uv_guess_handle(fd) != UV_NAMED_PIPE) {
    return MS_IO_WATCH_ALWAYS; /* a file, directory or device never blocks */
  }
  const bool writes = (events & MS_IO_BIT_WRITE) != 0 && (events & MS_IO_BIT_READ) == 0;
  bool ready = true;
  if (!ms_sys_fd_ready(fd, writes, &ready) || ready) {
    return MS_IO_WATCH_ALWAYS;
  }
  if (reactor->refused == NULL) {
    reactor->refused = ms_io_refused_open(&reactor->loop, on_refused_ready, reactor);
    if (reactor->refused == NULL) {
      return MS_IO_WATCH_FAILED;
    }
  }
  MsIoRow *row = reactor->rows.ptr[fd];
  if (row == NULL) {
    row = row_take(reactor);
    *row = (MsIoRow){.fd = fd, .polled = true};
    reactor->rows.ptr[fd] = row;
  }
  row->writes = writes;
  row->keep = (events & MS_IO_BIT_KEEP) != 0;
  ms_io_refused_add(reactor->refused, fd, writes);
  row->started = true;
  return MS_IO_WATCH_ARMED;
}

/* An edge wait: the interest is recorded and the next edge of the registration reports it. */
static MsIoWatch watch_edge(MsIoReactor *reactor, int fd, uint32_t events) {
  const uint32_t bits = events & (MS_IO_BIT_READ | MS_IO_BIT_WRITE);
  if (reactor->edge == NULL || !ms_edge_arm(reactor->edge, fd, bits != 0 ? bits : MS_IO_BIT_READ, reactor->ring)) {
    return MS_IO_WATCH_FAILED;
  }
  return MS_IO_WATCH_ARMED;
}

bool ms_io_edge_supported(void) { return ms_edge_supported() && thread_reactor != NULL; }

bool ms_io_edge_reset(int fd, uint64_t cookie, uint32_t bits) {
  MsIoReactor *reactor = thread_reactor;
  if (reactor == NULL || fd < 0 || !ms_edge_supported()) {
    return false;
  }
  if (reactor->edge == NULL) {
    reactor->edge = ms_edge_open(&reactor->loop, reactor->ring);
    if (reactor->edge == NULL) {
      return false;
    }
  }
  return ms_edge_reset(reactor->edge, fd, cookie, bits);
}

bool ms_io_edge_ready(int fd, uint32_t bits) {
  MsIoReactor *reactor = thread_reactor;
  return reactor != NULL && reactor->edge != NULL && ms_edge_ready(reactor->edge, fd, bits);
}

MsIoWatch ms_io_watch(int fd, uint32_t events) {
  MsIoReactor *reactor = thread_reactor;
  if (reactor == NULL || fd < 0) {
    return MS_IO_WATCH_FAILED;
  }
  if ((events & MS_IO_BIT_EDGE) != 0) {
    return watch_edge(reactor, fd, events);
  }
  table_reserve(reactor, fd);
  if (ms_io_platform_owns(reactor, (uintptr_t)fd)) {
    return MS_IO_WATCH_ARMED; /* an object reports through its own events */
  }
  MsIoRow *row = reactor->rows.ptr[fd];
  if (row != NULL && row->polled) {
    return watch_refused(reactor, fd, events);
  }
  if (row == NULL) {
    const MsIoWatch opened = row_open(reactor, fd, &row);
    if (opened == MS_IO_WATCH_ALWAYS) {
      return watch_refused(reactor, fd, events);
    }
    if (opened != MS_IO_WATCH_ARMED) {
      return opened;
    }
    reactor->rows.ptr[fd] = row;
  }
  row->keep = (events & MS_IO_BIT_KEEP) != 0;
  if (uv_poll_start(&row->handle, interest_of(events), on_poll) != 0) {
    row_discard(reactor, row);
    return MS_IO_WATCH_FAILED;
  }
  row->started = true;
  return MS_IO_WATCH_ARMED;
}

void ms_io_unwatch(int fd) {
  MsIoReactor *reactor = thread_reactor;
  if (reactor != NULL && reactor->edge != NULL) {
    ms_edge_disarm(reactor->edge, fd);
  }
  MsIoRow *row = reactor == NULL ? NULL : row_find(reactor, fd);
  if (row == NULL) {
    return;
  }
  if (row->keep) {
    row_stop(reactor, row);
  } else {
    row_discard(reactor, row);
  }
}

void ms_io_forget(int fd) {
  MsIoReactor *reactor = thread_reactor;
  if (reactor != NULL && reactor->edge != NULL) {
    ms_edge_forget(reactor->edge, fd);
  }
  MsIoRow *row = reactor == NULL ? NULL : row_find(reactor, fd);
  if (row != NULL) {
    row_discard(reactor, row);
  }
}

/* Blocks for at most `timeout_ns`, ending early for readiness or a wake-up. */
static void run_bounded(MsIoReactor *reactor, int64_t timeout_ns) {
  /* libuv adds new descriptors to the system poller only inside uv_run, so a pass that does not block comes first:
   * it registers them and collects what is already ready. */
  (void)uv_run(&reactor->loop, UV_RUN_NOWAIT);
  if (ms_io_ring_length(reactor->ring) > 0 || ms_io_ring_length(reactor->completions) > 0 || reactor->woken) {
    return;
  }
  if (ms_io_platform_wait(reactor, timeout_ns)) {
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

/* Hands every queued completion to the sink, outside any libuv callback. */
static void deliver_completions(MsIoReactor *reactor) {
  MsIoEvent event;
  while (reactor->sink != NULL && ms_io_ring_pop(reactor->completions, &event)) {
    reactor->sink(event.id, event.result, event.kind);
  }
}

bool ms_io_wait(int64_t timeout_ns, MsIoReady *out, size_t capacity, size_t *count) {
  MsIoReactor *reactor = thread_reactor;
  if (reactor == NULL) {
    return false;
  }
  reactor->woken = false;
  ms_io_platform_flush(reactor);
  if (reactor->edge != NULL && ms_edge_drain(reactor->edge, reactor->ring) > 0 && (++reactor->edge_turns & 7) != 0) {
    /* Edges are in: the loop's own events (timers, completions, wake-ups) wait for at most seven such passes. */
    *count = drain_events(reactor, out, capacity);
    deliver_completions(reactor);
    return true;
  }
  if (timeout_ns == 0 || ms_io_ring_length(reactor->ring) > 0 || ms_io_ring_length(reactor->completions) > 0) {
    (void)uv_run(&reactor->loop, UV_RUN_NOWAIT); /* events left from an earlier wait are ready now */
  } else if (timeout_ns > 0) {
    run_bounded(reactor, timeout_ns);
  } else {
    (void)uv_run(&reactor->loop, UV_RUN_ONCE);
  }
  *count = drain_events(reactor, out, capacity);
  deliver_completions(reactor);
  return true;
}

/* Reserves room for one completion; false when MS_IO_MAX_COMPLETIONS are outstanding. */
static bool completion_reserve(MsIoReactor *reactor) {
  if (reactor->pending + ms_io_ring_length(reactor->completions) >= MS_IO_MAX_COMPLETIONS) {
    return false;
  }
  reactor->pending++;
  return true;
}

/* Ends a reserved completion. The reservation guarantees the ring has room. */
static void completion_push(MsIoReactor *reactor, MsIoEvent event) {
  reactor->pending--;
  (void)ms_io_ring_push(reactor->completions, event);
}

typedef struct MsIoWorkRequest {
  uv_work_t request;
  MsIoWorkFn function;
  void *argument;
  uint64_t id;
  int32_t result;
} MsIoWorkRequest;

static void on_work(uv_work_t *request) {
  MsIoWorkRequest *work = request->data;
  work->result = work->function(work->argument);
}

static void on_work_done(uv_work_t *request, int status) {
  MsIoWorkRequest *work = request->data;
  MsIoReactor *reactor = uv_loop_get_data(request->loop);
  const int32_t result = status < 0 ? status : work->result;
  completion_push(reactor, (MsIoEvent){.id = work->id, .result = result, .kind = MS_IO_WORK});
  ms_free(work);
}

bool ms_io_work(MsIoWorkFn work, void *argument, uint64_t id) {
  MsIoReactor *reactor = thread_reactor;
  if (reactor == NULL || !completion_reserve(reactor)) {
    return false;
  }
  MsIoWorkRequest *request = ms_alloc(sizeof *request);
  *request = (MsIoWorkRequest){.function = work, .argument = argument, .id = id};
  request->request.data = request;
  if (uv_queue_work(&reactor->loop, &request->request, on_work, on_work_done) != 0) {
    reactor->pending--;
    ms_free(request);
    return false;
  }
  return true;
}

struct MsIoAddresses {
  uv_getaddrinfo_t request;
  uint64_t id;
  bool finished;  /* libuv has ended the request: its completion is pushed */
  bool abandoned; /* the caller gave up before that; the callback releases the record */
};

static void on_resolved(uv_getaddrinfo_t *request, int status, struct addrinfo *list) {
  (void)list; /* stays in request->addrinfo until ms_io_addresses_free */
  MsIoAddresses *addresses = request->data;
  MsIoReactor *reactor = uv_loop_get_data(request->loop);
  addresses->finished = true;
  if (addresses->abandoned) {
    reactor->pending--;
    ms_io_addresses_free(addresses);
    return;
  }
  completion_push(reactor, (MsIoEvent){.id = addresses->id, .result = status, .kind = MS_IO_RESOLVE});
}

bool ms_io_resolve(const char *host, const char *service, uint64_t id, MsIoAddresses **out) {
  MsIoReactor *reactor = thread_reactor;
  if (reactor == NULL || !completion_reserve(reactor)) {
    return false;
  }
  MsIoAddresses *addresses = ms_alloc(sizeof *addresses);
  *addresses = (MsIoAddresses){.id = id};
  addresses->request.data = addresses;
  const struct addrinfo hints = {.ai_socktype = SOCK_STREAM};
  if (uv_getaddrinfo(&reactor->loop, &addresses->request, on_resolved, host, service, &hints) != 0) {
    reactor->pending--;
    ms_free(addresses);
    return false;
  }
  *out = addresses;
  return true;
}

void ms_io_addresses_free(MsIoAddresses *addresses) {
  uv_freeaddrinfo(addresses->request.addrinfo);
  ms_free(addresses);
}

void ms_io_set_completion_sink(MsIoCompletionSink sink) {
  MsIoReactor *reactor = thread_reactor;
  if (reactor != NULL) {
    reactor->sink = sink;
  }
}

bool ms_io_completion(MsIoEvent *event) {
  MsIoReactor *reactor = thread_reactor;
  return reactor != NULL && ms_io_ring_pop(reactor->completions, event);
}
