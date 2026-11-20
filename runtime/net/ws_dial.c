#include "ws_dial.h"

#include <stdlib.h>
#include <string.h>

#include "conn_object.h"
#include "http1.h"
#include "ms_rt/chars.h"
#include "ws_client.h"

#define LITERAL(text) ms_bytes_of((const uint8_t *)(text), sizeof(text) - 1)

enum {
    REQUEST_LIMIT = 2 << 20, /* the largest upgrade request: 1 MiB of caller fields and what we add */
    HEAD_LIMIT = 1 << 20,    /* the largest answer head */
    FIELD_CAP = 128,
    READ_CHUNK = 8192
};

static bool is_reserved(MsBytes name) {
    return ms_ascii_equal_fold(name, LITERAL("host")) || ms_ascii_equal_fold(name, LITERAL("upgrade")) ||
           ms_ascii_equal_fold(name, LITERAL("connection")) ||
           (name.len >= 14 && ms_ascii_equal_fold(ms_bytes_of(name.ptr, 14), LITERAL("sec-websocket-")));
}

static bool value_ok(MsBytes value) {
    for (size_t i = 0; i < value.len; i++) {
        if (value.ptr[i] == '\r' || value.ptr[i] == '\n' || value.ptr[i] == 0) return false;
    }
    return true;
}

/* The offered subprotocols as "a, b"; NULL with *length 0 for none or on failure (*ok says which). */
static char *join_protocols(const MsWsDial *dial, size_t *length, bool *ok) {
    size_t total = 0;
    *ok = true;
    for (size_t i = 0; i < dial->protocol_count; i++) {
        if (!ms_h1_is_token(dial->protocols[i])) {
            *ok = false;
            return NULL;
        }
        total += dial->protocols[i].len + 2;
    }
    *length = 0;
    if (total == 0) return NULL;
    char *joined = malloc(total);
    if (joined == NULL) {
        *ok = false;
        return NULL;
    }
    for (size_t i = 0; i < dial->protocol_count; i++) {
        if (i > 0) {
            joined[*length] = ',';
            joined[*length + 1] = ' ';
            *length += 2;
        }
        memcpy(joined + *length, dial->protocols[i].ptr, dial->protocols[i].len);
        *length += dial->protocols[i].len;
    }
    return joined;
}

/* Writes the whole request into buf[cap]: 0, -1 when it does not fit, -2 for a field that is not allowed. */
static int write_request(char *buf, size_t cap, size_t *used, const MsWsDial *dial, const char *key, MsBytes protocols) {
    *used = 0;
    int rc = ms_ws_write_upgrade(buf, cap, used, dial->authority, dial->target, key, protocols);
    const size_t count = dial->headers == NULL ? 0 : ms_headers_count(dial->headers);
    for (size_t i = 0; rc == 0 && i < count; i++) {
        MsBytes name, value;
        ms_headers_field(dial->headers, i, &name, &value);
        if (is_reserved(name) || !ms_h1_is_token(name) || !value_ok(value)) return -2;
        rc = ms_h1_write_field(buf, cap, used, (const char *)name.ptr, name.len, (const char *)value.ptr, value.len);
    }
    if (rc == 0 && dial->compression) {
        rc = ms_h1_write_field(buf, cap, used, "Sec-WebSocket-Extensions", 24, MS_WS_OFFER_DEFLATE, sizeof MS_WS_OFFER_DEFLATE - 1);
    }
    return rc == 0 ? ms_h1_write_head_end(buf, cap, used) : rc;
}

static MsWsStatus status_of(MsNetStatus net) {
    switch (net) {
    case MS_NET_OK: return MS_WSS_OK;
    case MS_NET_TIMEOUT: return MS_WSS_TIMEOUT;
    case MS_NET_CANCELLED: return MS_WSS_CANCELLED;
    case MS_NET_CLOSED: return MS_WSS_CLOSED;
    default: return MS_WSS_FAILED;
    }
}

