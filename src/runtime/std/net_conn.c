/* Connections: dialing, reading, writing and shutting down a TCP or Unix stream on the network loop (net_core.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <errno.h>
#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#include <winsock2.h>
#else
#include <sys/socket.h>
#include <unistd.h>
#endif

#include "base/alloc.h"
#include "base/bytes.h"
#include "runtime/core/isolate.h"
#include "runtime/core/task.h"
#include "runtime/io/reactor.h"
#include "runtime/std/fail.h"
#include "runtime/std/net_calls.h"
#include "runtime/std/net.h"
#include "runtime/std/net_conn.h"
#include "runtime/std/net_core.h"
#include "runtime/std/net_filter.h"
#include "runtime/std/net_ip.h"

enum { READ_DEFAULT = 64 * 1024, READ_LIMIT = 1024 * 1024, CIPHER_BYTES = 16 * 1024 };

/* ---- dial ---- */

typedef struct ConnectOp {
  MsNetOp op;
  char *host; /* the name or literal to dial; NULL for a Unix socket */
  char *path; /* the Unix socket's path; NULL for TCP */
  char service[8];
  uv_getaddrinfo_t resolve;
  uv_connect_t connect;
  struct addrinfo *found;
  const struct addrinfo *next;
  MsNetFilter *filter; /* a reference, or NULL */
  MsNetCore *core; /* the attempt in progress; the result when it succeeds */
  bool cancelled;
  int last;
} ConnectOp;

static void connect_release(MsNetOp *op) {
  ConnectOp *dial = (ConnectOp *)op;
  if (dial->found != NULL) {
    uv_freeaddrinfo(dial->found);
  }
  if (dial->core != NULL) {
    ms_net_core_close(dial->core); /* an abandoned success: close what nobody took */
  }
  ms_net_filter_release(dial->filter);
  ms_free(dial->host);
  ms_free(dial->path);
}

static void next_attempt(ConnectOp *dial);

static void connected(ConnectOp *dial, int status) {
  if (status == 0) {
    ms_net_core_name(dial->core);
    ms_net_op_done(&dial->op, 0);
    return;
  }
  ms_net_core_discard(dial->core);
  dial->core = NULL;
  dial->last = status;
  if (dial->cancelled || dial->path != NULL) {
    ms_net_op_done(&dial->op, status);
    return;
  }
  next_attempt(dial);
}

static void on_connect(uv_connect_t *request, int status) {
  ConnectOp *dial = request->data;
  connected(dial, dial->cancelled ? UV_ECANCELED : status);
}

/* Starts a connection to the next address of the lookup, or ends the operation when none is left. */
static void next_attempt(ConnectOp *dial) {
  while (dial->next != NULL) {
    const struct addrinfo *entry = dial->next;
    dial->next = entry->ai_next;
    if (!ms_net_filter_address_allowed(dial->filter, entry->ai_addr)) {
      dial->last = UV_EACCES;
      continue;
    }
    dial->core = ms_net_core_new(MS_NET_CONNECTION, false);
    int code = uv_tcp_init(ms_net_loop(), &dial->core->h.tcp);
    if (code != 0) {
      ms_net_core_unref(dial->core); /* no handle was made: only the creation reference exists */
      dial->core = NULL;
      dial->last = code;
      continue;
    }
    code = uv_tcp_connect(&dial->connect, &dial->core->h.tcp, entry->ai_addr, on_connect);
    if (code == 0) {
      return;
    }
    dial->last = code;
    ms_net_core_discard(dial->core);
    dial->core = NULL;
  }
  ms_net_op_done(&dial->op, dial->last != 0 ? dial->last : UV_EADDRNOTAVAIL);
}

static void on_resolved(uv_getaddrinfo_t *request, int status, struct addrinfo *found) {
  ConnectOp *dial = request->data;
  dial->found = found;
  dial->next = found;
  if (status < 0 || dial->cancelled) {
    ms_net_op_done(&dial->op, dial->cancelled ? UV_ECANCELED : status);
    return;
  }
  next_attempt(dial);
}

