#include "http1.h"
#include <llhttp.h>
#include <string.h>

typedef struct {
    const char *base;
    ms_h1_request *out;
    uint32_t cap;
    uint8_t have_target, name_open, value_open, too_many;
} state;

static uint32_t at(const state *s, const char *p) { return (uint32_t)(p - s->base); }

static int on_url(llhttp_t *p, const char *c, size_t n) {
    state *s = p->data;
    if (!s->have_target) { s->out->target.off = at(s, c); s->out->target.len = (uint32_t)n; s->have_target = 1; }
    else s->out->target.len = at(s, c) + (uint32_t)n - s->out->target.off;
    return 0;
}

static int on_name(llhttp_t *p, const char *c, size_t n) {
    state *s = p->data;
    ms_h1_request *r = s->out;
    if (s->name_open) {
        ms_h1_field *f = &r->fields[r->nfields - 1];
        f->name.len = at(s, c) + (uint32_t)n - f->name.off;
        return 0;
    }
    if (r->nfields == s->cap) { s->too_many = 1; return HPE_USER; }
    ms_h1_field *f = &r->fields[r->nfields++];
    f->name.off = at(s, c); f->name.len = (uint32_t)n; f->value.off = at(s, c) + (uint32_t)n; f->value.len = 0;
    s->name_open = 1;
    return 0;
}

static int on_name_done(llhttp_t *p) { ((state *)p->data)->name_open = 0; return 0; }

static int on_value(llhttp_t *p, const char *c, size_t n) {
    state *s = p->data;
    ms_h1_field *f = &s->out->fields[s->out->nfields - 1];
    if (!s->value_open) { f->value.off = at(s, c); f->value.len = (uint32_t)n; s->value_open = 1; }
    else f->value.len = at(s, c) + (uint32_t)n - f->value.off;
    return 0;
}

static int on_value_done(llhttp_t *p) { ((state *)p->data)->value_open = 0; return 0; }
static int on_headers_done(llhttp_t *p) { (void)p; return HPE_PAUSED; }

int ms_h1_parse_request(const char *buf, size_t len, size_t head_limit, ms_h1_request *out, uint32_t field_cap) {
    ms_h1_field *fields = out->fields;
    memset(out, 0, sizeof *out);
    out->fields = fields;
    if (len > UINT32_MAX) { out->status = 431; return MS_H1_BAD; }
    state s = {buf, out, field_cap, 0, 0, 0, 0};
    llhttp_settings_t cb;
    llhttp_settings_init(&cb);
    cb.on_url = on_url;
    cb.on_header_field = on_name;
    cb.on_header_field_complete = on_name_done;
    cb.on_header_value = on_value;
    cb.on_header_value_complete = on_value_done;
    cb.on_headers_complete = on_headers_done;
    llhttp_t p;
    llhttp_init(&p, HTTP_REQUEST, &cb);
    p.data = &s;
    enum llhttp_errno e = llhttp_execute(&p, buf, len);
    if (e == HPE_PAUSED) {
        size_t used = (size_t)(llhttp_get_error_pos(&p) - buf);
        if (used > head_limit) { out->status = 431; return MS_H1_BAD; }
        out->head_len = (uint32_t)used;
        out->method = (uint8_t)p.method;
        out->minor = (uint8_t)p.http_minor;
        return MS_H1_COMPLETE;
    }
    if (e == HPE_OK) {
        if (len > head_limit) { out->status = 431; return MS_H1_BAD; }
        return MS_H1_PARTIAL;
    }
    out->status = s.too_many ? 431 : e == HPE_INVALID_METHOD ? 501 : 400;
    return MS_H1_BAD;
}
