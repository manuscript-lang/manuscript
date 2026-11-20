#include "http1.h"
#include <llhttp.h>
#include <stdbool.h>
#include <string.h>
#include "ms_rt/chars.h"

/* Collects the first line's span and the header fields of a request or a response head. */
typedef struct {
    const char *base;
    MsH1Field *fields;
    uint32_t *nfields;
    MsSpan *first_line; /* the target of a request, the reason of a response */
    uint32_t cap;
    uint8_t have_first_line, name_open, value_open, too_many;
} MsH1State;

static uint32_t at(const MsH1State *s, const char *p) { return (uint32_t)(p - s->base); }

static int on_first_line(llhttp_t *p, const char *c, size_t n) {
    MsH1State *s = p->data;
    if (!s->have_first_line) { s->first_line->off = at(s, c); s->first_line->len = (uint32_t)n; s->have_first_line = 1; }
    else s->first_line->len = at(s, c) + (uint32_t)n - s->first_line->off;
    return 0;
}

static int on_name(llhttp_t *p, const char *c, size_t n) {
    MsH1State *s = p->data;
    if (s->name_open) {
        MsH1Field *f = &s->fields[*s->nfields - 1];
        f->name.len = at(s, c) + (uint32_t)n - f->name.off;
        return 0;
    }
    if (*s->nfields == s->cap) { s->too_many = 1; return HPE_USER; }
    MsH1Field *f = &s->fields[(*s->nfields)++];
    f->name.off = at(s, c); f->name.len = (uint32_t)n; f->value.off = at(s, c) + (uint32_t)n; f->value.len = 0;
    s->name_open = 1;
    return 0;
}

static int on_name_done(llhttp_t *p) { ((MsH1State *)p->data)->name_open = 0; return 0; }

static int on_value(llhttp_t *p, const char *c, size_t n) {
    MsH1State *s = p->data;
    MsH1Field *f = &s->fields[*s->nfields - 1];
    if (!s->value_open) { f->value.off = at(s, c); f->value.len = (uint32_t)n; s->value_open = 1; }
    else f->value.len = at(s, c) + (uint32_t)n - f->value.off;
    return 0;
}

static int on_value_done(llhttp_t *p) { ((MsH1State *)p->data)->value_open = 0; return 0; }
static int on_headers_done(llhttp_t *p) { (void)p; return HPE_PAUSED; }

static void head_settings(llhttp_settings_t *cb) {
    llhttp_settings_init(cb);
    cb->on_header_field = on_name;
    cb->on_header_field_complete = on_name_done;
    cb->on_header_value = on_value;
    cb->on_header_value_complete = on_value_done;
    cb->on_headers_complete = on_headers_done;
}

/* The status to refuse with: too many fields, an unknown method, or any other malformed head. */
static uint16_t refusal_status(bool too_many, enum llhttp_errno error) {
    if (too_many) return 431;
    if (error == HPE_INVALID_METHOD) return 501;
    return 400;
}

/* Parses a request head with `parser`, which the caller initialized for requests; the parser stays paused at the end of
   the head on COMPLETE. */
static int parse_request_with(llhttp_t *p, const char *buf, size_t len, size_t head_limit, MsH1Request *out, uint32_t field_cap) {
    MsH1Field *fields = out->fields;
    memset(out, 0, sizeof *out);
    out->fields = fields;
    if (len > UINT32_MAX) { out->status = 431; return MS_H1_BAD; }
    MsH1State s = {buf, fields, &out->nfields, &out->target, field_cap, 0, 0, 0, 0};
    p->data = &s;
    enum llhttp_errno e = llhttp_execute(p, buf, len);
    if (e == HPE_PAUSED) {
        size_t used = (size_t)(llhttp_get_error_pos(p) - buf);
        if (used > head_limit) { out->status = 431; return MS_H1_BAD; }
        out->head_len = (uint32_t)used;
        out->method = p->method;
        out->minor = p->http_minor;
        out->keep_alive = (uint8_t)llhttp_should_keep_alive(p);
        return MS_H1_COMPLETE;
    }
    if (e == HPE_OK) {
        if (len > head_limit) { out->status = 431; return MS_H1_BAD; }
        return MS_H1_PARTIAL;
    }
    out->status = refusal_status(s.too_many, e);
    return MS_H1_BAD;
}

