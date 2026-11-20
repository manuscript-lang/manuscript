/* HTTP/1 exchanges (http1_exchange.h). */
#include "http1_exchange.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/chars.h"

enum { CHUNK_BYTES = 16384, FIRST_HEAD_BYTES = 4096 };

/* ---- reading a head ---- */

static MsNetStatus grow(MsHttp1Head *head) {
    size_t wanted = head->capacity == 0 ? FIRST_HEAD_BYTES : head->capacity * 2;
    if (wanted > MS_HTTP1_HEAD_LIMIT + CHUNK_BYTES) {
        return MS_NET_FAILED;
    }
    uint8_t *bigger = realloc(head->bytes, wanted);
    if (bigger == NULL) {
        return MS_NET_FAILED;
    }
    head->bytes = bigger;
    head->capacity = wanted;
    return MS_NET_OK;
}

/* Drops the first `count` bytes (an interim head already seen). */
static void drop_front(MsHttp1Head *head, size_t count) {
    memmove(head->bytes, head->bytes + count, head->length - count);
    head->length -= count;
}

MsNetStatus ms_http1_read_head(MsConnTable *table, MsConnId id, int head_request, int64_t deadline_ns, MsHttp1Head *head) {
    memset(head, 0, sizeof *head);
    for (;;) {
        head->response.fields = head->fields;
        const int parsed = head->length == 0 ? MS_H1_PARTIAL
                                             : ms_h1_parse_response(&head->reader, (const char *)head->bytes, head->length,
                                                                    MS_HTTP1_HEAD_LIMIT, &head->response, MS_HTTP1_MAX_FIELDS, head_request);
        if (parsed == MS_H1_BAD) {
            ms_http1_head_free(head);
            return MS_NET_FAILED;
        }
        if (parsed == MS_H1_COMPLETE && head->response.status >= 100 && head->response.status < 200 && head->response.status != 101) {
            drop_front(head, head->response.head_len); /* an interim answer such as 100 Continue */
            continue;
        }
        if (parsed == MS_H1_COMPLETE) {
            return MS_NET_OK;
        }
        if (head->capacity - head->length < CHUNK_BYTES / 4 && grow(head) != MS_NET_OK) {
            ms_http1_head_free(head);
            return MS_NET_FAILED;
        }
        size_t count = 0;
        const MsNetStatus read = ms_conn_read(table, id, head->bytes + head->length, head->capacity - head->length, deadline_ns, &count);
        if (read != MS_NET_OK || count == 0) {
            ms_http1_head_free(head);
            return read != MS_NET_OK ? read : MS_NET_CLOSED; /* the peer closed before a whole head */
        }
        head->length += count;
    }
}

void ms_http1_head_free(MsHttp1Head *head) {
    free(head->bytes);
    head->bytes = NULL;
    head->length = head->capacity = 0;
}

/* ---- the body ---- */

typedef struct MsHttp1Body {
    MsHttpBody base; /* first member: the handle the caller holds */
    MsConnTable *table;
    MsConnId id;
    MsHttp1Head head;
    const uint8_t *input; /* bytes read and not yet fed to the framing: the rest of the head buffer, then `chunk` */
    size_t input_length;
    const uint8_t *run;   /* decoded bytes waiting for the caller */
    size_t run_length;
    uint8_t finished;
    uint8_t chunk[CHUNK_BYTES];
} MsHttp1Body;

/* Reads more bytes from the row into `chunk`. MS_NET_OK with the stream's end handled: `finished` is set when the
 * peer's close ends a body that had no length, and a close that truncates one is MS_NET_FAILED. */
static MsNetStatus refill(MsHttp1Body *body, int64_t deadline_ns) {
    size_t count = 0;
    const MsNetStatus read = ms_conn_read(body->table, body->id, body->chunk, sizeof body->chunk, deadline_ns, &count);
    if (read != MS_NET_OK) {
        return read;
    }
    if (count == 0) {
        if (ms_h1_read_body_eof(&body->head.reader) != MS_H1_BODY_DONE) {
            return MS_NET_FAILED;
        }
        body->finished = 1;
        return MS_NET_OK;
    }
    body->input = body->chunk;
    body->input_length = count;
    return MS_NET_OK;
}

static int body_read(MsHttpBody *handle, MsBytesMut out, int64_t deadline_ns, size_t *n) {
    MsHttp1Body *body = (MsHttp1Body *)handle;
    *n = 0;
    while (out.len > 0) {
        if (body->run_length > 0) {
            const size_t take = body->run_length < out.len ? body->run_length : out.len;
            memcpy(out.ptr, body->run, take);
            body->run += take;
            body->run_length -= take;
            *n = take;
            return MS_NET_OK;
        }
        if (body->finished) {
            return MS_NET_OK;
        }
        MsSpan data = {0, 0};
        size_t used = 0;
        const uint8_t *fed = body->input;
        const int step = ms_h1_read_body(&body->head.reader, (const char *)fed, body->input_length, &data, &used);
        body->input += used;
        body->input_length -= used;
        if (step == MS_H1_BODY_BAD) {
            return MS_NET_FAILED;
        }
        if (step == MS_H1_BODY_DATA) {
            body->run = fed + data.off;
            body->run_length = data.len;
        } else if (step == MS_H1_BODY_DONE) {
            body->finished = 1;
        } else {
            const MsNetStatus refilled = refill(body, deadline_ns);
            if (refilled != MS_NET_OK) {
                return refilled;
            }
        }
    }
    return MS_NET_OK;
}

