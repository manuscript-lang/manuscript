/* runtime/std/http_client_send.c: validating a request and the loop over its redirect hops. */
#include "base/alloc.h"
#include "base/chars.h"
#include "runtime/std/http_client_internal.h"

static uint8_t fail(MsString *err, uint8_t status, const char *text) {
  *err = ms_string_from_span(ms_span_of_text(text));
  return status;
}

/* Header names are tokens, values are text, and the names the transport owns are refused. */
static bool outgoing_valid(const MsHeaders *headers) {
  for (size_t g = 0; headers != NULL && g < ms_headers_group_count(headers); g++) {
    const MsSpan name = ms_headers_group_name(headers, g);
    if (!ms_header_valid_name(name) || ms_ascii_is_text_fold(name, "Host") ||
        ms_ascii_is_text_fold(name, "Content-Length") || ms_ascii_is_text_fold(name, "Transfer-Encoding")) {
      return false;
    }
    for (size_t v = 0; v < ms_headers_group_size(headers, g); v++) {
      if (!ms_header_valid_value(ms_headers_group_value(headers, g, v))) {
        return false;
      }
    }
  }
  return true;
}

static uint8_t check(MsHttpClient *client, const MsHttpRequest *request) {
  if (ms_http_client_closed(client)) {
    return MS_STATUS_CLOSED;
  }
  if ((request->limit_response && request->max_response < 0) ||
      (request->has_timeout && request->timeout_ns < 0) || !ms_header_valid_name(request->method) ||
      !outgoing_valid(request->headers)) {
    return MS_STATUS_INVALID_INPUT;
  }
  return MS_STATUS_OK;
}

static bool allowed(const MsHttpRequest *request, const MsHttpUrl *url) {
  if (request->host_allowed == NULL) {
    return true;
  }
  MsString host = ms_http_url_host(url);
  const bool ok = request->host_allowed(request->context, ms_string_span(&host));
  ms_string_release(&host);
  return ok;
}

/* The state of one exchange across its hops. */
typedef struct Exchange {
  MsString method;
  MsHttpUrl *first;
  MsHttpUrl *last; /* the URL of the hop being sent */
  MsHttpUrl *current;
  MsHeaders *headers; /* the hop's own fields */
  bool keep_body;
  size_t followed;
} Exchange;

static void exchange_free(Exchange *x) {
  ms_string_release(&x->method);
  ms_http_url_free(x->first);
  if (x->last != x->first) {
    ms_http_url_free(x->last);
  }
  if (x->current != x->last && x->current != x->first) {
    ms_http_url_free(x->current);
  }
  ms_headers_free(x->headers);
}

/* Where a redirect response leads: OK with `*next` set, OK with NULL when it is returned as it is, or a
 * failure. */
static uint8_t redirect_target(const MsHttpClient *client, const MsHttpRequest *request, Exchange *x,
                               MsHttpResponse *response, MsHttpUrl **next, MsString *method, MsString *err) {
  *next = NULL;
  MsSpan location;
  if (!ms_http_redirect_method(ms_http_response_status(response), ms_string_span(&x->method), method,
                               &x->keep_body) ||
      !ms_http_head_find(response, "Location", &location) ||
      (client->options.limit_redirects && client->options.max_redirects == 0)) {
    return MS_STATUS_OK;
  }
  MsHttpUrl *target = ms_http_url_resolve(x->current, location);
  if (target == NULL) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "failed to parse Location header \"");
    ms_strbuild_append(&text, location);
    ms_strbuild_append_text(&text, "\": invalid redirect target");
    *err = ms_strbuild_finish(&text);
    ms_strbuild_free(&text);
    return MS_STATUS_FAILED;
  }
  if (client->options.limit_redirects && x->followed >= (size_t)client->options.max_redirects) {
    ms_http_url_free(target);
    return fail(err, MS_STATUS_FAILED, "redirect limit exceeded");
  }
  if (ms_http_url_is_https(x->current) && !ms_http_url_is_https(target)) {
    ms_http_url_free(target);
    return fail(err, MS_STATUS_FAILED, "TLS downgrade redirect rejected");
  }
  if (!allowed(request, target)) {
    ms_http_url_free(target);
    return fail(err, MS_STATUS_FAILED, "network policy denied redirect");
  }
  *next = target;
  return MS_STATUS_OK;
}

