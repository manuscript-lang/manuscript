#include "h2.h"
#include <nghttp2/nghttp2.h>
#include "ms_rt/safe.h"
#include <stdlib.h>
#include <string.h>

/* The body of one stream while it is sent: queued bytes data[off..len), then optionally a trailer block. */
typedef struct MsH2Body {
    uint8_t *data;              /* owned */
    size_t len, off, cap;
    nghttp2_nv *trailers;       /* owned, names and values point into trailer_text */
    char *trailer_text;         /* owned */
    size_t ntrailers;
    int32_t stream;             /* the stream it feeds */
    uint8_t ended;              /* no more bytes will be queued */
    uint8_t blocked;            /* a send was cut short: raise MS_H2_WRITABLE when the queue drains */
    struct MsH2Body *prev, *next;
} MsH2Body;

struct MsH2 {
    nghttp2_session *session;
    char *arena; size_t arena_len, arena_cap;
    MsH2Field *fields; size_t nfields, fields_cap;
    MsH2Event *events; size_t nevents, events_cap, next;
    size_t block_first;  /* first field of the header block being received */
    MsH2Body *bodies; /* every unsent body, so teardown frees streams that never closed */
    const uint8_t *pend; size_t pend_len; /* output nghttp2 handed out that did not fit the caller's buffer yet */
    int failed;
};

static int grow(void **p, size_t *cap, size_t need, size_t unit) {
    if (need <= *cap) return 0;
    size_t c = *cap ? *cap : 16;
    while (c < need) c *= 2;
    void *q = realloc(*p, c * unit);
    if (!q) return -1;
    *p = q; *cap = c;
    return 0;
}

static int put(MsH2 *h, const void *s, size_t n, MsH2Span *span) {
    if (n > UINT32_MAX || h->arena_len + n > UINT32_MAX) return -1;
    if (grow((void **)&h->arena, &h->arena_cap, h->arena_len + n, 1)) return -1;
    memcpy(h->arena + h->arena_len, s, n);
    span->off = (uint32_t)h->arena_len; span->len = (uint32_t)n;
    h->arena_len += n;
    return 0;
}

static MsH2Event *push(MsH2 *h, int type, int32_t stream) {
    if (grow((void **)&h->events, &h->events_cap, h->nevents + 1, sizeof *h->events)) return NULL;
    MsH2Event *e = &h->events[h->nevents++];
    memset(e, 0, sizeof *e);
    e->type = type; e->stream = stream;
    return e;
}

static int on_begin_headers(nghttp2_session *s, const nghttp2_frame *f, void *u) {
    (void)s; (void)f;
    MsH2 *h = u;
    h->block_first = h->nfields;
    return 0;
}

static int on_header(nghttp2_session *s, const nghttp2_frame *f, const uint8_t *name, size_t nl, const uint8_t *value,
                     size_t vl, uint8_t flags, void *u) {
    (void)s; (void)f; (void)flags;
    MsH2 *h = u;
    if (grow((void **)&h->fields, &h->fields_cap, h->nfields + 1, sizeof *h->fields)) return NGHTTP2_ERR_CALLBACK_FAILURE;
    MsH2Field *fl = &h->fields[h->nfields];
    if (put(h, name, nl, &fl->name) || put(h, value, vl, &fl->value)) return NGHTTP2_ERR_CALLBACK_FAILURE;
    h->nfields++;
    return 0;
}

