#include "conn.h"
#include <stdlib.h>
#include <string.h>

struct ms_conn_table {
    ms_conn *rows;
    uint32_t cap, next_free, live; /* next_free == cap: none left */
    uint32_t used;                 /* rows ever handed out; rows past it are untouched */
};

ms_conn_table *ms_conn_table_new(uint32_t cap) {
    if (cap == 0 || cap == UINT32_MAX) return NULL;
    ms_conn_table *t = calloc(1, sizeof *t);
    if (!t) return NULL;
    t->rows = calloc(cap, sizeof *t->rows);
    if (!t->rows) { free(t); return NULL; }
    t->cap = cap; t->next_free = cap;
    return t;
}

static void release(ms_conn *c) {
    free(c->stash); free(c->wpend);
    c->stash = c->wpend = NULL;
    c->stash_len = c->wlen = c->wcap = 0;
}

void ms_conn_table_free(ms_conn_table *t) {
    if (!t) return;
    for (uint32_t i = 0; i < t->used; i++) release(&t->rows[i]);
    free(t->rows);
    free(t);
}

ms_conn_id ms_conn_open(ms_conn_table *t, int fd, uint8_t proto) {
    uint32_t i;
    if (t->next_free != t->cap) { i = t->next_free; t->next_free = t->rows[i].timer; }
    else if (t->used < t->cap) i = t->used++;
    else return 0;
    ms_conn *c = &t->rows[i];
    uint32_t gen = c->gen ? c->gen : 1;
    memset(c, 0, sizeof *c);
    c->gen = gen; c->fd = fd; c->proto = proto;
    t->live++;
    return (uint64_t)gen << 32 | i;
}

ms_conn *ms_conn_get(ms_conn_table *t, ms_conn_id id) {
    uint32_t i = (uint32_t)id, gen = (uint32_t)(id >> 32);
    if (i >= t->used || gen == 0) return NULL;
    ms_conn *c = &t->rows[i];
    return c->gen == gen && c->proto != MS_CONN_NONE ? c : NULL;
}

int ms_conn_close(ms_conn_table *t, ms_conn_id id) {
    ms_conn *c = ms_conn_get(t, id);
    if (!c) return -1;
    release(c);
    uint32_t i = (uint32_t)(c - t->rows), gen = c->gen + 1;
    memset(c, 0, sizeof *c);
    c->gen = gen ? gen : 1; /* never 0 */
    c->timer = t->next_free;
    t->next_free = i;
    t->live--;
    return 0;
}

uint32_t ms_conn_live(const ms_conn_table *t) { return t->live; }

/* Appends n bytes to the stash. */
static int stash_add(ms_conn *c, const uint8_t *buf, size_t n) {
    if (n > UINT32_MAX - c->stash_len) return -1;
    uint8_t *p = realloc(c->stash, c->stash_len + n);
    if (!p) return -1;
    memcpy(p + c->stash_len, buf, n);
    c->stash = p; c->stash_len += (uint32_t)n;
    return 0;
}

int ms_conn_h1_feed(ms_conn *c, const uint8_t *buf, size_t n, size_t head_limit, ms_h1_field *fields, uint32_t cap,
                    ms_h1_request *req, const uint8_t **base, size_t *avail) {
    const uint8_t *data = buf;
    size_t len = n;
    req->fields = fields;
    if (c->stash_len) { /* earlier bytes first: join, then parse from the stash */
        if (n && stash_add(c, buf, n)) { req->status = 500; return MS_CONN_BAD; }
        data = c->stash; len = c->stash_len;
    }
    if (len == 0) return MS_CONN_NEED_MORE;
    int r = ms_h1_parse_request((const char *)data, len, head_limit, req, cap);
    if (r == MS_H1_BAD) return MS_CONN_BAD;
    if (r == MS_H1_PARTIAL) {
        if (data == buf && stash_add(c, buf, n)) { req->status = 500; return MS_CONN_BAD; }
        return MS_CONN_NEED_MORE;
    }
    *base = data; *avail = len;
    return MS_CONN_REQUEST;
}

size_t ms_conn_request_done(ms_conn *c, const uint8_t *base, size_t avail, size_t consumed) {
    size_t left = consumed < avail ? avail - consumed : 0;
    if (base == c->stash) {
        if (left) memmove(c->stash, c->stash + consumed, left);
        c->stash_len = (uint32_t)left;
        if (!left) { free(c->stash); c->stash = NULL; }
        return left;
    }
    if (left) {
        c->stash = malloc(left);
        if (!c->stash) return 0;
        memcpy(c->stash, base + consumed, left);
        c->stash_len = (uint32_t)left;
    }
    return left;
}
