/* Listeners: binding, accepting and the network's listen natives (see net_core.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <string.h>

#include "base/alloc.h"
#include "runtime/std/fail.h"
#include "runtime/std/net_calls.h"
#include "runtime/std/net.h"
#include "runtime/std/net_conn.h"
#include "runtime/core/unwind.h"
#include "runtime/std/net_core.h"
#include "runtime/std/net_ip.h"
#include "runtime/std/net_tls_conn.h"

enum { BACKLOG = 511 };

typedef struct AcceptOp {
  MsNetOp op;
  MsNetCore *listener; /* a reference */
  MsNetCore *result;   /* the accepted connection, until a handle takes it */
  struct AcceptOp *next;
} AcceptOp;

/* An accepted connection nobody asked for yet. */
typedef struct Ready {
  MsNetCore *core;
  struct Ready *next;
} Ready;

/* ---- listening ---- */

typedef struct ListenOp {
  MsNetOp op;
  struct sockaddr_storage address;
  char *path;     /* the Unix socket's path, NULL for TCP */
  bool datagram;  /* a UDP socket: bound, not listening */
  bool any_host;  /* the address is `::` standing for every interface (an empty host) */
  MsNetCore *core;
} ListenOp;

static void listen_release(MsNetOp *op) {
  ListenOp *listen = (ListenOp *)op;
  if (listen->core != NULL) {
    ms_net_core_close(listen->core);
  }
  ms_free(listen->path);
}

static void accept_ready(MsNetCore *listener, MsNetCore *client);

static void on_connection(uv_stream_t *server, int status) {
  MsNetCore *listener = (MsNetCore *)(void *)server;
  if (status < 0) {
    return;
  }
  MsNetCore *client = ms_net_core_new(MS_NET_CONNECTION, listener->is_pipe);
  const int init = listener->is_pipe ? uv_pipe_init(ms_net_loop(), &client->h.pipe, 0)
                                     : uv_tcp_init(ms_net_loop(), &client->h.tcp);
  if (init != 0) {
    ms_net_core_unref(client);
    return;
  }
  if (uv_accept(server, &client->h.stream) != 0) {
    ms_net_core_discard(client);
    return;
  }
  ms_net_core_name(client);
  accept_ready(listener, client);
}

/* After `::` failed because the host has no IPv6: the same port on every IPv4 interface; false when it is not that case. */
static bool retry_any_v4(ListenOp *listen, int code) {
  if (!listen->any_host || (code != UV_EAFNOSUPPORT && code != UV_EPROTONOSUPPORT && code != UV_EADDRNOTAVAIL)) {
    return false;
  }
  const uint16_t port = ntohs(((const struct sockaddr_in6 *)(const void *)&listen->address)->sin6_port);
  listen->any_host = false;
  return uv_ip4_addr("0.0.0.0", port, (struct sockaddr_in *)(void *)&listen->address) == 0;
}

static void datagram_bind(ListenOp *bind) {
  MsNetCore *core = ms_net_core_new(MS_NET_DATAGRAM, false);
  int code = uv_udp_init(ms_net_loop(), &core->h.udp);
  if (code != 0) {
    ms_net_core_unref(core);
    ms_net_op_done(&bind->op, code);
    return;
  }
  code = uv_udp_bind(&core->h.udp, (const struct sockaddr *)(const void *)&bind->address, 0);
  if (code != 0) {
    ms_net_core_discard(core);
    if (retry_any_v4(bind, code)) {
      datagram_bind(bind);
      return;
    }
    ms_net_op_done(&bind->op, code);
    return;
  }
  ms_net_core_name(core);
  bind->core = core;
  ms_net_op_done(&bind->op, 0);
}

static void listen_start(MsNetOp *op) {
  ListenOp *listen = (ListenOp *)op;
  const bool is_pipe = listen->path != NULL;
  if (listen->datagram) {
    datagram_bind(listen);
    return;
  }
  MsNetCore *core = ms_net_core_new(MS_NET_LISTENER, is_pipe);
  int code = is_pipe ? uv_pipe_init(ms_net_loop(), &core->h.pipe, 0) : uv_tcp_init(ms_net_loop(), &core->h.tcp);
  if (code != 0) {
    ms_net_core_unref(core);
    ms_net_op_done(op, code);
    return;
  }
  code = is_pipe ? uv_pipe_bind(&core->h.pipe, listen->path)
                 : uv_tcp_bind(&core->h.tcp, (const struct sockaddr *)(const void *)&listen->address, 0);
  if (code == 0) {
    code = uv_listen(&core->h.stream, BACKLOG, on_connection);
  }
  if (code != 0) {
    ms_net_core_discard(core);
    if (retry_any_v4(listen, code)) {
      listen_start(op);
      return;
    }
    ms_net_op_done(op, code);
    return;
  }
  if (is_pipe) {
    core->path = listen->path;
    listen->path = NULL;
  }
  ms_net_core_name(core);
  listen->core = core;
  ms_net_op_done(op, 0);
}

