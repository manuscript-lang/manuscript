/* TLS on a connection of the network loop: the ciphertext pump, the handshake and the natives that start TLS, accept
 * it, connect with it and describe it (see net_tls.h for the session, net_conn.c for TLS reads and writes). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/fail.h"
#include "runtime/std/net_calls.h"
#include "runtime/std/net_tls_conn.h"

#include <string.h>

#include "base/alloc.h"
#include "base/strbuild.h"
#include "runtime/core/unwind.h"
#include "runtime/std/net_conn.h"
#include "runtime/std/net_network.h"

enum { CIPHER_BYTES = 16 * 1024 };

/* ---- the pump ---- */

void ms_net_cipher_collect(MsNetCore *core, uint8_t **data, size_t *length) {
  uint8_t chunk[CIPHER_BYTES];
  MsStrBuild collected = ms_strbuild_new();
  size_t count = 0;
  while ((count = ms_net_tls_outgoing(core->tls, chunk, sizeof chunk)) > 0) {
    ms_strbuild_append(&collected, ms_span_of(chunk, count));
  }
  const MsSpan all = ms_strbuild_span(&collected);
  *data = ms_alloc(all.len + 1);
  if (all.len != 0) {
    memcpy(*data, all.ptr, all.len);
  }
  *length = all.len;
  ms_strbuild_free(&collected);
}

typedef struct CipherWrite {
  uv_write_t request;
  uint8_t *data;
  void (*done)(void *argument, int status);
  void *argument;
} CipherWrite;

static void on_cipher_written(uv_write_t *request, int status) {
  CipherWrite *write = request->data;
  if (write->done != NULL) {
    write->done(write->argument, status);
  }
  ms_free(write->data);
  ms_free(write);
}

int ms_net_cipher_flush(MsNetCore *core, void (*done)(void *argument, int status), void *argument) {
  uint8_t *data = NULL;
  size_t length = 0;
  ms_net_cipher_collect(core, &data, &length);
  if (length == 0) {
    ms_free(data);
    return 0;
  }
  CipherWrite *write = ms_alloc_zeroed(sizeof *write);
  write->data = data;
  write->done = done;
  write->argument = argument;
  write->request.data = write;
  uv_buf_t buffer = uv_buf_init((char *)data, (unsigned int)length);
  const int code = uv_write(&write->request, &core->h.stream, &buffer, 1, on_cipher_written);
  if (code != 0) {
    ms_free(data);
    ms_free(write);
    return code;
  }
  return 1;
}

/* ---- the handshake ---- */

typedef struct HandshakeOp {
  MsNetOp op;
  MsNetCore *core;  /* a reference */
  MsNetTls *session; /* owned until the core takes it */
  uint8_t *cipher;
} HandshakeOp;

static void handshake_release(MsNetOp *op) {
  HandshakeOp *handshake = (HandshakeOp *)op;
  ms_net_tls_free(handshake->session);
  ms_free(handshake->cipher);
  ms_net_core_unref(handshake->core);
}

static void step(HandshakeOp *handshake);

static void on_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
  HandshakeOp *handshake = ((MsNetCore *)(void *)handle)->reading;
  (void)suggested;
  *buffer = uv_buf_init((char *)handshake->cipher, CIPHER_BYTES);
}

static void on_data(uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
  MsNetCore *core = (MsNetCore *)(void *)stream;
  HandshakeOp *handshake = core->reading;
  (void)buffer;
  if (count == 0 || handshake == NULL) {
    return;
  }
  core->reading = NULL;
  (void)uv_read_stop(stream);
  if (count < 0) {
    ms_net_op_done(&handshake->op, count == UV_EOF ? UV_ECONNRESET : (int)count);
    return;
  }
  ms_net_tls_incoming(core->tls, ms_span_of(handshake->cipher, (size_t)count));
  step(handshake);
}

static void on_final_flight(void *argument, int status) {
  ms_net_op_done(argument, status);
}

/* Advances the handshake as far as the bytes allow, then waits for more or ends. */
static void step(HandshakeOp *handshake) {
  MsNetCore *core = handshake->core;
  switch (ms_net_tls_handshake(core->tls)) {
  case MS_NET_TLS_DONE: {
    const int sent = ms_net_cipher_flush(core, on_final_flight, handshake);
    if (sent != 1) {
      ms_net_op_done(&handshake->op, sent);
    }
    return;
  }
  case MS_NET_TLS_WANT_IO:
    break;
  default:
    ms_net_op_done(&handshake->op, UV_EPROTO);
    return;
  }
  const int sent = ms_net_cipher_flush(core, NULL, NULL);
  if (sent < 0) {
    ms_net_op_done(&handshake->op, sent);
    return;
  }
  core->reading = handshake;
  const int code = uv_read_start(&core->h.stream, on_alloc, on_data);
  if (code != 0) {
    core->reading = NULL;
    ms_net_op_done(&handshake->op, code);
  }
}