static int on_frame_recv(nghttp2_session *s, const nghttp2_frame *f, void *u) {
    (void)s;
    MsH2 *h = u;
    MsH2Event *e;
    switch (f->hd.type) {
    case NGHTTP2_HEADERS:
        e = push(h, MS_H2_HEADERS, f->hd.stream_id);
        if (e == NULL) return NGHTTP2_ERR_CALLBACK_FAILURE;
        e->end_stream = (f->hd.flags & NGHTTP2_FLAG_END_STREAM) != 0;
        e->nfields = (uint32_t)(h->nfields - h->block_first);
        e->error_code = (uint32_t)h->block_first; /* patched to a pointer in ms_h2_next: the array may move */
        break;
    case NGHTTP2_DATA:
        if (f->hd.flags & NGHTTP2_FLAG_END_STREAM) {
            e = push(h, MS_H2_DATA, f->hd.stream_id);
            if (e == NULL) return NGHTTP2_ERR_CALLBACK_FAILURE;
            e->end_stream = 1; /* empty final chunk, so the reader sees the end */
        }
        break;
    case NGHTTP2_RST_STREAM:
        e = push(h, MS_H2_RESET, f->hd.stream_id);
        if (e == NULL) return NGHTTP2_ERR_CALLBACK_FAILURE;
        e->error_code = f->rst_stream.error_code;
        break;
    case NGHTTP2_GOAWAY:
        e = push(h, MS_H2_GOAWAY, f->goaway.last_stream_id);
        if (e == NULL) return NGHTTP2_ERR_CALLBACK_FAILURE;
        e->error_code = f->goaway.error_code;
        break;
    default: break;
    }
    return 0;
}

static int on_data_chunk(nghttp2_session *s, uint8_t flags, int32_t stream, const uint8_t *data, size_t len, void *u) {
    (void)s; (void)flags;
    MsH2 *h = u;
    MsH2Event *e = push(h, MS_H2_DATA, stream);
    if (!e || put(h, data, len, &e->data)) return NGHTTP2_ERR_CALLBACK_FAILURE;
    return 0;
}

static void drop(MsH2 *h, MsH2Body *b) {
    if (b->prev) b->prev->next = b->next; else h->bodies = b->next;
    if (b->next) b->next->prev = b->prev;
    free(b->data); free(b->trailers); free(b->trailer_text); free(b);
}

static int on_stream_close(nghttp2_session *s, int32_t stream, uint32_t code, void *u) {
    MsH2 *h = u;
    MsH2Body *b = nghttp2_session_get_stream_user_data(s, stream);
    if (b) { drop(h, b); nghttp2_session_set_stream_user_data(s, stream, NULL); }
    MsH2Event *e = push(h, MS_H2_CLOSED, stream);
    if (!e) return NGHTTP2_ERR_CALLBACK_FAILURE;
    e->error_code = code;
    return 0;
}

/* nghttp2 asks for the next bytes of a body: none queued yet defers the stream until ms_h2_send resumes it. */
static ssize_t read_body(nghttp2_session *s, int32_t stream, uint8_t *buf, size_t len, uint32_t *flags,
                         nghttp2_data_source *src, void *u) {
    MsH2 *h = u;
    MsH2Body *b = src->ptr;
    size_t queued = b->len - b->off;
    if (queued == 0 && !b->ended) return NGHTTP2_ERR_DEFERRED;
    size_t n = queued < len ? queued : len;
    memcpy(buf, b->data + b->off, n);
    b->off += n;
    if (b->off == b->len) b->off = b->len = 0;
    if (b->blocked && b->len - b->off < MS_H2_SEND_HOLD / 2) {
        b->blocked = 0;
        if (push(h, MS_H2_WRITABLE, stream) == NULL) return NGHTTP2_ERR_CALLBACK_FAILURE;
    }
    if (b->ended && b->len == b->off) {
        *flags |= NGHTTP2_DATA_FLAG_EOF;
        if (b->ntrailers) {
            *flags |= NGHTTP2_DATA_FLAG_NO_END_STREAM;
            if (nghttp2_submit_trailer(s, stream, b->trailers, b->ntrailers)) return NGHTTP2_ERR_CALLBACK_FAILURE;
        }
    }
    return (ssize_t)n;
}

static int submit_limits(MsH2 *h, const MsH2Limits *limits);

