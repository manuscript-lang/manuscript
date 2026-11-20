/* The stream table over runtime/net/h2.c. Streams live in a flat array of records found by stream id through an
   open-addressed index of slot numbers (linear probing, backward-shift deletion). A record owns its head block, its
   trailer block and its queued body bytes. */
#include "h2conn.h"
#include <stdlib.h>
#include <string.h>

enum { DEFAULT_STREAMS = 100 };

enum { F_QUEUED_READ = 1, F_RELEASED = 2, F_LOCAL_END = 4 /* everything we send is queued */ };

/* The memory behind a head: its regular fields and the bytes every name and value points into. */
typedef struct { MsH2Header *fields; uint8_t *text; } MsH2Block; /* owned, both */

typedef struct {
    int32_t id;          /* 0: free slot */
    uint32_t next_free;  /* while free: the next free slot + 1, 0 ends the list */
    unsigned state;      /* MS_H2S_* */
    unsigned flags;      /* F_* */
    uint32_t reset_code;
    uint64_t user[2];        /* the handler's word and the gone watcher's word */
    MsH2Head head, trailers;
    MsH2Block head_block, trailer_block;
    uint8_t *body;           /* owned: queued bytes body[off..len) */
    size_t body_off, body_len, body_cap;
} MsH2Stream;

struct MsH2Conn {
    MsH2 *wire;                 /* owned */
    int server;
    uint32_t cap;               /* stream records */
    MsH2Stream *streams;        /* owned, cap entries */
    uint32_t *index;            /* owned: slot + 1 per hash cell, 0 empty; index_mask + 1 cells */
    uint32_t index_mask;
    uint32_t free_slot;         /* first free slot + 1, 0: none */
    uint32_t open;              /* streams not closed on the wire */
    int going_away;
    MsH2ConnEvent *events;      /* owned: events[next..count) are waiting */
    size_t event_count, event_cap, event_next;
};

/* ---- index ---- */

static uint32_t cell_of(const MsH2Conn *c, int32_t id) { return ((uint32_t)id * 2654435761u >> 7) & c->index_mask; }

static MsH2Stream *find(const MsH2Conn *c, int32_t id) {
    if (id <= 0) return NULL;
    for (uint32_t cell = cell_of(c, id); c->index[cell] != 0; cell = (cell + 1) & c->index_mask) {
        MsH2Stream *s = &c->streams[c->index[cell] - 1];
        if (s->id == id) return s;
    }
    return NULL;
}

static void index_remove(MsH2Conn *c, int32_t id) {
    uint32_t hole = cell_of(c, id);
    while (c->streams[c->index[hole] - 1].id != id) hole = (hole + 1) & c->index_mask;
    for (uint32_t cell = (hole + 1) & c->index_mask; c->index[cell] != 0; cell = (cell + 1) & c->index_mask) {
        uint32_t home = cell_of(c, c->streams[c->index[cell] - 1].id);
        bool movable = hole <= cell ? (home <= hole || home > cell) : (home <= hole && home > cell);
        if (!movable) continue;
        c->index[hole] = c->index[cell];
        hole = cell;
    }
    c->index[hole] = 0;
}

static void block_free(MsH2Block *block) {
    free(block->fields); free(block->text);
    *block = (MsH2Block){0};
}

/* A fresh record for `id`, or NULL when the table is full. */
static MsH2Stream *stream_add(MsH2Conn *c, int32_t id) {
    if (c->free_slot == 0) return NULL;
    uint32_t slot = c->free_slot - 1;
    MsH2Stream *s = &c->streams[slot];
    c->free_slot = s->next_free;
    *s = (MsH2Stream){.id = id};
    uint32_t cell = cell_of(c, id);
    while (c->index[cell] != 0) cell = (cell + 1) & c->index_mask;
    c->index[cell] = slot + 1;
    c->open++;
    return s;
}

