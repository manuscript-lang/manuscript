/* runtime/std/ws_handshake.c: the opening handshake of RFC 6455 and the origin policy of the server upgrade.
 * Pure functions over parsed heads: the server exchange and the client do the I/O. */
#include "base/alloc.h"
#include "base/chars.h"
#include "runtime/std/crypto.h"
#include "runtime/std/encoding.h"
#include "runtime/std/http_h1.h"
#include "runtime/std/http_wire.h"
#include "runtime/std/random.h"
#include "runtime/std/ws.h"

#define GUID "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

/* `Sec-WebSocket-Accept` for a challenge key. */
static void ms_ws_accept_key(MsSpan challenge, MsStrBuild *out) {
  MsBytes input = ms_bytes_from_span(challenge);
  const MsSpan guid = ms_span_of_text(GUID);
  __builtin_memcpy(ms_list_extend(&input, 1, guid.len), guid.ptr, guid.len);
  MsBytes digest = {0};
  msstd_crypto_digest(1, &input, &digest); /* SHA-1 */
  MsString text = ms_string_empty();
  msstd_encoding_base64_encode(&digest, 0, &text);
  ms_strbuild_append_string(out, &text);
  ms_string_release(&text);
  ms_bytes_free(&digest);
  ms_bytes_free(&input);
}

bool ms_ws_generate_key(MsStrBuild *out) {
  uint8_t bytes[16];
  MsBytes random = {0};
  MsString err = ms_string_empty();
  const bool ok = msstd_random_os_bytes(16, &random, &err) == MS_STATUS_OK && random.len == 16;
  ms_string_release(&err);
  if (ok) {
    __builtin_memcpy(bytes, random.ptr, 16);
    MsBytes raw = ms_bytes_from_span(ms_span_of(bytes, 16));
    MsString text = ms_string_empty();
    msstd_encoding_base64_encode(&raw, 0, &text);
    ms_strbuild_append_string(out, &text);
    ms_string_release(&text);
    ms_bytes_free(&raw);
  }
  ms_bytes_free(&random);
  return ok;
}