static void handshake_start(MsNetOp *op) {
  HandshakeOp *handshake = (HandshakeOp *)op;
  MsNetCore *core = handshake->core;
  if (atomic_load(&core->closed) || core->broken) {
    ms_net_op_done(op, MS_NET_CLOSED);
  } else if (core->tls != NULL) {
    ms_net_op_done(op, UV_EISCONN);
  } else if (core->reading != NULL) {
    ms_net_op_done(op, UV_EBUSY);
  } else {
    core->tls = handshake->session;
    handshake->session = NULL;
    handshake->cipher = ms_alloc(CIPHER_BYTES);
    step(handshake);
  }
}

static void handshake_abandon(MsNetOp *op) {
  HandshakeOp *handshake = (HandshakeOp *)op;
  if (handshake->core->reading == handshake) {
    handshake->core->reading = NULL;
    (void)uv_read_stop(&handshake->core->h.stream);
    ms_net_op_done(op, UV_ECANCELED);
  }
}

/* Runs a TLS handshake on `core` with a new session of `ctx`. A failed or timed out handshake closes the connection. */
static uint8_t upgrade(MsNetCore *core, MsNetTlsCtx *ctx, MsSpan host, int64_t timeout_ns, MsString *err) {
  *err = ms_string_empty();
  MsNetTls *session = ms_net_tls_new(ctx, host);
  if (session == NULL) {
    return MS_STATUS_INVALID_INPUT;
  }
  HandshakeOp *handshake = ms_net_op_new(sizeof *handshake, handshake_start, handshake_abandon, handshake_release);
  atomic_fetch_add(&core->references, 1);
  handshake->core = core;
  handshake->session = session;
  const MsNetWait wait = ms_net_run(&handshake->op, timeout_ns);
  if (wait == MS_NET_WAIT_DONE && handshake->op.status == UV_EISCONN) {
    ms_net_op_free(&handshake->op);
    return MS_STATUS_INVALID_INPUT;
  }
  const bool protocol = wait == MS_NET_WAIT_DONE && handshake->op.status == UV_EPROTO;
  uint8_t status = ms_net_finish(wait, wait == MS_NET_WAIT_DONE ? handshake->op.status : 0, "tls handshake", err);
  if (protocol) {
    ms_string_release(err);
    *err = ms_string_from_span(ms_span_of_text(ms_net_tls_error(core->tls)));
  }
  if (wait == MS_NET_WAIT_DONE) {
    ms_net_op_free(&handshake->op);
  }
  if (status != MS_STATUS_OK) {
    ms_net_core_close(core);
  }
  return status;
}

/* ---- options ---- */

/* The context the options describe, or NULL for options that cannot be used. */
MsNetTlsCtx *ms_net_tls_ctx_from_options(bool server, const MsTlsOptions *options) {
  const MsSpan roots = ms_string_span(&options->roots_pem);
  if (!server && options->require_client_certificate != 0) {
    return NULL;
  }
  MsNetTlsCtx *ctx = ms_net_tls_ctx_new(server, ms_string_span(&options->certificate_pem),
                                        ms_string_span(&options->private_key_pem), server ? ms_span_of(NULL, 0) : roots);
  if (ctx == NULL) {
    return NULL;
  }
  const bool clients = server && (roots.len > 0 || options->require_client_certificate != 0);
  const MsString *names = (const MsString *)(const void *)options->alpn.ptr;
  const bool ok = (options->alpn.len == 0 || ms_net_tls_ctx_set_alpn(ctx, names, options->alpn.len)) &&
                  (!clients || ms_net_tls_ctx_verify_clients(ctx, roots, options->require_client_certificate != 0));
  if (!ok) {
    ms_net_tls_ctx_release(ctx);
    return NULL;
  }
  return ctx;
}

static bool usable_name(const MsString *name) {
  const MsSpan text = ms_string_span(name);
  return text.len > 0 && memchr(text.ptr, 0, text.len) == NULL;
}

/* ---- natives ---- */

uint8_t ms_net_connection_start_tls(const MsObj *handle, const MsTlsOptions *options, uint8_t has_timeout,
                                       int64_t timeout, MsObj **out, MsString *err) {
  *err = ms_string_empty();
  if (!usable_name(&options->server_name)) {
    return MS_STATUS_INVALID_INPUT;
  }
  MsNetTlsCtx *ctx = ms_net_tls_ctx_from_options(false, options);
  if (ctx == NULL) {
    return MS_STATUS_INVALID_INPUT;
  }
  MsNetCore *core = ms_net_handle_core(handle);
  const uint8_t status = upgrade(core, ctx, ms_string_span(&options->server_name), ms_net_timeout(has_timeout, timeout), err);
  ms_net_tls_ctx_release(ctx);
  if (status == MS_STATUS_OK) {
    *out = ms_net_handle_upgraded(handle); /* `plain` is consumed */
  }
  return status;
}

uint8_t msstd_net_connection_start_tls(const MsObj *handle, const MsTlsOptions *options, uint8_t has_timeout,
                                       int64_t timeout, MsObj **out, MsString *err) {
  return ms_native_return(ms_net_connection_start_tls(handle, options, has_timeout, timeout, out, err), err);
}

