/* Unit tests for runtime/net/h2.c: a client and a server session exchange a request and response through memory,
   with a body larger than one frame, then a reset, and the server refuses garbage. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../net/h2.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)
#define S(x) x, sizeof x - 1

static size_t window = 32768; /* output buffer size: a tiny one proves partial output keeps its order */
static void pump(ms_h2 *from, ms_h2 *to) {
    static char b[32768];
    long n;
    while ((n = ms_h2_output(from, b, window)) > 0) CHECK(ms_h2_input(to, b, (size_t)n) == n);
}
static void settle(ms_h2 *a, ms_h2 *b) { for (int i = 0; i < 40; i++) { pump(a, b); pump(b, a); } }

static int has(const ms_h2 *h, const ms_h2_event *e, const char *name, const char *value) {
    for (uint32_t i = 0; i < e->nfields; i++) {
        const ms_h2_field *f = &e->fields[i];
        if (f->name.len == strlen(name) && !memcmp(ms_h2_arena(h) + f->name.off, name, f->name.len) &&
            f->value.len == strlen(value) && !memcmp(ms_h2_arena(h) + f->value.off, value, f->value.len)) return 1;
    }
    return 0;
}

int main(void) {
    ms_h2_limits lim = {100, 0};
    ms_h2 *srv = ms_h2_new(1, &lim), *cli = ms_h2_new(0, NULL);
    CHECK(srv && cli);
    ms_h2_nv req[] = {{S(":method"), S("POST")}, {S(":scheme"), S("https")}, {S(":path"), S("/up?x=1")},
                      {S(":authority"), S("example.test")}, {S("content-type"), S("text/plain")}};
    size_t blen = 100000;
    char *payload = malloc(blen);
    for (size_t i = 0; i < blen; i++) payload[i] = (char)('a' + i % 26);
    int32_t id = ms_h2_submit_request(cli, req, 5, payload, blen);
    CHECK(id == 1);
    settle(cli, srv);

    ms_h2_event e; size_t got = 0; int saw_headers = 0, saw_end = 0;
    char *copy = malloc(blen);
    while (ms_h2_next(srv, &e)) {
        if (e.type == MS_H2_HEADERS) {
            saw_headers = 1;
            CHECK(e.stream == 1 && !e.end_stream);
            CHECK(has(srv, &e, ":method", "POST") && has(srv, &e, ":path", "/up?x=1") && has(srv, &e, "content-type", "text/plain"));
        } else if (e.type == MS_H2_DATA) {
            CHECK(got + e.data.len <= blen);
            memcpy(copy + got, ms_h2_arena(srv) + e.data.off, e.data.len);
            got += e.data.len;
            if (e.end_stream) saw_end = 1;
        }
    }
    CHECK(saw_headers && saw_end && got == blen && !memcmp(copy, payload, blen));

    ms_h2_nv resp[] = {{S(":status"), S("200")}, {S("content-length"), S("5")}};
    CHECK(ms_h2_submit_response(srv, 1, resp, 2, "hello", 5) == 0);
    settle(cli, srv);
    int status_ok = 0, body_ok = 0, closed = 0;
    while (ms_h2_next(cli, &e)) {
        if (e.type == MS_H2_HEADERS && has(cli, &e, ":status", "200")) status_ok = 1;
        if (e.type == MS_H2_DATA && e.data.len == 5 && !memcmp(ms_h2_arena(cli) + e.data.off, "hello", 5)) body_ok = 1;
        if (e.type == MS_H2_CLOSED && e.stream == 1) closed = 1;
    }
    CHECK(status_ok && body_ok && closed);

    /* a reset reaches the other side */
    ms_h2_nv get[] = {{S(":method"), S("GET")}, {S(":scheme"), S("https")}, {S(":path"), S("/")}, {S(":authority"), S("example.test")}};
    id = ms_h2_submit_request(cli, get, 4, NULL, 0);
    CHECK(id == 3);
    settle(cli, srv);
    while (ms_h2_next(srv, &e)) {}
    CHECK(ms_h2_reset(srv, 3, 8) == 0);
    settle(cli, srv);
    int reset = 0;
    while (ms_h2_next(cli, &e)) if (e.type == MS_H2_RESET && e.stream == 3 && e.error_code == 8) reset = 1;
    CHECK(reset);

    /* garbage: a fatal error, and the server leaves a GOAWAY to send */
    ms_h2 *bad = ms_h2_new(1, NULL);
    CHECK(ms_h2_input(bad, "GET / HTTP/1.1\r\nHost: x\r\n\r\n", 28) == -1);
    char out[512];
    CHECK(ms_h2_output(bad, out, sizeof out) > 0);
    ms_h2_free(bad);

    /* the same exchange through a 7-byte output buffer */
    window = 7;
    ms_h2 *s2 = ms_h2_new(1, &lim), *c2 = ms_h2_new(0, NULL);
    CHECK(ms_h2_submit_request(c2, req, 5, payload, 30000) == 1);
    for (int i = 0; i < 20000; i++) { pump(c2, s2); pump(s2, c2); }
    size_t got2 = 0;
    while (ms_h2_next(s2, &e)) if (e.type == MS_H2_DATA) got2 += e.data.len;
    CHECK(got2 == 30000);
    ms_h2_free(s2); ms_h2_free(c2);

    free(payload); free(copy);
    ms_h2_free(srv); ms_h2_free(cli);
    if (!failed) printf("h2 ok\n");
    return failed;
}
