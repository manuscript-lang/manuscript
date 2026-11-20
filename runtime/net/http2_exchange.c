/* HTTP/2 exchanges (http2_exchange.h). */
#include "http2_exchange.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "h2conn.h"
#include "ms_rt/chars.h"

enum { CHUNK_BYTES = 16384, H2_CANCEL = 8 };

typedef struct MsHttp2Body {
    MsHttpBody base; /* first, so the handle converts back */
    MsConnTable *table;
    MsConnId id;
    MsH2Conn *h2;
    int32_t stream;
    bool finished;       /* the body was read to its end */
    uint8_t *head_bytes; /* the response head's names and values, which `fields` index */
    size_t head_length;
    MsH1Field *fields;
} MsHttp2Body;

/* ---- moving bytes between the connection and the row ---- */

static MsNetStatus flush(MsHttp2Body *x, int64_t deadline_ns) {
    uint8_t buffer[CHUNK_BYTES];
    long count;
    while ((count = ms_h2conn_output(x->h2, buffer, sizeof buffer)) > 0) {
        const MsNetStatus status = ms_conn_write(x->table, x->id, buffer, (size_t)count, deadline_ns);
        if (status != MS_NET_OK) {
            return status;
        }
    }
    return MS_NET_OK;
}

/* Sends what is pending, reads one chunk from the row and feeds it in. The events the connection queues are dropped:
 * this driver reads stream state instead. */
static MsNetStatus pump(MsHttp2Body *x, int64_t deadline_ns) {
    MsNetStatus status = flush(x, deadline_ns);
    if (status != MS_NET_OK) {
        return status;
    }
    uint8_t buffer[CHUNK_BYTES];
    size_t count = 0;
    status = ms_conn_read(x->table, x->id, buffer, sizeof buffer, deadline_ns, &count);
    if (status != MS_NET_OK) {
        return status;
    }
    if (count == 0) {
        return MS_NET_CLOSED; /* the peer ended the connection before the exchange */
    }
    const long used = ms_h2conn_input(x->h2, buffer, count);
    MsH2ConnEvent event;
    while (ms_h2conn_next(x->h2, &event) != 0) {
    }
    if (used < 0) {
        (void)flush(x, deadline_ns); /* the GOAWAY */
        return MS_NET_FAILED;
    }
    return flush(x, deadline_ns);
}

/* ---- the body ---- */

static int body_read(MsHttpBody *handle, MsBytesMut out, int64_t deadline_ns, size_t *n) {
    MsHttp2Body *x = (MsHttp2Body *)handle;
    *n = 0;
    for (;;) {
        const long count = out.len == 0 ? 0 : ms_h2conn_read(x->h2, x->stream, out.ptr, out.len);
        if (count < 0) {
            return MS_NET_FAILED;
        }
        if (count > 0) {
            *n = (size_t)count;
            const MsNetStatus status = flush(x, deadline_ns); /* the window updates the read queued */
            return status == MS_NET_OK ? 0 : (int)status;
        }
        const unsigned state = ms_h2conn_state(x->h2, x->stream);
        if ((state & MS_H2S_RESET) != 0) {
            return MS_NET_FAILED;
        }
        if ((state & MS_H2S_ENDED) != 0) {
            x->finished = true;
            return 0;
        }
        if (out.len == 0) {
            return 0;
        }
        const MsNetStatus status = pump(x, deadline_ns);
        if (status != MS_NET_OK) {
            return (int)status;
        }
    }
}

static void body_close(MsHttpBody *handle) {
    MsHttp2Body *x = (MsHttp2Body *)handle;
    ms_h2conn_release(x->h2, x->stream, x->finished ? 0 : H2_CANCEL);
    (void)ms_conn_close_io(x->table, x->id);
    ms_h2conn_free(x->h2);
    free(x->head_bytes);
    free(x->fields);
    free(x);
}

/* ---- the request ---- */

/* HTTP/2 forbids these; a request that names one is refused rather than rewritten. */
static bool field_refused(MsBytes name) {
    static const char *const refused[] = {"host", "content-length", "transfer-encoding", "connection", "keep-alive",
                                          "proxy-connection", "upgrade"};
    for (size_t i = 0; i < sizeof refused / sizeof refused[0]; i++) {
        if (ms_ascii_equal_fold(name, ms_bytes_of((const uint8_t *)refused[i], strlen(refused[i])))) {
            return true;
        }
    }
    return false;
}

/* The header block: four pseudo-headers, the caller's fields with lower-case names, then content-length. Names are
 * lowered into `names`, which the block's entries point into. Returns false when a field is refused. */
static bool build_block(const MsHttpRequest *request, bool secure, MsH2Nv *block, char *names, char length_text[24], size_t *count) {
    const char *scheme = secure ? "https" : "http";
    size_t used = 0;
    block[used++] = (MsH2Nv){":method", 7, (const char *)request->method.ptr, request->method.len};
    block[used++] = (MsH2Nv){":scheme", 7, scheme, strlen(scheme)};
    block[used++] = (MsH2Nv){":authority", 10, (const char *)request->authority.ptr, request->authority.len};
    block[used++] = (MsH2Nv){":path", 5, (const char *)request->target.ptr, request->target.len};
    for (uint32_t i = 0; i < request->nfields; i++) {
        const MsH1Field *f = &request->fields[i];
        const MsBytes name = ms_bytes_of(request->head.ptr + f->name.off, f->name.len);
        if (field_refused(name)) {
            return false;
        }
        for (size_t k = 0; k < name.len; k++) {
            names[k] = (char)ms_ascii_to_lower(name.ptr[k]);
        }
        block[used++] = (MsH2Nv){names, name.len, (const char *)request->head.ptr + f->value.off, f->value.len};
        names += name.len;
    }
    if (request->body.len > 0) {
        const int digits = snprintf(length_text, 24, "%zu", request->body.len);
        block[used++] = (MsH2Nv){"content-length", 14, length_text, (size_t)digits};
    }
    *count = used;
    return true;
}