/* A body that ends the message with nothing left over leaves the row ready for the next request, provided the peer
 * agreed to keep it open. Anything else (an unread rest, bytes past the message, a closing peer) closes the row. */
static bool row_reusable(MsHttp1Body *body) {
    if (!body->finished) {
        /* A body with no bytes (HEAD, 204, 304, length 0) ends when asked, without a read. */
        MsSpan data = {0, 0};
        size_t used = 0;
        const int step = ms_h1_read_body(&body->head.reader, (const char *)body->input, body->input_length, &data, &used);
        body->input += used;
        body->input_length -= used;
        body->finished = step == MS_H1_BODY_DONE;
    }
    return body->finished && body->head.response.keep_alive != 0 && body->input_length == 0 && body->run_length == 0;
}

static void body_close(MsHttpBody *handle) {
    MsHttp1Body *body = (MsHttp1Body *)handle;
    if (!row_reusable(body)) {
        (void)ms_conn_close_io(body->table, body->id);
    }
    ms_http1_head_free(&body->head);
    free(body);
}

/* ---- sending a request ---- */

typedef struct Out {
    uint8_t *bytes;
    size_t used, capacity;
} Out;

/* The bytes the request head can take at most, so one allocation holds it: the lines it is made of and their
 * separators. Fails on overflow. */
static bool head_capacity(const MsHttpRequest *request, size_t *capacity) {
    size_t total = 128; /* the request line's version, Host and Content-Length names, the length digits, blank line */
    if (!ms_size_add(total, request->method.len, &total) || !ms_size_add(total, request->target.len, &total) ||
        !ms_size_add(total, request->authority.len, &total)) {
        return false;
    }
    for (uint32_t i = 0; i < request->nfields; i++) {
        const MsH1Field *f = &request->fields[i];
        if (!ms_size_add(total, (size_t)f->name.len + f->value.len + 4, &total)) {
            return false;
        }
    }
    *capacity = total;
    return true;
}

/* Writes the request head into `out`. 0, or -1 when a field is refused or the head holds a byte the writers refuse. */
static int write_request_head(Out *out, const MsHttpRequest *request) {
    for (uint32_t i = 0; i < request->nfields; i++) {
        const MsH1Field *f = &request->fields[i];
        if (ms_http_field_refused(ms_bytes_of(request->head.ptr + f->name.off, f->name.len), false)) {
            return -1;
        }
    }
    char *at = (char *)out->bytes;
    if (ms_h1_write_request_line(at, out->capacity, &out->used, (const char *)request->method.ptr, request->method.len,
                                 (const char *)request->target.ptr, request->target.len) != 0 ||
        ms_h1_write_field(at, out->capacity, &out->used, "Host", 4, (const char *)request->authority.ptr, request->authority.len) != 0) {
        return -1;
    }
    char length[24];
    const int digits = snprintf(length, sizeof length, "%zu", request->body.len);
    if (ms_h1_write_field(at, out->capacity, &out->used, "Content-Length", 14, length, (size_t)digits) != 0) {
        return -1;
    }
    for (uint32_t i = 0; i < request->nfields; i++) {
        const MsH1Field *f = &request->fields[i];
        if (ms_h1_write_field(at, out->capacity, &out->used, (const char *)request->head.ptr + f->name.off, f->name.len,
                              (const char *)request->head.ptr + f->value.off, f->value.len) != 0) {
            return -1;
        }
    }
    return ms_h1_write_head_end(at, out->capacity, &out->used) == 0 ? 0 : -1;
}

MsNetStatus ms_http1_exchange(MsConnTable *table, MsConnId id, const MsHttpRequest *request, int64_t deadline_ns,
                              MsHttpResponse *response, MsHttpBody **body_out) {
    Out out = {NULL, 0, 0};
    if (!head_capacity(request, &out.capacity)) {
        return MS_NET_FAILED;
    }
    out.bytes = malloc(out.capacity);
    if (out.bytes == NULL) {
        return MS_NET_FAILED;
    }
    if (write_request_head(&out, request) != 0) {
        free(out.bytes);
        return MS_NET_FAILED;
    }
    MsNetStatus status = ms_conn_write(table, id, out.bytes, out.used, deadline_ns);
    free(out.bytes);
    if (status == MS_NET_OK && request->body.len > 0) {
        status = ms_conn_write(table, id, request->body.ptr, request->body.len, deadline_ns);
    }
    if (status != MS_NET_OK) {
        return status;
    }
    MsHttp1Body *body = calloc(1, sizeof *body);
    if (body == NULL) {
        return MS_NET_FAILED;
    }
    const int is_head = request->method.len == 4 && memcmp(request->method.ptr, "HEAD", 4) == 0;
    status = ms_http1_read_head(table, id, is_head, deadline_ns, &body->head);
    if (status != MS_NET_OK) {
        free(body);
        return status;
    }
    body->base.read = body_read;
    body->base.close = body_close;
    body->table = table;
    body->id = id;
    body->input = body->head.bytes + body->head.response.head_len;
    body->input_length = body->head.length - body->head.response.head_len;
    response->status = body->head.response.status;
    response->head = ms_bytes_of(body->head.bytes, body->head.response.head_len);
    response->fields = body->head.fields;
    response->nfields = body->head.response.nfields;
    *body_out = &body->base;
    return MS_NET_OK;
}
