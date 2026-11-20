#include "h2.h"
#include <nghttp2/nghttp2.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint8_t *data; size_t len, off; } body;

struct ms_h2 {
    nghttp2_session *session;
    char *arena; size_t arena_len, arena_cap;
    ms_h2_field *fields; size_t nfields, fields_cap;
    ms_h2_event *events; size_t nevents, events_cap, next;
    size_t block_first;  /* first field of the header block being received */
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

static int put(ms_h2 *h, const void *s, size_t n, ms_h2_span *span) {
    if (n > UINT32_MAX || h->arena_len + n > UINT32_MAX) return -1;
    if (grow((void **)&h->arena, &h->arena_cap, h->arena_len + n, 1)) return -1;
    memcpy(h->arena + h->arena_len, s, n);
    span->off = (uint32_t)h->arena_len; span->len = (uint32_t)n;
    h->arena_len += n;
    return 0;
}

static ms_h2_event *push(ms_h2 *h, int type, int32_t stream) {
    if (grow((void **)&h->events, &h->events_cap, h->nevents + 1, sizeof *h->events)) return NULL;
    ms_h2_event *e = &h->events[h->nevents++];
    memset(e, 0, sizeof *e);
    e->type = type; e->stream = stream;
    return e;
}

static int on_begin_headers(nghttp2_session *s, const nghttp2_frame *f, void *u) {
    (void)s; (void)f;
    ms_h2 *h = u;
    h->block_first = h->nfields;
    return 0;
}

static int on_header(nghttp2_session *s, const nghttp2_frame *f, const uint8_t *name, size_t nl, const uint8_t *value,
                     size_t vl, uint8_t flags, void *u) {
    (void)s; (void)f; (void)flags;
    ms_h2 *h = u;
    if (grow((void **)&h->fields, &h->fields_cap, h->nfields + 1, sizeof *h->fields)) return NGHTTP2_ERR_CALLBACK_FAILURE;
    ms_h2_field *fl = &h->fields[h->nfields];
    if (put(h, name, nl, &fl->name) || put(h, value, vl, &fl->value)) return NGHTTP2_ERR_CALLBACK_FAILURE;
    h->nfields++;
    return 0;
}

static int on_frame_recv(nghttp2_session *s, const nghttp2_frame *f, void *u) {
    (void)s;
    ms_h2 *h = u;
    ms_h2_event *e;
    switch (f->hd.type) {
    case NGHTTP2_HEADERS:
        if (!(e = push(h, MS_H2_HEADERS, f->hd.stream_id))) return NGHTTP2_ERR_CALLBACK_FAILURE;
        e->end_stream = (f->hd.flags & NGHTTP2_FLAG_END_STREAM) != 0;
        e->nfields = (uint32_t)(h->nfields - h->block_first);
        e->error_code = (uint32_t)h->block_first; /* patched to a pointer in ms_h2_next: the array may move */
        break;
    case NGHTTP2_DATA:
        if (f->hd.flags & NGHTTP2_FLAG_END_STREAM) {
            if (!(e = push(h, MS_H2_DATA, f->hd.stream_id))) return NGHTTP2_ERR_CALLBACK_FAILURE;
            e->end_stream = 1; /* empty final chunk, so the reader sees the end */
        }
        break;
    case NGHTTP2_RST_STREAM:
        if (!(e = push(h, MS_H2_RESET, f->hd.stream_id))) return NGHTTP2_ERR_CALLBACK_FAILURE;
        e->error_code = f->rst_stream.error_code;
        break;
    case NGHTTP2_GOAWAY:
        if (!(e = push(h, MS_H2_GOAWAY, f->goaway.last_stream_id))) return NGHTTP2_ERR_CALLBACK_FAILURE;
        e->error_code = f->goaway.error_code;
        break;
    default: break;
    }
    return 0;
}

static int on_data_chunk(nghttp2_session *s, uint8_t flags, int32_t stream, const uint8_t *data, size_t len, void *u) {
    (void)s; (void)flags;
    ms_h2 *h = u;
    ms_h2_event *e = push(h, MS_H2_DATA, stream);
    if (!e || put(h, data, len, &e->data)) return NGHTTP2_ERR_CALLBACK_FAILURE;
    return 0;
}

static int on_stream_close(nghttp2_session *s, int32_t stream, uint32_t code, void *u) {
    ms_h2 *h = u;
    body *b = nghttp2_session_get_stream_user_data(s, stream);
    if (b) { free(b->data); free(b); nghttp2_session_set_stream_user_data(s, stream, NULL); }
    ms_h2_event *e = push(h, MS_H2_CLOSED, stream);
    if (!e) return NGHTTP2_ERR_CALLBACK_FAILURE;
    e->error_code = code;
    return 0;
}

static ssize_t read_body(nghttp2_session *s, int32_t stream, uint8_t *buf, size_t len, uint32_t *flags,
                         nghttp2_data_source *src, void *u) {
    (void)s; (void)stream; (void)u;
    body *b = src->ptr;
    size_t n = b->len - b->off < len ? b->len - b->off : len;
    memcpy(buf, b->data + b->off, n);
    b->off += n;
    if (b->off == b->len) *flags |= NGHTTP2_DATA_FLAG_EOF;
    return (ssize_t)n;
}

ms_h2 *ms_h2_new(int server, const ms_h2_limits *limits) {
    ms_h2 *h = calloc(1, sizeof *h);
    if (!h) return NULL;
    nghttp2_session_callbacks *cb;
    if (nghttp2_session_callbacks_new(&cb)) { free(h); return NULL; }
    nghttp2_session_callbacks_set_on_begin_headers_callback(cb, on_begin_headers);
    nghttp2_session_callbacks_set_on_header_callback(cb, on_header);
    nghttp2_session_callbacks_set_on_frame_recv_callback(cb, on_frame_recv);
    nghttp2_session_callbacks_set_on_data_chunk_recv_callback(cb, on_data_chunk);
    nghttp2_session_callbacks_set_on_stream_close_callback(cb, on_stream_close);
    int rc = server ? nghttp2_session_server_new(&h->session, cb, h) : nghttp2_session_client_new(&h->session, cb, h);
    nghttp2_session_callbacks_del(cb);
    if (rc) { free(h); return NULL; }
    nghttp2_settings_entry iv[2];
    size_t n = 0;
    if (limits && limits->max_concurrent_streams) iv[n++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, limits->max_concurrent_streams};
    if (limits && limits->max_header_list_size) iv[n++] = (nghttp2_settings_entry){NGHTTP2_SETTINGS_MAX_HEADER_LIST_SIZE, limits->max_header_list_size};
    if (nghttp2_submit_settings(h->session, NGHTTP2_FLAG_NONE, iv, n)) { ms_h2_free(h); return NULL; }
    return h;
}

void ms_h2_free(ms_h2 *h) {
    if (!h) return;
    nghttp2_session_del(h->session); /* closes live streams, which frees their bodies through on_stream_close */
    free(h->arena); free(h->fields); free(h->events);
    free(h);
}

long ms_h2_input(ms_h2 *h, const void *buf, size_t n) {
    ssize_t r = nghttp2_session_mem_recv(h->session, buf, n);
    if (r < 0) { h->failed = 1; nghttp2_session_terminate_session(h->session, NGHTTP2_PROTOCOL_ERROR); return -1; }
    return (long)r;
}

long ms_h2_output(ms_h2 *h, void *buf, size_t cap) {
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

int ms_h2_alive(ms_h2 *h) {
    return h->pend_len || (!h->failed && (nghttp2_session_want_read(h->session) || nghttp2_session_want_write(h->session)));
}

int ms_h2_next(ms_h2 *h, ms_h2_event *ev) {
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

const char *ms_h2_arena(const ms_h2 *h) { return h->arena; }

static nghttp2_nv *convert(const ms_h2_nv *nv, size_t n) {
    nghttp2_nv *out = malloc((n ? n : 1) * sizeof *out);
    if (!out) return NULL;
    for (size_t i = 0; i < n; i++)
        out[i] = (nghttp2_nv){(uint8_t *)nv[i].name, (uint8_t *)nv[i].value, nv[i].name_len, nv[i].value_len, NGHTTP2_NV_FLAG_NONE};
    return out;
}

static body *make_body(const void *data, size_t len) {
    if (len == 0) return NULL;
    body *b = malloc(sizeof *b);
    if (!b) return NULL;
    b->data = malloc(len); b->len = len; b->off = 0;
    if (!b->data) { free(b); return NULL; }
    memcpy(b->data, data, len);
    return b;
}

int32_t ms_h2_submit_request(ms_h2 *h, const ms_h2_nv *nv, size_t nnv, const void *data, size_t len) {
    nghttp2_nv *v = convert(nv, nnv);
    body *b = make_body(data, len);
    if (!v || (len && !b)) { free(v); return -1; }
    nghttp2_data_provider prov = {{.ptr = b}, read_body};
    int32_t id = nghttp2_submit_request(h->session, NULL, v, nnv, b ? &prov : NULL, b);
    free(v);
    if (id < 0 && b) { free(b->data); free(b); }
    return id;
}

int ms_h2_submit_response(ms_h2 *h, int32_t stream, const ms_h2_nv *nv, size_t nnv, const void *data, size_t len) {
    nghttp2_nv *v = convert(nv, nnv);
    body *b = make_body(data, len);
    if (!v || (len && !b)) { free(v); return -1; }
    if (b) nghttp2_session_set_stream_user_data(h->session, stream, b);
    nghttp2_data_provider prov = {{.ptr = b}, read_body};
    int rc = nghttp2_submit_response(h->session, stream, v, nnv, b ? &prov : NULL);
    free(v);
    if (rc && b) { nghttp2_session_set_stream_user_data(h->session, stream, NULL); free(b->data); free(b); }
    return rc ? -1 : 0;
}

int ms_h2_reset(ms_h2 *h, int32_t stream, uint32_t code) { return nghttp2_submit_rst_stream(h->session, NGHTTP2_FLAG_NONE, stream, code) ? -1 : 0; }

int ms_h2_goaway(ms_h2 *h, uint32_t code) {
    return nghttp2_submit_goaway(h->session, NGHTTP2_FLAG_NONE, nghttp2_session_get_last_proc_stream_id(h->session), code, NULL, 0) ? -1 : 0;
}