static void stream_free(MsH2Conn *c, MsH2Stream *s) {
    index_remove(c, s->id);
    block_free(&s->head_block); block_free(&s->trailer_block); free(s->body);
    uint32_t slot = (uint32_t)(s - c->streams);
    *s = (MsH2Stream){.next_free = c->free_slot};
    c->free_slot = slot + 1;
}

/* ---- events ---- */

static bool push_event(MsH2Conn *c, int type, int32_t stream, uint32_t code) {
    if (c->event_next == c->event_count) c->event_next = c->event_count = 0;
    if (c->event_count == c->event_cap) {
        size_t cap = c->event_cap ? c->event_cap * 2 : 16;
        MsH2ConnEvent *grown = realloc(c->events, cap * sizeof *grown);
        if (grown == NULL) return false;
        c->events = grown; c->event_cap = cap;
    }
    c->events[c->event_count++] = (MsH2ConnEvent){type, stream, code};
    return true;
}

static void wake_reader(MsH2Conn *c, MsH2Stream *s) {
    if (s->flags & F_QUEUED_READ) return;
    if (push_event(c, MS_H2C_READABLE, s->id, 0)) s->flags |= F_QUEUED_READ;
}

static void drain(MsH2Conn *c);

int ms_h2conn_next(MsH2Conn *c, MsH2ConnEvent *event) {
    drain(c);
    if (c->event_next == c->event_count) return 0;
    *event = c->events[c->event_next++];
    if (event->type == MS_H2C_READABLE) {
        MsH2Stream *s = find(c, event->stream);
        if (s != NULL) s->flags &= ~(unsigned)F_QUEUED_READ;
    }
    return 1;
}

/* ---- heads ---- */

static uint32_t status_of(MsBytes value) {
    uint32_t status = 0;
    if (value.len != 3) return 0;
    for (size_t i = 0; i < value.len; i++) {
        if (value.ptr[i] < '0' || value.ptr[i] > '9') return 0;
        status = status * 10 + (uint32_t)(value.ptr[i] - '0');
    }
    return status;
}

static bool is_name(MsBytes name, const char *text) { return name.len == strlen(text) && memcmp(name.ptr, text, name.len) == 0; }

/* Stores a pseudo-header value in its place in the head; unknown pseudo-headers cannot arrive (nghttp2 rejects them). */
static void pseudo_set(MsH2Head *head, MsBytes name, MsBytes value) {
    if (is_name(name, ":status")) head->status = status_of(value);
    else if (is_name(name, ":method")) head->method = value;
    else if (is_name(name, ":scheme")) head->scheme = value;
    else if (is_name(name, ":authority")) head->authority = value;
    else if (is_name(name, ":path")) head->path = value;
}

/* Copies a header block out of the connection's event arena. Returns false when out of memory. */
static bool head_copy(const MsH2 *wire, const MsH2Event *e, MsH2Head *head, MsH2Block *block) {
    size_t regular = 0, text = 0;
    const char *arena = ms_h2_arena(wire);
    for (uint32_t i = 0; i < e->nfields; i++) {
        text += (size_t)e->fields[i].name.len + e->fields[i].value.len;
        regular += arena[e->fields[i].name.off] != ':';
    }
    block->fields = calloc(regular ? regular : 1, sizeof *block->fields);
    block->text = malloc(text ? text : 1);
    if (block->fields == NULL || block->text == NULL) { block_free(block); return false; }
    uint8_t *at = block->text;
    *head = (MsH2Head){.fields = block->fields};
    for (uint32_t i = 0; i < e->nfields; i++) {
        const MsH2Field *f = &e->fields[i];
        memcpy(at, arena + f->name.off, f->name.len);
        MsBytes name = ms_bytes_of(at, f->name.len);
        at += f->name.len;
        memcpy(at, arena + f->value.off, f->value.len);
        MsBytes value = ms_bytes_of(at, f->value.len);
        at += f->value.len;
        if (name.len > 0 && name.ptr[0] == ':') pseudo_set(head, name, value);
        else block->fields[head->nfields++] = (MsH2Header){name, value};
    }
    return true;
}

