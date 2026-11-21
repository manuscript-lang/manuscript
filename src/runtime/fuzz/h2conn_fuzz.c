/* Fuzz harness for src/runtime/net/h2conn.c (and the nghttp2 layer under it). Input: byte 0 picks a server or a
   client with one request open, the rest is fed as wire bytes in pieces of a size byte 1 picks. Every event is
   handled the way a native would: heads read, bodies read, streams released. The harness aborts on a broken
   invariant; ASan and UBSan catch memory errors. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "../net/h2conn.h"

#define REQUIRE(c) do { if (!(c)) abort(); } while (0)
#define S(x) x, sizeof x - 1

static void handle(MsH2Conn *c, int server) {
    MsH2ConnEvent e;
    uint8_t chunk[256];
    while (ms_h2conn_next(c, &e)) {
        if (e.type == MS_H2C_GOAWAY) continue;
        const MsH2Head *head = ms_h2conn_head(c, e.stream);
        if (head != NULL) {
            REQUIRE(head->nfields == 0 || head->fields != NULL);
            for (size_t i = 0; i < head->nfields; i++) {
                REQUIRE(head->fields[i].name.len > 0);
                REQUIRE(head->fields[i].name.ptr[0] != ':');
                (void)head->fields[i].value.ptr[0 < head->fields[i].value.len ? head->fields[i].value.len - 1 : 0];
            }
        }
        long n;
        while ((n = ms_h2conn_read(c, e.stream, chunk, sizeof chunk)) > 0) REQUIRE((size_t)n <= sizeof chunk);
        if (server && e.type == MS_H2C_HEAD) {
            MsH2Nv ok[] = {{S(":status"), S("200")}};
            (void)ms_h2conn_respond(c, e.stream, ok, 1, 1);
            (void)ms_h2conn_send(c, e.stream, "fuzz", 4, 1);
        }
        unsigned state = ms_h2conn_state(c, e.stream);
        if (state & (MS_H2S_ENDED | MS_H2S_RESET)) ms_h2conn_release(c, e.stream, 0);
    }
    uint8_t out[512];
    while (ms_h2conn_output(c, out, sizeof out) > 0) {}
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 2) return 0;
    int server = data[0] & 1;
    size_t piece = (size_t)data[1] + 1;
    MsH2Limits limits = {8, 4096, 16384, 65535};
    MsH2Conn *c = ms_h2conn_new(server, &limits);
    REQUIRE(c != NULL);
    if (!server) {
        MsH2Nv get[] = {{S(":method"), S("GET")}, {S(":scheme"), S("https")}, {S(":path"), S("/")}, {S(":authority"), S("fuzz.test")}};
        REQUIRE(ms_h2conn_open(c, get, 4, 0) == 1);
    }
    for (size_t at = 2; at < size; at += piece) {
        size_t n = size - at < piece ? size - at : piece;
        if (ms_h2conn_input(c, data + at, n) < 0) break;
        handle(c, server);
    }
    handle(c, server);
    ms_h2conn_free(c);
    return 0;
}