static MsWsStatus send_request(MsNetConn *conn, const MsWsDial *dial, const char *key, int64_t deadline_ns) {
    bool ok;
    size_t protocols_length = 0;
    char *protocols = join_protocols(dial, &protocols_length, &ok);
    if (!ok) return MS_WSS_INVALID_INPUT;
    MsWsStatus status = MS_WSS_NOMEM;
    for (size_t cap = 2048; cap <= REQUEST_LIMIT; cap *= 2) {
        char *buf = malloc(cap);
        if (buf == NULL) break;
        size_t used;
        const int rc = write_request(buf, cap, &used, dial, key, ms_bytes_of((const uint8_t *)protocols, protocols_length));
        if (rc == 0) {
            status = status_of(ms_conn_write(ms_netconn_table(conn), ms_netconn_id(conn), (const uint8_t *)buf, used, deadline_ns));
        } else if (rc == -2) {
            status = MS_WSS_INVALID_INPUT;
        }
        free(buf);
        if (rc != -1) break;
        status = MS_WSS_INVALID_INPUT; /* still too large at the limit */
    }
    free(protocols);
    return status;
}

/* Reads until the answer head is complete. On OK, buf[0..*length) holds the head and what followed it. */
static MsWsStatus read_answer(MsNetConn *conn, int64_t deadline_ns, uint8_t **buf, size_t *length, MsH1Response *response,
                              MsH1Field *fields) {
    size_t cap = 0;
    *buf = NULL;
    *length = 0;
    for (;;) {
        if (cap - *length < READ_CHUNK) {
            cap = cap == 0 ? (size_t)READ_CHUNK * 2 : cap * 2;
            uint8_t *grown = realloc(*buf, cap);
            if (grown == NULL) return MS_WSS_NOMEM;
            *buf = grown;
        }
        size_t count = 0;
        const MsNetStatus net = ms_conn_read(ms_netconn_table(conn), ms_netconn_id(conn), *buf + *length, cap - *length, deadline_ns, &count);
        if (net != MS_NET_OK) return status_of(net);
        if (count == 0) return MS_WSS_FAILED; /* closed before the answer */
        *length += count;
        MsH1Reader reader;
        response->fields = fields;
        const int parsed = ms_h1_parse_response(&reader, (const char *)*buf, *length, HEAD_LIMIT, response, FIELD_CAP, 0);
        if (parsed == MS_H1_COMPLETE) return MS_WSS_OK;
        if (parsed == MS_H1_BAD) return MS_WSS_FAILED;
    }
}

MsWsStatus ms_ws_dial(const MsObj *conn, const MsWsDial *dial, int64_t deadline_ns, MsWsSocket **out, const char **why) {
    MsNetConn *const core = ms_netconn_of(conn);
    char key[MS_WS_KEY_LEN + 1];
    *why = "connection closed before the exchange completed";
    if (dial->max_message_bytes == 0 || ms_ws_client_key(key) != 0) return MS_WSS_INVALID_INPUT;
    MsWsStatus status = send_request(core, dial, key, deadline_ns);
    if (status != MS_WSS_OK) return status;
    uint8_t *buf;
    size_t length;
    MsH1Response response;
    MsH1Field fields[FIELD_CAP];
    status = read_answer(core, deadline_ns, &buf, &length, &response, fields);
    if (status == MS_WSS_FAILED) *why = "malformed HTTP response";
    MsWsAccepted accepted;
    if (status == MS_WSS_OK) {
        bool ok;
        size_t offered_length = 0;
        char *joined = join_protocols(dial, &offered_length, &ok);
        const MsBytes offered = ms_bytes_of((const uint8_t *)joined, offered_length);
        if (ms_ws_client_accept((const char *)buf, &response, key, offered, &accepted, why) != 0) status = MS_WSS_FAILED;
        free(joined);
    }
    if (status == MS_WSS_OK) {
        const MsWsConfig config = {.max_message_bytes = dial->max_message_bytes, .compress = accepted.compress, .subprotocol = accepted.subprotocol};
        MsObj *const held = ms_netconn_alias(conn); /* the session owns its handle; the caller keeps theirs */
        MsWsSocket *session = held == NULL ? NULL : ms_ws_socket_new(held, MS_WS_ROLE_CLIENT, &config);
        if (session == NULL && held != NULL) held->drop(held);
        const size_t head = response.head_len;
        status = session == NULL ? MS_WSS_NOMEM : MS_WSS_OK;
        if (session != NULL && length > head) status = ms_ws_socket_feed(session, ms_bytes_of(buf + head, length - head));
        if (status == MS_WSS_OK) {
            *out = session;
        } else if (session != NULL) {
            ms_ws_socket_release(session);
        }
    }
    free(buf);
    return status;
}
