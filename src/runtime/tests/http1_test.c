/* Unit tests for src/runtime/net/http1.c: heads as offsets, partial reads, limits and smuggling refusals. */
#include <stdio.h>
#include <string.h>
#include <llhttp.h>
#include "../net/http1.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)
static int span_is(const char *b, MsSpan s, const char *v) { return s.len == strlen(v) && !memcmp(b + s.off, v, s.len); }

static int parse(const char *text, size_t limit, MsH1Request *r, MsH1Field *f, uint32_t cap) {
    r->fields = f;
    return ms_h1_parse_request(text, strlen(text), limit, r, cap);
}

/* Reads a whole response body in `step`-byte reads: the decoded bytes in `out`, the result of the last call. */
static int read_all(MsH1Reader *r, const char *buf, size_t len, size_t step, char *out, size_t *got) {
    size_t at = 0;
    int result = MS_H1_BODY_NEED_MORE;
    *got = 0;
    while (at < len && result != MS_H1_BODY_DONE) {
        size_t n = len - at < step ? len - at : step;
        while (1) {
            MsSpan d; size_t used;
            result = ms_h1_read_body(r, buf + at, n, &d, &used);
            if (result == MS_H1_BODY_DATA) { memcpy(out + *got, buf + at + d.off, d.len); *got += d.len; }
            at += used; n -= used;
            if (result != MS_H1_BODY_DATA) break;
        }
        if (result == MS_H1_BODY_BAD) return result;
    }
    return result;
}