int ms_h1_parse_request(const char *buf, size_t len, size_t head_limit, MsH1Request *out, uint32_t field_cap) {
    llhttp_settings_t cb;
    head_settings(&cb);
    cb.on_url = on_first_line;
    llhttp_t p;
    llhttp_init(&p, HTTP_REQUEST, &cb);
    return parse_request_with(&p, buf, len, head_limit, out, field_cap);
}

/* The reader's state behind the opaque storage of MsH1Reader. */
typedef struct {
    llhttp_t parser;
    const char *base; /* the buffer of the current ms_h1_read_body call */
    MsSpan data;
    uint8_t have_data, done, no_body;
} MsH1ReaderState;

_Static_assert(sizeof(MsH1ReaderState) <= sizeof(MsH1Reader), "MS_H1_READER_BYTES holds the llhttp parser and its state");
_Static_assert(_Alignof(MsH1ReaderState) <= _Alignof(MsH1Reader), "the reader storage is aligned for the llhttp parser");

static MsH1ReaderState *reader_state(MsH1Reader *reader) { return (MsH1ReaderState *)reader; }

/* Response heads and bodies. The reader keeps the llhttp parser from the head through the body, so chunked and
   length framing are llhttp's; a body span points into the buffer of the call that found it. */
static int on_body(llhttp_t *p, const char *c, size_t n) {
    MsH1ReaderState *r = p->data;
    if (n == 0) return 0; /* llhttp reports an empty span for a body read to end of stream; it is no data */
    r->data.off = (uint32_t)(c - r->base);
    r->data.len = (uint32_t)n;
    r->have_data = 1;
    return HPE_PAUSED;
}

static int on_message_done(llhttp_t *p) {
    ((MsH1ReaderState *)p->data)->done = 1;
    return HPE_PAUSED;
}

/* llhttp keeps its settings as a plain pointer, so this is not const; nothing writes it. */
static llhttp_settings_t body_settings = {.on_body = on_body, .on_message_complete = on_message_done};

int ms_h1_parse_response(MsH1Reader *reader, const char *buf, size_t len, size_t head_limit, MsH1Response *out,
                         uint32_t field_cap, int head_request) {
    MsH1ReaderState *r = reader_state(reader);
    MsH1Field *fields = out->fields;
    memset(out, 0, sizeof *out);
    out->fields = fields;
    memset(reader, 0, sizeof *reader);
    if (len > UINT32_MAX) return MS_H1_BAD;
    MsH1State s = {buf, fields, &out->nfields, &out->reason, field_cap, 0, 0, 0, 0};
    llhttp_settings_t cb;
    head_settings(&cb);
    cb.on_status = on_first_line;
    llhttp_init(&r->parser, HTTP_RESPONSE, &cb);
    r->parser.data = &s;
    enum llhttp_errno e = llhttp_execute(&r->parser, buf, len);
    if (e == HPE_OK) return len > head_limit ? MS_H1_BAD : MS_H1_PARTIAL;
    const size_t used = (size_t)(llhttp_get_error_pos(&r->parser) - buf);
    if (e != HPE_PAUSED || used > head_limit) return MS_H1_BAD;
    out->head_len = (uint32_t)used;
    out->status = r->parser.status_code;
    out->minor = r->parser.http_minor;
    out->keep_alive = (uint8_t)llhttp_should_keep_alive(&r->parser);
    /* HEAD answers, 1xx, 204 and 304 carry no body whatever their headers claim. */
    r->no_body = head_request || out->status < 200 || out->status == 204 || out->status == 304;
    r->parser.settings = &body_settings;
    r->parser.data = r;
    llhttp_resume(&r->parser);
    return MS_H1_COMPLETE;
}

void ms_h1_reader_moved(MsH1Reader *reader) {
    MsH1ReaderState *r = reader_state(reader);
    r->parser.data = r;
}

int ms_h1_parse_request_body(MsH1Reader *reader, const char *buf, size_t len, size_t head_limit, MsH1Request *out,
                             uint32_t field_cap) {
    MsH1ReaderState *r = reader_state(reader);
    memset(reader, 0, sizeof *reader);
    llhttp_settings_t cb;
    head_settings(&cb);
    cb.on_url = on_first_line;
    llhttp_init(&r->parser, HTTP_REQUEST, &cb);
    const int result = parse_request_with(&r->parser, buf, len, head_limit, out, field_cap);
    if (result != MS_H1_COMPLETE) return result;
    /* Without a length or chunked framing llhttp ends the message at the end of the head, but only on the next bytes it
       sees, which belong to the next request; the head already says there is no body. */
    r->no_body = (r->parser.flags & F_CHUNKED) == 0 && r->parser.content_length == 0;
    r->parser.settings = &body_settings;
    r->parser.data = r;
    llhttp_resume(&r->parser);
    return MS_H1_COMPLETE;
}