/* Whether `text` is the base64 text of exactly 16 bytes. */
static bool ms_ws_valid_challenge_key(MsSpan text) {
  /* 16 bytes are 22 base64 digits and "=="; the unused trailing bits may be set (standard base64). */
  if (text.len != 24 || text.ptr[22] != '=' || text.ptr[23] != '=') {
    return false;
  }
  for (size_t i = 0; i < 22; i++) {
    const uint8_t b = text.ptr[i];
    const bool digit =
        (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z') || (b >= '0' && b <= '9') || b == '+' || b == '/';
    if (!digit) {
      return false;
    }
  }
  return true;
}

/* ---- text scanning ---- */

static bool is_token_octet(uint8_t b) {
  if ((b >= '0' && b <= '9') || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')) {
    return true;
  }
  size_t at = 0;
  return b != 0 && ms_span_find(ms_span_of_text("!#$%&'*+-.^_`|~"), ms_span_of(&b, 1), &at);
}

static MsSpan tail(MsSpan s, size_t n) {
  return ms_span_of(s.ptr + n, s.len - n);
}

static MsSpan skip_space(MsSpan s) {
  size_t n = 0;
  while (n < s.len && (s.ptr[n] == ' ' || s.ptr[n] == '\t')) {
    n++;
  }
  return tail(s, n);
}

/* The leading token of `s`: *token and the rest. */
static MsSpan next_token(MsSpan s, MsSpan *token) {
  size_t end = 0;
  while (end < s.len && is_token_octet(s.ptr[end])) {
    end++;
  }
  *token = ms_span_of(s.ptr, end);
  return tail(s, end);
}

/* After a token or quoted string: the rest of `s`. Malformed quoting yields an empty rest. */
static MsSpan skip_token_or_quoted(MsSpan s) {
  if (s.len == 0 || s.ptr[0] != '"') {
    MsSpan token;
    return next_token(s, &token);
  }
  bool escape = false;
  for (size_t i = 1; i < s.len; i++) {
    if (escape) {
      escape = false;
    } else if (s.ptr[i] == '\\') {
      escape = true;
    } else if (s.ptr[i] == '"') {
      return tail(s, i + 1);
    }
  }
  return ms_span_of(s.ptr + s.len, 0);
}

static bool line_has_token(MsSpan line, const char *value) {
  MsSpan s = line;
  for (;;) {
    MsSpan token;
    s = skip_space(next_token(skip_space(s), &token));
    if (token.len == 0 || (s.len > 0 && s.ptr[0] != ',')) {
      return false;
    }
    if (ms_ascii_is_text_fold(token, value)) {
      return true;
    }
    if (s.len == 0) {
      return false;
    }
    s = tail(s, 1);
  }
}

/* Whether a comma-separated field holds `value` as a token, ignoring ASCII case; a malformed element skips
 * the rest of that line. */
static bool ms_ws_token_list_contains(const MsHeaders *fields, const char *name, const char *value) {
  MsList lines = {0};
  if (!ms_headers_values(fields, ms_span_of_text(name), &lines)) {
    return false;
  }
  bool found = false;
  for (size_t i = 0; i < lines.len && !found; i++) {
    found = line_has_token(ms_bytes_span((const MsBytes *)(const void *)lines.ptr + i), value);
  }
  ms_bytes_list_free(&lines);
  return found;
}

/* ---- extensions ---- */

/* What the handshake wants to know of the first permessage-deflate element. */
typedef struct DeflateOffer {
  bool found;
  bool server_no_context_takeover;
  bool client_no_context_takeover;
} DeflateOffer;

typedef struct ParamFlags {
  bool server;
  bool client;
} ParamFlags;

/* One `; key[=value]` parameter at the start of `s`; false when the line is malformed. */
static bool read_param(MsSpan *s, ParamFlags *flags) {
  MsSpan key;
  MsSpan rest = skip_space(next_token(skip_space(tail(*s, 1)), &key));
  if (key.len == 0) {
    return false;
  }
  if (rest.len > 0 && rest.ptr[0] == '=') {
    rest = skip_space(skip_token_or_quoted(skip_space(tail(rest, 1))));
  }
  if (rest.len > 0 && rest.ptr[0] != ',' && rest.ptr[0] != ';') {
    return false;
  }
  flags->server = flags->server || ms_span_is_text(key, "server_no_context_takeover");
  flags->client = flags->client || ms_span_is_text(key, "client_no_context_takeover");
  *s = rest;
  return true;
}

/* Reads one `Sec-WebSocket-Extensions` line; a malformed element ends it. */
static void parse_extension_line(MsSpan line, DeflateOffer *offer) {
  MsSpan s = line;
  for (;;) {
    MsSpan name;
    s = next_token(skip_space(s), &name);
    if (name.len == 0) {
      return;
    }
    ParamFlags flags = {0};
    for (s = skip_space(s); s.len > 0 && s.ptr[0] == ';'; s = skip_space(s)) {
      if (!read_param(&s, &flags)) {
        return;
      }
    }
    if (s.len > 0 && s.ptr[0] != ',') {
      return;
    }
    if (!offer->found && ms_span_is_text(name, "permessage-deflate")) {
      *offer = (DeflateOffer){true, flags.server, flags.client};
    }
    if (s.len == 0) {
      return;
    }
    s = tail(s, 1);
  }
}

static DeflateOffer find_deflate(const MsHeaders *fields) {
  DeflateOffer offer = {0};
  MsList lines = {0};
  if (ms_headers_values(fields, ms_span_of_text("Sec-WebSocket-Extensions"), &lines)) {
    for (size_t i = 0; i < lines.len; i++) {
      parse_extension_line(ms_bytes_span((const MsBytes *)(const void *)lines.ptr + i), &offer);
    }
    ms_bytes_list_free(&lines);
  }
  return offer;
}

/* ---- subprotocols and origin ---- */

static MsSpan trim(MsSpan s) {
  s = skip_space(s);
  while (s.len > 0 && (s.ptr[s.len - 1] == ' ' || s.ptr[s.len - 1] == '\t')) {
    s.len--;
  }
  return s;
}

/* The first server protocol, in the server's order, that the client offered on its first
 * Sec-WebSocket-Protocol line (comma-separated, trimmed); false when none matches. */
static bool select_subprotocol(const MsHeaders *fields, const MsSpan *server, size_t count, MsSpan *chosen) {
  MsSpan line = {0};
  if (!ms_headers_first(fields, ms_span_of_text("Sec-WebSocket-Protocol"), &line)) {
    return false;
  }
  line = trim(line);
  for (size_t i = 0; i < count && line.len > 0; i++) {
    size_t start = 0;
    for (size_t j = 0; j <= line.len; j++) {
      if (j == line.len || line.ptr[j] == ',') {
        if (ms_span_equal(trim(ms_span_of(line.ptr + start, j - start)), server[i])) {
          *chosen = server[i];
          return true;
        }
        start = j + 1;
      }
    }
  }
  return false;
}

static bool in_list(const MsSpan *list, size_t count, MsSpan value) {
  for (size_t i = 0; i < count; i++) {
    if (ms_span_equal(list[i], value)) {
      return true;
    }
  }
  return false;
}

/* A bare http or https origin: scheme://authority with nothing after the authority. */
static bool bare_origin(MsSpan origin, MsSpan *scheme, MsSpan *authority) {
  size_t at = 0;
  if (!ms_span_find(origin, ms_span_of_text("://"), &at)) {
    return false;
  }
  *scheme = ms_span_of(origin.ptr, at);
  *authority = tail(origin, at + 3);
  if (!ms_ascii_is_text_fold(*scheme, "http") && !ms_ascii_is_text_fold(*scheme, "https")) {
    return false;
  }
  return authority->len > 0 && ms_http_valid_authority(*authority);
}

/* The origin policy: a missing or empty Origin is accepted; otherwise it must be a bare http or https origin
 * that equals an allowed entry, or (with none allowed) has the request's scheme and host. */
static bool ms_ws_origin_allowed(const MsHeaders *fields, MsSpan host, bool tls, const MsSpan *allowed,
                          size_t count) {
  MsSpan origin = {0};
  if (!ms_headers_first(fields, ms_span_of_text("Origin"), &origin) || origin.len == 0) {
    return true;
  }
  MsSpan scheme;
  MsSpan authority;
  if (!bare_origin(origin, &scheme, &authority)) {
    return false;
  }
  if (in_list(allowed, count, origin)) {
    return true;
  }
  bool same_host = authority.len == host.len;
  for (size_t i = 0; same_host && i < host.len; i++) {
    same_host = ms_ascii_to_lower(authority.ptr[i]) == ms_ascii_to_lower(host.ptr[i]);
  }
  return count == 0 && ms_ascii_is_text_fold(scheme, tls ? "https" : "http") && same_host;
}

/* ---- server side ---- */

static bool reject(MsWsRejected *rejected, uint16_t status, const char *message) {
  *rejected = (MsWsRejected){.status = status, .message = message};
  return false;
}

/* Checks an upgrade request in RFC order up to the key; false (with `rejected`) when it is refused. */
static bool check_upgrade(const MsWsRequest *request, const MsWsServerOptions *options,
                          MsWsRejected *rejected) {
  const MsHeaders *fields = request->fields;
  if (!ms_ws_token_list_contains(fields, "Connection", "upgrade")) {
    return reject(rejected, 400, "websocket: 'Connection' header lacks the 'upgrade' token");
  }
  if (!ms_ws_token_list_contains(fields, "Upgrade", "websocket")) {
    return reject(rejected, 400, "websocket: 'Upgrade' header lacks the 'websocket' token");
  }
  if (!ms_span_is_text(request->method, "GET")) {
    return reject(rejected, 405, "websocket: upgrade method is not GET");
  }
  if (!ms_ws_token_list_contains(fields, "Sec-WebSocket-Version", "13")) {
    /* RFC 6455 section 4.4: a version the server lacks is 426; a missing header is 400. */
    MsSpan present;
    const bool has = ms_headers_first(fields, ms_span_of_text("Sec-WebSocket-Version"), &present);
    return reject(rejected, has ? 426 : 400, "websocket: 'Sec-WebSocket-Version' header must include 13");
  }
  if (!ms_ws_origin_allowed(fields, request->host, request->tls, options->allowed_origins,
                            options->allowed_origin_count)) {
    return reject(rejected, 403, "websocket: request origin not allowed");
  }
  return true;
}

static void append_header(MsBytes *out, const char *name, MsSpan value) {
  MsStrBuild line = ms_strbuild_new();
  ms_h1_header_line(&line, ms_span_of_text(name), value);
  MsString text = ms_strbuild_finish(&line);
  ms_strbuild_free(&line);
  MsSpan span = ms_string_span(&text);
  __builtin_memcpy(ms_list_extend(out, 1, span.len), span.ptr, span.len);
  ms_string_release(&text);
}

static void append_text(MsBytes *out, const char *text) {
  const MsSpan span = ms_span_of_text(text);
  __builtin_memcpy(ms_list_extend(out, 1, span.len), span.ptr, span.len);
}

bool ms_ws_accept(const MsWsRequest *request, const MsWsServerOptions *options, MsWsAccepted *accepted,
                  MsWsRejected *rejected) {
  if (!check_upgrade(request, options, rejected)) {
    return false;
  }
  MsSpan key = {0};
  MsList keys = {0};
  /* The field must appear once (RFC 6455 section 4.1), or two parsers could read two keys. */
  const bool has_key = ms_headers_values(request->fields, ms_span_of_text("Sec-WebSocket-Key"), &keys);
  const bool once = has_key && keys.len == 1;
  if (has_key) {
    key = ms_bytes_span((const MsBytes *)(const void *)keys.ptr);
  }
  const bool key_ok = once && ms_ws_valid_challenge_key(key);
  if (!key_ok) {
    ms_bytes_list_free(&keys);
    return reject(rejected, 400, "websocket: 'Sec-WebSocket-Key' header must be the Base64 text of 16 bytes");
  }
  MsSpan chosen = {0};
  const bool has_protocol =
      select_subprotocol(request->fields, options->subprotocols, options->subprotocol_count, &chosen);
  const bool compress = options->compression && find_deflate(request->fields).found;
  MsBytes response = {0};
  append_text(&response, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n");
  MsStrBuild accept = ms_strbuild_new();
  ms_ws_accept_key(key, &accept);
  MsString accept_text = ms_strbuild_finish(&accept);
  ms_strbuild_free(&accept);
  append_header(&response, "Sec-WebSocket-Accept", ms_string_span(&accept_text));
  ms_string_release(&accept_text);
  if (has_protocol) {
    append_header(&response, "Sec-WebSocket-Protocol", chosen);
  }
  if (compress) {
    append_header(&response, "Sec-WebSocket-Extensions", ms_span_of_text(MS_WS_DEFLATE_RESPONSE));
  }
  append_text(&response, "\r\n");
  ms_bytes_list_free(&keys);
  *accepted = (MsWsAccepted){.subprotocol = has_protocol ? ms_string_from_span(chosen) : ms_string_empty(),
                             .compress = compress,
                             .response = response};
  return true;
}

void ms_ws_accepted_release(MsWsAccepted *accepted) {
  ms_string_release(&accepted->subprotocol);
  ms_bytes_free(&accepted->response);
}

void ms_ws_rejected_response(const MsWsRejected *rejected, int64_t date, bool close, MsBytes *out) {
  MsStrBuild head = ms_strbuild_new();
  const char *status_text = ms_h1_status_text(rejected->status);
  ms_h1_status_line(&head, rejected->status);
  ms_h1_header_line(&head, ms_span_of_text("Content-Type"), ms_span_of_text("text/plain; charset=utf-8"));
  ms_h1_header_line(&head, ms_span_of_text("Sec-Websocket-Version"), ms_span_of_text("13"));
  ms_h1_header_line(&head, ms_span_of_text("X-Content-Type-Options"), ms_span_of_text("nosniff"));
  MsStrBuild when = ms_strbuild_new();
  ms_h1_http_date(&when, date);
  MsString when_text = ms_strbuild_finish(&when);
  ms_strbuild_free(&when);
  ms_h1_header_line(&head, ms_span_of_text("Date"), ms_string_span(&when_text));
  ms_string_release(&when_text);
  ms_h1_header_number(&head, ms_span_of_text("Content-Length"), ms_span_of_text(status_text).len + 1);
  if (close) {
    ms_h1_header_line(&head, ms_span_of_text("Connection"), ms_span_of_text("close"));
  }
  ms_strbuild_append_text(&head, "\r\n");
  ms_strbuild_append_text(&head, status_text);
  ms_strbuild_append_byte(&head, '\n');
  MsString text = ms_strbuild_finish(&head);
  ms_strbuild_free(&head);
  const MsSpan span = ms_string_span(&text);
  __builtin_memcpy(ms_list_extend(out, 1, span.len), span.ptr, span.len);
  ms_string_release(&text);
}

/* ---- client side ---- */

/* One field to send: a name and a cleaned value. */
typedef struct SendField {
  MsString name;
  MsBytes value;
} SendField;

/* `textproto` trims header values and turns line breaks into spaces. */
static MsBytes clean_value(MsSpan value) {
  MsBytes out = ms_bytes_from_span(value);
  for (size_t i = 0; i < out.len; i++) {
    if (out.ptr[i] == '\r' || out.ptr[i] == '\n') {
      out.ptr[i] = ' ';
    }
  }
  const MsSpan trimmed = trim(ms_bytes_span(&out));
  MsBytes result = ms_bytes_from_span(trimmed);
  ms_bytes_free(&out);
  return result;
}

static void push_field(MsList *fields, MsSpan name, MsBytes value) {
  const SendField field = {.name = ms_string_from_span(name), .value = value};
  ms_list_push(fields, sizeof field, &field);
}

static void push_fixed_fields(const MsWsClientRequest *request, MsList *fields) {
  push_field(fields, ms_span_of_text("Connection"), ms_bytes_from_span(ms_span_of_text("Upgrade")));
  push_field(fields, ms_span_of_text("Sec-WebSocket-Key"), ms_bytes_from_span(request->key));
  push_field(fields, ms_span_of_text("Sec-WebSocket-Version"), ms_bytes_from_span(ms_span_of_text("13")));
  push_field(fields, ms_span_of_text("Upgrade"), ms_bytes_from_span(ms_span_of_text("websocket")));
  if (request->subprotocol_count > 0) {
    MsBytes joined = {0};
    for (size_t i = 0; i < request->subprotocol_count; i++) {
      if (i > 0) {
        __builtin_memcpy(ms_list_extend(&joined, 1, 2), ", ", 2);
      }
      __builtin_memcpy(ms_list_extend(&joined, 1, request->subprotocols[i].len), request->subprotocols[i].ptr,
                       request->subprotocols[i].len);
    }
    push_field(fields, ms_span_of_text("Sec-WebSocket-Protocol"), joined);
  }
  if (request->compression) {
    push_field(fields, ms_span_of_text("Sec-WebSocket-Extensions"),
               ms_bytes_from_span(ms_span_of_text(MS_WS_DEFLATE_RESPONSE)));
  }
}

/* Adds the caller's fields; a User-Agent replaces the default one (the last wins). */
static void push_caller_fields(const MsHeaders *headers, MsList *fields, MsBytes *agent) {
  for (size_t g = 0; headers != NULL && g < ms_headers_group_count(headers); g++) {
    const MsSpan name = ms_headers_group_name(headers, g);
    for (size_t v = 0; v < ms_headers_group_size(headers, g); v++) {
      MsBytes value = clean_value(ms_headers_group_value(headers, g, v));
      if (ms_ascii_is_text_fold(name, "User-Agent")) {
        ms_bytes_free(agent);
        *agent = value;
        continue;
      }
      MsStrBuild canonical = ms_strbuild_new();
      ms_header_canonical(name, &canonical);
      MsString text = ms_strbuild_finish(&canonical);
      ms_strbuild_free(&canonical);
      push_field(fields, ms_string_span(&text), value);
      ms_string_release(&text);
    }
  }
}

/* A stable sort by name, bytewise. */
static void sort_fields(MsList *fields) {
  SendField *items = (SendField *)(void *)fields->ptr;
  for (size_t i = 1; i < fields->len; i++) {
    const SendField moved = items[i];
    size_t at = i;
    while (at > 0 && ms_string_compare(&items[at - 1].name, &moved.name) > 0) {
      items[at] = items[at - 1];
      at--;
    }
    items[at] = moved;
  }
}

void ms_ws_client_request(const MsWsClientRequest *request, MsBytes *out) {
  MsList fields = {0};
  MsBytes agent = ms_bytes_from_span(ms_span_of_text("ms-http"));
  push_fixed_fields(request, &fields);
  push_caller_fields(request->headers, &fields, &agent);
  sort_fields(&fields);
  MsStrBuild head = ms_strbuild_new();
  ms_strbuild_append_text(&head, "GET ");
  ms_strbuild_append(&head, request->target);
  ms_strbuild_append_text(&head, " HTTP/1.1\r\n");
  ms_h1_header_line(&head, ms_span_of_text("Host"), request->host);
  ms_h1_header_line(&head, ms_span_of_text("User-Agent"), ms_bytes_span(&agent));
  for (size_t i = 0; i < fields.len; i++) {
    SendField *field = (SendField *)(void *)fields.ptr + i;
    ms_h1_header_line(&head, ms_string_span(&field->name), ms_bytes_span(&field->value));
    ms_string_release(&field->name);
    ms_bytes_free(&field->value);
  }
  ms_strbuild_append_text(&head, "\r\n");
  MsString text = ms_strbuild_finish(&head);
  ms_strbuild_free(&head);
  const MsSpan span = ms_string_span(&text);
  __builtin_memcpy(ms_list_extend(out, 1, span.len), span.ptr, span.len);
  ms_string_release(&text);
  ms_list_free(&fields);
  ms_bytes_free(&agent);
}

const char *ms_ws_client_message(MsWsClientResult result) {
  switch (result) {
  case MS_WS_CLIENT_BAD_HANDSHAKE:
    return "websocket: bad handshake";
  case MS_WS_CLIENT_INVALID_COMPRESSION:
    return "websocket: invalid compression negotiation";
  default:
    return "";
  }
}

MsWsClientResult ms_ws_check_response(uint16_t status, const MsHeaders *fields, MsSpan key,
                                      const MsSpan *offered, size_t offered_count, MsString *subprotocol,
                                      bool *compress) {
  MsSpan accept = {0};
  MsSpan protocol = {0};
  (void)ms_headers_first(fields, ms_span_of_text("Sec-WebSocket-Accept"), &accept);
  (void)ms_headers_first(fields, ms_span_of_text("Sec-WebSocket-Protocol"), &protocol);
  MsStrBuild expected = ms_strbuild_new();
  ms_ws_accept_key(key, &expected);
  MsString expected_text = ms_strbuild_finish(&expected);
  ms_strbuild_free(&expected);
  const bool good = status == 101 && ms_ws_token_list_contains(fields, "Upgrade", "websocket") &&
                    ms_ws_token_list_contains(fields, "Connection", "upgrade") &&
                    ms_span_equal(accept, ms_string_span(&expected_text)) &&
                    (protocol.len == 0 || in_list(offered, offered_count, protocol));
  ms_string_release(&expected_text);
  if (!good) {
    return MS_WS_CLIENT_BAD_HANDSHAKE;
  }
  const DeflateOffer offer = find_deflate(fields);
  if (offer.found && !(offer.server_no_context_takeover && offer.client_no_context_takeover)) {
    return MS_WS_CLIENT_INVALID_COMPRESSION;
  }
  *compress = offer.found;
  *subprotocol = ms_string_from_span(protocol);
  return MS_WS_CLIENT_OK;
}
