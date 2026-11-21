/* Fuzz harness for src/runtime/net/http1.c. Input: byte 0 picks the head limit, byte 1 the field capacity, the rest is
   fed to the request parser as wire bytes, then split into name and value for the response writers. The harness
   aborts on a broken invariant; ASan and UBSan catch memory errors. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "../net/http1.h"

#define REQUIRE(c) do { if (!(c)) abort(); } while (0)

static void check_parse(const char *text, size_t len, size_t limit, uint32_t cap) {
    MsH1Field *fields = malloc((cap ? cap : 1) * sizeof *fields);
    MsH1Request r;
    memset(&r, 0, sizeof r);
    r.fields = fields;
    int rc = ms_h1_parse_request(text, len, limit, &r, cap);
    REQUIRE(rc == MS_H1_PARTIAL || rc == MS_H1_COMPLETE || rc == MS_H1_BAD);
    if (rc == MS_H1_COMPLETE) {
        REQUIRE(r.head_len <= len && r.nfields <= cap);
        REQUIRE((uint64_t)r.target.off + r.target.len <= r.head_len);
        for (uint32_t i = 0; i < r.nfields; i++) {
            REQUIRE((uint64_t)fields[i].name.off + fields[i].name.len <= r.head_len);
            REQUIRE((uint64_t)fields[i].value.off + fields[i].value.len <= r.head_len);
        }
        /* the head alone parses to the same head: a request does not depend on bytes after it */
        MsH1Request again;
        memset(&again, 0, sizeof again);
        again.fields = fields;
        char *exact = malloc(r.head_len ? r.head_len : 1);
        memcpy(exact, text, r.head_len);
        REQUIRE(ms_h1_parse_request(exact, r.head_len, limit, &again, cap) == MS_H1_COMPLETE);
        REQUIRE(again.head_len == r.head_len && again.nfields == r.nfields);
        free(exact);
    } else if (rc == MS_H1_BAD) {
        REQUIRE(r.status >= 400 && r.status < 600);
    }
    free(fields);
}

static void check_writers(const uint8_t *d, size_t n, size_t split) {
    const char *name = (const char *)d, *value = (const char *)d + split;
    size_t name_len = split, value_len = n - split;
    size_t cap = n + 64, used = 0;
    char *dst = malloc(cap);
    int rc = ms_h1_write_field(dst, cap, &used, name, name_len, value, value_len);
    REQUIRE(rc == 0 || rc == -1 || rc == -2);
    REQUIRE(used <= cap);
    if (rc == 0) { /* exactly one line: the only CRLF is the last two bytes */
        REQUIRE(used >= 2 && dst[used - 2] == '\r' && dst[used - 1] == '\n');
        for (size_t i = 0; i + 2 < used; i++) REQUIRE(dst[i] != '\r' && dst[i] != '\n');
    } else if (rc == -2) {
        REQUIRE(used == 0);
    }
    used = 0;
    rc = ms_h1_write_chunk(dst, cap, &used, value, value_len);
    REQUIRE((rc == 0 || rc == -1) && used <= cap);
    used = 0;
    rc = ms_h1_write_status(dst, cap, &used, d[0] & 1, 100 + (n % 900), name, name_len);
    REQUIRE(used <= cap);
    free(dst);
    /* a destination that is too small must refuse and leave `used` alone */
    used = 0;
    char tiny[4];
    rc = ms_h1_write_field(tiny, sizeof tiny, &used, name, name_len, value, value_len);
    REQUIRE(rc != 0 ? used == 0 : used <= sizeof tiny);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 2) return 0;
    static const size_t limits[] = {16, 64, 256, 1024, 8192, 1 << 20, 0};
    size_t limit = limits[data[0] % (sizeof limits / sizeof *limits)];
    uint32_t cap = data[1] % 33;
    const uint8_t *body = data + 2;
    size_t n = size - 2;
    check_parse((const char *)body, n, limit, cap);
    /* every prefix: no crash on a partial read, and a COMPLETE one never needs more bytes than it was given */
    for (size_t k = 0; k < n && k < 512; k += 1 + n / 64) check_parse((const char *)body, k, limit, cap);
    if (n) {
        /* a short name from the input (usually refused as a non-token) and a fixed valid name with the whole input as value */
        check_writers(body, n, body[0] % (n < 8 ? n : 8));
        uint8_t *named = malloc(n + 1);
        named[0] = 'X';
        memcpy(named + 1, body, n);
        check_writers(named, n + 1, 1);
        free(named);
    }
    return 0;
}