int ms_h1_read_body(MsH1Reader *reader, const char *buf, size_t len, MsSpan *data, size_t *used) {
    MsH1ReaderState *r = reader_state(reader);
    *used = 0;
    if (r->no_body || r->done) return MS_H1_BODY_DONE;
    if (len > UINT32_MAX) return MS_H1_BODY_BAD;
    r->base = buf;
    r->have_data = 0;
    const enum llhttp_errno e = llhttp_execute(&r->parser, buf, len);
    if (e == HPE_OK) { *used = len; return MS_H1_BODY_NEED_MORE; }
    if (e != HPE_PAUSED) return MS_H1_BODY_BAD;
    *used = (size_t)(llhttp_get_error_pos(&r->parser) - buf);
    llhttp_resume(&r->parser);
    if (r->have_data) { *data = r->data; return MS_H1_BODY_DATA; }
    return r->done ? MS_H1_BODY_DONE : MS_H1_BODY_NEED_MORE;
}

int ms_h1_read_body_eof(MsH1Reader *reader) {
    MsH1ReaderState *r = reader_state(reader);
    if (r->no_body || r->done) return MS_H1_BODY_DONE;
    r->have_data = 0;
    const enum llhttp_errno e = llhttp_finish(&r->parser);
    if (e != HPE_OK && e != HPE_PAUSED) return MS_H1_BODY_BAD;
    llhttp_resume(&r->parser);
    return r->done ? MS_H1_BODY_DONE : MS_H1_BODY_BAD;
}

const MsH1Field *ms_h1_find_field(const char *base, const MsH1Field *fields, uint32_t count, MsBytes name) {
    for (uint32_t i = 0; i < count; i++) {
        const MsBytes candidate = ms_bytes_of((const uint8_t *)base + fields[i].name.off, fields[i].name.len);
        if (ms_ascii_equal_fold(candidate, name)) return &fields[i];
    }
    return NULL;
}

bool ms_h1_value_has_token(MsBytes value, MsBytes token) {
    size_t start = 0;
    while (start <= value.len) {
        size_t end = start;
        while (end < value.len && value.ptr[end] != ',') end++;
        size_t from = start, to = end;
        while (from < to && (value.ptr[from] == ' ' || value.ptr[from] == '\t')) from++;
        while (to > from && (value.ptr[to - 1] == ' ' || value.ptr[to - 1] == '\t')) to--;
        if (ms_ascii_equal_fold(ms_bytes_of(value.ptr + from, to - from), token)) return true;
        start = end + 1;
    }
    return false;
}

static int put(char *dst, size_t cap, size_t *used, const char *s, size_t n) {
    if (n > cap - *used) return -1;
    if (n > 0) memcpy(dst + *used, s, n);
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
    if (ms_ascii_is_alnum(c)) return 1;
    return c && strchr("!#$%&'*+-.^_`|~", c) != NULL;
}

bool ms_h1_is_token(MsBytes text) {
    if (text.len == 0) {
        return false;
    }
    for (size_t i = 0; i < text.len; i++) {
        if (!is_token(text.ptr[i])) {
            return false;
        }
    }
    return true;
}

int ms_h1_write_request_line(char *dst, size_t cap, size_t *used, const char *method, size_t method_len,
                             const char *target, size_t target_len) {
    if (method_len == 0 || target_len == 0) return -2;
    for (size_t i = 0; i < method_len; i++) if (!is_token((unsigned char)method[i])) return -2;
    for (size_t i = 0; i < target_len; i++) if ((unsigned char)target[i] <= ' ' || target[i] == 0x7f) return -2;
    static const char version[] = " HTTP/1.1\r\n";
    if (method_len + target_len + sizeof version > cap - *used) return -1; /* sizeof counts the NUL, room for the space */
    put(dst, cap, used, method, method_len);
    put(dst, cap, used, " ", 1);
    put(dst, cap, used, target, target_len);
    return put(dst, cap, used, version, sizeof version - 1);
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
