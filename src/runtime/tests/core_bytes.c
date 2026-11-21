/* Unit test for src/runtime/core/bytes.c; `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/bytes.h"
#include "ms_rt/list.h"
#include "rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_bytes.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static MsList make(const char *text) {
    MsList b;
    msrt_list_new(&b);
    for (const char *p = text; *p != 0; p++) {
        msrt_bytes_append(&b, (unsigned char)*p);
    }
    return b;
}

static bool is(const MsList *b, const char *text) { return b->len == strlen(text) && (b->len == 0 || memcmp(b->ptr, text, b->len) == 0); }

/* The value a faulting body works on is the test's, so the test frees it after the jump. */
static MsList subject;

static void body_with_value_bad_value(void) {
    MsList out;
    msrt_bytes_with_value(&subject, 0, 300, &out);
}

static void body_append_bad(void) { msrt_bytes_append(&subject, -1); }

static void body_view_bad(void) {
    MsList out;
    msrt_bytes_view(&subject, 2, 9, &out);
}

static bool faults(void (*body)(void)) {
    jmp_buf jump;
    ms_test_fault = &jump;
    if (setjmp(jump) == 0) {
        body();
        ms_test_fault = NULL;
        return false;
    }
    ms_test_fault = NULL;
    return true;
}

int main(void) {
    MsList hay = make("the quick brown fox, the lazy dog");
    MsList the = make("the");
    MsList none = make("cat");
    MsList empty = make("");
    int64_t at = -1;
    CHECK(msrt_bytes_contains(&hay, &the) && !msrt_bytes_contains(&hay, &none) && msrt_bytes_contains(&hay, &empty));
    CHECK(msrt_bytes_index_of(&hay, &the, &at) && at == 0);
    CHECK(msrt_bytes_last_index_of(&hay, &the, &at) && at == 21);
    CHECK(msrt_bytes_last_index_of(&hay, &empty, &at) && at == (int64_t)hay.len);
    CHECK(!msrt_bytes_last_index_of(&hay, &none, &at));
    CHECK(msrt_bytes_index_of_byte(&hay, 'q', 0, &at) && at == 4);
    CHECK(msrt_bytes_index_of_byte(&hay, 't', 1, &at) && at == 21);
    CHECK(!msrt_bytes_index_of_byte(&hay, 'q', 5, &at) && !msrt_bytes_index_of_byte(&hay, 256, 0, &at));
    CHECK(msrt_bytes_starts_with(&hay, &the) && !msrt_bytes_ends_with(&hay, &the));
    CHECK(msrt_bytes_get(&hay, -1, 0, 0) == 'g' && msrt_bytes_get(&hay, 99, 1, 7) == 7);
    MsList out;
    CHECK(msrt_bytes_slice(&hay, 4, 9, &out) == MS_STATUS_OK && is(&out, "quick"));
    msrt_bytes_drop(&out);
    CHECK(msrt_bytes_slice(&hay, 9, 4, &out) == MS_STATUS_OUT_OF_RANGE);
    msrt_bytes_view(&hay, 4, 9, &out);
    CHECK(out.cap == 0 && is(&out, "quick"));
    msrt_bytes_drop(&out);
    msrt_bytes_reversed(&the, &out);
    CHECK(is(&out, "eht"));
    msrt_bytes_drop(&out);
    msrt_bytes_with_value(&the, -1, 'y', &out);
    CHECK(is(&out, "thy"));
    msrt_bytes_drop(&out);
    MsList sep = make(", ");
    msrt_bytes_split(&hay, &sep, &out);
    CHECK(out.len == 2);
    MsList joined;
    msrt_bytes_join(&out, &joined);
    CHECK(is(&joined, "the quick brown foxthe lazy dog"));
    msrt_bytes_drop(&joined);
    msrt_list_drop(&out, &msrt_desc_bytes);
    msrt_bytes_split(&the, &empty, &out);
    CHECK(out.len == 3);
    msrt_list_drop(&out, &msrt_desc_bytes);
    msrt_bytes_split(&empty, &sep, &out);
    CHECK(out.len == 1);
    msrt_list_drop(&out, &msrt_desc_bytes);
    msrt_bytes_concat(&the, &none, &out);
    CHECK(is(&out, "thecat"));
    CHECK(msrt_bytes_eq(&out, &out) && !msrt_bytes_eq(&out, &the));
    msrt_bytes_extend(&out, &the);
    CHECK(is(&out, "thecatthe"));
    msrt_bytes_drop(&out);
    MsList codes = make("\x01\x02\x03\x04\x05\x06\x07\x08");
    int64_t word = 0;
    CHECK(msrt_bytes_read_word(&codes, 0, 4, 1, &word) == MS_STATUS_OK && word == 0x04030201);
    CHECK(msrt_bytes_read_word(&codes, 0, 4, 0, &word) == MS_STATUS_OK && word == 0x01020304);
    CHECK(msrt_bytes_read_word(&codes, 0, 8, 0, &word) == MS_STATUS_OK && word == 0x0102030405060708);
    CHECK(msrt_bytes_read_word(&codes, 1, 2, 0, &word) == MS_STATUS_OK && word == 0x0203);
    CHECK(msrt_bytes_read_word(&codes, 7, 1, 1, &word) == MS_STATUS_OK && word == 8);
    CHECK(msrt_bytes_read_word(&codes, 5, 4, 1, &word) == MS_STATUS_OUT_OF_RANGE);
    CHECK(msrt_bytes_read_word(&codes, -1, 1, 1, &word) == MS_STATUS_OUT_OF_RANGE);
    CHECK(msrt_bytes_read_word(&codes, 0, 3, 1, &word) == MS_STATUS_OUT_OF_RANGE);
    subject = make("abc");
    CHECK(faults(body_with_value_bad_value) && strcmp(ms_test_fault_message, "Bytes.with_value: value must be between 0 and 255, found 300") == 0);
    CHECK(faults(body_append_bad));
    CHECK(faults(body_view_bad) && strcmp(ms_test_fault_message, "Bytes.view: bounds 2..9 are outside a length of 3") == 0);
    msrt_bytes_drop(&subject);
    msrt_bytes_drop(&hay);
    msrt_bytes_drop(&the);
    msrt_bytes_drop(&none);
    msrt_bytes_drop(&empty);
    msrt_bytes_drop(&sep);
    msrt_bytes_drop(&codes);
    puts("core_bytes: ok");
    return 0;
}
