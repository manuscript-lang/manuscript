/* runtime/std/http_serve_abi.c: the server natives (http_serve_abi.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/http_serve_abi.h"
#include "runtime/std/net_core.h"

#include "base/alloc.h"
#include "runtime/std/fail.h"
#include "runtime/std/http_serve_internal.h"
#include "runtime/std/net_conn.h"
#include "runtime/std/net_tls_conn.h"
#include "runtime/std/ws_abi.h"

/* ---- the program's handler ---- */

/* A compiled closure: the header, then the code. The code of `fn(move NativeExchange) Bool` takes the closure, then
 * the handle, which the handler now owns and drops, and answers whether the program's handler returned an error:
 * the wrapper releases that error itself. */
typedef struct HandlerClosure {
  MsObj header;
  uint8_t (*code)(void *closure, int64_t exchange); /* true when the handler returned an error (`native_handler`) */
} HandlerClosure;
_Static_assert(offsetof(HandlerClosure, code) == 16, "the compiler puts a closure's code after its header");

static MsHandlerEnd call_handler(void *context, MsExchange *exchange) {
  HandlerClosure *closure = context;
  MsObj *handle = ms_exchange_handle(exchange);
  return closure->code(closure, (int64_t)(intptr_t)handle) == 0 ? MS_HANDLER_OK : MS_HANDLER_ERROR;
}

static void drop_handler(void *context) {
  MsObj *closure = context;
  closure->drop(closure);
}

/* The handles natives receive are const views of objects the runtime owns. */
static MsObj *mutable_object(const MsObj *object) {
  return (MsObj *)(uintptr_t)object;
}

/* ---- the objects ---- */

typedef struct Serving {
  MsObj header;
  MsServeShared *shared;
  MsObj *listener;
} Serving;

typedef struct Spec {
  MsObj header;
  MsServeShared *shared;
} Spec;

typedef struct Worker {
  MsObj header;
  MsServeWorker *worker;
} Worker;

static void serving_drop(MsObj *object) {
  Serving *serving = (Serving *)(void *)object;
  msstd_net_listener_close(serving->listener);
  serving->listener->drop(serving->listener);
  ms_serve_shared_release(serving->shared);
  ms_free(serving);
}

static void spec_drop(MsObj *object) {
  Spec *spec = (Spec *)(void *)object;
  ms_serve_shared_release(spec->shared);
  ms_free(spec);
}

static void worker_drop(MsObj *object) {
  Worker *worker = (Worker *)(void *)object;
  if (worker->worker != NULL) {
    ms_serve_worker_close(worker->worker);
  }
  ms_free(worker);
}

/* ---- options ---- */

/* The size a limit option names: SIZE_MAX for none, false for a negative one. */
static bool size_limit(MsOptionalInt option, size_t *out) {
  if (!option.present) {
    *out = SIZE_MAX;
    return true;
  }
  *out = (size_t)option.value;
  return option.value >= 0;
}

static bool time_limit(MsOptionalInt option, int64_t *out) {
  *out = option.present ? option.value : -1;
  return !option.present || option.value >= 0;
}

enum { DEFAULT_HEADER_BYTES = 1 << 20 };

static bool limits_of(const MsHttpServerOptionsWire *wire, MsServeLimits *limits) {
  MsOptionalInt header = wire->max_header_bytes;
  if (!header.present) {
    header = (MsOptionalInt){1, DEFAULT_HEADER_BYTES};
  }
  const bool valid =
      size_limit(wire->max_requests, &limits->admission) && size_limit(wire->max_body_bytes, &limits->body) &&
      size_limit(wire->max_response_bytes, &limits->response) && size_limit(header, &limits->header) &&
      time_limit(wire->timeout, &limits->timeout_ns) && time_limit(wire->grace, &limits->grace_ns);
  return valid && limits->admission != 0 && limits->header != 0 && limits->timeout_ns != 0;
}

/* ---- the TLS handshake of an accepted connection ---- */

typedef struct Secure {
  MsNetTlsCtx *ctx;
} Secure;

static uint8_t secure_accept(void *context, MsWsTransport *io, int64_t timeout_ns, bool *h2, MsString *err) {
  const Secure *secure = context;
  MsNetCore *core = ms_net_handle_core(io->context);
  core->tls_ctx = ms_net_tls_ctx_retain(secure->ctx);
  const uint8_t status = ms_net_tls_serve(core, timeout_ns, err);
  if (status == MS_STATUS_OK) {
    *h2 = ms_span_is_text(ms_net_tls_alpn(core->tls), "h2");
  }
  return status;
}

