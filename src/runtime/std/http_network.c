/* runtime/std/http_network.c: the HTTP client natives of a Network (http_network.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/http_network.h"

#include "runtime/std/fail.h"
#include "runtime/std/net_filter.h"
#include "runtime/std/net_network.h"

/* ---- the policy: the network's filter ---- */

static bool host_allowed(void *context, MsSpan host) {
  return ms_net_filter_host_allowed(context, host);
}

static bool address_allowed(void *context, const void *address) {
  return ms_net_filter_address_allowed(context, address);
}

static void *filter_retain(void *context) {
  return ms_net_filter_retain(context);
}

static void filter_release(void *context) {
  ms_net_filter_release(context);
}

/* The policy of `net` (all NULL when it is unrestricted); the caller releases `filter` with it. */
static MsHttpPolicy policy_of(MsNetFilter *filter) {
  if (filter == NULL) {
    return (MsHttpPolicy){0};
  }
  return (MsHttpPolicy){.host_allowed = host_allowed,
                        .address_allowed = address_allowed,
                        .context = filter,
                        .retain = filter_retain,
                        .release = filter_release};
}

/* A handle on `client` with the policy of `net`, and a second one the network closes with itself. */
static uint8_t bind_client(const MsObj *net, MsHttpClient *client, MsObj **out) {
  MsNetFilter *filter = ms_net_network_filter(net);
  const MsHttpPolicy policy = policy_of(filter);
  MsObj *handle = ms_http_client_handle_with_policy(client, &policy);
  MsObj *owned = ms_http_client_handle_with_policy(client, &policy);
  ms_net_filter_release(filter);
  if (!ms_net_network_adopt_client(net, owned)) {
    msstd_http_client_close(handle);
    owned->drop(owned);
    handle->drop(handle);
    return MS_STATUS_CLOSED;
  }
  *out = handle;
  return MS_STATUS_OK;
}

static uint8_t finish(uint8_t status, MsString *text, MsString *err) {
  MsFail fail = ms_fail_new();
  fail.status = status;
  fail.message = *text;
  *text = ms_string_empty();
  return ms_fail_finish(&fail, err);
}

/* ---- Network.http_client ---- */

static bool options_valid(const MsHttpClientOptionsWire *o) {
  return !(o->max_redirects_present && o->max_redirects < 0) &&
         !(o->max_idle_present && o->max_idle_connections < 0) &&
         !(o->max_header_present && o->max_header_bytes <= 0) &&
         !(o->idle_timeout_present && o->idle_timeout < 0);
}

uint8_t msstd_net_network_http_client(const MsObj *net, const MsHttpClientOptionsWire *o, MsObj **out,
                                      MsString *err) {
  *err = ms_string_empty();
  if (!options_valid(o)) {
    return MS_STATUS_INVALID_INPUT;
  }
  const MsHttpClientOptions options = {.limit_redirects = o->max_redirects_present != 0,
                                       .max_redirects = o->max_redirects,
                                       .limit_idle = o->max_idle_present != 0,
                                       .max_idle = o->max_idle_connections,
                                       .max_header_bytes =
                                           o->max_header_present != 0 ? o->max_header_bytes : 0,
                                       .expire_idle = o->idle_timeout_present != 0,
                                       .idle_timeout_ns = o->idle_timeout,
                                       .decompress = o->decompress != 0,
                                       .cookies = o->cookies != 0,
                                       .roots_pem = ms_string_span(&o->tls_roots_pem),
                                       .certificate_pem = ms_string_span(&o->tls_certificate_pem),
                                       .private_key_pem = ms_string_span(&o->tls_private_key_pem)};
  MsString text = ms_string_empty();
  MsHttpClient *client = ms_http_client_new(&options, &text);
  if (client == NULL) {
    return finish(MS_STATUS_FAILED, &text, err);
  }
  const uint8_t status = bind_client(net, client, out);
  ms_http_client_release(client);
  return finish(status, &text, err);
}

/* ---- Network.request ---- */

/* Reads the whole body into `out`; the status of the first failure. */
static uint8_t read_whole(MsHttpResponse *response, MsBytes *out, MsString *err) {
  for (;;) {
    const size_t before = out->len;
    const uint8_t status = ms_http_response_read(response, (size_t)65536, out, err);
    if (status != MS_STATUS_OK || out->len == before) {
      return status;
    }
  }
}

static uint8_t one_shot(const MsObj *net, const MsHttpRequest *request, MsClientResponseWire *out,
                        MsString *err) {
  const MsHttpClientOptions options = {.limit_redirects = true, .max_redirects = 10};
  MsString text = ms_string_empty();
  MsHttpClient *client = ms_http_client_new(&options, &text);
  if (client == NULL) {
    *err = text;
    return MS_STATUS_FAILED;
  }
  MsObj *handle = NULL;
  uint8_t status = bind_client(net, client, &handle);
  ms_http_client_release(client);
  if (status != MS_STATUS_OK) {
    return status;
  }
  MsHttpResponse *response = NULL;
  status = ms_http_handle_send(handle, request, &response, err);
  if (status == MS_STATUS_OK) {
    MsBytes body = {0};
    status = read_whole(response, &body, err);
    out->status = ms_http_response_status(response);
    out->headers = ms_headers_object(ms_headers_copy(ms_http_response_headers(response)));
    out->protocol = ms_string_from_span(ms_string_span(ms_http_response_protocol(response)));
    out->body = body;
    if (status != MS_STATUS_OK) {
      ms_bytes_free(&out->body);
      out->headers->drop(out->headers);
      ms_string_release(&out->protocol);
    }
    ms_http_response_close(response);
  }
  msstd_http_client_close(handle);
  handle->drop(handle);
  return status;
}

uint8_t msstd_net_network_request_bytes(const MsObj *net, const MsString *method, const MsString *address,
                                        const MsObj *headers, const MsBytes *body, uint8_t has_max,
                                        int64_t max, uint8_t has_timeout, int64_t timeout,
                                        MsClientResponseWire *out, MsString *err) {
  *err = ms_string_empty();
  *out = (MsClientResponseWire){.protocol = ms_string_empty()};
  const MsHttpRequest request = {.method = ms_string_span(method),
                                 .url = ms_string_span(address),
                                 .headers = ms_headers_of(headers),
                                 .body = ms_bytes_span(body),
                                 .limit_response = has_max != 0,
                                 .max_response = max,
                                 .has_timeout = has_timeout != 0,
                                 .timeout_ns = timeout};
  MsString text = ms_string_empty();
  const uint8_t status = one_shot(net, &request, out, &text);
  return finish(status, &text, err);
}