static void test_responses(void) {
    MsH1Response resp; MsH1Field f[8]; MsH1Reader r; char body[64]; size_t got;
    resp.fields = f;
    const char *length = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nX: y\r\n\r\nhello";
    size_t head = strlen(length) - 5;
    CHECK(ms_h1_parse_response(&r, length, strlen(length), 1 << 20, &resp, 8, 0) == MS_H1_COMPLETE);
    CHECK(resp.status == 200 && resp.minor == 1 && resp.keep_alive && resp.nfields == 2 && resp.head_len == head);
    CHECK(span_is(length, resp.reason, "OK") && span_is(length, f[1].name, "X") && span_is(length, f[1].value, "y"));
    for (size_t step = 1; step <= 5; step++) {
        ms_h1_parse_response(&r, length, strlen(length), 1 << 20, &resp, 8, 0);
        CHECK(read_all(&r, length + head, 5, step, body, &got) == MS_H1_BODY_DONE && got == 5 && !memcmp(body, "hello", 5));
    }

    /* every prefix of the head is partial */
    for (size_t n = 0; n < head; n++) CHECK(ms_h1_parse_response(&r, length, n, 1 << 20, &resp, 8, 0) == MS_H1_PARTIAL);

    /* chunked, in every read size, and a chunked body split inside the framing */
    const char *chunked = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n4\r\ndefg\r\n0\r\n\r\n";
    head = strlen("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");
    for (size_t step = 1; step <= 8; step++) {
        CHECK(ms_h1_parse_response(&r, chunked, strlen(chunked), 1 << 20, &resp, 8, 0) == MS_H1_COMPLETE);
        CHECK(read_all(&r, chunked + head, strlen(chunked) - head, step, body, &got) == MS_H1_BODY_DONE && got == 7 && !memcmp(body, "abcdefg", 7));
    }

    /* a body that ends with the stream, and a truncated one */
    const char *eof = "HTTP/1.0 200 OK\r\n\r\nuntil close";
    head = strlen("HTTP/1.0 200 OK\r\n\r\n");
    CHECK(ms_h1_parse_response(&r, eof, strlen(eof), 1 << 20, &resp, 8, 0) == MS_H1_COMPLETE && !resp.keep_alive);
    CHECK(read_all(&r, eof + head, strlen(eof) - head, 100, body, &got) == MS_H1_BODY_NEED_MORE && got == 11);
    CHECK(ms_h1_read_body_eof(&r) == MS_H1_BODY_DONE);
    CHECK(ms_h1_parse_response(&r, length, strlen(length) - 2, 1 << 20, &resp, 8, 0) == MS_H1_COMPLETE);
    CHECK(read_all(&r, length + head, 3, 100, body, &got) != MS_H1_BODY_DONE && ms_h1_read_body_eof(&r) == MS_H1_BODY_BAD);

    /* no body: HEAD answers, 204, 304 and interim heads, whatever the headers claim */
    const char *no_body = "HTTP/1.1 204 No Content\r\nContent-Length: 9\r\n\r\n";
    MsSpan d; size_t used;
    CHECK(ms_h1_parse_response(&r, no_body, strlen(no_body), 1 << 20, &resp, 8, 0) == MS_H1_COMPLETE);
    CHECK(ms_h1_read_body(&r, "", 0, &d, &used) == MS_H1_BODY_DONE);
    CHECK(ms_h1_parse_response(&r, length, strlen(length), 1 << 20, &resp, 8, 1) == MS_H1_COMPLETE);
    CHECK(ms_h1_read_body(&r, "", 0, &d, &used) == MS_H1_BODY_DONE && used == 0);
    const char *interim = "HTTP/1.1 100 Continue\r\n\r\n";
    CHECK(ms_h1_parse_response(&r, interim, strlen(interim), 1 << 20, &resp, 8, 0) == MS_H1_COMPLETE && resp.status == 100);
    const char *upgrade = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n";
    CHECK(ms_h1_parse_response(&r, upgrade, strlen(upgrade), 1 << 20, &resp, 8, 0) == MS_H1_COMPLETE && resp.status == 101);
    CHECK(resp.head_len == strlen(upgrade));

    /* limits and smuggling refusals */
    CHECK(ms_h1_parse_response(&r, length, strlen(length), 20, &resp, 8, 0) == MS_H1_BAD);
    CHECK(ms_h1_parse_response(&r, length, strlen(length), 1 << 20, &resp, 1, 0) == MS_H1_BAD);
    const char *both = "HTTP/1.1 200 OK\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n";
    CHECK(ms_h1_parse_response(&r, both, strlen(both), 1 << 20, &resp, 8, 0) == MS_H1_BAD);
    CHECK(ms_h1_parse_response(&r, "HTTP/1.1 20 OK\r\n\r\n", 19, 1 << 20, &resp, 8, 0) == MS_H1_BAD);
    CHECK(ms_h1_parse_response(&r, "garbage\r\n\r\n", 11, 1 << 20, &resp, 8, 0) == MS_H1_BAD);
    const char *bad_chunk = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n";
    head = strlen("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");
    CHECK(ms_h1_parse_response(&r, bad_chunk, strlen(bad_chunk), 1 << 20, &resp, 8, 0) == MS_H1_COMPLETE);
    CHECK(read_all(&r, bad_chunk + head, 4, 4, body, &got) == MS_H1_BODY_BAD);
}

