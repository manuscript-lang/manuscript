/* Unit tests for src/runtime/net/conn.c: row table (generations, reuse, limits) and HTTP/1 input with short reads and
   pipelining. Also prints the bytes an idle connection costs. */
#include <stdio.h>
#include <string.h>
#include "../net/conn.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

int main(void) {
    MsConnTable *t = ms_conn_table_new(3);
    MsConnId a = ms_conn_open(t, 10, MS_CONN_HTTP1), b = ms_conn_open(t, 11, MS_CONN_WS), c3 = ms_conn_open(t, 12, MS_CONN_HTTP1);
    CHECK(a && b && c3 && ms_conn_live(t) == 3);
    CHECK(ms_conn_open(t, 13, MS_CONN_HTTP1) == 0); /* full */
    CHECK(ms_conn_get(t, a)->fd == 10 && ms_conn_get(t, b)->proto == MS_CONN_WS);
    CHECK(ms_conn_close(t, b) == 0 && ms_conn_get(t, b) == NULL && ms_conn_close(t, b) == -1);
    MsConnId b2 = ms_conn_open(t, 14, MS_CONN_WS); /* reuses the row with a new generation */
    CHECK(b2 && (uint32_t)b2 == (uint32_t)b && b2 != b && ms_conn_get(t, b) == NULL && ms_conn_get(t, b2)->fd == 14);
    CHECK(ms_conn_get(t, 0) == NULL && ms_conn_get(t, (uint64_t)99 << 32 | 7) == NULL);
    ms_conn_table_free(t);

    /* idle cost: a plain connection is its row and nothing on the heap */
    printf("idle plain connection: %zu bytes of row, 0 heap\n", sizeof(MsConn));

    t = ms_conn_table_new(4);
    MsConnId id = ms_conn_open(t, 5, MS_CONN_HTTP1);
    MsConn *c = ms_conn_get(t, id);
    MsH1Field f[8]; MsH1Request r; const uint8_t *base; size_t avail;
    const char *wire = "GET /a HTTP/1.1\r\nHost: x\r\n\r\nGET /b HTTP/1.1\r\nHost: y\r\n\r\n";
    size_t total = strlen(wire), first = 28;
    CHECK(strlen("GET /a HTTP/1.1\r\nHost: x\r\n\r\n") == first);

    /* a head split over two reads: the first is kept, the second completes it */
    CHECK(ms_conn_h1_feed(c, (const uint8_t *)wire, 10, 4096, f, 8, &r, &base, &avail) == MS_CONN_NEED_MORE);
    CHECK(c->stash_len == 10);
    CHECK(ms_conn_h1_feed(c, (const uint8_t *)wire + 10, first - 10, 4096, f, 8, &r, &base, &avail) == MS_CONN_REQUEST);
    CHECK(base == c->stash && avail == first && r.head_len == first && !memcmp(base + r.target.off, "/a", 2));
    CHECK(ms_conn_request_done(c, base, avail, first) == 0 && c->stash == NULL && c->stash_len == 0); /* idle again */

    /* two pipelined requests in one read: the second waits in the row */
    CHECK(ms_conn_h1_feed(c, (const uint8_t *)wire, total, 4096, f, 8, &r, &base, &avail) == MS_CONN_REQUEST);
    CHECK(base == (const uint8_t *)wire && !memcmp(base + r.target.off, "/a", 2));
    CHECK(ms_conn_request_done(c, base, avail, r.head_len) == total - first && c->stash_len == total - first);
    CHECK(ms_conn_h1_feed(c, NULL, 0, 4096, f, 8, &r, &base, &avail) == MS_CONN_REQUEST);
    CHECK(base == c->stash && !memcmp(base + r.target.off, "/b", 2));
    CHECK(ms_conn_request_done(c, base, avail, r.head_len) == 0 && c->stash == NULL);

    /* nothing to parse, bad input, and a head over the limit */
    CHECK(ms_conn_h1_feed(c, NULL, 0, 4096, f, 8, &r, &base, &avail) == MS_CONN_NEED_MORE);
    CHECK(ms_conn_h1_feed(c, (const uint8_t *)"\x16\x03\x01\x02\x00", 5, 4096, f, 8, &r, &base, &avail) == MS_CONN_BAD);
    CHECK(ms_conn_h1_feed(c, (const uint8_t *)"GET / HTTP/1.1\r\nA: bbbbbbbb", 27, 16, f, 8, &r, &base, &avail) == MS_CONN_BAD && r.status == 431);

    CHECK(ms_conn_close(t, id) == 0);
    ms_conn_table_free(t);
    if (!failed) printf("conn ok\n");
    return failed;
}