MsH2 *ms_h2_new(int server, const MsH2Limits *limits) {
    MsH2 *h = calloc(1, sizeof *h);
    if (!h) return NULL;
    nghttp2_session_callbacks *cb;
    if (nghttp2_session_callbacks_new(&cb)) { free(h); return NULL; }
    nghttp2_session_callbacks_set_on_begin_headers_callback(cb, on_begin_headers);
    nghttp2_session_callbacks_set_on_header_callback(cb, on_header);
    nghttp2_session_callbacks_set_on_frame_recv_callback(cb, on_frame_recv);
    nghttp2_session_callbacks_set_on_data_chunk_recv_callback(cb, on_data_chunk);
    nghttp2_session_callbacks_set_on_stream_close_callback(cb, on_stream_close);
    /* Receive windows are returned by ms_h2_consume, so a reader that stops reading stops the peer. The flood
       limits (queued acknowledgements, reset bursts) are nghttp2's defaults. */
    nghttp2_option *opt;
    if (nghttp2_option_new(&opt)) { nghttp2_session_callbacks_del(cb); free(h); return NULL; }
    nghttp2_option_set_no_auto_window_update(opt, 1);
    int rc = server ? nghttp2_session_server_new2(&h->session, cb, h, opt) : nghttp2_session_client_new2(&h->session, cb, h, opt);
    nghttp2_option_del(opt);
    nghttp2_session_callbacks_del(cb);
    if (rc) { free(h); return NULL; }
    if (submit_limits(h, limits)) { ms_h2_free(h); return NULL; }
    return h;
}

/* The initial SETTINGS frame and the connection receive window. */
static int submit_limits(MsH2 *h, const MsH2Limits *limits) {
    nghttp2_settings_entry iv[3];
    size_t n = 0;
    if (limits != NULL && limits->max_concurrent_streams)
        iv[n++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, limits->max_concurrent_streams};
    if (limits != NULL && limits->max_header_list_size)
        iv[n++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_MAX_HEADER_LIST_SIZE, limits->max_header_list_size};
    if (limits != NULL && limits->stream_window)
        iv[n++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_INITIAL_WINDOW_SIZE, limits->stream_window};
    if (nghttp2_submit_settings(h->session, NGHTTP2_FLAG_NONE, iv, n)) return -1;
    if (limits != NULL && limits->connection_window > NGHTTP2_INITIAL_CONNECTION_WINDOW_SIZE &&
        limits->connection_window <= (uint32_t)NGHTTP2_MAX_WINDOW_SIZE)
        return nghttp2_session_set_local_window_size(h->session, NGHTTP2_FLAG_NONE, 0, (int32_t)limits->connection_window);
    return 0;
}

void ms_h2_free(MsH2 *h) {
    if (!h) return;
    nghttp2_session_del(h->session);
    for (MsH2Body *b = h->bodies; b != NULL;) {
        MsH2Body *following = b->next;
        free(b->data);
        free(b);
        b = following;
    }
    free(h->arena); free(h->fields); free(h->events);
    free(h);
}

long ms_h2_input(MsH2 *h, const void *buf, size_t n) {
    ssize_t r = nghttp2_session_mem_recv(h->session, buf, n);
    if (r < 0) { h->failed = 1; nghttp2_session_terminate_session(h->session, NGHTTP2_PROTOCOL_ERROR); return -1; }
    return (long)r;
}

long ms_h2_output(MsH2 *h, void *buf, size_t cap) {
    size_t used = 0;
    for (;;) {
        if (!h->pend_len) {
            ssize_t n = nghttp2_session_mem_send(h->session, &h->pend);
            if (n <= 0) break;
            h->pend_len = (size_t)n;
        }
        size_t take = h->pend_len < cap - used ? h->pend_len : cap - used;
        memcpy((char *)buf + used, h->pend, take);
        used += take; h->pend += take; h->pend_len -= take;
        if (h->pend_len) break; /* buffer full: the rest comes first on the next call */
    }
    return (long)used;
}

int ms_h2_alive(MsH2 *h) {
    return h->pend_len || (!h->failed && (nghttp2_session_want_read(h->session) || nghttp2_session_want_write(h->session)));
}

int ms_h2_pending(MsH2 *h) { return h->pend_len || nghttp2_session_want_write(h->session); }

uint32_t ms_h2_max_requests(MsH2 *h) {
    if (!nghttp2_session_check_request_allowed(h->session)) return 0;
    return nghttp2_session_get_remote_settings(h->session, NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS);
}