static uint8_t listen_finish(ListenOp *listen, MsObj **out, MsString *err) {
  const MsNetWait wait = ms_net_run(&listen->op, -1);
  const uint8_t status = ms_net_finish(wait, wait == MS_NET_WAIT_DONE ? listen->op.status : 0, "listen", err);
  if (wait == MS_NET_WAIT_DONE) {
    if (status == MS_STATUS_OK) {
      *out = ms_net_handle_new(listen->core);
      listen->core = NULL;
    }
    ms_net_op_free(&listen->op);
  }
  return status;
}

/* The socket address of "ip:port" (an IP literal) into `out`; false when it is not one. */
bool ms_net_parse_literal(MsSpan address, struct sockaddr_storage *out) {
  MsSpan host = {0};
  MsSpan port_text = {0};
  uint16_t port = 0;
  char text[INET6_ADDRSTRLEN + 1];
  if (!ms_split_host_port(address, &host, &port_text) || !ms_parse_port(port_text, &port) ||
      host.len >= sizeof text) {
    return false;
  }
  memcpy(text, host.ptr, host.len);
  text[host.len] = 0;
  return (memchr(text, ':', host.len) != NULL ? uv_ip6_addr(text, port, (struct sockaddr_in6 *)(void *)out)
                                    : uv_ip4_addr(text, port, (struct sockaddr_in *)(void *)out)) == 0;
}

/* The socket address a listener or datagram socket binds. An empty host (":8080") is every interface: `::` with
 * IPv4 mapped, which `retry_any_v4` replaces with `0.0.0.0` on a host without IPv6. */
static bool parse_bind(MsSpan address, struct sockaddr_storage *out, bool *any_host) {
  MsSpan host = {0};
  MsSpan port_text = {0};
  uint16_t port = 0;
  *any_host = false;
  if (!ms_split_host_port(address, &host, &port_text) || host.len != 0) {
    return ms_net_parse_literal(address, out);
  }
  *any_host = true;
  return ms_parse_port(port_text, &port) && uv_ip6_addr("::", port, (struct sockaddr_in6 *)(void *)out) == 0;
}

static uint8_t bind_run(MsSpan address, bool datagram, MsObj **out, MsString *err) {
  struct sockaddr_storage parsed;
  *err = ms_string_empty();
  bool any_host = false;
  if (!parse_bind(address, &parsed, &any_host)) {
    return MS_STATUS_INVALID_INPUT;
  }
  ListenOp *listen = ms_net_op_new(sizeof *listen, listen_start, NULL, listen_release);
  listen->address = parsed;
  listen->any_host = any_host;
  listen->datagram = datagram;
  return listen_finish(listen, out, err);
}

uint8_t ms_net_listen(MsSpan address, MsObj **out, MsString *err) { return bind_run(address, false, out, err); }

uint8_t ms_net_bind_datagram(MsSpan address, MsObj **out, MsString *err) { return bind_run(address, true, out, err); }

uint8_t ms_net_listen_unix(MsSpan path, MsObj **out, MsString *err) {
  *err = ms_string_empty();
  if (path.len == 0 || memchr(path.ptr, 0, path.len) != NULL) {
    return MS_STATUS_INVALID_INPUT;
  }
  ListenOp *listen = ms_net_op_new(sizeof *listen, listen_start, NULL, listen_release);
  listen->path = ms_alloc(path.len + 1);
  memcpy(listen->path, path.ptr, path.len);
  listen->path[path.len] = 0;
  return listen_finish(listen, out, err);
}

/* ---- accepting ---- */

static void accept_release(MsNetOp *op) {
  AcceptOp *accept = (AcceptOp *)op;
  if (accept->result != NULL) {
    ms_net_core_close(accept->result); /* an abandoned accept: close what nobody took */
  }
  ms_net_core_unref(accept->listener);
}

static void accept_ready(MsNetCore *listener, MsNetCore *client) {
  AcceptOp *waiting = listener->accepting;
  if (waiting != NULL) {
    listener->accepting = waiting->next;
    waiting->result = client;
    ms_net_op_done(&waiting->op, 0);
    return;
  }
  Ready *entry = ms_alloc(sizeof *entry);
  entry->core = client;
  entry->next = NULL;
  Ready **tail = (Ready **)&listener->ready;
  while (*tail != NULL) {
    tail = &(*tail)->next;
  }
  *tail = entry;
}