static void on_pipe_connect(uv_connect_t *request, int status) {
  ConnectOp *dial = request->data;
  connected(dial, dial->cancelled ? UV_ECANCELED : status);
}

static void connect_start(MsNetOp *op) {
  ConnectOp *dial = (ConnectOp *)op;
  dial->connect.data = dial;
  dial->resolve.data = dial;
  if (dial->path != NULL) {
    dial->core = ms_net_core_new(MS_NET_CONNECTION, true);
    const int code = uv_pipe_init(ms_net_loop(), &dial->core->h.pipe, 0);
    if (code != 0) {
      ms_net_core_unref(dial->core);
      dial->core = NULL;
      ms_net_op_done(op, code);
      return;
    }
    uv_pipe_connect(&dial->connect, &dial->core->h.pipe, dial->path, on_pipe_connect);
    return;
  }
  const struct addrinfo hints = {.ai_family = AF_UNSPEC, .ai_socktype = SOCK_STREAM};
  const int code = uv_getaddrinfo(ms_net_loop(), &dial->resolve, on_resolved, dial->host, dial->service, &hints);
  if (code != 0) {
    ms_net_op_done(op, code);
  }
}

static void connect_abandon(MsNetOp *op) {
  ConnectOp *dial = (ConnectOp *)op;
  dial->cancelled = true;
  if (dial->core != NULL) {
    ms_net_core_discard(dial->core); /* the connect callback then reports the cancellation */
  } else if (dial->found == NULL) {
    (void)uv_cancel((uv_req_t *)&dial->resolve);
  }
}

static ConnectOp *connect_new(void) {
  return ms_net_op_new(sizeof(ConnectOp), connect_start, connect_abandon, connect_release);
}

static uint8_t connect_finish(ConnectOp *dial, MsNetWait wait, MsObj **out, MsString *err) {
  const uint8_t status = ms_net_finish(wait, wait == MS_NET_WAIT_DONE ? dial->op.status : 0, "connect", err);
  if (wait == MS_NET_WAIT_DONE) {
    if (status == MS_STATUS_OK) {
      *out = ms_net_handle_new(dial->core);
      dial->core = NULL; /* the handle holds the core now; the loop's reference is the libuv handle's */
    }
    ms_net_op_free(&dial->op);
  }
  return status;
}

uint8_t ms_net_dial(MsSpan address, MsNetFilter *filter, int64_t timeout_ns, MsObj **out, MsString *err) {
  MsSpan host = {0};
  MsSpan port_text = {0};
  uint16_t port = 0;
  *err = ms_string_empty();
  if (!ms_split_host_port(address, &host, &port_text) || host.len == 0 || !ms_parse_port(port_text, &port)) {
    return MS_STATUS_INVALID_INPUT;
  }
  ConnectOp *dial = connect_new();
  dial->filter = ms_net_filter_retain(filter);
  dial->host = ms_alloc(host.len + 1);
  memcpy(dial->host, host.ptr, host.len);
  dial->host[host.len] = 0;
  (void)snprintf(dial->service, sizeof dial->service, "%u", (unsigned)port);
  return connect_finish(dial, ms_net_run(&dial->op, timeout_ns), out, err);
}

uint8_t ms_net_dial_unix(MsSpan path, int64_t timeout_ns, MsObj **out, MsString *err) {
  *err = ms_string_empty();
  if (path.len == 0 || memchr(path.ptr, 0, path.len) != NULL) {
    return MS_STATUS_INVALID_INPUT;
  }
  ConnectOp *dial = connect_new();
  dial->path = ms_alloc(path.len + 1);
  memcpy(dial->path, path.ptr, path.len);
  dial->path[path.len] = 0;
  return connect_finish(dial, ms_net_run(&dial->op, timeout_ns), out, err);
}

/* ---- read ---- */

typedef struct ReadOp {
  MsNetOp op;
  MsNetCore *core; /* a reference */
  uint8_t *data;
  uint8_t *cipher; /* TLS: the buffer the socket is read into */
  size_t capacity;
  size_t length;
} ReadOp;