/* The first block of a stream is its head, later ones trailers. Interim (1xx) responses are dropped. */
static void on_headers(MsH2Conn *c, const MsH2Event *e) {
    MsH2Stream *s = find(c, e->stream);
    if (s == NULL && c->server) s = stream_add(c, e->stream);
    if (s == NULL) {
        if (c->server) (void)ms_h2_reset(c->wire, e->stream, 7 /* REFUSED_STREAM */);
        return;
    }
    if (!(s->state & MS_H2S_HEAD)) {
        if (!head_copy(c->wire, e, &s->head, &s->head_block)) {
            (void)ms_h2_reset(c->wire, e->stream, 2 /* INTERNAL_ERROR */);
            return;
        }
        if (!c->server && s->head.status >= 100 && s->head.status < 200) { block_free(&s->head_block); s->head = (MsH2Head){0}; return; }
        s->state |= MS_H2S_HEAD;
        (void)push_event(c, MS_H2C_HEAD, s->id, 0);
    } else if (!(s->state & MS_H2S_TRAILERS)) {
        if (head_copy(c->wire, e, &s->trailers, &s->trailer_block)) s->state |= MS_H2S_TRAILERS;
    }
    if (e->end_stream) s->state |= MS_H2S_ENDED;
    wake_reader(c, s);
}

/* ---- body ---- */

static bool body_put(MsH2Stream *s, const void *data, size_t n) {
    if (s->body_off == s->body_len) s->body_off = s->body_len = 0;
    size_t need;
    if (!ms_size_add(s->body_len, n, &need)) return false;
    if (need > s->body_cap) {
        size_t cap = s->body_cap ? s->body_cap : 4096;
        while (cap < need) {
            if (!ms_size_mul(cap, 2, &cap)) return false;
        }
        uint8_t *grown = realloc(s->body, cap);
        if (grown == NULL) return false;
        s->body = grown; s->body_cap = cap;
    }
    memcpy(s->body + s->body_len, data, n);
    s->body_len = need;
    return true;
}

static void on_data(MsH2Conn *c, const MsH2Event *e) {
    MsH2Stream *s = find(c, e->stream);
    if (s == NULL || (s->flags & F_RELEASED)) {
        if (e->data.len) (void)ms_h2_consume(c->wire, e->stream, e->data.len); /* nobody will read these */
        return;
    }
    if (e->data.len && !body_put(s, ms_h2_arena(c->wire) + e->data.off, e->data.len)) {
        (void)ms_h2_reset(c->wire, e->stream, 2 /* INTERNAL_ERROR */);
        return;
    }
    if (e->end_stream) s->state |= MS_H2S_ENDED;
    wake_reader(c, s);
}

long ms_h2conn_read(MsH2Conn *c, int32_t stream, void *buf, size_t cap) {
    MsH2Stream *s = find(c, stream);
    if (s == NULL) return -1;
    size_t queued = s->body_len - s->body_off;
    size_t n = queued < cap ? queued : cap;
    if (n == 0) return 0;
    memcpy(buf, s->body + s->body_off, n);
    s->body_off += n;
    (void)ms_h2_consume(c->wire, stream, n);
    return (long)n;
}

/* ---- wire events ---- */

static void on_closed(MsH2Conn *c, const MsH2Event *e) {
    MsH2Stream *s = find(c, e->stream);
    if (s == NULL) return;
    if (c->open > 0) c->open--;
    s->state |= MS_H2S_CLOSED;
    if (e->error_code != 0 && !(s->state & MS_H2S_RESET)) {
        s->state |= MS_H2S_RESET;
        s->reset_code = e->error_code;
        (void)push_event(c, MS_H2C_RESET, s->id, e->error_code);
    }
    if (s->flags & F_RELEASED) stream_free(c, s);
}

