/* Unit test for src/runtime/core/string.c; `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/string.h"
#include "ms_rt/utf8.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_string.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

/* A static string over `text`. */
static MsStr lit(const char *text) {
    MsStr s = {.bytes = (const uint8_t *)text, .tagged = strlen(text) | (UINT64_C(1) << 63)};
    return s;
}

/* An inline string of up to 15 bytes: the bytes in the value's own two words, length in bits 56..59. */
static MsStr inl(const char *text) {
    size_t n = strlen(text);
    uint8_t raw[16] = {0};
    memcpy(raw, text, n);
    MsStr s;
    memcpy(&s.ptr_word, raw, 8);
    uint64_t hi = 0;
    memcpy(&hi, raw + 8, 8);
    s.tagged = hi | (UINT64_C(1) << 62) | ((uint64_t)n << MS_STR_INLINE_SHIFT);
    return s;
}

int main(void) {
    /* The vectors core_hash.c also asserts for msrt_hash_bytes. */
    struct { const char *text; int64_t hash; } vectors[] = {
        {"", 5637604647281345049LL},
        {"a", -4589632175014895841LL},
        {"hello", -2768413155067229152LL},
        {"123456789012345", 1963792452095667305LL},
        {"1234567890123456", 6017223085291776624LL},
        {"The quick brown fox jumps over the lazy dog", 5716930301217669884LL},
    };
    for (size_t i = 0; i < sizeof vectors / sizeof vectors[0]; i++) {
        MsStr s = lit(vectors[i].text);
        CHECK(msrt_string_hash(&s) == vectors[i].hash);
        if (strlen(vectors[i].text) <= MS_STR_INLINE_MAX) {
            MsStr t = inl(vectors[i].text);
            CHECK(msrt_string_hash(&t) == vectors[i].hash);
            CHECK(msrt_string_eq(&s, &t) == 1);
        }
    }
    const char *words[] = {"", "a", "ab", "abc", "abcd", "abcdefg", "abcdefgh", "abcdefghijklmno", "abcdefghijklmnop", "abcdefghijklmnopq", "b", "ba"};
    size_t count = sizeof words / sizeof words[0];
    for (size_t i = 0; i < count; i++) {
        for (size_t j = 0; j < count; j++) {
            MsStr a = lit(words[i]), b = lit(words[j]);
            int expect = strcmp(words[i], words[j]);
            expect = expect < 0 ? -1 : expect > 0 ? 1 : 0;
            CHECK(msrt_string_compare(&a, &b) == expect);
            CHECK(msrt_string_eq(&a, &b) == (expect == 0));
            if (strlen(words[i]) <= 15 && strlen(words[j]) <= 15) {
                MsStr x = inl(words[i]), y = inl(words[j]);
                CHECK(msrt_string_compare(&x, &y) == expect);
                CHECK(msrt_string_compare(&x, &b) == expect);
                CHECK(msrt_string_eq(&x, &y) == (expect == 0));
            }
            size_t la = strlen(words[i]), lb = strlen(words[j]);
            CHECK(msrt_string_starts_with(&a, &b) == (lb <= la && strncmp(words[i], words[j], lb) == 0));
            CHECK(msrt_string_ends_with(&a, &b) == (lb <= la && strcmp(words[i] + la - lb, words[j]) == 0));
        }
    }
    MsStr empty = lit(""), nul = lit("a");
    CHECK(msrt_string_is_empty(&empty) == 1 && msrt_string_is_empty(&nul) == 0);
    CHECK(msrt_string_length(&nul) == 1);
    /* An inline string that continues with a NUL byte is longer than its prefix. */
    MsStr p = inl("ab"), q = inl("ab");
    q.tagged += UINT64_C(1) << MS_STR_INLINE_SHIFT; /* "ab\0" */
    CHECK(msrt_string_compare(&p, &q) == -1 && msrt_string_compare(&q, &p) == 1 && msrt_string_eq(&p, &q) == 0);
    /* Scalars: counted without the ASCII flag, taken at byte offsets. */
    MsStr mixed = lit("h\xc3\xa9llo \xf0\x9f\x98\x80");
    CHECK(msrt_string_scalar_length(&mixed) == 7 && msrt_string_length(&mixed) == 11);
    CHECK(msrt_string_char_width(&mixed, 0) == 1 && msrt_string_char_width(&mixed, 1) == 2 && msrt_string_char_width(&mixed, 7) == 4);
    CHECK(msrt_string_scalar_at_byte(&mixed, 1) == 0xE9 && msrt_string_scalar_at_byte(&mixed, 7) == 0x1F600);
    CHECK(msrt_string_scalar_step(&mixed, 7) == ((0x1F600 << 3) | 4));
    CHECK(msrt_string_scalar_at_byte(&mixed, 11) == 0xFFFD && msrt_string_char_width(&mixed, -1) == 1);
    MsStr ascii = inl("padded");
    CHECK(msrt_string_scalar_length(&ascii) == 6);
    MsStr flagged = lit("plain");
    flagged.tagged |= MS_STR_ASCII;
    CHECK(msrt_string_scalar_length(&flagged) == 5);
    /* Invalid sequences decode as U+FFFD with width 1, as in crates/ms-rt/src/utf8.rs. */
    const uint8_t bad[][4] = {{0xFF}, {0xC3}, {0xC0, 0x80}, {0xE0, 0x80, 0x80}, {0xED, 0xA0, 0x80}, {0xF4, 0x90, 0x80, 0x80}, {0xF0, 0x80, 0x80, 0x80}};
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        MsRune r = ms_utf8_decode(bad[i], bad[i][0] == 0xFF || bad[i][0] == 0xC3 ? 1 : (bad[i][0] == 0xC0 ? 2 : (bad[i][0] < 0xF0 ? 3 : 4)));
        CHECK(r.rune == MS_RUNE_ERROR && r.width == 1);
    }
    const uint8_t good[] = {0xED, 0x9F, 0xBF, 0xF4, 0x8F, 0xBF, 0xBF};
    CHECK(ms_utf8_decode(good, 3).rune == 0xD7FF && ms_utf8_decode(good + 3, 4).rune == 0x10FFFF);
    CHECK(ms_utf8_count((const uint8_t *)"a\xff" "b\xc3", 4) == 4);
    puts("core_string: ok");
    return 0;
}
