/* runtime/std/ws_dial.c: Network.web_socket (ws_dial.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/ws_dial.h"
#include "runtime/std/net_calls.h"

#include "base/alloc.h"
#include "base/chars.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "runtime/std/fail.h"
#include "runtime/std/http_client.h"
#include "runtime/std/net_conn.h"
#include "runtime/std/net_network.h"
#include "runtime/std/net_tls_conn.h"
#include "runtime/std/ws_abi.h"
#include "runtime/sys/sys.h"

#define HEAD_LIMIT ((size_t)1 << 20)

/* ---- the response head ---- */

static bool next_line(MsSpan *text, MsSpan *line) {
  for (size_t i = 0; i + 1 < text->len; i++) {
    if (text->ptr[i] == '\r' && text->ptr[i + 1] == '\n') {
      *line = ms_span_of(text->ptr, i);
      *text = ms_span_of(text->ptr + i + 2, text->len - i - 2);
      return true;
    }
  }
  return false;
}

/* "HTTP/1.x NNN reason" */
static bool parse_status(MsSpan line, uint16_t *status) {
  if (line.len < 12 || !ms_span_starts_with(line, ms_span_of_text("HTTP/1.")) || line.ptr[8] != ' ') {
    return false;
  }
  uint16_t value = 0;
  for (size_t i = 9; i < 12; i++) {
    if (!ms_ascii_is_digit(line.ptr[i])) {
      return false;
    }
    value = (uint16_t)(value * 10 + (line.ptr[i] - '0'));
  }
  *status = value;
  return line.len == 12 || line.ptr[12] == ' ';
}

static MsSpan trim_blank(MsSpan value) {
  while (value.len > 0 && (value.ptr[0] == ' ' || value.ptr[0] == '\t')) {
    value = ms_span_of(value.ptr + 1, value.len - 1);
  }
  while (value.len > 0 && (value.ptr[value.len - 1] == ' ' || value.ptr[value.len - 1] == '\t')) {
    value = ms_span_of(value.ptr, value.len - 1);
  }
  return value;
}

static bool parse_field(MsSpan line, MsHeaders *fields) {
  size_t colon = 0;
  while (colon < line.len && line.ptr[colon] != ':') {
    colon++;
  }
  const MsSpan name = ms_span_of(line.ptr, colon);
  if (colon == line.len || !ms_header_valid_name(name)) {
    return false;
  }
  const MsSpan value = trim_blank(ms_span_of(line.ptr + colon + 1, line.len - colon - 1));
  return ms_header_valid_value(value) && ms_headers_append(fields, name, value) == MS_STATUS_OK;
}

MsResponseHead ms_ws_parse_response_head(MsSpan buf, size_t limit, uint16_t *status, MsHeaders **fields,
                                         size_t *used) {
  MsSpan rest = buf;
  MsSpan line;
  if (!next_line(&rest, &line)) {
    return buf.len > limit ? MS_RESPONSE_BAD : MS_RESPONSE_PARTIAL;
  }
  if (!parse_status(line, status)) {
    return MS_RESPONSE_BAD;
  }
  MsHeaders *parsed = ms_headers_new();
  while (next_line(&rest, &line)) {
    if (line.len == 0) {
      *fields = parsed;
      *used = buf.len - rest.len;
      return MS_RESPONSE_COMPLETE;
    }
    if (line.ptr[0] == ' ' || line.ptr[0] == '\t' || !parse_field(line, parsed)) {
      ms_headers_free(parsed);
      return MS_RESPONSE_BAD;
    }
  }
  ms_headers_free(parsed);
  return buf.len > limit ? MS_RESPONSE_BAD : MS_RESPONSE_PARTIAL;
}

/* ---- validating the caller's input ---- */

static bool token_is(MsSpan name, const char *text) {
  if (name.len != __builtin_strlen(text)) {
    return false;
  }
  for (size_t i = 0; i < name.len; i++) {
    if (ms_ascii_to_lower(name.ptr[i]) != (uint8_t)text[i]) {
      return false;
    }
  }
  return true;
}

static bool has_prefix_ci(MsSpan name, const char *prefix) {
  const size_t n = __builtin_strlen(prefix);
  return name.len >= n && token_is(ms_span_of(name.ptr, n), prefix);
}

/* Handshake fields the caller may not set, and values that are not text. */
static bool handshake_headers_valid(const MsHeaders *headers) {
  for (size_t g = 0; g < ms_headers_group_count(headers); g++) {
    const MsSpan name = ms_headers_group_name(headers, g);
    if (!ms_header_valid_name(name) || token_is(name, "upgrade") || token_is(name, "connection") ||
        token_is(name, "host") || has_prefix_ci(name, "sec-websocket-")) {
      return false;
    }
    for (size_t i = 0; i < ms_headers_group_size(headers, g); i++) {
      const MsSpan value = ms_headers_group_value(headers, g, i);
      if (!ms_utf8_is_valid(value.ptr, value.len) || !ms_header_valid_value(value)) {
        return false;
      }
    }
  }
  return true;
}

