#include "ws_client.h"
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <string.h>
#include "ms_rt/chars.h"
#include "ws.h"

#define LITERAL(text) ms_bytes_of((const uint8_t *)(text), sizeof(text) - 1)

int ms_ws_client_key(char out[MS_WS_KEY_LEN + 1]) {
    unsigned char nonce[16];
    if (RAND_bytes(nonce, sizeof nonce) != 1) return -1;
    return EVP_EncodeBlock((unsigned char *)out, nonce, sizeof nonce) == MS_WS_KEY_LEN ? 0 : -1;
}

static int write_field(char *dst, size_t cap, size_t *used, const char *name, MsBytes value) {
    return ms_h1_write_field(dst, cap, used, name, strlen(name), (const char *)value.ptr, value.len);
}

int ms_ws_write_upgrade(char *dst, size_t cap, size_t *used, MsBytes authority, MsBytes target, const char *key,
                        MsBytes protocols) {
    int rc = ms_h1_write_request_line(dst, cap, used, "GET", 3, (const char *)target.ptr, target.len);
    if (rc == 0) rc = write_field(dst, cap, used, "Host", authority);
    if (rc == 0) rc = write_field(dst, cap, used, "Upgrade", LITERAL("websocket"));
    if (rc == 0) rc = write_field(dst, cap, used, "Connection", LITERAL("Upgrade"));
    if (rc == 0) rc = write_field(dst, cap, used, "Sec-WebSocket-Key", ms_bytes_of((const uint8_t *)key, MS_WS_KEY_LEN));
    if (rc == 0) rc = write_field(dst, cap, used, "Sec-WebSocket-Version", LITERAL("13"));
    if (rc == 0 && protocols.len > 0) rc = write_field(dst, cap, used, "Sec-WebSocket-Protocol", protocols);
    return rc;
}

static MsBytes field_value(const char *base, const MsH1Response *response, const char *name) {
    const MsH1Field *field = ms_h1_find_field(base, response->fields, response->nfields,
                                              ms_bytes_of((const uint8_t *)name, strlen(name)));
    if (field == NULL) return ms_bytes_of(NULL, 0);
    return ms_bytes_of((const uint8_t *)base + field->value.off, field->value.len);
}

int ms_ws_check_upgrade(const char *base, const MsH1Response *response, const char *key, const char **why) {
    if (response->status != 101) { *why = "the server did not switch protocols"; return -1; }
    if (!ms_ascii_equal_fold(field_value(base, response, "Upgrade"), LITERAL("websocket"))) {
        *why = "the response is missing Upgrade: websocket";
        return -1;
    }
    if (!ms_h1_value_has_token(field_value(base, response, "Connection"), LITERAL("upgrade"))) {
        *why = "the response is missing Connection: Upgrade";
        return -1;
    }
    char expected[29];
    const MsBytes accept = field_value(base, response, "Sec-WebSocket-Accept");
    if (ms_ws_accept_key(key, MS_WS_KEY_LEN, expected) != 0 || !ms_bytes_equal(accept, ms_bytes_of((const uint8_t *)expected, 28))) {
        *why = "the response has a wrong Sec-WebSocket-Accept";
        return -1;
    }
    return 0;
}