static void secure_release(void *context) {
  Secure *secure = context;
  ms_net_tls_ctx_release(secure->ctx);
  ms_free(secure);
}

/* A server context for `wire`'s TLS leaves; offers HTTP/1.1 unless the caller named protocols. */
static MsNetTlsCtx *server_context(const MsHttpServerOptionsWire *wire) {
  MsTlsOptions options = {.server_name = wire->tls_server_name,
                          .roots_pem = wire->tls_roots_pem,
                          .certificate_pem = wire->tls_certificate_pem,
                          .private_key_pem = wire->tls_private_key_pem,
                          .alpn = wire->tls_alpn,
                          .require_client_certificate = wire->tls_require_client_certificate};
  MsString protocol = ms_string_from_span(ms_span_of_text("http/1.1"));
  MsList fallback = {0};
  if (options.alpn.len == 0) {
    ms_list_push(&fallback, sizeof protocol, &protocol);
    options.alpn = fallback;
  }
  MsNetTlsCtx *ctx = ms_net_tls_ctx_from_options(true, &options);
  ms_list_free(&fallback);
  ms_string_release(&protocol);
  return ctx;
}

/* ---- the serving ---- */

uint8_t msstd_http_serving_new(const MsString *address, const MsHttpServerOptionsWire *wire, MsObj *handler,
                               MsObj **out, MsString *err) {
  *err = ms_string_empty();
  MsServeLimits limits;
  MsNetTlsCtx *ctx = NULL;
  uint8_t status = MS_STATUS_INVALID_INPUT;
  const bool valid = limits_of(wire, &limits);
  if (valid && wire->tls_present) {
    ctx = server_context(wire);
  }
  MsObj *listener = NULL;
  if (valid && (!wire->tls_present || ctx != NULL)) {
    status = ms_net_listen(ms_string_span(address), &listener, err);
  }
  if (status != MS_STATUS_OK) {
    handler->drop(handler);
    ms_net_tls_ctx_release(ctx);
    return status;
  }
  Serving *serving = ms_alloc_zeroed(sizeof *serving);
  serving->header.drop = serving_drop;
  serving->listener = listener;
  serving->shared = ms_serve_shared_new(&limits, call_handler, handler, drop_handler);
  if (ctx != NULL) {
    Secure *secure = ms_alloc_zeroed(sizeof *secure);
    secure->ctx = ctx;
    serving->shared->secure = secure_accept;
    serving->shared->secure_context = secure;
    serving->shared->secure_release = secure_release;
  }
  *out = &serving->header;
  return MS_STATUS_OK;
}

MsObj *msstd_http_serving_spec(const MsObj *object) {
  Spec *spec = ms_alloc_zeroed(sizeof *spec);
  spec->header.drop = spec_drop;
  spec->shared = ms_serve_shared_retain(((const Serving *)(const void *)object)->shared);
  return &spec->header;
}

void msstd_http_serving_address(const MsObj *object, MsString *out) {
  msstd_net_listener_address(((const Serving *)(const void *)object)->listener, out);
}

uint8_t msstd_http_serving_accept(const MsObj *object, int64_t *out, MsString *err) {
  return msstd_net_listener_accept_raw(((const Serving *)(const void *)object)->listener, 0, 0, out, err);
}

void msstd_http_serving_release(const MsObj *object) {
  msstd_net_listener_close(((const Serving *)(const void *)object)->listener);
}

uint8_t msstd_http_serving_worker(const MsObj *object, MsObj **out, MsString *err) {
  *err = ms_string_empty();
  Worker *worker = ms_alloc_zeroed(sizeof *worker);
  worker->header.drop = worker_drop;
  worker->worker = ms_serve_worker_new(((const Spec *)(const void *)object)->shared);
  *out = &worker->header;
  return MS_STATUS_OK;
}

void msstd_http_worker_adopt(const MsObj *object, int64_t raw) {
  Worker *worker = (Worker *)(void *)mutable_object(object);
  MsObj *connection = NULL;
  MsString err = ms_string_empty();
  if (worker->worker == NULL || msstd_net_connection_adopt(raw, &connection, &err) != MS_STATUS_OK) {
    ms_string_release(&err);
    return;
  }
  const MsWsTransport stream = ms_net_connection_transport(connection);
  ms_net_core_set_stealable(ms_net_handle_core(connection), true); /* another thread may take it between requests */
  ms_serve_worker_adopt(worker->worker, &stream, false);
}