/* The scheme of `text` swapped for the one the URL parser knows: ws is http, wss is https. */
static bool http_form(MsSpan text, bool *secure, MsString *out) {
  const bool wss = text.len >= 4 && token_is(ms_span_of(text.ptr, 4), "wss:");
  const bool ws = text.len >= 3 && token_is(ms_span_of(text.ptr, 3), "ws:");
  if (!ws && !wss) {
    return false;
  }
  *secure = wss;
  const size_t skip = wss ? 3 : 2;
  MsStrBuild build = ms_strbuild_new();
  ms_strbuild_append_text(&build, wss ? "https" : "http");
  ms_strbuild_append(&build, ms_span_of(text.ptr + skip, text.len - skip));
  *out = ms_strbuild_finish(&build);
  return true;
}

/* ---- the dial ---- */

typedef struct Dial {
  const MsObj *net;
  int64_t start;
  int64_t timeout_ns; /* negative: none */
} Dial;

static int64_t time_left(const Dial *dial) {
  if (dial->timeout_ns < 0) {
    return -1;
  }
  const int64_t left = dial->timeout_ns - (ms_sys_monotonic_ns() - dial->start);
  return left > 0 ? left : 0;
}

static uint8_t connect_to(const Dial *dial, const MsHttpUrl *url, bool secure,
                          const MsWebSocketOptionsWire *o, MsObj **conn, MsString *err) {
  MsString address = ms_http_url_dial_address(url);
  const int64_t left = time_left(dial);
  if (!secure) {
    const uint8_t status = ms_net_network_connect(dial->net, &address, left >= 0, left, conn, err);
    ms_string_release(&address);
    return status;
  }
  MsString protocol = ms_string_from_span(ms_span_of_text("http/1.1"));
  MsList alpn = {0};
  ms_list_push(&alpn, sizeof protocol, &protocol);
  MsString host = ms_http_url_host(url);
  const MsTlsOptions tls = {.server_name = host,
                            .roots_pem = o->tls_roots_pem,
                            .certificate_pem = o->tls_certificate_pem,
                            .private_key_pem = o->tls_private_key_pem,
                            .alpn = alpn,
                            .require_client_certificate = o->tls_require_client_certificate};
  const uint8_t status =
      ms_net_network_connect_tls_config(dial->net, &address, &tls, left >= 0, left, conn, err);
  ms_string_release(&protocol);
  ms_list_free(&alpn);
  ms_string_release(&host);
  ms_string_release(&address);
  return status;
}

/* Reads until the response head is complete; `*rest` holds what came after it. */
static uint8_t read_head(const Dial *dial, MsObj *conn, uint16_t *status, MsHeaders **fields, MsBytes *rest,
                         MsString *err) {
  MsBytes buffer = {0};
  for (;;) {
    size_t used = 0;
    const MsResponseHead parsed =
        ms_ws_parse_response_head(ms_bytes_span(&buffer), HEAD_LIMIT, status, fields, &used);
    if (parsed == MS_RESPONSE_COMPLETE) {
      *rest = ms_bytes_from_span(ms_span_of(buffer.ptr + used, buffer.len - used));
      ms_bytes_free(&buffer);
      return MS_STATUS_OK;
    }
    uint8_t result = MS_STATUS_FAILED;
    if (parsed == MS_RESPONSE_BAD) {
      *err = ms_string_from_span(ms_span_of_text("malformed HTTP response"));
    } else {
      const int64_t left = time_left(dial);
      MsBytes chunk = {0};
      result = ms_net_connection_read(conn, 1, 8192, left >= 0, left, &chunk, err);
      if (result == MS_STATUS_OK) {
        __builtin_memcpy(ms_list_extend(&buffer, 1, chunk.len), chunk.ptr, chunk.len);
        ms_bytes_free(&chunk);
        continue;
      }
      ms_bytes_free(&chunk);
      if (result == MS_STATUS_NONE) {
        result = MS_STATUS_FAILED;
        *err = ms_string_from_span(ms_span_of_text("connection closed before the exchange completed"));
      }
    }
    ms_bytes_free(&buffer);
    return result;
  }
}

