/* The @std/data/encoding natives (src/runtime/std/encoding.c): the RFC 4648 vectors, strict rejections, the order of error
 * checks (budget, shape, size, symbols) and ASCII85. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/encoding.h"
#include "ms_rt/strbuild.h"
#include "fake_rt.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

enum { NO_LIMIT = 0, HAS_LIMIT = 1, STD = 0, URL = 1 };

static MsStr text_of(const char *text) {
    return (MsStr){.bytes = (const uint8_t *)text, .tagged = MS_STR_STATIC | strlen(text)};
}

static bool str_is(const MsStr *s, const char *want) {
    return ms_str_len(s) == strlen(want) && memcmp(ms_str_data(s), want, strlen(want)) == 0;
}

static void str_free(MsStr *s) {
    if ((s->tagged >> 62) == 0) {
        free(s->ptr_word);
    }
}

static bool bytes_are(const MsVec *v, const char *want) { return v->len == strlen(want) && (v->len == 0 || memcmp(v->ptr, want, v->len) == 0); }

/* Decodes `text` and checks the status and, on success, the bytes. */
static void expect_base64(const char *text, int url, int has_max, int64_t max, uint8_t status, const char *want) {
    const MsStr in = text_of(text);
    MsVec out = {0};
    const uint8_t got = msstd_encoding_base64_decode(&in, (uint8_t)url, (uint8_t)has_max, max, &out);
    CHECK(got == status);
    CHECK(status != STATUS_OK || bytes_are(&out, want));
    CHECK(status == STATUS_OK || out.len == 0);
    free(out.ptr);
}

static void expect_unpadded(const char *text, int url, int has_max, int64_t max, uint8_t status, const char *want) {
    const MsStr in = text_of(text);
    MsVec out = {0};
    const uint8_t got = msstd_encoding_base64_decode_unpadded(&in, (uint8_t)url, (uint8_t)has_max, max, &out);
    CHECK(got == status);
    CHECK(status != STATUS_OK || bytes_are(&out, want));
    free(out.ptr);
}

static void expect_base32(const char *text, int hex, int padded, int has_max, int64_t max, uint8_t status, const char *want) {
    const MsStr in = text_of(text);
    MsVec out = {0};
    const uint8_t got = msstd_encoding_base32_decode(&in, (uint8_t)hex, (uint8_t)padded, (uint8_t)has_max, max, &out);
    CHECK(got == status);
    CHECK(status != STATUS_OK || bytes_are(&out, want));
    free(out.ptr);
}

static void expect_hex(const char *text, int has_max, int64_t max, uint8_t status, const char *want) {
    const MsStr in = text_of(text);
    MsVec out = {0};
    const uint8_t got = msstd_encoding_hex_decode(&in, (uint8_t)has_max, max, &out);
    CHECK(got == status);
    CHECK(status != STATUS_OK || bytes_are(&out, want));
    free(out.ptr);
}

static void expect_ascii85(const char *text, int has_max, int64_t max, uint8_t status, const char *want) {
    const MsStr in = text_of(text);
    MsVec out = {0};
    const uint8_t got = msstd_encoding_ascii85_decode(&in, (uint8_t)has_max, max, &out);
    CHECK(got == status);
    CHECK(status != STATUS_OK || bytes_are(&out, want));
    free(out.ptr);
}

