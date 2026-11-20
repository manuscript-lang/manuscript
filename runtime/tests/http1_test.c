/* Unit tests for runtime/net/http1.c: heads as offsets, partial reads, limits and smuggling refusals. */
#include <stdio.h>
#include <string.h>
#include <llhttp.h>
#include "../net/http1.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)
static int span_is(const char *b, ms_span s, const char *v) { return s.len == strlen(v) && !memcmp(b + s.off, v, s.len); }

static int parse(const char *text, size_t limit, ms_h1_request *r, ms_h1_field *f, uint32_t cap) {
    r->fields = f;
    return ms_h1_parse_request(text, strlen(text), limit, r, cap);
}

int main(void) {
    ms_h1_request r; ms_h1_field f[8];
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

    if (!failed) printf("http1 ok\n");
    return failed;
}