uint8_t ms_net_connection_accept_tls(const MsObj *handle, const MsTlsOptions *options, uint8_t has_timeout,
                                        int64_t timeout, MsObj **out, MsString *err) {
  *err = ms_string_empty();
  MsNetTlsCtx *ctx = ms_net_tls_ctx_from_options(true, options);
  if (ctx == NULL) {
    return MS_STATUS_INVALID_INPUT;
  }
  const uint8_t status = upgrade(ms_net_handle_core(handle), ctx, ms_span_of(NULL, 0),
                                 ms_net_timeout(has_timeout, timeout), err);
  ms_net_tls_ctx_release(ctx);
  if (status == MS_STATUS_OK) {
    *out = ms_net_handle_upgraded(handle); /* `plain` is consumed */
  }
  return status;
}

uint8_t msstd_net_connection_accept_tls(const MsObj *handle, const MsTlsOptions *options, uint8_t has_timeout,
                                        int64_t timeout, MsObj **out, MsString *err) {
  return ms_native_return(ms_net_connection_accept_tls(handle, options, has_timeout, timeout, out, err), err);
}

uint8_t ms_net_tls_serve(MsNetCore *core, int64_t timeout_ns, MsString *err) {
  return upgrade(core, core->tls_ctx, ms_span_of(NULL, 0), timeout_ns, err);
}

uint8_t msstd_net_connection_tls_info(const MsObj *handle, MsTlsInfo *out) {
  const MsNetTls *tls = ms_net_handle_core(handle)->tls;
  if (tls == NULL) {
    return MS_STATUS_INVALID_INPUT; /* a plain connection has no TLS details */
  }
  out->version = ms_net_tls_version(tls);
  out->cipher_suite = ms_net_tls_cipher(tls);
  out->alpn = ms_string_from_span(ms_net_tls_alpn(tls));
  const size_t count = ms_net_tls_peer_count(tls);
  out->peer_certificates = (MsList){0};
  for (size_t i = 0; i < count; i++) {
    MsBytes der = ms_net_tls_peer_der(tls, i);
    ms_list_push(&out->peer_certificates, sizeof der, &der);
  }
  out->verified = ms_net_tls_verified(tls) ? 1 : 0;
  return MS_STATUS_OK;
}

uint8_t ms_net_network_connect_tls_config(const MsObj *net, const MsString *address, const MsTlsOptions *options,
                                             uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err) {
  *err = ms_string_empty();
  if (!usable_name(&options->server_name)) {
    return MS_STATUS_INVALID_INPUT;
  }
  MsNetTlsCtx *ctx = ms_net_tls_ctx_from_options(false, options);
  if (ctx == NULL) {
    return MS_STATUS_INVALID_INPUT;
  }
  const int64_t limit = ms_net_timeout(has_timeout, timeout);
  const uint64_t started = uv_hrtime();
  MsObj *socket = NULL;
  uint8_t status = ms_net_network_connect(net, address, has_timeout, timeout, &socket, err);
  if (status == MS_STATUS_OK) {
    const int64_t left = limit < 0 ? -1 : limit - (int64_t)(uv_hrtime() - started);
    status = upgrade(ms_net_handle_core(socket), ctx, ms_string_span(&options->server_name), limit >= 0 && left <= 0 ? 0 : left, err);
    if (status == MS_STATUS_OK) {
      *out = socket;
    } else {
      socket->drop(socket);
    }
  }
  ms_net_tls_ctx_release(ctx);
  return status;
}

uint8_t msstd_net_network_connect_tls_config(const MsObj *net, const MsString *address, const MsTlsOptions *options,
                                             uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err) {
  return ms_native_return(ms_net_network_connect_tls_config(net, address, options, has_timeout, timeout, out, err), err);
}

uint8_t ms_net_network_listen_tls(const MsObj *net, const MsString *address, const MsTlsOptions *options,
                                     uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err) {
  (void)has_timeout;
  (void)timeout;
  *err = ms_string_empty();
  MsNetTlsCtx *ctx = ms_net_tls_ctx_from_options(true, options);
  if (ctx == NULL) {
    return MS_STATUS_INVALID_INPUT;
  }
  MsObj *listener = NULL;
  const uint8_t status = ms_net_network_listen(net, address, &listener, err);
  if (status == MS_STATUS_OK) {
    ms_net_handle_core(listener)->tls_ctx = ctx; /* the listener owns the reference */
    *out = listener;
  } else {
    ms_net_tls_ctx_release(ctx);
  }
  return status;
}

uint8_t msstd_net_network_listen_tls(const MsObj *net, const MsString *address, const MsTlsOptions *options,
                                     uint8_t has_timeout, int64_t timeout, MsObj **out, MsString *err) {
  return ms_native_return(ms_net_network_listen_tls(net, address, options, has_timeout, timeout, out, err), err);
}