static void read_release(MsNetOp *op) {
  ReadOp *read = (ReadOp *)op;
  atomic_fetch_sub(&read->core->reads_posted, 1);
  ms_net_core_unref(read->core);
  ms_free(read->data);
  ms_free(read->cipher);
}

/* Keeps bytes a reader gave up on for the next one. */
static void stash_put(MsNetCore *core, const uint8_t *data, size_t length) {
  core->stash = ms_realloc(core->stash, core->stash_length + length);
  memcpy(core->stash + core->stash_length, data, length);
  core->stash_length += length;
}

static void on_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
  ReadOp *read = ((MsNetCore *)(void *)handle)->reading;
  (void)suggested;
  if (read->cipher != NULL) {
    *buffer = uv_buf_init((char *)read->cipher, CIPHER_BYTES);
    return;
  }
  *buffer = uv_buf_init((char *)read->data, (unsigned int)read->capacity);
}

/* The read has `read->length` bytes: hand them to the waiter, or keep them for the next read when it left. */
static void read_deliver(ReadOp *read) {
  if (atomic_load(&read->op.state) == MS_NET_OP_ABANDONED && read->length > 0) {
    stash_put(read->core, read->data, read->length);
    read->length = 0;
  }
  ms_net_op_done(&read->op, 0);
}

static void tls_read_step(ReadOp *read);

/* TLS: ciphertext arrived (or the stream ended): feed the session and read again. */
static void on_cipher(uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
  MsNetCore *core = (MsNetCore *)(void *)stream;
  ReadOp *read = core->reading;
  (void)buffer;
  if (count == 0 || read == NULL) {
    return;
  }
  core->reading = NULL;
  (void)uv_read_stop(stream);
  if (count == UV_EOF) {
    core->eof = true;
    ms_net_op_done(&read->op, 0);
  } else if (count < 0) {
    ms_net_op_done(&read->op, (int)count);
  } else {
    ms_net_tls_incoming(core->tls, ms_span_of(read->cipher, (size_t)count));
    tls_read_step(read);
  }
}

static void tls_read_step(ReadOp *read) {
  MsNetCore *core = read->core;
  size_t count = 0;
  switch (ms_net_tls_read(core->tls, read->data, read->capacity, &count)) {
  case MS_NET_TLS_DONE:
    read->length = count;
    read_deliver(read);
    return;
  case MS_NET_TLS_CLOSED:
    core->eof = true; /* the peer sent close_notify */
    ms_net_op_done(&read->op, 0);
    return;
  case MS_NET_TLS_ERROR:
    ms_net_op_done(&read->op, UV_EPROTO);
    return;
  case MS_NET_TLS_WANT_IO:
    break;
  }
  (void)ms_net_cipher_flush(core, NULL, NULL);
  if (read->cipher == NULL) {
    read->cipher = ms_alloc(CIPHER_BYTES);
  }
  core->reading = read;
  const int code = uv_read_start(&core->h.stream, on_alloc, on_cipher);
  if (code != 0) {
    core->reading = NULL;
    ms_net_op_done(&read->op, code);
  }
}

static void on_read(uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
  MsNetCore *core = (MsNetCore *)(void *)stream;
  ReadOp *read = core->reading;
  (void)buffer;
  if (count == 0 || read == NULL) {
    return;
  }
  core->reading = NULL;
  (void)uv_read_stop(stream);
  if (count == UV_EOF) {
    core->eof = true;
    ms_net_op_done(&read->op, 0);
    return;
  }
  if (count < 0) {
    ms_net_op_done(&read->op, (int)count);
    return;
  }
  read->length = (size_t)count;
  read_deliver(read);
}

