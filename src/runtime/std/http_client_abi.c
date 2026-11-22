/* runtime/std/http_client_abi.c: the HttpClient and response-body natives (http_client_abi.h). */
#include "runtime/std/http_client_abi.h"

#include "base/alloc.h"
#include "runtime/core/task.h"
#include "runtime/core/isolate.h"
#include "runtime/std/fail.h"
#include "runtime/std/http_sync.h"

#define BODY_CHUNK ((size_t)65536)

typedef struct ClientCell {
  MsObj header;
  MsHttpClient *client;
  MsHttpPolicy policy; /* all NULL: unrestricted */
} ClientCell;

typedef struct BodyCell {
  MsObj header;
  MsHttpResponse *response; /* NULL once closed */
  int64_t status;
  MsHeaders *headers;
  MsString protocol;
} BodyCell;

static void client_drop(MsObj *object) {
  ClientCell *cell = (ClientCell *)(void *)object;
  ms_http_client_release(cell->client);
  if (cell->policy.release != NULL) {
    cell->policy.release(cell->policy.context);
  }
  ms_free(cell);
}

static void body_drop(MsObj *object) {
  BodyCell *cell = (BodyCell *)(void *)object;
  if (cell->response != NULL) {
    ms_http_response_close(cell->response);
  }
  ms_headers_free(cell->headers);
  ms_string_release(&cell->protocol);
  ms_free(cell);
}

static ClientCell *client_of(const MsObj *object) {
  return (ClientCell *)(void *)(uintptr_t)object;
}

static BodyCell *body_of(const MsObj *object) {
  return (BodyCell *)(void *)(uintptr_t)object;
}

MsObj *ms_http_client_handle_with_policy(MsHttpClient *client, const MsHttpPolicy *policy) {
  ClientCell *cell = ms_alloc_zeroed(sizeof *cell);
  cell->header.drop = client_drop;
  cell->client = ms_http_client_retain(client);
  if (policy != NULL) {
    cell->policy = *policy;
    if (policy->retain != NULL) {
      cell->policy.context = policy->retain(policy->context);
    }
  }
  return &cell->header;
}

MsObj *ms_http_client_handle(MsHttpClient *client) {
  return ms_http_client_handle_with_policy(client, NULL);
}

bool ms_http_client_handle_closed(const MsObj *handle) {
  return ms_http_client_closed(client_of(handle)->client);
}

/* ---- waiting through scheduler tokens ---- */

static uint64_t token_begin(void) {
  return ms_token_new(MS_TOKEN_REMOTE);
}

static MsHttpWake token_wait(uint64_t waiter, int64_t timeout_ns) {
  uint64_t value = 0;
  uint32_t result = 0;
  (void)ms_token_park(waiter, timeout_ns, &value, &result);
  if ((result & MS_WAIT_CANCELLED) != 0) {
    return MS_HTTP_WAIT_CANCELLED;
  }
  return (result & MS_WAIT_TIMEOUT) != 0 ? MS_HTTP_WAIT_TIMED_OUT : MS_HTTP_WOKEN;
}

static void token_wake(uint64_t waiter) {
  ms_token_post_remote(waiter, 1);
}

static void token_end(uint64_t waiter) {
  (void)ms_token_free(waiter);
}

void ms_http_install_task_waiter(void) {
  static const MsHttpWaitOps ops = {
      .begin = token_begin, .wait = token_wait, .wake = token_wake, .end = token_end};
  ms_http_set_wait_ops(&ops);
}

/* ---- the natives ---- */

void msstd_http_client_close(const MsObj *c) {
  ms_http_client_close(client_of(c)->client);
}

MsObj *msstd_http_client_share(const MsObj *c) {
  return ms_http_client_handle_with_policy(client_of(c)->client, &client_of(c)->policy);
}

/* Ends a native with the status of a call and the text it left. */
static uint8_t finish(uint8_t status, MsString *text, MsString *err) {
  MsFail fail = ms_fail_new();
  fail.status = status;
  fail.message = *text;
  *text = ms_string_empty();
  return ms_fail_finish(&fail, err);
}

