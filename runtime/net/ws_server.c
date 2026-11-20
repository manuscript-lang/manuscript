/* The server side of the WebSocket opening handshake (ws_server.h). */
#include "ws_server.h"

#include <stdbool.h>
#include <string.h>

#include "../std/abi.h"
#include "conn_object.h"
#include "headers.h"
#include "http1.h"
#include "status.h"
#include "ws.h"
#include "ws_natives.h"
#include "ws_socket.h"

static MsBytes bytes_of_str(const MsStr *text) { return ms_bytes_of((const uint8_t *)msrt_str_data(text), msrt_str_len(text)); }

static char lower(char c) {
    if (c < 'A' || c > 'Z') {
        return c;
    }
    return (char)(c + ('a' - 'A'));
}

/* Whether `name` is `want`, ignoring ASCII case. */
static bool name_is(MsBytes name, const char *want) {
    const size_t length = strlen(want);
    if (name.len != length) {
        return false;
    }
    for (size_t i = 0; i < length; i++) {
        if (lower((char)name.ptr[i]) != lower(want[i])) {
            return false;
        }
    }
    return true;
}

/* How many fields are called `name`, and the first one's value (empty when none). */
static size_t field_count(const MsHeaders *fields, const char *name, MsBytes *first) {
    size_t found = 0;
    *first = ms_bytes_of(NULL, 0);
    for (size_t i = 0; i < ms_headers_count(fields); i++) {
        MsBytes field_name, value;
        ms_headers_field(fields, i, &field_name, &value);
        if (name_is(field_name, name)) {
            if (found++ == 0) {
                *first = value;
            }
        }
    }
    return found;
}

/* Whether some `name` field lists `token`. */
static bool field_has_token(const MsHeaders *fields, const char *name, const char *token) {
    for (size_t i = 0; i < ms_headers_count(fields); i++) {
        MsBytes field_name, value;
        ms_headers_field(fields, i, &field_name, &value);
        if (name_is(field_name, name) && ms_h1_value_has_token(value, ms_bytes_of((const uint8_t *)token, strlen(token)))) {
            return true;
        }
    }
    return false;
}

/* The base64 text of exactly 16 bytes: 22 characters, the last of which carries no stray bits, and "==". */
static bool valid_key(MsBytes key) {
    if (key.len != 24 || key.ptr[22] != '=' || key.ptr[23] != '=') {
        return false;
    }
    for (size_t i = 0; i < 22; i++) {
        const uint8_t c = key.ptr[i];
        const bool alphabet = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '+' || c == '/';
        if (!alphabet) {
            return false;
        }
    }
    return strchr("AQgw", key.ptr[21]) != NULL;
}

static bool equal_text(MsBytes a, MsBytes b) { return a.len == b.len && (a.len == 0 || memcmp(a.ptr, b.ptr, a.len) == 0); }

static bool equal_text_nocase(MsBytes a, MsBytes b) {
    if (a.len != b.len) {
        return false;
    }
    for (size_t i = 0; i < a.len; i++) {
        if (lower((char)a.ptr[i]) != lower((char)b.ptr[i])) {
            return false;
        }
    }
    return true;
}

/* Origin policy: a missing or empty Origin passes; else a bare http(s) origin, equal to an allowed one or (when none
 * is listed) of the request's scheme and host. */
static bool origin_allowed(MsBytes origin, MsBytes host, bool tls, const MsVec *allowed) {
    if (origin.len == 0) {
        return true;
    }
    const char *scheme = tls ? "https://" : "http://";
    const MsBytes prefixes[2] = {ms_bytes_of((const uint8_t *)"http://", 7), ms_bytes_of((const uint8_t *)"https://", 8)};
    size_t used = 0;
    for (size_t i = 0; i < 2; i++) {
        if (origin.len > prefixes[i].len && memcmp(origin.ptr, prefixes[i].ptr, prefixes[i].len) == 0) {
            used = prefixes[i].len;
        }
    }
    if (used == 0) {
        return false;
    }
    for (size_t i = used; i < origin.len; i++) { /* no user info, path, query, fragment or blanks */
        const uint8_t c = origin.ptr[i];
        if (c <= 0x20 || c == 0x7F || c == '/' || c == '?' || c == '#' || c == '@' || c == '\\') {
            return false;
        }
    }
    const MsStr *items = allowed->ptr;
    for (size_t i = 0; i < allowed->len; i++) {
        if (equal_text(origin, bytes_of_str(&items[i]))) {
            return true;
        }
    }
    const MsBytes authority = ms_bytes_of(origin.ptr + used, origin.len - used);
    const size_t scheme_length = strlen(scheme);
    return allowed->len == 0 && used == scheme_length && equal_text_nocase(authority, host);
}

/* The first of `server` (in its order) that `offered`, a comma-separated list, names; empty for none. */
static MsBytes select_subprotocol(MsBytes offered, const MsVec *server) {
    const MsStr *items = server->ptr;
    for (size_t i = 0; i < server->len; i++) {
        const MsBytes wanted = bytes_of_str(&items[i]);
        size_t start = 0;
        for (size_t at = 0; at <= offered.len; at++) {
            if (at == offered.len || offered.ptr[at] == ',') {
                size_t from = start, to = at;
                while (from < to && (offered.ptr[from] == ' ' || offered.ptr[from] == '\t')) from++;
                while (to > from && (offered.ptr[to - 1] == ' ' || offered.ptr[to - 1] == '\t')) to--;
                if (equal_text(wanted, ms_bytes_of(offered.ptr + from, to - from))) {
                    return wanted;
                }
                start = at + 1;
            }
        }
    }
    return ms_bytes_of(NULL, 0);
}