static void read_start(MsNetOp *op) {
  ReadOp *read = (ReadOp *)op;
  MsNetCore *core = read->core;
  if (atomic_load(&core->closed) || core->broken) {
    ms_net_op_done(op, MS_NET_CLOSED);
  } else if (core->stash_length > 0) {
    read->length = core->stash_length < read->capacity ? core->stash_length : read->capacity;
    memcpy(read->data, core->stash, read->length);
    core->stash_length -= read->length;
    memmove(core->stash, core->stash + read->length, core->stash_length);
    ms_net_op_done(op, 0);
  } else if (core->eof) {
    ms_net_op_done(op, 0);
  } else if (core->reading != NULL) {
    ms_net_op_done(op, UV_EBUSY);
  } else if (core->tls != NULL) {
    tls_read_step(read);
  } else {
    core->reading = read;
    const int code = uv_read_start(&core->h.stream, on_alloc, on_read);
    if (code != 0) {
      core->reading = NULL;
      ms_net_op_done(op, code);
    }
  }
}

static void read_abandon(MsNetOp *op) {
  ReadOp *read = (ReadOp *)op;
  if (read->core->reading == read) {
    read->core->reading = NULL;
    (void)uv_read_stop(&read->core->h.stream);
    ms_net_op_done(op, UV_ECANCELED);
  }
}

static void steal_lock(MsNetCore *core) {
  while (atomic_exchange_explicit(&core->steal_lock, 1, memory_order_acquire) != 0) {
  }
}

static void steal_unlock(MsNetCore *core) { atomic_store_explicit(&core->steal_lock, 0, memory_order_release); }

void ms_net_core_set_stealable(MsNetCore *core, bool stealable) { atomic_store(&core->stealable, stealable); }

bool ms_net_core_steal_read(MsNetCore *core, MsBytes *out) {
  steal_lock(core);
  ReadOp *read = core->open_read;
  const bool ready = read != NULL && atomic_load(&read->op.state) == MS_NET_OP_DONE && read->op.status == 0 &&
                     read->length > 0;
  if (ready) {
    core->open_read = NULL; /* the registration's reference passes to us */
  }
  steal_unlock(core);
  if (!ready) {
    return false;
  }
  *out = ms_bytes_from_span(ms_span_of(read->data, read->length));
  ms_net_op_free(&read->op);
  return true;
}

/* With one scheduler thread the loop thread's wait overlaps the thread's own work and wins (one CPU: 82k against 66k
 * requests a second); with several it is the ceiling. So with no read posted, the bytes already in the socket are
 * read on the calling thread, which keeps the loop thread (the one thread every connection shares) out of the common
 * case of a busy connection. Returns the byte count, 0 for the end of the stream, or -1 to use the loop (nothing yet,
 * an error to report there, or a case the loop owns). libuv's sockets are non-blocking on every platform, and on
 * Windows its reads are zero-length overlapped ones that take no bytes, so a read here cannot lose any. */
static ssize_t read_direct(MsNetCore *core, size_t capacity, MsBytes *out) {
  static _Thread_local uint8_t scratch[READ_DEFAULT];
  if (core->kind != MS_NET_CONNECTION || core->is_pipe || core->tls != NULL || capacity == 0 ||
      atomic_load(&core->reads_posted) != 0 || ms_isolate_count() < 2) {
    return -1;
  }
  atomic_fetch_add(&core->direct, 1);
  ssize_t count = -1;
  uv_os_fd_t fd;
  if (!atomic_load(&core->closed) && !atomic_load(&core->broken) && atomic_load(&core->reads_posted) == 0 &&
      uv_fileno((const uv_handle_t *)&core->h.stream, &fd) == 0) {
    const size_t length = capacity < sizeof scratch ? capacity : sizeof scratch;
#ifdef _WIN32
    count = recv((SOCKET)fd, (char *)scratch, (int)length, 0);
#else
    count = read(fd, scratch, length);
#endif
    if (count > 0) {
      *out = ms_bytes_from_span(ms_span_of(scratch, (size_t)count));
    } else if (count < 0) {
      count = -1; /* would block: wait on the loop; any other error is reported there */
    }
  }
  atomic_fetch_sub(&core->direct, 1);
  return count;
}