static MsObj *body_new(MsHttpResponse *response) {
  BodyCell *cell = ms_alloc_zeroed(sizeof *cell);
  cell->header.drop = body_drop;
  cell->response = response;
  cell->status = ms_http_response_status(response);
  cell->headers = ms_headers_copy(ms_http_response_headers(response));
  cell->protocol = ms_string_from_span(ms_string_span(ms_http_response_protocol(response)));
  return &cell->header;
}

uint8_t ms_http_handle_send(const MsObj *handle, const MsHttpRequest *request, MsHttpResponse **out,
                            MsString *err) {
  const ClientCell *cell = client_of(handle);
  MsHttpRequest bound = *request;
  bound.host_allowed = cell->policy.host_allowed;
  bound.address_allowed = cell->policy.address_allowed;
  bound.context = cell->policy.context;
  return ms_http_client_send(cell->client, &bound, out, err);
}

uint8_t msstd_http_client_request_bytes(const MsObj *c, const MsString *method, const MsString *address,
                                        const MsObj *headers, const MsBytes *body, uint8_t has_max,
                                        int64_t max, uint8_t has_timeout, int64_t timeout, MsObj **out,
                                        MsString *err) {
  const MsHttpRequest request = {.method = ms_string_span(method),
                                 .url = ms_string_span(address),
                                 .headers = ms_headers_of(headers),
                                 .body = ms_bytes_span(body),
                                 .limit_response = has_max != 0,
                                 .max_response = max,
                                 .has_timeout = has_timeout != 0,
                                 .timeout_ns = timeout};
  MsHttpResponse *response = NULL;
  MsString text = ms_string_empty();
  const uint8_t status = ms_http_handle_send(c, &request, &response, &text);
  if (status == MS_STATUS_OK) {
    *out = body_new(response);
  }
  return finish(status, &text, err);
}

void msstd_http_body_close(const MsObj *b) {
  BodyCell *cell = body_of(b);
  if (cell->response != NULL) {
    ms_http_response_close(cell->response);
    cell->response = NULL;
  }
}

void msstd_http_body_metadata(const MsObj *b, MsHttpMetadataOut *out) {
  const BodyCell *cell = body_of(b);
  out->status = cell->status;
  out->headers = ms_headers_object(ms_headers_copy(cell->headers));
  out->protocol = ms_string_from_span(ms_string_span(&cell->protocol));
}

uint8_t msstd_http_body_read(const MsObj *b, uint8_t has_max, int64_t max, MsBytes *out, MsString *err) {
  BodyCell *cell = body_of(b);
  size_t limit = BODY_CHUNK;
  if (has_max != 0 && max <= 0) {
    MsString none = ms_string_empty();
    return finish(MS_STATUS_INVALID_INPUT, &none, err);
  }
  if (has_max != 0 && (uint64_t)max < limit) {
    limit = (size_t)max;
  }
  MsString text = ms_string_empty();
  uint8_t status = MS_STATUS_CLOSED;
  if (cell->response != NULL) {
    const size_t before = out->len;
    status = ms_http_response_read(cell->response, limit, out, &text);
    if (status == MS_STATUS_OK && out->len == before) {
      status = MS_STATUS_NONE;
    }
  }
  return finish(status, &text, err);
}

uint8_t msstd_http_body_read_all(const MsObj *b, MsBytes *out, MsString *err) {
  BodyCell *cell = body_of(b);
  MsString text = ms_string_empty();
  uint8_t status = MS_STATUS_CLOSED;
  while (cell->response != NULL) {
    const size_t before = out->len;
    status = ms_http_response_read(cell->response, BODY_CHUNK, out, &text);
    if (status != MS_STATUS_OK || out->len == before) {
      break;
    }
  }
  if (status != MS_STATUS_OK) {
    ms_bytes_free(out);
  }
  return finish(status, &text, err);
}
