/* msstd_http_fetch and the response body natives of ms_rt/net.h: one HTTP exchange on a dialed connection, over
 * http1_exchange.h or http2_exchange.h by the protocol the TLS handshake negotiated. */
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "conn_object.h"
#include "headers.h"
#include "http1_exchange.h"
#include "http2_exchange.h"
#include "ms_rt/alloc.h"
#include "ms_rt/chars.h"
#include "ms_rt/net.h"
#include "status.h"
#include "tls.h"

enum { READ_DEFAULT = 64 * 1024, READ_ALL_LIMIT = 1 << 30 };

/* ---- the body object (BodyH) ---- */

typedef struct BodyObject {
    MsObj header;
    MsObj *conn;           /* a handle on the connection's core, which the exchange needs open */
    MsHttpBody *exchange;  /* NULL once the body is closed */
    MsObj *headers;        /* the response's, kept for `metadata` after the close */
    int64_t status;
    const char *protocol;
    int64_t deadline_ns;   /* one deadline covers the head and the whole body */
    bool failed;           /* a read failed: the connection is not reusable */
} BodyObject;

static void release(MsObj *object) {
    if (object != NULL && object->drop != NULL) {
        object->drop(object);
    }
}

/* Ends the exchange: a clean end leaves the connection for the next request, a failed one closes it. */
static void body_end(BodyObject *body) {
    if (body->exchange == NULL) {
        return;
    }
    body->exchange->close(body->exchange);
    body->exchange = NULL;
    if (body->failed) {
        ms_netconn_close(body->conn);
    }
    ms_netconn_end_exchange(ms_netconn_of(body->conn));
}

static void body_drop(MsObj *object) {
    BodyObject *body = (BodyObject *)object;
    body_end(body);
    release(body->headers);
    release(body->conn);
    msrt_free(body);
}

static int body_error_code(const BodyObject *body) {
    const MsNetConn *conn = ms_netconn_of(body->conn);
    return ms_conn_error_code(ms_netconn_table(conn), ms_netconn_id(conn));
}

/* One read of at most `capacity` bytes into `buffer`; *n is 0 at the end of the body. */
static uint8_t body_read_some(BodyObject *body, uint8_t *buffer, size_t capacity, size_t *n, MsStr *err) {
    *n = 0;
    if (body->exchange == NULL) {
        return STATUS_CLOSED;
    }
    const int status = body->exchange->read(body->exchange, ms_bytes_mut(buffer, capacity), body->deadline_ns, n);
    if (status == 0) {
        return STATUS_OK;
    }
    body->failed = true;
    return ms_net_finish((MsNetStatus)status, body_error_code(body), err);
}

