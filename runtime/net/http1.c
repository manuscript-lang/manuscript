#include "http1.h"
#include <llhttp.h>
#include <stdbool.h>
#include <string.h>

typedef struct {
    const char *base;
    MsH1Request *out;
    uint32_t cap;
    uint8_t have_target, name_open, value_open, too_many;
} MsH1State;

static uint32_t at(const MsH1State *s, const char *p) { return (uint32_t)(p - s->base); }

static int on_url(llhttp_t *p, const char *c, size_t n) {
    MsH1State *s = p->data;
    if (!s->have_target) { s->out->target.off = at(s, c); s->out->target.len = (uint32_t)n; s->have_target = 1; }
    else s->out->target.len = at(s, c) + (uint32_t)n - s->out->target.off;
    return 0;
}

static int on_name(llhttp_t *p, const char *c, size_t n) {
    MsH1State *s = p->data;
    MsH1Request *r = s->out;
    if (s->name_open) {
        MsH1Field *f = &r->fields[r->nfields - 1];
        f->name.len = at(s, c) + (uint32_t)n - f->name.off;
        return 0;
    }
    if (r->nfields == s->cap) { s->too_many = 1; return HPE_USER; }
    MsH1Field *f = &r->fields[r->nfields++];
    f->name.off = at(s, c); f->name.len = (uint32_t)n; f->value.off = at(s, c) + (uint32_t)n; f->value.len = 0;
    s->name_open = 1;
    return 0;
}

static int on_name_done(llhttp_t *p) { ((MsH1State *)p->data)->name_open = 0; return 0; }

static int on_value(llhttp_t *p, const char *c, size_t n) {
    MsH1State *s = p->data;
    MsH1Field *f = &s->out->fields[s->out->nfields - 1];
    if (!s->value_open) { f->value.off = at(s, c); f->value.len = (uint32_t)n; s->value_open = 1; }
    else f->value.len = at(s, c) + (uint32_t)n - f->value.off;
    return 0;
}

static int on_value_done(llhttp_t *p) { ((MsH1State *)p->data)->value_open = 0; return 0; }
static int on_headers_done(llhttp_t *p) { (void)p; return HPE_PAUSED; }

/* The status to refuse with: too many fields, an unknown method, or any other malformed head. */
static uint16_t refusal_status(bool too_many, enum llhttp_errno error) {
    if (too_many) return 431;
    if (error == HPE_INVALID_METHOD) return 501;
    return 400;
}

int ms_h1_parse_request(const char *buf, size_t len, size_t head_limit, MsH1Request *out, uint32_t field_cap) {
    MsH1Field *fields = out->fields;
    memset(out, 0, sizeof *out);
    out->fields = fields;
    if (len > UINT32_MAX) { out->status = 431; return MS_H1_BAD; }
    MsH1State s = {buf, out, field_cap, 0, 0, 0, 0};
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
        out->method = p.method;
        out->minor = p.http_minor;
        return MS_H1_COMPLETE;
    }
    if (e == HPE_OK) {
        if (len > head_limit) { out->status = 431; return MS_H1_BAD; }
        return MS_H1_PARTIAL;
    }
    out->status = refusal_status(s.too_many, e);
    return MS_H1_BAD;
}

static int put(char *dst, size_t cap, size_t *used, const char *s, size_t n) {
    if (n > cap - *used) return -1;
    memcpy(dst + *used, s, n);
    *used += n;
    return 0;
}

static size_t decimal(char *out, unsigned v) {
    char t[10];
    size_t n = 0, i = 0;
    do { t[n++] = (char)('0' + v % 10); v /= 10; } while (v);
    while (n) out[i++] = t[--n];
    return i;
}

int ms_h1_write_status(char *dst, size_t cap, size_t *used, int minor, unsigned status, const char *reason, size_t reason_len) {
    if (status > 999 || reason_len > 1024) return -2;
    for (size_t i = 0; i < reason_len; i++) if (reason[i] == '\r' || reason[i] == '\n' || reason[i] == 0) return -2;
    char line[16 + 1024 + 2];
    size_t n = 0;
    memcpy(line, minor ? "HTTP/1.1 " : "HTTP/1.0 ", 9); /* NOLINT(bugprone-not-null-terminated-result): the status line is not a C string */
    n = 9;
    char d[10];
    size_t dn = decimal(d, status);
    for (size_t pad = dn; pad < 3; pad++) line[n++] = '0';
    memcpy(line + n, d, dn); n += dn;
    line[n++] = ' ';
    memcpy(line + n, reason, reason_len); n += reason_len;
    line[n++] = '\r'; line[n++] = '\n';
    return put(dst, cap, used, line, n);
}

static int is_token(unsigned char c) {
    if (c >= '0' && c <= '9') return 1;
    if ((c | 32) >= 'a' && (c | 32) <= 'z') return 1;
    return c && strchr("!#$%&'*+-.^_`|~", c) != NULL;
}

int ms_h1_write_field(char *dst, size_t cap, size_t *used, const char *name, size_t name_len, const char *value, size_t value_len) {
    if (name_len == 0) return -2;
    for (size_t i = 0; i < name_len; i++) if (!is_token((unsigned char)name[i])) return -2;
    for (size_t i = 0; i < value_len; i++) if (value[i] == '\r' || value[i] == '\n' || value[i] == 0) return -2;
    if (name_len + value_len + 4 > cap - *used) return -1;
    put(dst, cap, used, name, name_len);
    put(dst, cap, used, ": ", 2);
    put(dst, cap, used, value, value_len);
    return put(dst, cap, used, "\r\n", 2);
}

int ms_h1_write_head_end(char *dst, size_t cap, size_t *used) { return put(dst, cap, used, "\r\n", 2); }

int ms_h1_write_chunk(char *dst, size_t cap, size_t *used, const char *data, size_t n) {
    static const char hex[] = "0123456789abcdef";
    char size[2 * sizeof(size_t) + 2];
    size_t k = 0;
    for (int shift = (int)(8 * sizeof(size_t)) - 4; shift >= 0; shift -= 4) {
        unsigned nib = (unsigned)((n >> shift) & 15);
        if (k || nib || shift == 0) size[k++] = hex[nib];
    }
    size[k++] = '\r'; size[k++] = '\n';
    if (n > cap || k + n + 2 > cap - *used) return -1;
    put(dst, cap, used, size, k);
    put(dst, cap, used, data, n);
    return put(dst, cap, used, "\r\n", 2);
}