int main(void) {
    MsH1Request r; MsH1Field f[8];
    const char *ok = "POST /a?b=1 HTTP/1.1\r\nHost: x.test\r\nContent-Length: 3\r\nX-Empty:\r\n\r\nabc";
    CHECK(parse(ok, 1 << 20, &r, f, 8) == MS_H1_COMPLETE);
    CHECK(r.method == HTTP_POST && r.minor == 1 && r.nfields == 3);
    CHECK(span_is(ok, r.target, "/a?b=1"));
    CHECK(span_is(ok, f[0].name, "Host") && span_is(ok, f[0].value, "x.test"));
    CHECK(span_is(ok, f[1].name, "Content-Length") && span_is(ok, f[1].value, "3"));
    CHECK(span_is(ok, f[2].name, "X-Empty") && f[2].value.len == 0);
    CHECK(r.head_len == strlen(ok) - 3);

    /* every prefix of a valid head is partial, and the full head completes */
    const char *h = "GET /p HTTP/1.0\r\nA: b\r\n\r\n";
    for (size_t n = 0; n < strlen(h); n++) {
        r.fields = f;
        CHECK(ms_h1_parse_request(h, n, 1 << 20, &r, 8) == MS_H1_PARTIAL);
    }
    CHECK(parse(h, 1 << 20, &r, f, 8) == MS_H1_COMPLETE && r.minor == 0 && r.head_len == strlen(h));

    /* limits */
    CHECK(parse("GET / HTTP/1.1\r\nA: b\r\nC: d\r\n\r\n", 1 << 20, &r, f, 1) == MS_H1_BAD && r.status == 431);
    CHECK(parse("GET / HTTP/1.1\r\nA: bbbbbbbbbb\r\n\r\n", 20, &r, f, 8) == MS_H1_BAD && r.status == 431);
    CHECK(parse("GET / HTTP/1.1\r\nA: bbbbbbbbbb", 20, &r, f, 8) == MS_H1_BAD && r.status == 431);

    /* refusals that guard request smuggling */
    CHECK(parse("GET / HTTP/1.1\r\nA: b\nC: d\r\n\r\n", 1 << 20, &r, f, 8) == MS_H1_BAD && r.status == 400);
    CHECK(parse("GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n", 1 << 20, &r, f, 8) == MS_H1_BAD);
    CHECK(parse("GET / HTTP/1.1\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n", 1 << 20, &r, f, 8) == MS_H1_BAD);
    CHECK(parse("GET / HTTP/1.1\r\nA : b\r\n\r\n", 1 << 20, &r, f, 8) == MS_H1_BAD);
    CHECK(parse("GET / HTTP/1.1\r\n A: b\r\n\r\n", 1 << 20, &r, f, 8) == MS_H1_BAD);
    CHECK(parse("BREW / HTTP/1.1\r\n\r\n", 1 << 20, &r, f, 8) == MS_H1_BAD && r.status == 501);
    CHECK(parse("GET / HTTP/1.1\r\nA: b\r\nHost\r\n\r\n", 1 << 20, &r, f, 8) == MS_H1_BAD);

    /* response writers */
    char o[256]; size_t u = 0;
    CHECK(ms_h1_write_status(o, sizeof o, &u, 1, 200, "OK", 2) == 0);
    CHECK(ms_h1_write_field(o, sizeof o, &u, "Content-Type", 12, "text/plain", 10) == 0);
    CHECK(ms_h1_write_head_end(o, sizeof o, &u) == 0);
    CHECK(u == strlen("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n") && !memcmp(o, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n", u));
    u = 0;
    CHECK(ms_h1_write_field(o, sizeof o, &u, "X", 1, "a\r\nSet-Cookie: b", 17) == -2 && u == 0);
    CHECK(ms_h1_write_field(o, sizeof o, &u, "X Y", 3, "v", 1) == -2);
    CHECK(ms_h1_write_field(o, sizeof o, &u, "", 0, "v", 1) == -2);
    CHECK(ms_h1_write_status(o, sizeof o, &u, 1, 200, "O\nK", 4) == -2);
    CHECK(ms_h1_write_field(o, 8, &u, "Name", 4, "value", 5) == -1 && u == 0);
    CHECK(ms_h1_write_chunk(o, sizeof o, &u, "hello world!", 12) == 0 && !memcmp(o, "c\r\nhello world!\r\n", u) && u == 17);
    u = 0;
    CHECK(ms_h1_write_chunk(o, sizeof o, &u, "", 0) == 0 && u == 5 && !memcmp(o, "0\r\n\r\n", 5));
    u = 0;
    CHECK(ms_h1_write_chunk(o, 6, &u, "hello", 5) == -1 && u == 0);

    /* request line */
    u = 0;
    CHECK(ms_h1_write_request_line(o, sizeof o, &u, "GET", 3, "/a?b=1", 6) == 0 && !memcmp(o, "GET /a?b=1 HTTP/1.1\r\n", u) && u == 21);
    u = 0;
    CHECK(ms_h1_write_request_line(o, sizeof o, &u, "GE T", 4, "/", 1) == -2);
    CHECK(ms_h1_write_request_line(o, sizeof o, &u, "GET", 3, "/a b", 4) == -2);
    CHECK(ms_h1_write_request_line(o, sizeof o, &u, "GET", 3, "/a\r\nX: y", 9) == -2);
    CHECK(ms_h1_write_request_line(o, 12, &u, "GET", 3, "/long-target", 12) == -1 && u == 0);

    test_responses();
    if (!failed) printf("http1 ok\n");
    return failed;
}