static void test_base64(void) {
    static const char *const raw[] = {"", "f", "fo", "foo", "foob", "fooba", "foobar"};
    static const char *const padded[] = {"", "Zg==", "Zm8=", "Zm9v", "Zm9vYg==", "Zm9vYmE=", "Zm9vYmFy"};
    for (size_t i = 0; i < 7; i++) {
        char bytes[8];
        memcpy(bytes, raw[i], strlen(raw[i]) + 1);
        const MsVec data = {bytes, strlen(raw[i]), strlen(raw[i])};
        MsStr out = {0};
        msstd_encoding_base64_encode(&data, STD, &out);
        CHECK(str_is(&out, padded[i]));
        str_free(&out);
        msstd_encoding_base64_encode_unpadded(&data, STD, &out);
        char bare[16];
        snprintf(bare, sizeof bare, "%s", padded[i]);
        bare[strcspn(bare, "=")] = 0;
        CHECK(str_is(&out, bare));
        str_free(&out);
        expect_base64(padded[i], STD, NO_LIMIT, 0, STATUS_OK, raw[i]);
        expect_unpadded(bare, STD, NO_LIMIT, 0, STATUS_OK, raw[i]);
    }
    char fbff[] = {(char)0xfb, (char)0xff};
    const MsVec data = {fbff, 2, 2};
    MsStr out = {0};
    msstd_encoding_base64_encode(&data, STD, &out);
    CHECK(str_is(&out, "+/8="));
    msstd_encoding_base64_encode(&data, URL, &out);
    CHECK(str_is(&out, "-_8="));
    expect_base64("-_8=", URL, NO_LIMIT, 0, STATUS_OK, "\xfb\xff");
    expect_base64("-_8=", STD, NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_base64("+AAA", URL, NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    // Strictness: length, padding, trailing bits, interior padding, whitespace.
    for (const char *const *bad = (const char *const[]){"Zg", "Zh==", "Zm9=", "=AAA", "A=AA", "AA=A", "AA==AAAA", "Zm9 v", "\xc3\xa9" "AA", NULL}; *bad != NULL; bad++) {
        expect_base64(*bad, STD, NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    }
    // Whitespace is judged before the budget, the alphabet after it.
    expect_base64("AA A", STD, HAS_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_base64("!!!!", STD, HAS_LIMIT, 0, STATUS_LIMIT_EXCEEDED, "");
    expect_base64("Zm9vYg==", STD, HAS_LIMIT, 3, STATUS_LIMIT_EXCEEDED, "");
    expect_base64("Zm9vYg==", STD, HAS_LIMIT, 4, STATUS_OK, "foob");
    expect_base64("Zg==", STD, HAS_LIMIT, -1, STATUS_INVALID_INPUT, "");
    // Unpadded: a lone symbol, padding, trailing bits; the budget precedes the alphabet.
    expect_unpadded("Zh", STD, NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_unpadded("Z", STD, NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_unpadded("Zg==", STD, NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_unpadded("-_8", URL, NO_LIMIT, 0, STATUS_OK, "\xfb\xff");
    for (int64_t max = 0; max < 3; max++) {
        expect_unpadded("AA==", STD, HAS_LIMIT, max, STATUS_LIMIT_EXCEEDED, "");
    }
    expect_unpadded("AA==", STD, HAS_LIMIT, 3, STATUS_INVALID_DATA, "");
    expect_unpadded("A", STD, HAS_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_unpadded("!!!!", STD, HAS_LIMIT, 0, STATUS_LIMIT_EXCEEDED, "");
    expect_unpadded("!!!!", STD, HAS_LIMIT, 3, STATUS_INVALID_DATA, "");
    expect_unpadded("Zg", STD, HAS_LIMIT, 1, STATUS_OK, "f");
    expect_unpadded("Zg", STD, HAS_LIMIT, -1, STATUS_INVALID_INPUT, "");
    str_free(&out);
}

static void test_base32(void) {
    static const struct {
        const char *raw, *std, *hex;
    } vectors[] = {{"", "", ""}, {"f", "MY======", "CO======"}, {"fo", "MZXQ====", "CPNG===="},
                   {"foo", "MZXW6===", "CPNMU==="}, {"foob", "MZXW6YQ=", "CPNMUOG="},
                   {"fooba", "MZXW6YTB", "CPNMUOJ1"}, {"foobar", "MZXW6YTBOI======", "CPNMUOJ1E8======"}};
    for (size_t i = 0; i < sizeof vectors / sizeof vectors[0]; i++) {
        char bytes[8];
        memcpy(bytes, vectors[i].raw, strlen(vectors[i].raw) + 1);
        const MsVec data = {bytes, strlen(vectors[i].raw), strlen(vectors[i].raw)};
        for (int hex = 0; hex < 2; hex++) {
            const char *want = hex ? vectors[i].hex : vectors[i].std;
            char bare[24];
            snprintf(bare, sizeof bare, "%s", want);
            bare[strcspn(bare, "=")] = 0;
            MsStr out = {0};
            msstd_encoding_base32_encode(&data, (uint8_t)hex, 1, &out);
            CHECK(str_is(&out, want));
            str_free(&out);
            msstd_encoding_base32_encode(&data, (uint8_t)hex, 0, &out);
            CHECK(str_is(&out, bare));
            str_free(&out);
            expect_base32(want, hex, 1, NO_LIMIT, 0, STATUS_OK, vectors[i].raw);
            expect_base32(bare, hex, 0, NO_LIMIT, 0, STATUS_OK, vectors[i].raw);
        }
    }
    for (const char *const *bad = (const char *const[]){"M", "MY=====", "MY======MY======", "my======", "MZ======", "M=Y=====", NULL}; *bad != NULL; bad++) {
        expect_base32(*bad, 0, 1, NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    }
    expect_base32("MY", 0, 0, NO_LIMIT, 0, STATUS_OK, "f");
    expect_base32("MY======", 0, 0, NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_base32("MY", 0, 1, NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_base32("MZXW6===", 0, 1, HAS_LIMIT, 2, STATUS_LIMIT_EXCEEDED, "");
    expect_base32("M=Y=====", 0, 1, HAS_LIMIT, 0, STATUS_INVALID_DATA, "");
}

static void test_hex(void) {
    uint8_t all[256];
    for (size_t i = 0; i < 256; i++) all[i] = (uint8_t)i;
    const MsVec data = {all, 256, 256};
    MsStr text = {0};
    msstd_encoding_hex_encode(&data, &text);
    CHECK(ms_str_len(&text) == 512 && memcmp(ms_str_data(&text), "00010203", 8) == 0);
    MsVec back = {0};
    CHECK(msstd_encoding_hex_decode(&text, NO_LIMIT, 0, &back) == STATUS_OK && back.len == 256 && memcmp(back.ptr, all, 256) == 0);
    free(back.ptr);
    str_free(&text);
    expect_hex("", NO_LIMIT, 0, STATUS_OK, "");
    expect_hex("6A6b", NO_LIMIT, 0, STATUS_OK, "jk");
    // The budget precedes parity, and parity precedes the digits.
    expect_hex("zz", HAS_LIMIT, 0, STATUS_LIMIT_EXCEEDED, "");
    expect_hex("abc", HAS_LIMIT, 1, STATUS_INVALID_DATA, "");
    expect_hex("zz", NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_hex("0g", NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_hex("00 0", NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_hex("00", HAS_LIMIT, -1, STATUS_INVALID_INPUT, "");
}

static void test_ascii85(void) {
    char bytes[8] = {0};
    const MsVec zeros = {bytes, 4, 4};
    MsStr out = {0};
    msstd_encoding_ascii85_encode(&zeros, &out);
    CHECK(str_is(&out, "z"));
    const MsVec partial = {bytes, 2, 2};
    msstd_encoding_ascii85_encode(&partial, &out);
    CHECK(str_is(&out, "!!!"));
    char hello[] = "hello";
    const MsVec word = {hello, 5, 5};
    msstd_encoding_ascii85_encode(&word, &out);
    CHECK(str_is(&out, "BOu!rDZ"));
    str_free(&out);
    expect_ascii85("BOu!rDZ", NO_LIMIT, 0, STATUS_OK, "hello");
    expect_ascii85("BO u!\nrDZ", NO_LIMIT, 0, STATUS_OK, "hello");
    expect_ascii85("", NO_LIMIT, 0, STATUS_OK, "");
    expect_ascii85("B", NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_ascii85("Bz", NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_ascii85("v", NO_LIMIT, 0, STATUS_INVALID_DATA, "");
    expect_ascii85("s8W-\"", NO_LIMIT, 0, STATUS_INVALID_DATA, ""); /* a group past 2^32 - 1 */
    // The budget is spent group by group, before later bytes are read.
    expect_ascii85("zzzz!", HAS_LIMIT, 4, STATUS_LIMIT_EXCEEDED, "");
    {
        const MsStr zz = text_of("zz");
        MsVec decoded = {0};
        CHECK(msstd_encoding_ascii85_decode(&zz, HAS_LIMIT, 8, &decoded) == STATUS_OK && decoded.len == 8);
        free(decoded.ptr);
    }
    expect_ascii85("BOu!rDZ", HAS_LIMIT, -1, STATUS_INVALID_INPUT, "");
}

int main(void) {
    test_base64();
    test_base32();
    test_hex();
    test_ascii85();
    puts(failures == 0 ? "std_encoding: ok" : "std_encoding: FAILED");
    return failures == 0 ? 0 : 1;
}