void ms_net_conn_wake_readers(MsNetCore *core) {
#ifndef _WIN32
  uv_os_fd_t fd;
  if (atomic_load(&core->edge_waiting) != 0 && uv_fileno((const uv_handle_t *)&core->h.handle, &fd) == 0) {
    (void)shutdown((int)fd, SHUT_RD); /* an edge wakes the waiter, whose read then sees the end of the stream */
  }
#else
  (void)core;
#endif
}

#ifndef _WIN32
/* Whether the last failed read found nothing to take; only the edge reads ask, and they are not built on Windows. */
static bool would_block(void) {
  return errno == EAGAIN || errno == EWOULDBLOCK;
}
#endif

/* A plain connection of a program with one scheduler thread has nobody to take it from this thread, and the network
 * loop thread would only be a hand-off between the task and the socket. */
static bool edge_reads(const MsNetCore *core) {
  return core->kind == MS_NET_CONNECTION && !core->is_pipe && core->tls == NULL && ms_isolate_count() < 2 &&
         ms_io_edge_supported();
}

/* Reads on the calling thread and, when the socket has nothing, waits for its next edge on this thread's poller: the
 * descriptor stays registered between reads, so a wait costs no system call of its own and one epoll_wait reports
 * every ready connection. An edge says "something changed", so a read that took less than it asked for is taken to
 * have drained the socket (a TCP receive queue that still held bytes would have filled the buffer) and the next one
 * waits first. False when the loop must serve the read (an error to report, a socket the loop owns): nothing was
 * consumed. Otherwise *result is the call's status. */
static bool read_edge(MsNetCore *core, size_t capacity, int64_t timeout_ns, MsBytes *out, MsString *err,
                      uint8_t *result) {
#ifdef _WIN32
  (void)core;
  (void)capacity;
  (void)timeout_ns;
  (void)out;
  (void)err;
  (void)result;
  return false;
#else
  static _Thread_local uint8_t scratch[READ_DEFAULT];
  uv_os_fd_t fd;
  if (capacity == 0 || atomic_load(&core->reads_posted) != 0 ||
      uv_fileno((const uv_handle_t *)&core->h.stream, &fd) != 0) {
    return false;
  }
  const int64_t deadline = ms_sched_deadline_after(timeout_ns);
  const size_t length = capacity < sizeof scratch ? capacity : sizeof scratch;
  atomic_fetch_add(&core->direct, 1);
  bool handled = false;
  MsNetWait ended = MS_NET_WAIT_DONE;
  for (;;) {
    if (atomic_load(&core->closed) || atomic_load(&core->broken) || atomic_load(&core->reads_posted) != 0) {
      break;
    }
    if (!core->drained || ms_io_edge_ready((int)fd, MS_IO_BIT_READ)) {
      if (!ms_io_edge_reset((int)fd, core->id, MS_IO_BIT_READ)) {
        break;
      }
      const ssize_t count = read((int)fd, scratch, length);
      if (count > 0) {
        core->drained = (size_t)count < length;
        *out = ms_bytes_from_span(ms_span_of(scratch, (size_t)count));
        *err = ms_string_empty();
        *result = MS_STATUS_OK;
        handled = true;
        break;
      }
      if (count == 0) {
        *err = ms_string_empty();
        *result = MS_STATUS_NONE;
        handled = true;
        break;
      }
      if (!would_block()) {
        break; /* an error to report where the loop reports it */
      }
      core->drained = true;
    }
    atomic_fetch_add(&core->edge_waiting, 1);
    const bool open = !atomic_load(&core->closed);
    const uint32_t waited = open ? ms_task_wait_fd_at((int)fd, MS_WAIT_READ | MS_WAIT_EDGE, deadline) : MS_WAIT_READ;
    atomic_fetch_sub(&core->edge_waiting, 1);
    if ((waited & MS_WAIT_FAILED) != 0) {
      break;
    }
    if ((waited & (MS_WAIT_TIMEOUT | MS_WAIT_CANCELLED)) != 0) {
      ended = (waited & MS_WAIT_CANCELLED) != 0 ? MS_NET_WAIT_CANCELLED : MS_NET_WAIT_TIMED_OUT;
      handled = true;
      break;
    }
    core->drained = false;
  }
  atomic_fetch_sub(&core->direct, 1);
  if (ended != MS_NET_WAIT_DONE) {
    *result = ms_net_finish(ended, 0, "read", err);
  }
  return handled;
#endif
}

