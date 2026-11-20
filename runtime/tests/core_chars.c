/* Unit test for ms_rt/chars.h: every byte against its <ctype.h> or reference meaning in the C locale, and the
 * UTF-8 encoder against the decoder. `make c-test` builds it with ASan and UBSan. */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include "ms_rt/chars.h"
#include "ms_rt/utf8.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_chars.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

int main(void) {
    for (uint32_t value = 0; value < 256; value++) {
        const uint8_t b = (uint8_t)value;
        CHECK(ms_ascii_is_digit(b) == (isdigit(b) != 0));
        CHECK(ms_ascii_is_alpha(b) == (isalpha(b) != 0));
        CHECK(ms_ascii_is_alnum(b) == (isalnum(b) != 0));
        CHECK(ms_ascii_is_upper(b) == (isupper(b) != 0));
        CHECK(ms_ascii_is_lower(b) == (islower(b) != 0));
        CHECK(ms_ascii_is_hex(b) == (isxdigit(b) != 0));
        CHECK(ms_ascii_is_ident(b) == (isalnum(b) != 0 || b == '_'));
        CHECK(ms_ascii_to_lower(b) == (uint8_t)tolower(b));
        CHECK(ms_ascii_to_upper(b) == (uint8_t)toupper(b));
        uint32_t digit = 99;
        CHECK(ms_hex_digit_value(b, &digit) == ms_ascii_is_hex(b));
        CHECK(ms_ascii_is_hex(b) ? digit < 16 : digit == 99);
    }
    uint32_t digit = 0;
    CHECK(ms_hex_digit_value('a', &digit) && digit == 10);
    CHECK(ms_hex_digit_value('F', &digit) && digit == 15);
    CHECK(ms_ascii_equal_fold(ms_bytes_of((const uint8_t *)"HeLLo", 5), ms_bytes_of((const uint8_t *)"hello", 5)));
    CHECK(!ms_ascii_equal_fold(ms_bytes_of((const uint8_t *)"hello", 5), ms_bytes_of((const uint8_t *)"hellp", 5)));
    CHECK(!ms_ascii_equal_fold(ms_bytes_of((const uint8_t *)"hello", 5), ms_bytes_of((const uint8_t *)"hell", 4)));
    for (uint32_t scalar = 0; scalar <= 0x10FFFF; scalar++) {
        if (scalar >= 0xD800 && scalar <= 0xDFFF) {
            continue;
        }
        uint8_t out[4] = {0};
        const size_t width = ms_utf8_encode(scalar, out);
        const MsRune back = ms_utf8_decode(out, width);
        CHECK(back.rune == scalar && back.width == width);
        CHECK(!ms_utf8_is_continuation(out[0]));
        for (size_t i = 1; i < width; i++) {
            CHECK(ms_utf8_is_continuation(out[i]));
        }
    }
    puts("core_chars ok");
    return 0;
}
