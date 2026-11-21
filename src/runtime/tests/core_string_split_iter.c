/* Unit test for src/runtime/core/string_split_iter.c: the pieces a split loop sees, at one-byte, multi-byte and empty
 * separators, over inline and heap texts. `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/alloc.h"
#include "ms_rt/string.h"
#include "support/rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_string_split_iter.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static MsStr make(const char *text) {
    MsStr s;
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &s);
    return s;
}

/* Joins the pieces of splitting `text` at `separator` with '|', so a test compares one string. */
static void pieces_of(const char *text, const char *separator, char *joined, size_t capacity) {
    MsStr s = make(text);
    MsStr sep = make(separator);
    MsSplitIter *iter = msrt_string_split_iter(&s, &sep);
    size_t used = 0;
    MsStr piece;
    size_t count = 0;
    while (msrt_split_next(iter, &piece) != 0) {
        CHECK(used + ms_str_len(&piece) + 2 < capacity);
        if (count++ > 0) {
            joined[used++] = '|';
        }
        memcpy(joined + used, ms_str_data(&piece), ms_str_len(&piece));
        used += ms_str_len(&piece);
    }
    CHECK(msrt_split_next(iter, &piece) == 0); /* used up stays used up */
    joined[used] = '\0';
    MsObj *object = (MsObj *)iter; /* the iterator is an object: its header comes first */
    object->drop(object);
    msrt_string_free(&s);
    msrt_string_free(&sep);
}

static bool splits_to(const char *text, const char *separator, const char *want) {
    char joined[512];
    pieces_of(text, separator, joined, sizeof joined);
    return strcmp(joined, want) == 0;
}

int main(void) {
    CHECK(splits_to("a,b,c", ",", "a|b|c"));
    CHECK(splits_to("a,,b,", ",", "a||b|"));
    CHECK(splits_to(",", ",", "|"));
    CHECK(splits_to("", ",", ""));
    CHECK(splits_to("abc", ",", "abc"));
    CHECK(splits_to("a--b--c", "--", "a|b|c"));
    CHECK(splits_to("a---b", "--", "a|-b"));
    CHECK(splits_to("--", "--", "|"));
    CHECK(splits_to("h\xc3\xa9llo w\xc3\xb6rld", " ", "h\xc3\xa9llo|w\xc3\xb6rld"));
    CHECK(splits_to("h\xc3\xa9\xf0\x9f\x99\x82z", "", "h|\xc3\xa9|\xf0\x9f\x99\x82|z"));
    CHECK(splits_to("", "", ""));
    CHECK(splits_to("a\xffz", "", "a|\xff|z")); /* a stray byte is one piece */
    /* A heap text and a piece longer than an inline string, which is a view of the text. */
    CHECK(splits_to("a rather long first field;second;a rather long third field", ";",
                    "a rather long first field|second|a rather long third field"));
    return puts("core_string_split_iter ok") < 0;
}