uint8_t ms_net_read(MsNetCore *core, size_t capacity, int64_t timeout_ns, MsBytes *out, MsString *err) {
  uint8_t result = MS_STATUS_OK;
  if (edge_reads(core) && read_edge(core, capacity, timeout_ns, out, err, &result)) {
    return result;
  }
  const ssize_t direct = read_direct(core, capacity, out);
  if (direct >= 0) {
    *err = ms_string_empty();
    return direct == 0 ? MS_STATUS_NONE : MS_STATUS_OK;
  }
  ReadOp *read = ms_net_op_new(sizeof *read, read_start, read_abandon, read_release);
  atomic_fetch_add(&core->references, 1);
  atomic_fetch_add(&core->reads_posted, 1);
  read->core = core;
  read->capacity = capacity;
  read->data = ms_alloc(capacity);
  const bool registered = atomic_load(&core->stealable);
  if (registered) {
    atomic_fetch_add(&read->op.references, 1); /* the registration's */
    steal_lock(core);
    core->open_read = read;
    steal_unlock(core);
  }
  const MsNetWait wait = ms_net_run(&read->op, timeout_ns);
  bool stolen = false;
  if (registered) {
    steal_lock(core);
    stolen = core->open_read != read;
    core->open_read = stolen ? core->open_read : NULL;
    steal_unlock(core);
    if (!stolen) {
      ms_net_op_free(&read->op); /* the registration's reference */
    }
  }
  if (stolen) {
    ms_net_op_free(&read->op); /* ours: the thief holds the registration's and the bytes */
    *err = ms_string_empty();
    return MS_STATUS_CLOSED;
  }
  const uint8_t status = ms_net_finish(wait, wait == MS_NET_WAIT_DONE ? read->op.status : 0, "read", err);
  if (wait != MS_NET_WAIT_DONE) {
    return status;
  }
  if (status == MS_STATUS_OK) {
    if (read->length == 0) {
      ms_net_op_free(&read->op);
      return MS_STATUS_NONE; /* the end of the stream */
    }
    *out = ms_bytes_from_span(ms_span_of(read->data, read->length));
  }
  ms_net_op_free(&read->op);
  return status;
}

/* ---- write and shutdown ---- */

typedef struct WriteOp {
  MsNetOp op;
  MsNetCore *core;
  uint8_t *data;
  size_t length;
  uv_write_t request;
  uv_shutdown_t shutdown;
  bool shutting;
} WriteOp;

static void write_release(MsNetOp *op) {
  WriteOp *write = (WriteOp *)op;
  atomic_fetch_sub(&write->core->writing, 1);
  ms_net_core_unref(write->core);
  ms_free(write->data);
}

static void on_shutdown(uv_shutdown_t *request, int status);

static void on_write(uv_write_t *request, int status) {
  WriteOp *write = request->data;
  if (write->shutting && status == 0) { /* a TLS close_notify went out; now the socket's own half-close */
    const int code = uv_shutdown(&write->shutdown, &write->core->h.stream, on_shutdown);
    status = code;
    if (code == 0) {
      return;
    }
  }
  ms_net_op_done(&write->op, status);
}

static void on_shutdown(uv_shutdown_t *request, int status) {
  WriteOp *write = request->data;
  ms_net_op_done(&write->op, status);
}

/* TLS: turns the plaintext into ciphertext (or, for a shutdown, queues close_notify) and puts it in `data`. */
static bool tls_seal(WriteOp *write) {
  MsNetCore *core = write->core;
  size_t offset = 0;
  if (write->shutting) {
    ms_net_tls_shutdown(core->tls);
  }
  while (offset < write->length) {
    size_t count = 0;
    if (ms_net_tls_write(core->tls, write->data + offset, write->length - offset, &count) != MS_NET_TLS_DONE) {
      return false;
    }
    offset += count;
  }
  ms_free(write->data);
  ms_net_cipher_collect(core, &write->data, &write->length);
  return true;
}

