/* Unit tests for runtime/net/h2conn.c: a client and a server connection exchange requests through memory, with
   bodies, trailers, resets, releases before close, a full stream table and a graceful close. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../net/h2conn.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)
#define S(x) x, sizeof x - 1

static void pump(MsH2Conn *from, MsH2Conn *to) {
    static char b[16384];
    long n;
    while ((n = ms_h2conn_output(from, b, sizeof b)) > 0) CHECK(ms_h2conn_input(to, b, (size_t)n) == n);
}
static void settle(MsH2Conn *a, MsH2Conn *b) { for (int i = 0; i < 20; i++) { pump(a, b); pump(b, a); } }

static int same(MsBytes got, const char *want) { return got.len == strlen(want) && !memcmp(got.ptr, want, got.len); }

static int field(const MsH2Head *head, const char *name, const char *value) {
    for (size_t i = 0; i < head->nfields; i++)
        if (same(head->fields[i].name, name) && same(head->fields[i].value, value)) return 1;
    return 0;
}

/* The next event of a type for a stream, dropping others; 0 when none is queued. */
static int take(MsH2Conn *c, int type, int32_t stream, MsH2ConnEvent *out) {
    MsH2ConnEvent e;
    while (ms_h2conn_next(c, &e)) {
        if (e.type == type && e.stream == stream) { *out = e; return 1; }
    }
    return 0;
}


typedef struct UserSeen { int streams; int32_t id; uint64_t handler, watcher; } UserSeen;

static void note_user(void *context, int32_t stream, const uint64_t *user) {
    UserSeen *seen = context;
    seen->streams++;
    seen->id = stream;
    seen->handler = user[0];
    seen->watcher = user[1];
}

static void exchange(void) {
    MsH2Limits lim = {100, 0, 65535, 65535};
    MsH2Conn *srv = ms_h2conn_new(1, &lim), *cli = ms_h2conn_new(0, &lim);
    CHECK(srv && cli);
    MsH2Nv req[] = {{S(":method"), S("POST")}, {S(":scheme"), S("https")}, {S(":path"), S("/up?x=1")},
                    {S(":authority"), S("example.test")}, {S("content-type"), S("text/plain")}};
    int32_t id = ms_h2conn_open(cli, req, 5, 1);
    CHECK(id == 1 && ms_h2conn_open_streams(cli) == 1);
    size_t blen = 200000, sent = 0;
    char *payload = malloc(blen), *copy = malloc(blen);
    for (size_t i = 0; i < blen; i++) payload[i] = (char)('a' + i % 26);

    size_t got = 0;
    MsH2ConnEvent e;
    for (int round = 0; round < 200 && !(ms_h2conn_state(srv, id) & MS_H2S_ENDED && got == blen); round++) {
        if (sent < blen) {
            long took = ms_h2conn_send(cli, id, payload + sent, blen - sent, 1);
            CHECK(took >= 0);
            sent += (size_t)took;
        }
        settle(cli, srv);
        long n;
        char chunk[8192];
        while ((n = ms_h2conn_read(srv, id, chunk, sizeof chunk)) > 0) { memcpy(copy + got, chunk, (size_t)n); got += (size_t)n; }
    }
    const MsH2Head *head = ms_h2conn_head(srv, id);
    CHECK(head != NULL && same(head->method, "POST") && same(head->path, "/up?x=1") && same(head->authority, "example.test"));
    CHECK(head && head->nfields == 1 && field(head, "content-type", "text/plain"));
    CHECK(got == blen && !memcmp(copy, payload, blen));
    CHECK(take(srv, MS_H2C_HEAD, id, &e));

    /* the response: an interim head is dropped, the final one arrives with the body and a trailer */
    MsH2Nv head_nv[] = {{S(":status"), S("200")}, {S("content-type"), S("text/plain")}};
    CHECK(ms_h2conn_respond(srv, id, head_nv, 2, 1) == 0);
    CHECK(ms_h2conn_send(srv, id, "hello", 5, 0) == 5);
    MsH2Nv tr[] = {{S("x-sum"), S("7")}};
    CHECK(ms_h2conn_trailers_send(srv, id, tr, 1) == 0);
    settle(cli, srv);
    CHECK(take(cli, MS_H2C_HEAD, id, &e));
    const MsH2Head *resp = ms_h2conn_head(cli, id);
    CHECK(resp && resp->status == 200 && field(resp, "content-type", "text/plain"));
    char small[16];
    CHECK(ms_h2conn_read(cli, id, small, sizeof small) == 5 && !memcmp(small, "hello", 5));
    CHECK(ms_h2conn_read(cli, id, small, sizeof small) == 0);
    unsigned state = ms_h2conn_state(cli, id);
    CHECK((state & MS_H2S_ENDED) && (state & MS_H2S_TRAILERS));
    const MsH2Head *trailers = ms_h2conn_trailers(cli, id);
    CHECK(trailers && field(trailers, "x-sum", "7"));

    *ms_h2conn_user(cli, id) = 77;
    CHECK(*ms_h2conn_user(cli, id) == 77 && ms_h2conn_user(cli, 99) == NULL);
    /* the watcher's word is a second one: it starts at 0, is not the handler's, and for_each shows both */
    CHECK(ms_h2conn_watch(cli, 99) == NULL && ms_h2conn_watch(cli, id) != NULL && ms_h2conn_watch(cli, id) != ms_h2conn_user(cli, id));
    CHECK(*ms_h2conn_watch(cli, id) == 0);
    *ms_h2conn_watch(cli, id) = 99;
    CHECK(*ms_h2conn_user(cli, id) == 77 && *ms_h2conn_watch(cli, id) == 99);
    UserSeen seen = {0};
    ms_h2conn_for_each(cli, note_user, &seen);
    CHECK(seen.streams == 1 && seen.id == id && seen.handler == 77 && seen.watcher == 99);
    ms_h2conn_release(cli, id, 0);
    ms_h2conn_release(srv, id, 0);
    settle(cli, srv);
    CHECK(ms_h2conn_head(cli, id) == NULL && ms_h2conn_head(srv, id) == NULL);
    CHECK(ms_h2conn_open_streams(cli) == 0 && ms_h2conn_open_streams(srv) == 0);
    CHECK(ms_h2conn_idle(cli) && ms_h2conn_idle(srv));
    free(payload); free(copy);
    ms_h2conn_free(srv); ms_h2conn_free(cli);
}