void msstd_http_worker_close(const MsObj *object) {
  Worker *worker = (Worker *)(void *)mutable_object(object);
  MsServeWorker *engine = worker->worker;
  worker->worker = NULL;
  if (engine != NULL) {
    ms_serve_worker_close(engine);
  }
}

/* ---- the exchange ---- */

static MsExchange *exchange_of(const MsObj *object) {
  return (MsExchange *)(void *)mutable_object(object);
}

void msstd_http_exchange_close(const MsObj *object) {
  ms_exchange_close(exchange_of(object));
}

MsObj *msstd_http_exchange_headers(const MsObj *object) {
  return ms_headers_object(ms_headers_copy(exchange_of(object)->headers));
}

void msstd_http_exchange_method(const MsObj *object, MsString *out) {
  *out = ms_string_from_span(ms_string_span(&exchange_of(object)->method));
}

void msstd_http_exchange_path(const MsObj *object, MsString *out) {
  *out = ms_string_from_span(ms_string_span(&exchange_of(object)->path));
}

void msstd_http_exchange_query(const MsObj *object, MsString *out) {
  *out = ms_string_from_span(ms_string_span(&exchange_of(object)->query));
}

void msstd_http_exchange_protocol(const MsObj *object, MsString *out) {
  *out = ms_string_from_span(ms_span_of_text(exchange_of(object)->protocol));
}

uint8_t msstd_http_exchange_read(const MsObj *object, uint8_t has_max, int64_t max, MsBytes *out,
                                 MsString *err) {
  *err = ms_string_empty();
  MsString text = ms_string_empty();
  const uint8_t status = ms_exchange_read(exchange_of(object), has_max != 0, max, out, &text);
  return ms_fail_finish_with(status, &text, err);
}

uint8_t msstd_http_exchange_send_headers(const MsObj *object, int64_t status, const MsObj *headers,
                                         MsString *err) {
  *err = ms_string_empty();
  MsString text = ms_string_empty();
  return ms_fail_finish_with(ms_exchange_send_headers(exchange_of(object), status, ms_headers_of(headers)), &text, err);
}

uint8_t msstd_http_exchange_send(const MsObj *object, int64_t status, const MsObj *headers,
                                 const MsBytes *body, MsString *err) {
  *err = ms_string_empty();
  MsString text = ms_string_empty();
  const uint8_t result =
      ms_exchange_send(exchange_of(object), status, ms_headers_of(headers), ms_bytes_span(body), &text);
  return ms_fail_finish_with(result, &text, err);
}

uint8_t msstd_http_exchange_write(const MsObj *object, const MsString *data, MsString *err) {
  *err = ms_string_empty();
  MsString text = ms_string_empty();
  return ms_fail_finish_with(ms_exchange_write(exchange_of(object), ms_string_span(data), &text), &text, err);
}

uint8_t msstd_http_exchange_write_bytes(const MsObj *object, const MsBytes *data, MsString *err) {
  *err = ms_string_empty();
  MsString text = ms_string_empty();
  return ms_fail_finish_with(ms_exchange_write(exchange_of(object), ms_bytes_span(data), &text), &text, err);
}

/* The spans of a list of strings; free with ms_free. */
static MsSpan *spans_of(const MsList *list) {
  const MsString *items = (const MsString *)(const void *)list->ptr;
  MsSpan *spans = ms_alloc_zeroed((list->len + 1) * sizeof *spans);
  for (size_t i = 0; i < list->len; i++) {
    spans[i] = ms_string_span(&items[i]);
  }
  return spans;
}

uint8_t msstd_http_exchange_upgrade(const MsObj *object, const MsList *origins, const MsList *subprotocols,
                                    uint8_t has_max, int64_t max, MsObj **out, MsString *err) {
  *err = ms_string_empty();
  MsString text = ms_string_empty();
  MsSpan *allowed = spans_of(origins);
  MsSpan *offered = spans_of(subprotocols);
  MsWsSession *session = NULL;
  const uint8_t status = ms_exchange_upgrade(exchange_of(object), allowed, origins->len, offered,
                                             subprotocols->len, has_max != 0, max, &session, &text);
  ms_free(allowed);
  ms_free(offered);
  if (status == MS_STATUS_OK) {
    *out = ms_ws_handle_new(session);
    ms_ws_session_release(session);
  }
  return ms_fail_finish_with(status, &text, err);
}
