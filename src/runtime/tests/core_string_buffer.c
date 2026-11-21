/* Unit test for src/runtime/core/string_buffer.c: the text builder at every result kind (empty, one byte, inline,
 * heap, ASCII and not) and across growth. `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/string.h"
#include "support/rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_string_buffer.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static MsStr make(const char *text) {
    MsStr s;
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &s);
    return s;
}

static bool is(const MsStr *s, const char *text) {
    return ms_str_len(s) == strlen(text) && memcmp(ms_str_data(s), text, strlen(text)) == 0;
}

static void test_sizes(void) {
    const char *parts[] = {"", "a", "ab", "fifteen-bytes!!", "sixteen-bytes!!!", "caf\xc3\xa9 and more than enough text to make a heap block"};
    for (size_t i = 0; i < sizeof parts / sizeof *parts; i++) {
        MsStrBuf *buffer = msrt_strbuf_new();
        MsStr part = make(parts[i]);
        MsStr result;
        msrt_strbuf_push(buffer, &part);
        msrt_strbuf_finish(buffer, &result);
        CHECK(is(&result, parts[i]));
        msrt_string_free(&result);
        msrt_string_free(&part);
    }
}

static void test_growth(void) {
    MsStrBuf *buffer = msrt_strbuf_new();
    MsStr piece = make("0123456789");
    for (int i = 0; i < 300; i++) {
        msrt_strbuf_push(buffer, &piece);
    }
    MsStr result;
    msrt_strbuf_finish(buffer, &result);
    CHECK(ms_str_len(&result) == 3000);
    for (size_t i = 0; i < 3000; i++) {
        CHECK(ms_str_data(&result)[i] == (uint8_t)('0' + i % 10));
    }
    msrt_string_free(&result);
    msrt_string_free(&piece);
}

static void test_slack_is_given_back(void) {
    MsStrBuf *buffer = msrt_strbuf_new();
    MsStr big = make("a block of text that is long enough to need a heap allocation of its own");
    MsStr result;
    for (int i = 0; i < 20; i++) {
        msrt_strbuf_push(buffer, &big);
    }
    msrt_strbuf_finish(buffer, &result);
    CHECK(ms_str_len(&result) == 20 * ms_str_len(&big));
    msrt_string_free(&result);
    msrt_string_free(&big);
}

int main(void) {
    test_sizes();
    test_growth();
    test_slack_is_given_back();
    puts("core_string_buffer: ok");
    return 0;
}