static uint8_t handshake(const Dial *dial, MsObj *conn, const MsHttpUrl *url, const MsHeaders *headers,
                         const MsSpan *offered, size_t offered_count, const MsWebSocketOptionsWire *o,
                         MsWsConfig *config, MsBytes *leftover, MsString *err) {
  MsStrBuild key = ms_strbuild_new();
  if (!ms_ws_generate_key(&key)) {
    ms_strbuild_free(&key);
    *err = ms_string_from_span(ms_span_of_text("no random bytes for the handshake key"));
    return MS_STATUS_FAILED;
  }
  MsString target = ms_http_url_target(url);
  MsString authority = ms_http_url_authority(url);
  const MsWsClientRequest request = {.target = ms_string_span(&target),
                                     .host = ms_string_span(&authority),
                                     .key = ms_strbuild_span(&key),
                                     .subprotocols = offered,
                                     .subprotocol_count = offered_count,
                                     .headers = headers,
                                     .compression = o->compression != 0};
  MsBytes wire = {0};
  ms_ws_client_request(&request, &wire);
  const int64_t left = time_left(dial);
  uint8_t status = ms_net_connection_write_bytes(conn, &wire, left >= 0, left, err);
  ms_bytes_free(&wire);
  uint16_t code = 0;
  MsHeaders *fields = NULL;
  if (status == MS_STATUS_OK) {
    status = read_head(dial, conn, &code, &fields, leftover, err);
  }
  if (status == MS_STATUS_OK) {
    bool compress = false;
    MsString subprotocol = ms_string_empty();
    const MsWsClientResult checked = ms_ws_check_response(code, fields, ms_strbuild_span(&key), offered,
                                                          offered_count, &subprotocol, &compress);
    if (checked == MS_WS_CLIENT_OK) {
      config->compress = compress;
      config->subprotocol = subprotocol;
    } else {
      *err = ms_string_from_span(ms_span_of_text(ms_ws_client_message(checked)));
      status = MS_STATUS_FAILED;
      ms_bytes_free(leftover);
    }
    ms_headers_free(fields);
  }
  ms_string_release(&target);
  ms_string_release(&authority);
  ms_strbuild_free(&key);
  return status;
}

static bool subprotocols_valid(const MsList *list, MsSpan **spans) {
  const MsString *items = (const MsString *)(const void *)list->ptr;
  *spans = ms_alloc_zeroed((list->len + 1) * sizeof **spans);
  for (size_t i = 0; i < list->len; i++) {
    (*spans)[i] = ms_string_span(&items[i]);
    if (!ms_header_valid_name((*spans)[i])) {
      return false;
    }
  }
  return true;
}

/* Everything after the arguments are valid: connect, handshake and wrap the connection. */
static uint8_t open_session(const Dial *dial, const MsHttpUrl *url, bool secure, const MsHeaders *headers,
                            const MsSpan *offered, size_t count, const MsWebSocketOptionsWire *o, MsObj **out,
                            MsString *err) {
  MsObj *conn = NULL;
  uint8_t status = connect_to(dial, url, secure, o, &conn, err);
  if (status != MS_STATUS_OK) {
    return status;
  }
  MsWsConfig config = {.client = true,
                       .has_limit = o->max_message_bytes_present != 0,
                       .max_message_bytes = (uint64_t)o->max_message_bytes,
                       .subprotocol = ms_string_empty()};
  MsBytes leftover = {0};
  status = handshake(dial, conn, url, headers, offered, count, o, &config, &leftover, err);
  if (status != MS_STATUS_OK) {
    msstd_net_connection_close(conn);
    conn->drop(conn);
    return status;
  }
  MsWsSession *session = ms_ws_connection_session(conn, &config, ms_bytes_span(&leftover));
  ms_bytes_free(&leftover);
  *out = ms_ws_handle_new(session);
  ms_ws_session_release(session);
  return MS_STATUS_OK;
}

uint8_t msstd_net_network_web_socket(const MsObj *net, const MsString *address, const MsObj *headers,
                                     const MsList *subprotocols, const MsWebSocketOptionsWire *o, MsObj **out,
                                     MsString *err) {
  *err = ms_string_empty();
  MsString text = ms_string_empty();
  MsString http = ms_string_empty();
  bool secure = false;
  MsSpan *offered = NULL;
  MsHttpUrl *url = NULL;
  uint8_t status = MS_STATUS_INVALID_INPUT;
  const bool numbers_ok =
      !(o->max_message_bytes_present && o->max_message_bytes <= 0) && !(o->timeout_present && o->timeout < 0);
  if (numbers_ok && http_form(ms_string_span(address), &secure, &http) &&
      subprotocols_valid(subprotocols, &offered) && handshake_headers_valid(ms_headers_of(headers))) {
    url = ms_http_url_parse(ms_string_span(&http));
  }
  if (url != NULL) {
    const Dial dial = {
        .net = net, .start = ms_sys_monotonic_ns(), .timeout_ns = o->timeout_present ? o->timeout : -1};
    status =
        open_session(&dial, url, secure, ms_headers_of(headers), offered, subprotocols->len, o, out, &text);
    ms_http_url_free(url);
  }
  ms_free(offered);
  ms_string_release(&http);
  return ms_fail_finish_with(status, &text, err);
}