/* The fields of the next hop: the redirect rules, then a fresh Referer. */
static MsHeaders *next_headers(const MsHttpRequest *request, Exchange *x, const MsHttpUrl *next) {
  MsHeaders *headers = ms_http_redirect_headers(x->headers, x->first, x->current, next, x->keep_body);
  ms_headers_remove(headers, ms_span_of_text("Referer"));
  MsString referer = ms_string_empty();
  MsHeaders *initial = request->headers != NULL ? ms_headers_copy(request->headers) : ms_headers_new();
  if (ms_http_referer_for(x->current, next, initial, &referer)) {
    ms_headers_set(headers, ms_span_of_text("Referer"), ms_string_span(&referer));
  }
  ms_string_release(&referer);
  ms_headers_free(initial);
  return headers;
}

static uint8_t one_hop(MsHttpClient *client, const MsHttpRequest *request, Exchange *x, MsHttpResponse **out,
                       MsString *err) {
  MsString url = ms_http_url_text(x->current);
  MsHttpResponse *response = ms_http_response_new(client, request);
  const HttpHop hop = {.method = ms_string_span(&x->method),
                       .url = ms_string_span(&url),
                       .headers = x->headers,
                       .body = request->body,
                       .send_body = x->followed == 0 || x->keep_body};
  const uint8_t sent = ms_http_hop_run(response, &hop, err);
  ms_string_release(&url);
  if (sent != MS_STATUS_OK) {
    ms_http_response_close(response);
    return sent;
  }
  *out = response;
  return MS_STATUS_OK;
}

/* Reads each hop's head until one is final. */
static uint8_t follow(MsHttpClient *client, const MsHttpRequest *request, Exchange *x, MsHttpResponse **out,
                      MsString *err) {
  for (;;) {
    MsHttpResponse *response = NULL;
    uint8_t status = one_hop(client, request, x, &response, err);
    if (status != MS_STATUS_OK) {
      return status;
    }
    MsHttpUrl *next = NULL;
    MsString method = ms_string_empty();
    status = redirect_target(client, request, x, response, &next, &method, err);
    if (status != MS_STATUS_OK || next == NULL) {
      ms_string_release(&method);
      if (status != MS_STATUS_OK) {
        ms_http_response_close(response);
        return status;
      }
      *out = response;
      return MS_STATUS_OK;
    }
    ms_http_response_discard(response);
    MsHeaders *headers = next_headers(request, x, next);
    ms_headers_free(x->headers);
    x->headers = headers;
    ms_string_release(&x->method);
    x->method = method;
    if (x->current != x->first) {
      ms_http_url_free(x->current);
    }
    x->current = next;
    x->last = next;
    x->followed++;
  }
}

uint8_t ms_http_client_send(MsHttpClient *client, const MsHttpRequest *request, MsHttpResponse **out,
                            MsString *err) {
  uint8_t status = check(client, request);
  if (status != MS_STATUS_OK) {
    return status;
  }
  MsHttpUrl *url = ms_http_url_parse(request->url);
  if (url == NULL) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (!allowed(request, url)) {
    ms_http_url_free(url);
    return MS_STATUS_PERMISSION_DENIED;
  }
  Exchange x = {.method = ms_string_from_span(request->method),
                .first = url,
                .last = url,
                .current = url,
                .headers = request->headers != NULL ? ms_headers_copy(request->headers) : ms_headers_new(),
                .keep_body = true};
  MsHttpResponse *response = NULL;
  status = follow(client, request, &x, &response, err);
  if (status == MS_STATUS_OK) {
    status = ms_http_head_finish(response);
    if (status != MS_STATUS_OK) {
      ms_http_response_close(response);
      response = NULL;
    }
  }
  exchange_free(&x);
  *out = response;
  return status;
}