int ms_h2_next(MsH2 *h, MsH2Event *ev) {
    if (h->next == h->nevents) {
        h->nevents = h->next = h->arena_len = h->nfields = 0;
        return 0;
    }
    *ev = h->events[h->next++];
    if (ev->type == MS_H2_HEADERS) {
        ev->fields = h->fields + ev->error_code;
        ev->error_code = 0;
    }
    return 1;
}

const char *ms_h2_arena(const MsH2 *h) { return h->arena; }

/* nghttp2_nv declares its text mutable but only reads it (a header table copy is made on the way in), so the
 * one place that drops const is here. */
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-qual"
#endif
static uint8_t *nghttp2_text(const char *text) { return (uint8_t *)text; }
#ifdef __clang__
#pragma clang diagnostic pop
#endif

static nghttp2_nv *convert(const MsH2Nv *nv, size_t n) {
    nghttp2_nv *out = malloc((n ? n : 1) * sizeof *out);
    if (!out) return NULL;
    for (size_t i = 0; i < n; i++)
        out[i] = (nghttp2_nv){nghttp2_text(nv[i].name), nghttp2_text(nv[i].value), nv[i].name_len, nv[i].value_len, NGHTTP2_NV_FLAG_NONE};
    return out;
}

/* A body for a stream about to open. The stream owns it once nghttp2 has it; until then a failure drops it. */
static MsH2Body *body_new(MsH2 *h) {
    MsH2Body *b = calloc(1, sizeof *b);
    if (b == NULL) return NULL;
    b->next = h->bodies;
    if (h->bodies) h->bodies->prev = b;
    h->bodies = b;
    return b;
}

/* Appends to the queue, ignoring the hold limit. Returns 0 or -1 on allocation failure or size overflow. */
static int body_append(MsH2Body *b, const void *data, size_t n) {
    if (b->off == b->len) b->off = b->len = 0;
    size_t need;
    if (n == 0) return 0;
    if (!ms_size_add(b->len, n, &need)) return -1;
    if (need > b->cap) {
        size_t cap = b->cap ? b->cap : 4096;
        while (cap < need) {
            if (!ms_size_mul(cap, 2, &cap)) return -1;
        }
        uint8_t *grown = realloc(b->data, cap);
        if (grown == NULL) return -1;
        b->data = grown; b->cap = cap;
    }
    memcpy(b->data + b->len, data, n);
    b->len = need;
    return 0;
}

/* The body of a stream. A client stream exists inside nghttp2 only once its head went out, so a stream whose head
   is still queued is found by scanning the bodies (at most one per open stream). */
static MsH2Body *body_of(MsH2 *h, int32_t stream) {
    MsH2Body *b = nghttp2_session_get_stream_user_data(h->session, stream);
    for (b = b ? b : h->bodies; b != NULL && b->stream != stream; b = b->next) {}
    return b;
}

static void body_resume(MsH2 *h, int32_t stream) {
    (void)nghttp2_session_resume_data(h->session, stream); /* only fails for a stream that is already gone */
}

int32_t ms_h2_open(MsH2 *h, const MsH2Nv *nv, size_t nnv, int has_body) {
    nghttp2_nv *v = convert(nv, nnv);
    MsH2Body *b = has_body ? body_new(h) : NULL;
    if (!v || (has_body && !b)) { free(v); return -1; }
    nghttp2_data_provider prov = {{.ptr = b}, read_body};
    int32_t id = nghttp2_submit_request(h->session, NULL, v, nnv, b ? &prov : NULL, b);
    free(v);
    if (id < 0 && b) drop(h, b);
    if (id >= 0 && b) b->stream = id;
    return id;
}

int ms_h2_respond(MsH2 *h, int32_t stream, const MsH2Nv *nv, size_t nnv, int has_body) {
    nghttp2_nv *v = convert(nv, nnv);
    MsH2Body *b = has_body ? body_new(h) : NULL;
    if (!v || (has_body && !b)) { free(v); return -1; }
    if (b) { b->stream = stream; nghttp2_session_set_stream_user_data(h->session, stream, b); }
    nghttp2_data_provider prov = {{.ptr = b}, read_body};
    int rc = nghttp2_submit_response(h->session, stream, v, nnv, b ? &prov : NULL);
    free(v);
    if (rc && b) { nghttp2_session_set_stream_user_data(h->session, stream, NULL); drop(h, b); }
    return rc ? -1 : 0;
}