/* Sends the request body, waiting on the peer's flow control as often as it takes. */
static MsNetStatus send_body(MsHttp2Body *x, MsBytes body, int64_t deadline_ns) {
    size_t sent = 0;
    while (sent < body.len) {
        const long taken = ms_h2conn_send(x->h2, x->stream, body.ptr + sent, body.len - sent, 1);
        if (taken < 0) {
            return MS_NET_FAILED;
        }
        sent += (size_t)taken;
        if (sent < body.len || taken == 0) {
            const MsNetStatus status = pump(x, deadline_ns);
            if (status != MS_NET_OK) {
                return status;
            }
        }
    }
    return flush(x, deadline_ns);
}

/* ---- the response head ---- */

/* Copies the head's fields into one block of bytes with spans, the shape both protocols hand to the caller. */
static bool copy_head(MsHttp2Body *x, const MsH2Head *head) {
    size_t total = 0;
    for (size_t i = 0; i < head->nfields; i++) {
        if (!ms_size_add(total, head->fields[i].name.len, &total) || !ms_size_add(total, head->fields[i].value.len, &total)) {
            return false;
        }
    }
    x->head_bytes = malloc(total == 0 ? 1 : total);
    x->fields = calloc(head->nfields == 0 ? 1 : head->nfields, sizeof *x->fields);
    if (x->head_bytes == NULL || x->fields == NULL || total > UINT32_MAX) {
        return false;
    }
    x->head_length = total;
    uint32_t at = 0;
    for (size_t i = 0; i < head->nfields; i++) {
        const MsH2Header *h = &head->fields[i];
        memcpy(x->head_bytes + at, h->name.ptr, h->name.len);
        x->fields[i].name = (MsSpan){at, (uint32_t)h->name.len};
        at += (uint32_t)h->name.len;
        memcpy(x->head_bytes + at, h->value.ptr, h->value.len);
        x->fields[i].value = (MsSpan){at, (uint32_t)h->value.len};
        at += (uint32_t)h->value.len;
    }
    return true;
}

static MsNetStatus await_head(MsHttp2Body *x, int64_t deadline_ns) {
    for (;;) {
        const unsigned state = ms_h2conn_state(x->h2, x->stream);
        if ((state & MS_H2S_RESET) != 0) {
            return MS_NET_FAILED;
        }
        if ((state & MS_H2S_HEAD) != 0) {
            return MS_NET_OK;
        }
        const MsNetStatus status = pump(x, deadline_ns);
        if (status != MS_NET_OK) {
            return status;
        }
    }
}

MsNetStatus ms_http2_exchange(MsConnTable *table, MsConnId id, const MsHttpRequest *request, int64_t deadline_ns,
                              MsHttpResponse *response, MsHttpBody **body_out) {
    size_t name_bytes = 0;
    for (uint32_t i = 0; i < request->nfields; i++) {
        name_bytes += request->fields[i].name.len;
    }
    MsH2Nv *block = calloc((size_t)request->nfields + 5, sizeof *block);
    char *names = malloc(name_bytes == 0 ? 1 : name_bytes);
    MsHttp2Body *x = calloc(1, sizeof *x);
    MsNetStatus status = MS_NET_FAILED;
    char length_text[24];
    size_t count = 0;
    if (block == NULL || names == NULL || x == NULL || !build_block(request, ms_conn_tls(table, id) != NULL, block, names, length_text, &count)) {
        goto fail;
    }
    x->base.read = body_read;
    x->base.close = body_close;
    x->table = table;
    x->id = id;
    x->h2 = ms_h2conn_new(0, NULL);
    if (x->h2 == NULL) {
        goto fail;
    }
    x->stream = ms_h2conn_open(x->h2, block, count, request->body.len > 0);
    if (x->stream < 0) {
        goto fail;
    }
    status = request->body.len > 0 ? send_body(x, request->body, deadline_ns) : flush(x, deadline_ns);
    if (status == MS_NET_OK) {
        status = await_head(x, deadline_ns);
    }
    const MsH2Head *head = status == MS_NET_OK ? ms_h2conn_head(x->h2, x->stream) : NULL;
    if (head == NULL || !copy_head(x, head)) {
        status = status == MS_NET_OK ? MS_NET_FAILED : status;
        goto fail;
    }
    response->status = (uint16_t)head->status;
    response->head = ms_bytes_of(x->head_bytes, x->head_length);
    response->fields = x->fields;
    response->nfields = (uint32_t)head->nfields;
    free(block);
    free(names);
    *body_out = &x->base;
    return MS_NET_OK;

fail:
    free(block);
    free(names);
    if (x != NULL) {
        if (x->h2 != NULL) {
            ms_h2conn_free(x->h2);
        }
        free(x->head_bytes);
        free(x->fields);
        free(x);
    }
    return status;
}
