/* The socket core and its handles (see net_core.h). */
#ifndef __APPLE__                /* Apple hides MSG_DONTWAIT once _POSIX_C_SOURCE is set */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */
#endif

#include "runtime/std/net_core.h"

#include "base/alloc.h"
#include "base/strbuild.h"
#include "runtime/core/unwind.h"
#include "runtime/std/fail.h"
#include "runtime/std/net_ip.h"

MsNetCore *ms_net_core_new(MsNetKind kind, bool is_pipe) {
  MsNetCore *core = ms_alloc_zeroed(sizeof *core);
  core->kind = kind;
  core->is_pipe = is_pipe;
  atomic_init(&core->references, 1);
  atomic_init(&core->handles, 0);
  atomic_init(&core->ends, 1);
  atomic_init(&core->closed, false);
  atomic_init(&core->stealable, false);
  atomic_init(&core->steal_lock, 0);
  core->local = ms_string_empty();
  core->peer = ms_string_empty();
  return core;
}

static void core_free(MsNetCore *core) {
  ms_string_release(&core->local);
  ms_string_release(&core->peer);
  ms_free(core->path);
  ms_net_tls_free(core->tls);
  ms_net_tls_ctx_release(core->tls_ctx);
  ms_free(core->stash);
  ms_free(core);
}

void ms_net_core_unref(MsNetCore *core) {
  if (atomic_fetch_sub(&core->references, 1) == 1) {
    core_free(core);
  }
}

/* ---- closing ---- */

typedef struct CloseOp {
  MsNetOp op;
  MsNetCore *core; /* a reference, released by the operation */
} CloseOp;

static void on_closed(uv_handle_t *handle) {
  MsNetCore *core = (MsNetCore *)handle;
  if (core->path != NULL) {
    uv_fs_t request;
    (void)uv_fs_unlink(NULL, &request, core->path, NULL);
    uv_fs_req_cleanup(&request);
  }
  ms_net_core_unref(core); /* the libuv handle's reference */
}

#ifdef _WIN32
#include <winsock2.h>
#else
#include <sys/socket.h>
#endif

/* Reads and drops what the peer sent that nobody read. Closing a socket with unread bytes in its receive queue
 * sends a reset, which can discard the data this side wrote and the peer has not read yet (a TLS server's
 * post-handshake tickets are such bytes), so a connection drains before it closes. */
static void drain_unread(MsNetCore *core) {
  uv_os_fd_t fd;
  if (core->kind != MS_NET_CONNECTION || core->is_pipe || uv_fileno(&core->h.handle, &fd) != 0) {
    return;
  }
  char sink[4096];
#ifdef _WIN32
  while (recv((SOCKET)fd, sink, (int)sizeof sink, 0) > 0) {
  }
#else
  while (recv(fd, sink, sizeof sink, MSG_DONTWAIT) > 0) {
  }
#endif
}

static void close_start(MsNetOp *op) {
  MsNetCore *core = ((CloseOp *)op)->core;
  if (!uv_is_closing(&core->h.handle)) {
    drain_unread(core);
    ms_net_conn_close_ops(core);
    ms_net_listen_close_ops(core);
    ms_net_dgram_close_ops(core);
    uv_close(&core->h.handle, on_closed);
  }
  ms_net_core_unref(core);
  ms_net_op_done(op, 0);
}

void ms_net_core_close(MsNetCore *core) {
  if (atomic_exchange(&core->closed, true)) {
    return;
  }
  CloseOp *op = ms_net_op_new(sizeof *op, close_start, NULL, NULL);
  atomic_fetch_add(&core->references, 1);
  op->core = core;
  ms_net_post(&op->op);
}

/* ---- handles ---- */

static void handle_drop(MsObj *object) {
  MsNetHandle *handle = (MsNetHandle *)object;
  MsNetCore *core = handle->core;
  ms_free(handle);
  if (atomic_fetch_sub(&core->handles, 1) == 1) {
    ms_net_core_close(core);
  }
  ms_net_core_unref(core);
}

MsObj *ms_net_handle_new(MsNetCore *core) {
  MsNetHandle *handle = ms_alloc_zeroed(sizeof *handle);
  atomic_fetch_add(&core->references, 1);
  atomic_fetch_add(&core->handles, 1);
  handle->header.drop = handle_drop;
  handle->core = core;
  handle->generation = atomic_load(&core->generation);
  return &handle->header;
}

/* What a handle that an upgrade consumed finds: a closed connection. */
static MsNetCore *consumed_core(void) {
  static _Atomic(MsNetCore *) dead;
  static atomic_int once;
  if (atomic_exchange(&once, 1) == 0) {
    MsNetCore *core = ms_net_core_new(MS_NET_CONNECTION, false);
    atomic_store(&core->closed, true);
    atomic_store(&core->references, 1 << 30); /* never freed */
    atomic_store(&dead, core);
  }
  while (atomic_load(&dead) == NULL) {
  }
  return atomic_load(&dead);
}