static void write_start(MsNetOp *op) {
  WriteOp *write = (WriteOp *)op;
  MsNetCore *core = write->core;
  if (atomic_load(&core->closed) || core->broken) {
    ms_net_op_done(op, MS_NET_CLOSED);
    return;
  }
  int code = 0;
  write->request.data = write;
  write->shutdown.data = write;
  if (core->tls != NULL && !tls_seal(write)) {
    ms_net_op_done(op, UV_EPROTO);
    return;
  }
  if (write->shutting && write->length == 0) {
    code = uv_shutdown(&write->shutdown, &core->h.stream, on_shutdown);
  } else {
    uv_buf_t buffer = uv_buf_init((char *)write->data, (unsigned int)write->length);
    code = uv_write(&write->request, &core->h.stream, &buffer, 1, on_write);
  }
  if (code != 0) {
    ms_net_op_done(op, code);
  }
}

/* A write that cannot be taken back is under way: the stream is torn for whoever writes next. */
static void write_abandon(MsNetOp *op) { ((WriteOp *)op)->core->broken = true; }

/* Writes straight to a plain TCP socket from the calling thread when nothing else is writing it and the kernel
 * takes bytes now, which skips the hand-off to the loop thread (a queue, a wake and two task switches) and moves
 * the send, which on loopback includes the peer's receive work, off the loop thread. Returns the bytes written, or
 * a negative libuv status; 0 and UV_EAGAIN mean "use the loop for the rest". */
static ssize_t write_direct(MsNetCore *core, MsSpan data) {
  /* With one scheduler thread the loop thread's send overlaps the thread's own work and wins (one CPU: 70k against
   * 54k requests a second); with several the loop thread is the ceiling and the send spreads over them (four CPUs:
   * 98k against 150k). */
  if (core->kind != MS_NET_CONNECTION || core->is_pipe || core->tls != NULL || data.len == 0 ||
      data.len > (size_t)INT32_MAX || atomic_load(&core->writing) != 0 ||
      (ms_isolate_count() < 2 && !edge_reads(core))) {
    return UV_EAGAIN;
  }
  atomic_fetch_add(&core->direct, 1);
  ssize_t result = UV_EAGAIN;
  if (!atomic_load(&core->closed) && atomic_load(&core->writing) == 0) {
    uv_buf_t buffer = uv_buf_init((char *)(uintptr_t)data.ptr, (unsigned int)data.len); /* libuv only reads it */
    result = uv_try_write(&core->h.stream, &buffer, 1);
  }
  atomic_fetch_sub(&core->direct, 1);
  return result;
}

static uint8_t write_run(MsNetCore *core, MsSpan data, bool shutting, int64_t timeout_ns, const char *operation,
                         MsString *err) {
  if (!shutting) {
    const ssize_t sent = write_direct(core, data);
    if (sent >= 0 && (size_t)sent == data.len) {
      *err = ms_string_empty();
      return MS_STATUS_OK;
    }
    if (sent < 0 && sent != UV_EAGAIN) {
      return ms_net_finish(MS_NET_WAIT_DONE, (int)sent, operation, err);
    }
    if (sent > 0) {
      data = ms_span_of(data.ptr + sent, data.len - (size_t)sent);
    }
  }
  WriteOp *write = ms_net_op_new(sizeof *write, write_start, write_abandon, write_release);
  atomic_fetch_add(&core->references, 1);
  atomic_fetch_add(&core->writing, 1);
  write->core = core;
  write->shutting = shutting;
  write->length = data.len;
  write->data = ms_alloc(data.len + 1);
  if (data.len != 0) {
    memcpy(write->data, data.ptr, data.len);
  }
  const MsNetWait wait = ms_net_run(&write->op, timeout_ns);
  const uint8_t status = ms_net_finish(wait, wait == MS_NET_WAIT_DONE ? write->op.status : 0, operation, err);
  if (wait == MS_NET_WAIT_DONE) {
    ms_net_op_free(&write->op);
  }
  return status;
}