static void on_reset(MsH2Conn *c, const MsH2Event *e) {
    MsH2Stream *s = find(c, e->stream);
    if (s == NULL) return;
    s->state |= MS_H2S_RESET;
    s->reset_code = e->error_code;
    (void)push_event(c, MS_H2C_RESET, s->id, e->error_code);
}

static void drain(MsH2Conn *c) {
    MsH2Event e;
    while (ms_h2_next(c->wire, &e)) {
        switch (e.type) {
        case MS_H2_HEADERS: on_headers(c, &e); break;
        case MS_H2_DATA: on_data(c, &e); break;
        case MS_H2_RESET: on_reset(c, &e); break;
        case MS_H2_CLOSED: on_closed(c, &e); break;
        case MS_H2_GOAWAY:
            c->going_away = 1;
            (void)push_event(c, MS_H2C_GOAWAY, e.stream, e.error_code);
            break;
        case MS_H2_WRITABLE:
            if (find(c, e.stream) != NULL) (void)push_event(c, MS_H2C_WRITABLE, e.stream, 0);
            break;
        default: break;
        }
    }
}

long ms_h2conn_input(MsH2Conn *c, const void *buf, size_t n) {
    long used = ms_h2_input(c->wire, buf, n);
    drain(c);
    return used;
}

/* Sending is when nghttp2 finishes streams, so the events it raises are folded in here as well as after input. */
long ms_h2conn_output(MsH2Conn *c, void *buf, size_t cap) {
    long n = ms_h2_output(c->wire, buf, cap);
    drain(c);
    return n;
}
int ms_h2conn_pending(MsH2Conn *c) { return ms_h2_pending(c->wire); }
int ms_h2conn_alive(MsH2Conn *c) { return ms_h2_alive(c->wire); }
int ms_h2conn_idle(MsH2Conn *c) { return c->open == 0 && !ms_h2_pending(c->wire); }
uint32_t ms_h2conn_open_streams(const MsH2Conn *c) { return c->open; }

int ms_h2conn_usable(MsH2Conn *c) {
    if (c->going_away) return 0;
    if (c->server) return 1;
    return c->free_slot != 0 && c->open < ms_h2_max_requests(c->wire);
}

/* ---- lifetime ---- */

MsH2Conn *ms_h2conn_new(int server, const MsH2Limits *limits) {
    MsH2Limits wire_limits = limits != NULL ? *limits : (MsH2Limits){0};
    if (wire_limits.max_concurrent_streams == 0) wire_limits.max_concurrent_streams = DEFAULT_STREAMS;
    MsH2Conn *c = calloc(1, sizeof *c);
    if (c == NULL) return NULL;
    c->server = server;
    c->cap = wire_limits.max_concurrent_streams;
    uint32_t cells = 16;
    while (cells < c->cap * 2) cells *= 2;
    c->index_mask = cells - 1;
    c->streams = calloc(c->cap, sizeof *c->streams);
    c->index = calloc(cells, sizeof *c->index);
    c->wire = ms_h2_new(server, &wire_limits);
    if (c->streams == NULL || c->index == NULL || c->wire == NULL) { ms_h2conn_free(c); return NULL; }
    for (uint32_t i = 0; i < c->cap; i++) c->streams[i].next_free = i + 1 < c->cap ? i + 2 : 0;
    c->free_slot = 1;
    return c;
}

void ms_h2conn_free(MsH2Conn *c) {
    if (c == NULL) return;
    for (uint32_t i = 0; i < c->cap && c->streams != NULL; i++) {
        block_free(&c->streams[i].head_block); block_free(&c->streams[i].trailer_block); free(c->streams[i].body);
    }
    ms_h2_free(c->wire);
    free(c->streams); free(c->index); free(c->events);
    free(c);
}

/* ---- streams ---- */

const MsH2Head *ms_h2conn_head(const MsH2Conn *c, int32_t stream) {
    const MsH2Stream *s = find(c, stream);
    return s != NULL && (s->state & MS_H2S_HEAD) ? &s->head : NULL;
}