static void resets_and_limits(void) {
    MsH2Limits lim = {2, 0, 0, 0};
    MsH2Conn *srv = ms_h2conn_new(1, &lim), *cli = ms_h2conn_new(0, NULL);
    MsH2Nv get[] = {{S(":method"), S("GET")}, {S(":scheme"), S("https")}, {S(":path"), S("/")}, {S(":authority"), S("a.test")}};
    int32_t first = ms_h2conn_open(cli, get, 4, 0);
    int32_t second = ms_h2conn_open(cli, get, 4, 0);
    CHECK(first == 1 && second == 3);
    settle(cli, srv);
    CHECK(ms_h2conn_usable(cli) == 0 && ms_h2conn_open(cli, get, 4, 0) == -1); /* the server allows two */
    MsH2ConnEvent e;
    CHECK(take(srv, MS_H2C_HEAD, first, &e) && ms_h2conn_head(srv, second) != NULL);
    CHECK(ms_h2conn_reset(srv, first, 8) == 0);
    settle(cli, srv);
    CHECK(take(cli, MS_H2C_RESET, first, &e) && e.code == 8);
    CHECK((ms_h2conn_state(cli, first) & MS_H2S_RESET) && ms_h2conn_reset_code(cli, first) == 8);
    ms_h2conn_release(cli, first, 0);
    CHECK(ms_h2conn_usable(cli) == 1);

    /* a handler gives up on a stream whose client is still sending: released open, it is reset and freed */
    ms_h2conn_release(srv, second, 8);
    settle(cli, srv);
    CHECK(take(cli, MS_H2C_RESET, second, &e) && e.code == 8);
    ms_h2conn_release(cli, second, 0);
    CHECK(ms_h2conn_head(srv, second) == NULL && ms_h2conn_open_streams(srv) == 0);

    /* a graceful close reaches the client */
    CHECK(ms_h2conn_goaway(srv, 0) == 0);
    settle(cli, srv);
    CHECK(take(cli, MS_H2C_GOAWAY, 3, &e) && e.code == 0);
    CHECK(ms_h2conn_usable(cli) == 0 && ms_h2conn_usable(srv) == 0);
    ms_h2conn_free(srv); ms_h2conn_free(cli);

    /* garbage: a fatal error with a GOAWAY to send */
    MsH2Conn *bad = ms_h2conn_new(1, NULL);
    CHECK(ms_h2conn_input(bad, "GET / HTTP/1.1\r\nHost: x\r\n\r\n", 28) == -1);
    char out[256];
    CHECK(ms_h2conn_output(bad, out, sizeof out) > 0);
    ms_h2conn_free(bad);
}

/* Many short streams in a row reuse table slots and the index without leaking or mixing heads. */
static void churn(void) {
    MsH2Limits lim = {8, 0, 0, 0};
    MsH2Conn *srv = ms_h2conn_new(1, &lim), *cli = ms_h2conn_new(0, NULL);
    MsH2Nv get[] = {{S(":method"), S("GET")}, {S(":scheme"), S("https")}, {S(":path"), S("/n")}, {S(":authority"), S("a.test")}};
    for (int round = 0; round < 500; round++) {
        int32_t ids[8];
        int count = 0;
        while (ms_h2conn_usable(cli) && count < 8) ids[count++] = ms_h2conn_open(cli, get, 4, 0);
        CHECK(count > 0);
        settle(cli, srv);
        for (int i = 0; i < count; i++) {
            const MsH2Head *head = ms_h2conn_head(srv, ids[i]);
            CHECK(head && same(head->path, "/n"));
            MsH2Nv ok[] = {{S(":status"), S("204")}};
            CHECK(ms_h2conn_respond(srv, ids[i], ok, 1, 0) == 0);
            ms_h2conn_release(srv, ids[i], 0);
        }
        settle(cli, srv);
        for (int i = 0; i < count; i++) {
            const MsH2Head *head = ms_h2conn_head(cli, ids[i]);
            CHECK(head && head->status == 204);
            ms_h2conn_release(cli, ids[i], 0);
        }
        settle(cli, srv);
        CHECK(ms_h2conn_open_streams(cli) == 0 && ms_h2conn_open_streams(srv) == 0);
    }
    ms_h2conn_free(srv); ms_h2conn_free(cli);
}

int main(void) {
    exchange();
    resets_and_limits();
    churn();
    if (!failed) printf("h2conn ok\n");
    return failed;
}