uint8_t msstd_body_read(const void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err) {
    BodyObject *body = (BodyObject *)handle;
    if (has_max != 0 && max <= 0) {
        return STATUS_INVALID_INPUT;
    }
    const size_t capacity = has_max != 0 && max < READ_DEFAULT ? (size_t)max : READ_DEFAULT;
    uint8_t *buffer = malloc(capacity);
    if (buffer == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    size_t count = 0;
    uint8_t status = body_read_some(body, buffer, capacity, &count, err);
    if (status == STATUS_OK) {
        status = count > 0 ? STATUS_OK : STATUS_NONE;
        if (count > 0) {
            msrt_write_bytes(out, buffer, count);
        }
    }
    free(buffer);
    return status;
}

uint8_t msstd_body_read_all(const void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err) {
    BodyObject *body = (BodyObject *)handle;
    if (has_max != 0 && max < 0) {
        return STATUS_INVALID_INPUT;
    }
    const size_t limit = has_max != 0 ? (size_t)max : READ_ALL_LIMIT;
    uint8_t *data = NULL;
    size_t used = 0, capacity = 0;
    uint8_t status = STATUS_OK;
    for (;;) {
        if (used == capacity) {
            if (used > limit) {
                status = STATUS_LIMIT_EXCEEDED;
                break;
            }
            const size_t grown = capacity == 0 ? READ_DEFAULT : capacity * 2;
            uint8_t *bigger = realloc(data, grown);
            if (bigger == NULL) {
                status = ms_net_finish(MS_NET_FAILED, 0, err);
                break;
            }
            data = bigger;
            capacity = grown;
        }
        size_t count = 0;
        status = body_read_some(body, data + used, capacity - used, &count, err);
        if (status != STATUS_OK || count == 0) {
            break;
        }
        used += count;
        if (used > limit) {
            status = STATUS_LIMIT_EXCEEDED;
            break;
        }
    }
    if (status == STATUS_OK) {
        msrt_write_bytes(out, data, used);
    }
    free(data);
    return status;
}

void msstd_body_metadata(const void *handle, MsNetBodyMetadata *out) {
    const BodyObject *body = (const BodyObject *)handle;
    out->status = body->status;
    out->headers = msstd_headers_clone(body->headers);
    ms_net_write_text(&out->protocol, body->protocol);
}

void msstd_body_close(const void *handle) { body_end((BodyObject *)handle); }

/* ---- the request ---- */

/* The request's fields as one block of bytes with spans, the shape the exchanges take. Fails with STATUS_INVALID_INPUT
 * for a field the exchange refuses or a value that could split the head. */
typedef struct Block {
    uint8_t *bytes;
    MsH1Field *fields;
    size_t count, length;
} Block;

static uint8_t block_make(const MsHeaders *table, bool http2, Block *block) {
    const size_t count = ms_headers_count(table);
    size_t total = 0;
    for (size_t i = 0; i < count; i++) {
        MsBytes name, value;
        ms_headers_field(table, i, &name, &value);
        if (ms_http_field_refused(name, http2) || !ms_h1_is_token(name) ||
            memchr(value.ptr, '\r', value.len) != NULL || memchr(value.ptr, '\n', value.len) != NULL ||
            (value.len > 0 && memchr(value.ptr, 0, value.len) != NULL)) {
            return STATUS_INVALID_INPUT;
        }
        total += name.len + value.len;
    }
    block->bytes = malloc(total == 0 ? 1 : total);
    block->fields = calloc(count == 0 ? 1 : count, sizeof *block->fields);
    block->count = count;
    block->length = total;
    if (block->bytes == NULL || block->fields == NULL) {
        return STATUS_FAILED;
    }
    uint32_t at = 0;
    for (size_t i = 0; i < count; i++) {
        MsBytes name, value;
        ms_headers_field(table, i, &name, &value);
        memcpy(block->bytes + at, name.ptr, name.len);
        block->fields[i].name = (MsSpan){at, (uint32_t)name.len};
        at += (uint32_t)name.len;
        if (value.len > 0) {
            memcpy(block->bytes + at, value.ptr, value.len);
        }
        block->fields[i].value = (MsSpan){at, (uint32_t)value.len};
        at += (uint32_t)value.len;
    }
    return STATUS_OK;
}

static void block_free(Block *block) {
    free(block->bytes);
    free(block->fields);
}

/* Whether `text` is usable as a request line part: not empty, no space or control byte. */
static bool clean(MsBytes text) {
    for (size_t i = 0; i < text.len; i++) {
        if (text.ptr[i] <= ' ' || text.ptr[i] == 0x7f) {
            return false;
        }
    }
    return text.len > 0;
}

static MsBytes str_bytes(const MsStr *text) { return ms_bytes_of((const uint8_t *)msrt_str_data(text), msrt_str_len(text)); }

/* The response's fields as a headers table, names in canonical form. NULL when out of memory or past the limits. */
static MsObj *response_headers(const MsHttpResponse *response) {
    MsHeaders *table = ms_headers_new();
    for (uint32_t i = 0; table != NULL && i < response->nfields; i++) {
        const MsH1Field *f = &response->fields[i];
        if (!ms_headers_add_canonical(table, ms_bytes_of(response->head.ptr + f->name.off, f->name.len),
                                      ms_bytes_of(response->head.ptr + f->value.off, f->value.len))) {
            release(ms_headers_object(table));
            return NULL;
        }
    }
    return table == NULL ? NULL : ms_headers_object(table);
}

static bool negotiated_h2(MsConnTable *table, MsConnId id) {
    const MsTls *session = ms_conn_tls(table, id);
    return session != NULL && ms_bytes_equal(ms_tls_alpn(session), ms_bytes_of((const uint8_t *)"h2", 2));
}

/* The exchange on the connection: the response head in *response and the body stream in *exchange. */
static MsNetStatus run_exchange(MsNetConn *conn, bool http2, const MsHttpRequest *request, int64_t deadline_ns,
                                MsHttpResponse *response, MsHttpBody **exchange) {
    MsConnTable *table = ms_netconn_table(conn);
    const MsConnId id = ms_netconn_id(conn);
    if (!http2) {
        return ms_http1_exchange(table, id, request, deadline_ns, response, exchange);
    }
    MsH2Conn *session = ms_netconn_h2(conn);
    return session == NULL ? MS_NET_FAILED : ms_http2_exchange(table, id, session, request, deadline_ns, response, exchange);
}

uint8_t msstd_http_fetch(const void *handle, const MsStr *method, const MsStr *authority, const MsStr *target,
                         const void *headers, const MsVec *payload, uint8_t has_timeout, int64_t timeout, void **out,
                         MsStr *err) {
    MsNetConn *conn = ms_netconn_of(handle);
    const bool http2 = negotiated_h2(ms_netconn_table(conn), ms_netconn_id(conn));
    Block block = {NULL, NULL, 0, 0};
    uint8_t status = !ms_h1_is_token(str_bytes(method)) || !clean(str_bytes(authority)) || !clean(str_bytes(target))
                         ? STATUS_INVALID_INPUT
                         : block_make(ms_headers_of(headers), http2, &block);
    if (status == STATUS_OK && !ms_netconn_begin_exchange(conn)) {
        status = STATUS_BUSY;
    }
    if (status != STATUS_OK) {
        block_free(&block);
        return status;
    }
    const MsHttpRequest request = {.method = str_bytes(method), .authority = str_bytes(authority), .target = str_bytes(target),
                                   .head = ms_bytes_of(block.bytes, block.length),
                                   .fields = block.fields, .nfields = (uint32_t)block.count,
                                   .body = ms_bytes_of(payload->ptr, payload->len)};
    const int64_t deadline = ms_net_deadline_of(has_timeout, timeout);
    MsHttpResponse response;
    MsHttpBody *exchange = NULL;
    const MsNetStatus result = run_exchange(conn, http2, &request, deadline, &response, &exchange);
    block_free(&block);
    MsObj *received = result == MS_NET_OK ? response_headers(&response) : NULL;
    BodyObject *body = received == NULL ? NULL : msrt_alloc_zeroed(sizeof *body);
    if (body == NULL) {
        if (exchange != NULL) {
            exchange->close(exchange);
        }
        release(received);
        ms_netconn_close(handle); /* the exchange cannot be finished: the connection is not reusable */
        ms_netconn_end_exchange(conn);
        return ms_net_finish(result == MS_NET_OK ? MS_NET_FAILED : result,
                             ms_conn_error_code(ms_netconn_table(conn), ms_netconn_id(conn)), err);
    }
    body->header.drop = body_drop;
    body->conn = ms_netconn_alias(handle);
    body->exchange = exchange;
    body->headers = received;
    body->status = response.status;
    body->protocol = http2 ? "HTTP/2.0" : "HTTP/1.1";
    body->deadline_ns = deadline;
    *out = &body->header;
    return STATUS_OK;
}