MsNetCore *ms_net_handle_core(const MsObj *handle) {
  const MsNetHandle *self = (const MsNetHandle *)handle;
  return self->generation == atomic_load(&self->core->generation) ? self->core : consumed_core();
}

MsObj *ms_net_handle_upgraded(const MsObj *handle) {
  MsNetCore *core = ms_net_handle_core(handle);
  atomic_fetch_add(&core->generation, 1);
  return ms_net_handle_new(core);
}

MsObj *ms_net_handle_alias(const MsObj *handle) { return ms_net_handle_new(ms_net_handle_core(handle)); }

MsObj *ms_net_handle_share(const MsObj *handle) {
  MsNetCore *core = ms_net_handle_core(handle);
  atomic_fetch_add(&core->ends, 1);
  return ms_net_handle_new(core);
}

void ms_net_handle_close(const MsObj *handle) { ms_net_core_close(ms_net_handle_core(handle)); }

void ms_net_handle_close_if_last(const MsObj *handle) {
  MsNetCore *core = ms_net_handle_core(handle);
  if (atomic_fetch_sub(&core->ends, 1) == 1) {
    ms_net_core_close(core);
  }
}

/* ---- names ---- */

void ms_net_address_text(const struct sockaddr *address, MsString *out) {
  char host[INET6_ADDRSTRLEN + 1];
  uint16_t port = 0;
  if (address->sa_family == AF_INET6) {
    port = ntohs(((const struct sockaddr_in6 *)(const void *)address)->sin6_port);
  } else if (address->sa_family == AF_INET) {
    port = ntohs(((const struct sockaddr_in *)(const void *)address)->sin_port);
  } else {
    *out = ms_string_empty();
    return;
  }
  if (uv_ip_name(address, host, sizeof host) != 0) {
    *out = ms_string_empty();
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_join_host_port(ms_span_of_text(host), port, &text);
  *out = ms_strbuild_finish(&text);
}

static void pipe_name(MsNetCore *core, bool peer, MsString *out) {
  char buffer[1024];
  size_t size = sizeof buffer;
  const int code = peer ? uv_pipe_getpeername(&core->h.pipe, buffer, &size)
                        : uv_pipe_getsockname(&core->h.pipe, buffer, &size);
  *out = code == 0 ? ms_string_from_span(ms_span_of((const uint8_t *)buffer, size)) : ms_string_empty();
}

void ms_net_core_name(MsNetCore *core) {
  struct sockaddr_storage address;
  int length = (int)sizeof address;
  ms_string_release(&core->local);
  ms_string_release(&core->peer);
  if (core->is_pipe) {
    pipe_name(core, false, &core->local);
    pipe_name(core, true, &core->peer);
    return;
  }
  const struct sockaddr *socket_address = (const struct sockaddr *)(const void *)&address;
  const bool udp = core->kind == MS_NET_DATAGRAM;
  const int local = udp ? uv_udp_getsockname(&core->h.udp, (struct sockaddr *)(void *)&address, &length)
                        : uv_tcp_getsockname(&core->h.tcp, (struct sockaddr *)(void *)&address, &length);
  core->local = ms_string_empty();
  if (local == 0) {
    ms_net_address_text(socket_address, &core->local);
  }
  length = (int)sizeof address;
  core->peer = ms_string_empty();
  if (!udp && core->kind == MS_NET_CONNECTION &&
      uv_tcp_getpeername(&core->h.tcp, (struct sockaddr *)(void *)&address, &length) == 0) {
    ms_net_address_text(socket_address, &core->peer);
  }
}

void ms_net_core_discard(MsNetCore *core) {
  atomic_store(&core->closed, true);
  if (!uv_is_closing(&core->h.handle)) {
    ms_net_conn_close_ops(core);
    ms_net_listen_close_ops(core);
    ms_net_dgram_close_ops(core);
    uv_close(&core->h.handle, on_closed);
  }
}

uint8_t ms_net_finish(MsNetWait wait, int status, const char *operation, MsString *err) {
  *err = ms_string_empty();
  if (wait == MS_NET_WAIT_CANCELLED) {
    ms_cancelled();
  }
  if (wait == MS_NET_WAIT_TIMED_OUT) {
    return MS_STATUS_TIMED_OUT;
  }
  if (status == 0) {
    return MS_STATUS_OK;
  }
  if (status == MS_NET_CLOSED) {
    return MS_STATUS_CLOSED;
  }
  if (status == UV_EACCES) {
    return MS_STATUS_PERMISSION_DENIED;
  }
  MsFail fail = ms_fail_new();
  ms_fail_uv_text(&fail, status, operation, ms_span_of(NULL, 0));
  return ms_fail_finish(&fail, err);
}