const MsH2Head *ms_h2conn_trailers(const MsH2Conn *c, int32_t stream) {
    const MsH2Stream *s = find(c, stream);
    return s != NULL && (s->state & MS_H2S_TRAILERS) ? &s->trailers : NULL;
}

unsigned ms_h2conn_state(const MsH2Conn *c, int32_t stream) {
    const MsH2Stream *s = find(c, stream);
    return s != NULL ? s->state : 0;
}

uint32_t ms_h2conn_reset_code(const MsH2Conn *c, int32_t stream) {
    const MsH2Stream *s = find(c, stream);
    return s != NULL ? s->reset_code : 0;
}

void ms_h2conn_for_each(MsH2Conn *c, void (*fn)(void *context, int32_t stream, const uint64_t *user), void *context) {
    for (uint32_t i = 0; i < c->cap; i++) {
        if (c->streams[i].id != 0) fn(context, c->streams[i].id, c->streams[i].user);
    }
}

uint64_t *ms_h2conn_user(MsH2Conn *c, int32_t stream) {
    MsH2Stream *s = find(c, stream);
    return s != NULL ? &s->user[0] : NULL;
}

uint64_t *ms_h2conn_watch(MsH2Conn *c, int32_t stream) {
    MsH2Stream *s = find(c, stream);
    return s != NULL ? &s->user[1] : NULL;
}

int32_t ms_h2conn_open(MsH2Conn *c, const MsH2Nv *nv, size_t nnv, int has_body) {
    if (!ms_h2conn_usable(c)) return -1;
    int32_t id = ms_h2_open(c->wire, nv, nnv, has_body);
    if (id < 0) return -1;
    MsH2Stream *s = stream_add(c, id);
    if (s == NULL) { (void)ms_h2_reset(c->wire, id, 2 /* INTERNAL_ERROR */); return -1; }
    if (!has_body) s->flags |= F_LOCAL_END;
    return id;
}

int ms_h2conn_respond(MsH2Conn *c, int32_t stream, const MsH2Nv *nv, size_t nnv, int has_body) {
    MsH2Stream *s = find(c, stream);
    if (s == NULL || ms_h2_respond(c->wire, stream, nv, nnv, has_body)) return -1;
    if (!has_body) s->flags |= F_LOCAL_END;
    return 0;
}

long ms_h2conn_send(MsH2Conn *c, int32_t stream, const void *data, size_t n, int end) {
    MsH2Stream *s = find(c, stream);
    if (s == NULL) return -1;
    long took = ms_h2_send(c->wire, stream, data, n, end);
    if (took >= 0 && end && (size_t)took == n) s->flags |= F_LOCAL_END;
    return took;
}

int ms_h2conn_trailers_send(MsH2Conn *c, int32_t stream, const MsH2Nv *nv, size_t nnv) {
    MsH2Stream *s = find(c, stream);
    if (s == NULL || ms_h2_trailers(c->wire, stream, nv, nnv)) return -1;
    s->flags |= F_LOCAL_END;
    return 0;
}

int ms_h2conn_reset(MsH2Conn *c, int32_t stream, uint32_t code) {
    return find(c, stream) == NULL ? -1 : ms_h2_reset(c->wire, stream, code);
}

int ms_h2conn_goaway(MsH2Conn *c, uint32_t code) {
    c->going_away = 1;
    return ms_h2_goaway(c->wire, code);
}

void ms_h2conn_release(MsH2Conn *c, int32_t stream, uint32_t code) {
    MsH2Stream *s = find(c, stream);
    if (s == NULL || (s->flags & F_RELEASED)) return;
    size_t unread = s->body_len - s->body_off;
    if (unread > 0) (void)ms_h2_consume(c->wire, stream, unread);
    s->body_off = s->body_len = 0;
    s->flags |= F_RELEASED;
    if (s->state & MS_H2S_CLOSED) { stream_free(c, s); return; }
    if (!(s->state & MS_H2S_ENDED) || !(s->flags & F_LOCAL_END)) (void)ms_h2_reset(c->wire, stream, code);
}