long ms_h2_send(MsH2 *h, int32_t stream, const void *data, size_t n, int end) {
    MsH2Body *b = body_of(h, stream);
    if (b == NULL || b->ended) return -1;
    size_t queued = b->len - b->off;
    size_t room = queued < MS_H2_SEND_HOLD ? MS_H2_SEND_HOLD - queued : 0;
    size_t take = n < room ? n : room;
    if (body_append(b, data, take)) return -1;
    if (take < n) b->blocked = 1;
    else if (end) b->ended = 1;
    body_resume(h, stream);
    return (long)take;
}

int ms_h2_trailers(MsH2 *h, int32_t stream, const MsH2Nv *nv, size_t nnv) {
    MsH2Body *b = body_of(h, stream);
    if (b == NULL || b->ended || nnv == 0) return -1;
    size_t text = 0;
    for (size_t i = 0; i < nnv; i++) {
        if (!ms_size_add(text, nv[i].name_len, &text) || !ms_size_add(text, nv[i].value_len, &text)) return -1;
    }
    nghttp2_nv *copies = malloc(nnv * sizeof *copies);
    char *bytes = malloc(text ? text : 1);
    if (copies == NULL || bytes == NULL) { free(copies); free(bytes); return -1; }
    char *at = bytes;
    for (size_t i = 0; i < nnv; i++) {
        memcpy(at, nv[i].name, nv[i].name_len);
        uint8_t *name = (uint8_t *)at;
        at += nv[i].name_len;
        memcpy(at, nv[i].value, nv[i].value_len);
        copies[i] = (nghttp2_nv){name, (uint8_t *)at, nv[i].name_len, nv[i].value_len, NGHTTP2_NV_FLAG_NONE};
        at += nv[i].value_len;
    }
    b->trailers = copies; b->trailer_text = bytes; b->ntrailers = nnv; b->ended = 1;
    body_resume(h, stream);
    return 0;
}

int ms_h2_consume(MsH2 *h, int32_t stream, size_t n) {
    return nghttp2_session_consume(h->session, stream, n) ? -1 : 0;
}

int32_t ms_h2_submit_request(MsH2 *h, const MsH2Nv *nv, size_t nnv, const void *body, size_t body_len) {
    int32_t id = ms_h2_open(h, nv, nnv, body_len > 0);
    if (id < 0 || body_len == 0) return id;
    MsH2Body *b = body_of(h, id);
    if (b == NULL || body_append(b, body, body_len)) {
        (void)ms_h2_reset(h, id, NGHTTP2_INTERNAL_ERROR);
        return -1;
    }
    b->ended = 1;
    body_resume(h, id);
    return id;
}

int ms_h2_submit_response(MsH2 *h, int32_t stream, const MsH2Nv *nv, size_t nnv, const void *body, size_t body_len) {
    if (ms_h2_respond(h, stream, nv, nnv, body_len > 0)) return -1;
    if (body_len == 0) return 0;
    MsH2Body *b = body_of(h, stream);
    if (b == NULL || body_append(b, body, body_len)) {
        (void)ms_h2_reset(h, stream, NGHTTP2_INTERNAL_ERROR);
        return -1;
    }
    b->ended = 1;
    body_resume(h, stream);
    return 0;
}

int ms_h2_reset(MsH2 *h, int32_t stream, uint32_t code) { return nghttp2_submit_rst_stream(h->session, NGHTTP2_FLAG_NONE, stream, code) ? -1 : 0; }

int ms_h2_goaway(MsH2 *h, uint32_t code) {
    return nghttp2_submit_goaway(h->session, NGHTTP2_FLAG_NONE, nghttp2_session_get_last_proc_stream_id(h->session), code, NULL, 0) ? -1 : 0;
}