static void accept_start(MsNetOp *op) {
  AcceptOp *accept = (AcceptOp *)op;
  MsNetCore *listener = accept->listener;
  Ready *entry = listener->ready;
  if (atomic_load(&listener->closed)) {
    ms_net_op_done(op, MS_NET_CLOSED);
  } else if (entry != NULL) {
    listener->ready = entry->next;
    accept->result = entry->core;
    ms_free(entry);
    ms_net_op_done(op, 0);
  } else {
    AcceptOp **tail = (AcceptOp **)&listener->accepting;
    while (*tail != NULL) {
      tail = &(*tail)->next;
    }
    *tail = accept;
  }
}

static void accept_abandon(MsNetOp *op) {
  AcceptOp *accept = (AcceptOp *)op;
  AcceptOp **link = (AcceptOp **)&accept->listener->accepting;
  while (*link != NULL && *link != accept) {
    link = &(*link)->next;
  }
  if (*link == accept) {
    *link = accept->next;
    ms_net_op_done(op, UV_ECANCELED);
  }
}

void ms_net_listen_close_ops(MsNetCore *core) {
  if (core->kind != MS_NET_LISTENER) {
    return;
  }
  while (core->accepting != NULL) {
    AcceptOp *waiting = core->accepting;
    core->accepting = waiting->next;
    ms_net_op_done(&waiting->op, MS_NET_CLOSED);
  }
  while (core->ready != NULL) {
    Ready *entry = core->ready;
    core->ready = entry->next;
    ms_net_core_discard(entry->core);
    ms_free(entry);
  }
}

/* The next connection, as a handle or (`raw`) as a pending id for msstd_net_connection_adopt. */
static uint8_t accept_run(const MsObj *handle, int64_t timeout_ns, bool raw, MsObj **handle_out, int64_t *raw_out,
                          MsString *err) {
  MsNetCore *listener = ms_net_handle_core(handle);
  const uint64_t started = uv_hrtime();
  AcceptOp *accept = ms_net_op_new(sizeof *accept, accept_start, accept_abandon, accept_release);
  atomic_fetch_add(&listener->references, 1);
  accept->listener = listener;
  const MsNetWait wait = ms_net_run(&accept->op, timeout_ns);
  const uint8_t status = ms_net_finish(wait, wait == MS_NET_WAIT_DONE ? accept->op.status : 0, "accept", err);
  if (wait != MS_NET_WAIT_DONE) {
    return status;
  }
  if (status == MS_STATUS_OK) {
    MsNetCore *accepted = accept->result;
    accept->result = NULL;
    ms_net_op_free(&accept->op);
    if (raw) {
      *raw_out = (int64_t)(uintptr_t)accepted; /* the pending id keeps the creation reference */
      return status;
    }
    *handle_out = ms_net_handle_new(accepted);
    if (listener->tls_ctx == NULL) {
      return status;
    }
    /* A TLS listener hands out connections whose handshake is done. */
    accepted->tls_ctx = ms_net_tls_ctx_retain(listener->tls_ctx);
    const int64_t left = timeout_ns < 0 ? -1 : timeout_ns - (int64_t)(uv_hrtime() - started);
    const uint8_t served = ms_net_tls_serve(accepted, timeout_ns < 0 ? -1 : (left > 0 ? left : 0), err);
    if (served != MS_STATUS_OK) {
      (*handle_out)->drop(*handle_out);
      *handle_out = NULL;
    }
    return served;
  }
  ms_net_op_free(&accept->op);
  return status;
}

uint8_t ms_net_listener_accept(const MsObj *handle, uint8_t has_timeout, int64_t timeout, MsObj **out,
                                  MsString *err) {
  return accept_run(handle, ms_net_timeout(has_timeout, timeout), false, out, NULL, err);
}

uint8_t msstd_net_listener_accept(const MsObj *handle, uint8_t has_timeout, int64_t timeout, MsObj **out,
                                  MsString *err) {
  return ms_native_return(ms_net_listener_accept(handle, has_timeout, timeout, out, err), err);
}

uint8_t ms_net_listener_accept_raw(const MsObj *handle, uint8_t has_timeout, int64_t timeout, int64_t *out,
                                      MsString *err) {
  return accept_run(handle, ms_net_timeout(has_timeout, timeout), true, NULL, out, err);
}

uint8_t msstd_net_listener_accept_raw(const MsObj *handle, uint8_t has_timeout, int64_t timeout, int64_t *out,
                                      MsString *err) {
  return ms_native_return(ms_net_listener_accept_raw(handle, has_timeout, timeout, out, err), err);
}

void msstd_net_listener_address(const MsObj *handle, MsString *out) {
  *out = ms_string_clone(&ms_net_handle_core(handle)->local);
}

void msstd_net_listener_close(const MsObj *handle) { ms_net_handle_close(handle); }
MsObj *msstd_net_listener_share(const MsObj *handle) { return ms_net_handle_alias(handle); }
