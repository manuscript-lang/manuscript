/* Unit test for src/runtime/core/string_iter.c: chars, lines, fields, scalar_values, from_scalars, to_bytes and
 * view_bytes at ASCII, multi-byte and malformed texts. `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/alloc.h"
#include "ms_rt/string.h"
#include "support/rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_string_iter.c:%d: %s\n", line, text);
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

/* The list holds exactly the `count` strings of `want`, in order; frees the list. */
static bool strings_are(MsVec *list, const char *const *want, size_t count) {
    bool same = list->len == count;
    MsStr *items = list->ptr;
    for (size_t i = 0; i < list->len; i++) {
        same = same && i < count && is(&items[i], want[i]);
        msrt_string_free(&items[i]);
    }
    if (list->ptr != NULL) {
        msrt_free(list->ptr);
    }
    return same;
}

#define STRINGS_ARE(list, ...) \
    strings_are(&(list), (const char *const[]){__VA_ARGS__}, sizeof((const char *const[]){__VA_ARGS__}) / sizeof(char *))

static void test_chars(void) {
    MsStr ascii = make("hello, world, a long enough text");
    MsStr mixed = make("a\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80");
    MsStr empty = make("");
    const uint8_t stray_bytes[] = {'x', 0xff, 'y'};
    MsStr stray;
    msrt_string_from_bytes(stray_bytes, sizeof stray_bytes, &stray);
    MsVec list;
    msrt_string_chars(&ascii, &list);
    CHECK(list.len == strlen("hello, world, a long enough text"));
    CHECK(is(&((MsStr *)list.ptr)[4], "o"));
    msrt_free(list.ptr);
    msrt_string_chars(&mixed, &list);
    CHECK(STRINGS_ARE(list, "a", "\xc3\xa9", "\xe2\x82\xac", "\xf0\x9f\x98\x80"));
    msrt_string_chars(&stray, &list);
    CHECK(STRINGS_ARE(list, "x", "\xef\xbf\xbd", "y"));
    msrt_string_chars(&empty, &list);
    CHECK(list.len == 0 && list.ptr == NULL);
    msrt_string_free(&ascii);
}

static void test_lines(void) {
    MsVec list;
    MsStr text = make("one\r\ntwo\n\nthree\r\nfour and a longer last line");
    msrt_string_lines(&text, &list);
    CHECK(STRINGS_ARE(list, "one", "two", "", "three", "four and a longer last line"));
    msrt_string_free(&text);
    text = make("a\nb\n");
    msrt_string_lines(&text, &list);
    CHECK(STRINGS_ARE(list, "a", "b"));
    msrt_string_free(&text);
    text = make("\r\n\r");
    msrt_string_lines(&text, &list);
    CHECK(STRINGS_ARE(list, "", "\r"));
    text = make("");
    msrt_string_lines(&text, &list);
    CHECK(list.len == 0);
}

static void test_fields(void) {
    MsVec list;
    MsStr text = make("  alpha\tbeta\n gamma\xc2\xa0" "delta\xe3\x80\x80" "epsilon  ");
    msrt_string_fields(&text, &list);
    CHECK(STRINGS_ARE(list, "alpha", "beta", "gamma", "delta", "epsilon"));
    msrt_string_free(&text);
    text = make(" \t\n ");
    msrt_string_fields(&text, &list);
    CHECK(list.len == 0);
    text = make("solo");
    msrt_string_fields(&text, &list);
    CHECK(STRINGS_ARE(list, "solo"));
}

static void test_scalars(void) {
    MsStr text = make("a\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80");
    MsVec values;
    msrt_string_scalar_values(&text, &values);
    const int64_t *scalars = values.ptr;
    CHECK(values.len == 4 && scalars[0] == 'a' && scalars[1] == 0xE9 && scalars[2] == 0x20AC && scalars[3] == 0x1F600);
    MsStr round_trip;
    CHECK(msrt_string_from_scalars(&values, &round_trip) == 0);
    CHECK(is(&round_trip, "a\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80"));
    msrt_string_free(&round_trip);
    msrt_free(values.ptr);
    int64_t bad[][2] = {{'a', -1}, {'a', 0x110000}, {'a', 0xD800}, {'a', 0xDFFF}};
    for (size_t i = 0; i < sizeof bad / sizeof *bad; i++) {
        MsVec list = {.ptr = bad[i], .len = 2, .cap = 2};
        CHECK(msrt_string_from_scalars(&list, &round_trip) == 1);
    }
    int64_t ascii[40];
    for (size_t i = 0; i < 40; i++) {
        ascii[i] = 'a' + (int64_t)(i % 26);
    }
    MsVec ascii_list = {.ptr = ascii, .len = 40, .cap = 40};
    CHECK(msrt_string_from_scalars(&ascii_list, &round_trip) == 0 && ms_str_len(&round_trip) == 40);
    msrt_string_free(&round_trip);
    MsVec none = {0};
    CHECK(msrt_string_from_scalars(&none, &round_trip) == 0 && ms_str_len(&round_trip) == 0);
    msrt_string_free(&text);
}

static void test_bytes(void) {
    MsStr text = make("bytes of \xc3\xa9, long enough to live on the heap");
    MsVec copy;
    msrt_string_to_bytes(&text, &copy);
    CHECK(copy.len == ms_str_len(&text) && copy.cap == copy.len && memcmp(copy.ptr, ms_str_data(&text), copy.len) == 0);
    CHECK(copy.ptr != ms_str_data(&text));
    msrt_free(copy.ptr);
    MsVec view;
    msrt_string_view_bytes(&text, &view);
    CHECK(view.len == ms_str_len(&text) && view.cap == 0 && view.ptr == ms_str_data(&text));
    MsStr empty = make("");
    msrt_string_to_bytes(&empty, &copy);
    CHECK(copy.len == 0 && copy.ptr == NULL);
    msrt_string_view_bytes(&empty, &view);
    CHECK(view.len == 0 && view.ptr == NULL && view.cap == 0);
    msrt_string_free(&text);
}

int main(void) {
    test_chars();
    test_lines();
    test_fields();
    test_scalars();
    test_bytes();
    puts("core_string_iter: ok");
    return 0;
}
