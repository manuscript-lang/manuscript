/* Unit test for src/runtime/core/string_quote.c: escapes, UTF-8 pass-through, and the inline and heap results.
 * `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/string.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_string_quote.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

/* Whether quoting the `length` bytes at `text` gives exactly `want`. */
static bool quotes_to(const char *text, size_t length, const char *want) {
    MsStr s;
    MsStr out;
    msrt_string_from_bytes((const uint8_t *)text, length, &s);
    msrt_string_quote(&s, &out);
    const bool same = ms_str_len(&out) == strlen(want) && memcmp(ms_str_data(&out), want, strlen(want)) == 0;
    msrt_string_free(&out);
    msrt_string_free(&s);
    return same;
}

#define QUOTES_TO(text, want) quotes_to((text), strlen(text), (want))

int main(void) {
    CHECK(QUOTES_TO("", "\"\""));
    CHECK(QUOTES_TO("abc", "\"abc\""));
    CHECK(QUOTES_TO("say \"hi\"", "\"say \\\"hi\\\"\""));
    CHECK(QUOTES_TO("a\\b", "\"a\\\\b\""));
    CHECK(QUOTES_TO("l1\nl2\tc\r", "\"l1\\nl2\\tc\\r\""));
    CHECK(QUOTES_TO("\x01\x1f\x7f", "\"\\x01\\x1f\\x7f\""));
    CHECK(QUOTES_TO("\x0b\x0c", "\"\\x0b\\x0c\""));
    CHECK(quotes_to("a\0b", 3, "\"a\\x00b\""));
    /* UTF-8 and stray bytes pass through untouched. */
    CHECK(QUOTES_TO("h\xc3\xa9llo \xf0\x9f\x99\x82", "\"h\xc3\xa9llo \xf0\x9f\x99\x82\""));
    CHECK(QUOTES_TO("\xff", "\"\xff\""));
    /* Results at the inline limit (15 bytes) and past it. */
    CHECK(QUOTES_TO("abcdefghijklm", "\"abcdefghijklm\""));
    CHECK(QUOTES_TO("abcdefghijklmn", "\"abcdefghijklmn\""));
    CHECK(QUOTES_TO("abcdefghijklmno", "\"abcdefghijklmno\""));
    CHECK(QUOTES_TO("a long line of text that needs the heap\n", "\"a long line of text that needs the heap\\n\""));
    return puts("core_string_quote ok") < 0;
}