static uint8_t refuse(int64_t answer, const char *text, MsNetWsHandshake *out) {
    out->status = answer;
    ms_net_write_text(&out->reason, text);
    return STATUS_OK;
}

uint8_t msstd_ws_handshake(const MsStr *method, const MsStr *host, uint8_t tls, const void *request, const MsVec *origins,
                           const MsVec *subprotocols, const void *response, MsNetWsHandshake *out, MsStr *err) {
    ms_net_clear_text(err);
    out->status = 0; /* the record is uninitialized stack: every field is valid whatever the answer */
    msrt_string_from_bytes(NULL, 0, &out->subprotocol);
    msrt_string_from_bytes(NULL, 0, &out->reason);
    const MsStr *protocols = subprotocols->ptr;
    for (size_t i = 0; i < subprotocols->len; i++) {
        if (!ms_h1_is_token(bytes_of_str(&protocols[i]))) {
            return STATUS_INVALID_INPUT;
        }
    }
    const MsHeaders *fields = ms_headers_of(request);
    MsBytes value;
    if (!field_has_token(fields, "Connection", "upgrade")) {
        return refuse(400, "websocket: 'Connection' header lacks the 'upgrade' token", out);
    }
    if (!field_has_token(fields, "Upgrade", "websocket")) {
        return refuse(400, "websocket: 'Upgrade' header lacks the 'websocket' token", out);
    }
    if (!equal_text(bytes_of_str(method), ms_bytes_of((const uint8_t *)"GET", 3))) {
        return refuse(405, "websocket: upgrade method is not GET", out);
    }
    if (!field_has_token(fields, "Sec-WebSocket-Version", "13")) {
        const bool present = field_count(fields, "Sec-WebSocket-Version", &value) > 0;
        return refuse(present ? 426 : 400, "websocket: 'Sec-WebSocket-Version' header must include 13", out);
    }
    MsBytes origin;
    (void)field_count(fields, "Origin", &origin);
    if (!origin_allowed(origin, bytes_of_str(host), tls != 0, origins)) {
        return refuse(403, "websocket: request origin not allowed", out);
    }
    MsBytes key;
    const size_t keys = field_count(fields, "Sec-WebSocket-Key", &key);
    if (keys != 1 || !valid_key(key)) { /* the field must appear once, or two parsers could read two keys */
        return refuse(400, "websocket: 'Sec-WebSocket-Key' header must be the Base64 text of 16 bytes", out);
    }
    char accept[29];
    if (ms_ws_accept_key((const char *)key.ptr, key.len, accept) != 0) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    MsBytes offered;
    (void)field_count(fields, "Sec-WebSocket-Protocol", &offered);
    const MsBytes chosen = select_subprotocol(offered, subprotocols);

    MsHeaders *fields_out = ms_headers_of(response);
    const bool added = ms_headers_add_canonical(fields_out, ms_bytes_of((const uint8_t *)"Upgrade", 7), ms_bytes_of((const uint8_t *)"websocket", 9)) &&
                       ms_headers_add_canonical(fields_out, ms_bytes_of((const uint8_t *)"Connection", 10), ms_bytes_of((const uint8_t *)"Upgrade", 7)) &&
                       ms_headers_add_canonical(fields_out, ms_bytes_of((const uint8_t *)"Sec-WebSocket-Accept", 20), ms_bytes_of((const uint8_t *)accept, strlen(accept))) &&
                       (chosen.len == 0 || ms_headers_add_canonical(fields_out, ms_bytes_of((const uint8_t *)"Sec-WebSocket-Protocol", 22), chosen));
    if (!added) {
        return STATUS_LIMIT_EXCEEDED;
    }
    out->status = 101;
    msrt_string_from_bytes(chosen.ptr, chosen.len, &out->subprotocol);
    return STATUS_OK;
}

uint8_t msstd_ws_serve(const void *conn, const MsStr *subprotocol, uint8_t has_max, int64_t max, void **out, MsStr *err) {
    ms_net_clear_text(err); /* the caller reads the slot for every failure status; only STATUS_FAILED sets text */
    if (has_max != 0 && max <= 0) {
        return STATUS_INVALID_INPUT;
    }
    const MsWsConfig config = {.max_message_bytes = has_max != 0 ? (uint64_t)max : UINT64_MAX,
                               .compress = false,
                               .subprotocol = bytes_of_str(subprotocol)};
    MsObj *held = ms_netconn_alias(conn); /* the session owns its handle; the caller keeps theirs */
    MsWsSocket *session = held != NULL ? ms_ws_socket_new(held, MS_WS_ROLE_SERVER, &config) : NULL;
    if (session == NULL) {
        if (held != NULL) {
            held->drop(held);
        }
        ms_net_write_text(err, "out of memory");
        return STATUS_FAILED;
    }
    MsObj *handle = ms_ws_handle_new(session);
    if (handle == NULL) {
        ms_net_write_text(err, "out of memory");
        return STATUS_FAILED;
    }
    *out = handle;
    return STATUS_OK;
}
