/* Unit tests for src/runtime/net/ws_client.c: the upgrade request, and the check of every way an answer can be wrong. */
#include <stdio.h>
#include <string.h>
#include "../net/http1.h"
#include "../net/ws.h"
#include "../net/ws_client.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)
#define LITERAL(text) ms_bytes_of((const uint8_t *)(text), sizeof(text) - 1)

/* Parses `answer` and checks it against `key`. */
static int check(const char *answer, const char *key, const char **why) {
    MsH1Response response; MsH1Field fields[8]; MsH1Reader reader;
    response.fields = fields;
    if (ms_h1_parse_response(&reader, answer, strlen(answer), 1 << 16, &response, 8, 0) != MS_H1_COMPLETE) return -2;
    return ms_ws_check_upgrade(answer, &response, key, why);
}

int main(void) {
    char key[MS_WS_KEY_LEN + 1], other[MS_WS_KEY_LEN + 1];
    CHECK(ms_ws_client_key(key) == 0 && strlen(key) == MS_WS_KEY_LEN);
    CHECK(ms_ws_client_key(other) == 0 && strcmp(key, other) != 0);

    char out[512]; size_t used = 0;
    const char *sample = "dGhlIHNhbXBsZSBub25jZQ==";
    CHECK(ms_ws_write_upgrade(out, sizeof out, &used, LITERAL("example.test:8080"), LITERAL("/chat?x=1"), sample, LITERAL("")) == 0);
    CHECK(ms_h1_write_head_end(out, sizeof out, &used) == 0);
    const char *want = "GET /chat?x=1 HTTP/1.1\r\nHost: example.test:8080\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                       "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n";
    CHECK(used == strlen(want) && !memcmp(out, want, used));
    used = 0;
    CHECK(ms_ws_write_upgrade(out, sizeof out, &used, LITERAL("h"), LITERAL("/"), sample, LITERAL("chat, superchat")) == 0);
    CHECK(strstr(out, "Sec-WebSocket-Protocol: chat, superchat\r\n") != NULL);
    used = 0;
    CHECK(ms_ws_write_upgrade(out, sizeof out, &used, LITERAL("h\r\nX: y"), LITERAL("/"), sample, LITERAL("")) == -2); /* header splitting */
    used = 0;
    CHECK(ms_ws_write_upgrade(out, sizeof out, &used, LITERAL("h"), LITERAL("/a b"), sample, LITERAL("")) == -2);
    used = 0;
    CHECK(ms_ws_write_upgrade(out, 40, &used, LITERAL("h"), LITERAL("/"), sample, LITERAL("")) == -1);

    /* the RFC's sample key and answer */
    const char *why = "";
    const char *good = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: WebSocket\r\nConnection: keep-alive, Upgrade\r\n"
                       "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n";
    CHECK(check(good, sample, &why) == 0);
    CHECK(check(good, key, &why) == -1 && strstr(why, "Sec-WebSocket-Accept") != NULL);
    CHECK(check("HTTP/1.1 200 OK\r\n\r\n", sample, &why) == -1 && strstr(why, "switch") != NULL);
    CHECK(check("HTTP/1.1 101 X\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n", sample, &why) == -1);
    CHECK(strstr(why, "Upgrade: websocket") != NULL);
    CHECK(check("HTTP/1.1 101 X\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n", sample, &why) == -1);
    CHECK(strstr(why, "Connection") != NULL);
    CHECK(check("HTTP/1.1 101 X\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n", sample, &why) == -1);

    /* negotiation: the subprotocol must be one offered, and deflate needs both no-context-takeover parameters */
    {
        const char *head = "HTTP/1.1 101 X\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                           "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n";
        char answer[512];
        MsH1Response response; MsH1Field fields[8]; MsH1Reader reader;
        MsWsAccepted accepted;
        snprintf(answer, sizeof answer, "%sSec-WebSocket-Protocol: chat\r\n\r\n", head);
        response.fields = fields;
        CHECK(ms_h1_parse_response(&reader, answer, strlen(answer), 1 << 16, &response, 8, 0) == MS_H1_COMPLETE);
        CHECK(ms_ws_client_accept(answer, &response, sample, LITERAL("other, chat"), &accepted, &why) == 0);
        CHECK(accepted.subprotocol.len == 4 && memcmp(accepted.subprotocol.ptr, "chat", 4) == 0 && !accepted.compress);
        CHECK(ms_ws_client_accept(answer, &response, sample, LITERAL("other"), &accepted, &why) == -1 && strstr(why, "not offered") != NULL);
        CHECK(ms_ws_client_accept(answer, &response, sample, LITERAL(""), &accepted, &why) == -1);
        snprintf(answer, sizeof answer, "%sSec-WebSocket-Extensions: x-other, Permessage-Deflate; client_no_context_takeover; "
                 "server_no_context_takeover=\"1\"\r\n\r\n", head);
        CHECK(ms_h1_parse_response(&reader, answer, strlen(answer), 1 << 16, &response, 8, 0) == MS_H1_COMPLETE);
        CHECK(ms_ws_client_accept(answer, &response, sample, LITERAL(""), &accepted, &why) == 0 && accepted.compress && accepted.subprotocol.len == 0);
        snprintf(answer, sizeof answer, "%sSec-WebSocket-Extensions: permessage-deflate; server_no_context_takeover\r\n\r\n", head);
        CHECK(ms_h1_parse_response(&reader, answer, strlen(answer), 1 << 16, &response, 8, 0) == MS_H1_COMPLETE);
        CHECK(ms_ws_client_accept(answer, &response, sample, LITERAL(""), &accepted, &why) == -1 && strstr(why, "compression") != NULL);
    }

    /* tokens and fields */
    CHECK(ms_h1_value_has_token(LITERAL(" keep-alive ,\tUPGRADE"), LITERAL("upgrade")));
    CHECK(!ms_h1_value_has_token(LITERAL("upgrades"), LITERAL("upgrade")));
    CHECK(!ms_h1_value_has_token(LITERAL(""), LITERAL("upgrade")));
    CHECK(!ms_h1_value_has_token(LITERAL(","), LITERAL("upgrade")));

    if (!failed) printf("ws client ok\n");
    return failed;
}