uint8_t ms_net_write(MsNetCore *core, MsSpan data, int64_t timeout_ns, MsString *err) {
  return write_run(core, data, false, timeout_ns, "write", err);
}

uint8_t ms_net_shutdown(MsNetCore *core, MsString *err) {
  return write_run(core, ms_span_of(NULL, 0), true, -1, "shutdown", err);
}

/* ---- ending the operations of a closing core ---- */

void ms_net_conn_close_ops(MsNetCore *core) {
  if (core->kind != MS_NET_CONNECTION || core->reading == NULL) {
    return;
  }
  ReadOp *read = core->reading;
  core->reading = NULL;
  (void)uv_read_stop(&core->h.stream);
  ms_net_op_done(&read->op, MS_NET_CLOSED);
}

/* ---- natives ---- */

uint8_t ms_net_connection_read(const MsObj *handle, uint8_t has_max, int64_t max, uint8_t has_timeout,
                                  int64_t timeout, MsBytes *out, MsString *err) {
  *err = ms_string_empty();
  if (has_max != 0 && max < 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  size_t capacity = READ_DEFAULT;
  if (has_max != 0) {
    capacity = max > READ_LIMIT ? READ_LIMIT : (size_t)max;
  }
  if (capacity == 0) {
    return MS_STATUS_OK;
  }
  return ms_net_read(ms_net_handle_core(handle), capacity, ms_net_timeout(has_timeout, timeout), out, err);
}

uint8_t msstd_net_connection_read(const MsObj *handle, uint8_t has_max, int64_t max, uint8_t has_timeout,
                                  int64_t timeout, MsBytes *out, MsString *err) {
  return ms_native_return(ms_net_connection_read(handle, has_max, max, has_timeout, timeout, out, err), err);
}

uint8_t ms_net_connection_write_bytes(const MsObj *handle, const MsBytes *data, uint8_t has_timeout, int64_t timeout,
                                         MsString *err) {
  return ms_net_write(ms_net_handle_core(handle), ms_bytes_span(data), ms_net_timeout(has_timeout, timeout), err);
}

uint8_t msstd_net_connection_write_bytes(const MsObj *handle, const MsBytes *data, uint8_t has_timeout, int64_t timeout,
                                         MsString *err) {
  return ms_native_return(ms_net_connection_write_bytes(handle, data, has_timeout, timeout, err), err);
}

uint8_t ms_net_connection_shutdown_write(const MsObj *handle, MsString *err) {
  return ms_net_shutdown(ms_net_handle_core(handle), err);
}

uint8_t msstd_net_connection_shutdown_write(const MsObj *handle, MsString *err) {
  return ms_native_return(ms_net_connection_shutdown_write(handle, err), err);
}

void msstd_net_connection_close(const MsObj *handle) { ms_net_handle_close(handle); }
MsObj *msstd_net_connection_share(const MsObj *handle) { return ms_net_handle_share(handle); }
MsObj *msstd_net_connection_alias(const MsObj *handle) { return ms_net_handle_alias(handle); }
void msstd_net_connection_close_if_last(const MsObj *handle) { ms_net_handle_close_if_last(handle); }

void msstd_net_connection_local_address(const MsObj *handle, MsString *out) {
  *out = ms_string_clone(&ms_net_handle_core(handle)->local);
}

void msstd_net_connection_peer_address(const MsObj *handle, MsString *out) {
  *out = ms_string_clone(&ms_net_handle_core(handle)->peer);
}

uint8_t msstd_net_connection_adopt(int64_t raw, MsObj **out, MsString *err) {
  *err = ms_string_empty();
  if (raw == 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  *out = ms_net_handle_new((MsNetCore *)(uintptr_t)raw); /* the pending id's creation reference stays with the core */
  return MS_STATUS_OK;
}

void msstd_net_pending_release(int64_t raw) {
  MsNetCore *core = (MsNetCore *)(uintptr_t)raw;
  if (core == NULL) {
    return;
  }
  ms_net_core_close(core);
}
