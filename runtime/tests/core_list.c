/* Unit test for runtime/core/desc.c and list.c; `make c-test` builds it with ASan and UBSan. Faults, strings
 * and maps come from support/rt_stubs.c. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/desc.h"
#include "ms_rt/list.h"
#include "rt_calls.h"
#include "rt_stubs.h"

/* The two words of a string value; the runtime declares the type opaque to this layer. */
struct MsStr {
    uint64_t words[2];
};

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_list.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static const MsTypeDesc *const INT = &msrt_desc_int;
static const MsTypeDesc *const STR = &msrt_desc_string;
static const MsTypeDesc LIST_OF_INT = {.size = 24, .align = 8, .kind = MS_KIND_LIST, .inner0 = &msrt_desc_int};

static void push_int(MsList *list, int64_t value) { msrt_list_push(list, INT, (const uint8_t *)&value); }

static int64_t int_at(const MsList *list, size_t i) {
    int64_t value = 0;
    memcpy(&value, list->ptr + i * 8, sizeof value);
    return value;
}

static MsList ints(size_t count, const int64_t *values) {
    MsList list;
    msrt_list_new(&list);
    for (size_t i = 0; i < count; i++) {
        push_int(&list, values[i]);
    }
    return list;
}

static bool is_ints(const MsList *list, size_t count, const int64_t *values) {
    if (list->len != count) {
        return false;
    }
    for (size_t i = 0; i < count; i++) {
        if (int_at(list, i) != values[i]) {
            return false;
        }
    }
    return true;
}
#define IS_INTS(list, ...) is_ints(list, sizeof((int64_t[]){__VA_ARGS__}) / 8, (int64_t[]){__VA_ARGS__})

static MsStr make_string(const char *text) {
    MsStr s;
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &s);
    return s;
}

/* Runs `body` and reports whether it faulted (message and family in the rt_stubs globals). */
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

/* The lists a faulting body works on are the test's, so the test frees them after the jump. */
static MsList fixture;
static MsList replacement;

static void insert_out_of_range(void) {
    int64_t x = 9;
    msrt_list_insert(&fixture, INT, 3, (const uint8_t *)&x);
}

static void splice_bad_start(void) { msrt_list_splice(&fixture, INT, 5, 0, &replacement); }

static void at_without_default(void) { (void)msrt_list_at(&fixture, INT, -3, NULL); }

static void repeat_overflow(void) {
    MsList out;
    msrt_list_repeat(&fixture, INT, INT64_MAX, &out);
}

static void test_basic_edits(void) {
    MsList l = ints(0, NULL);
    for (int64_t i = 0; i < 10; i++) {
        push_int(&l, i);
    }
    CHECK(l.len == 10 && l.cap >= 10);
    int64_t v = 99;
    msrt_list_insert(&l, INT, 0, (const uint8_t *)&v);
    msrt_list_insert(&l, INT, -1, (const uint8_t *)&v); /* before the last element */
    msrt_list_insert(&l, INT, 12, (const uint8_t *)&v); /* at the end */
    CHECK(IS_INTS(&l, 99, 0, 1, 2, 3, 4, 5, 6, 7, 8, 99, 9, 99));
    msrt_list_remove(&l, INT, -1);
    msrt_list_remove(&l, INT, 0);
    msrt_list_swap(&l, INT, 0, -1);
    CHECK(IS_INTS(&l, 9, 1, 2, 3, 4, 5, 6, 7, 8, 99, 0));
    v = 7;
    msrt_list_set(&l, INT, 1, (const uint8_t *)&v);
    int64_t out = 0;
    msrt_list_replace(&l, INT, 2, (uint8_t *)&v, (uint8_t *)&out);
    CHECK(out == 2 && int_at(&l, 2) == 7);
    CHECK(msrt_list_pop(&l, INT, (uint8_t *)&out) == 1 && out == 0 && l.len == 10);
    msrt_list_reverse(&l, INT);
    CHECK(IS_INTS(&l, 99, 8, 7, 6, 5, 4, 3, 7, 7, 9));
    int64_t index = -1;
    v = 7;
    CHECK(msrt_list_index_of(&l, INT, (const uint8_t *)&v, &index) == 1 && index == 2);
    CHECK(msrt_list_last_index_of(&l, INT, (const uint8_t *)&v, &index) == 1 && index == 8);
    v = 1000;
    CHECK(msrt_list_contains(&l, INT, (const uint8_t *)&v) == 0);
    msrt_list_drop(&l, INT);
    CHECK(l.ptr == NULL && l.len == 0 && l.cap == 0);
    CHECK(msrt_list_pop(&l, INT, (uint8_t *)&out) == 0);
}

static void test_find_int_every_position(void) {
    MsList l = ints(0, NULL);
    for (int64_t i = 0; i < 37; i++) {
        push_int(&l, i * 3);
    }
    for (int64_t i = 0; i < 37; i++) {
        int64_t probe = i * 3;
        int64_t index = -1;
        CHECK(msrt_list_index_of(&l, INT, (const uint8_t *)&probe, &index) == 1 && index == i);
    }
    msrt_list_drop(&l, INT);
}

static void test_derived_lists(void) {
    MsList l = ints(5, (int64_t[]){10, 20, 30, 40, 50});
    MsList out;
    MsStr err;
    CHECK(msrt_list_slice(&l, INT, 1, -1, &out, &err) == MS_STATUS_OK && IS_INTS(&out, 20, 30, 40));
    msrt_string_free(&err);
    msrt_list_drop(&out, INT);
    CHECK(msrt_list_slice(&l, INT, 4, 2, &out, &err) == MS_STATUS_OUT_OF_RANGE);
    msrt_string_free(&err);
    CHECK(msrt_list_slice_view(&l, INT, 2, 4, &out, &err) == MS_STATUS_OK && out.cap == 0 && out.ptr == l.ptr + 16);
    msrt_string_free(&err);
    msrt_list_drop(&out, INT); /* a view frees nothing */
    msrt_list_take(&l, INT, 2, &out);
    CHECK(IS_INTS(&out, 10, 20));
    msrt_list_drop(&out, INT);
    msrt_list_drop_n(&l, INT, -3, &out);
    CHECK(out.len == 5);
    msrt_list_drop(&out, INT);
    msrt_list_drop_n(&l, INT, 4, &out);
    CHECK(IS_INTS(&out, 50));
    MsList b = ints(2, (int64_t[]){1, 2});
    MsList joined;
    msrt_list_concat(&out, &b, INT, &joined);
    CHECK(IS_INTS(&joined, 50, 1, 2));
    msrt_list_extend(&joined, INT, &b);
    CHECK(IS_INTS(&joined, 50, 1, 2, 1, 2));
    MsList repeated;
    msrt_list_repeat(&b, INT, 3, &repeated);
    CHECK(IS_INTS(&repeated, 1, 2, 1, 2, 1, 2));
    MsList reversed;
    msrt_list_reversed(&b, INT, &reversed);
    CHECK(IS_INTS(&reversed, 2, 1));
    msrt_list_drop(&out, INT);
    msrt_list_drop(&b, INT);
    msrt_list_drop(&joined, INT);
    msrt_list_drop(&repeated, INT);
    msrt_list_drop(&reversed, INT);
    msrt_list_drop(&l, INT);
}

static void test_splice_fill_copy_within(void) {
    MsList l = ints(6, (int64_t[]){0, 1, 2, 3, 4, 5});
    MsList r = ints(1, (int64_t[]){100});
    msrt_list_splice(&l, INT, 1, 3, &r);
    CHECK(IS_INTS(&l, 0, 100, 4, 5) && r.ptr == NULL);
    r = ints(3, (int64_t[]){7, 8, 9});
    msrt_list_splice(&l, INT, 4, 0, &r);
    CHECK(IS_INTS(&l, 0, 100, 4, 5, 7, 8, 9));
    int64_t fill = -1;
    msrt_list_fill(&l, INT, (const uint8_t *)&fill, 1, 3);
    CHECK(IS_INTS(&l, 0, -1, -1, 5, 7, 8, 9));
    msrt_list_copy_within(&l, INT, 0, 4, 7);
    CHECK(IS_INTS(&l, 7, 8, 9, 5, 7, 8, 9));
    msrt_list_copy_within(&l, INT, 5, 0, 5); /* clipped to the room after the target, overlapping */
    CHECK(IS_INTS(&l, 7, 8, 9, 5, 7, 7, 8));
    msrt_list_drop(&l, INT);
}

static void test_pieces(void) {
    MsList l = ints(5, (int64_t[]){1, 2, 3, 4, 5});
    MsList out;
    msrt_list_pieces(&l, INT, &LIST_OF_INT, 2, 2, 1, &out);
    CHECK(out.len == 3);
    const MsList *pieces = (const MsList *)(void *)out.ptr;
    CHECK(pieces[0].len == 2 && pieces[2].len == 1 && int_at(&pieces[2], 0) == 5);
    msrt_list_drop(&out, &LIST_OF_INT);
    msrt_list_pieces(&l, INT, &LIST_OF_INT, 3, 1, 0, &out); /* windows */
    CHECK(out.len == 3);
    msrt_list_drop(&out, &LIST_OF_INT);
    msrt_list_pieces(&l, INT, &LIST_OF_INT, 0, 1, 1, &out);
    CHECK(out.len == 0);
    msrt_list_drop(&l, INT);
}

static void test_strings(void) {
    MsList l;
    msrt_list_new(&l);
    const char *words[] = {"alpha", "beta", "a string longer than the inline size"};
    for (size_t i = 0; i < 3; i++) {
        MsStr s = make_string(words[i]);
        msrt_list_push(&l, STR, (const uint8_t *)&s);
    }
    MsList copy;
    msrt_list_copy(&l, STR, &copy);
    MsStr probe = make_string("beta");
    int64_t index = -1;
    CHECK(msrt_list_index_of(&copy, STR, (const uint8_t *)&probe, &index) == 1 && index == 1);
    CHECK(msrt_hash_list(&l, STR) == msrt_hash_list(&copy, STR));
    msrt_list_remove(&copy, STR, 0);
    CHECK(msrt_hash_list(&l, STR) != msrt_hash_list(&copy, STR));
    msrt_string_free(&probe);
    msrt_list_drop(&l, STR);
    msrt_list_drop(&copy, STR);
}

static void test_distinct_range_keys(void) {
    int64_t many[40];
    for (size_t i = 0; i < 40; i++) {
        many[i] = (int64_t)(i % 7);
    }
    MsList l = ints(40, many);
    MsList out;
    msrt_list_distinct(&l, INT, &out);
    CHECK(IS_INTS(&out, 0, 1, 2, 3, 4, 5, 6) && ms_test_cleanups == 0);
    MsList set_source = ints(3, (int64_t[]){4, 4, 5});
    MsMap set;
    msrt_list_to_set(&set_source, INT, &set);
    CHECK(set.len == 2);
    msrt_map_drop(&set, INT, NULL);
    msrt_list_drop(&out, INT);
    msrt_list_drop(&set_source, INT);
    msrt_list_drop(&l, INT);
    msrt_list_range(-2, 3, &out);
    CHECK(IS_INTS(&out, -2, -1, 0, 1, 2));
    msrt_list_drop(&out, INT);
    msrt_list_range(5, 5, &out);
    CHECK(out.len == 0);
    CHECK(msrt_list_range_by(10, 0, -4, 0, 0, &out) == MS_STATUS_OK && IS_INTS(&out, 10, 6, 2));
    msrt_list_drop(&out, INT);
    CHECK(msrt_list_range_by(0, 10, 0, 0, 0, &out) == MS_STATUS_INVALID_INPUT);
    CHECK(msrt_list_range_by(0, 10, 1, 1, 5, &out) == MS_STATUS_LIMIT_EXCEEDED);
    CHECK(msrt_list_range_by(INT64_MIN, INT64_MAX, INT64_MAX, 0, 0, &out) == MS_STATUS_OK && out.len == 3);
    msrt_list_drop(&out, INT);
    MsList k = ints(3, (int64_t[]){9, 9, 9});
    msrt_list_keys(&k, &out);
    CHECK(IS_INTS(&out, 0, 1, 2));
    msrt_list_drop(&out, INT);
    msrt_list_drop(&k, INT);
}

static bool faults_on_fixture(void (*body)(void)) {
    fixture = ints(2, (int64_t[]){1, 2});
    msrt_list_new(&replacement);
    const bool faulted = faults(body);
    msrt_list_drop(&fixture, INT);
    return faulted;
}

static void test_faults(void) {
    CHECK(faults_on_fixture(insert_out_of_range) && ms_test_fault_kind == 6);
    CHECK(faults_on_fixture(at_without_default) && ms_test_fault_kind == 6);
    CHECK(faults_on_fixture(splice_bad_start) &&
          strcmp(ms_test_fault_message, "List.splice: start must be between 0 and 2, found 5") == 0);
    CHECK(faults_on_fixture(repeat_overflow) && ms_test_fault_kind == 5 &&
          strcmp(ms_test_fault_message, "list size overflow") == 0);
}

static void test_nested_and_shadow(void) {
    MsList inner = ints(2, (int64_t[]){1, 2});
    MsList outer;
    msrt_list_new(&outer);
    msrt_list_push(&outer, &LIST_OF_INT, (const uint8_t *)&inner);
    MsList copy;
    msrt_list_copy(&outer, &LIST_OF_INT, &copy);
    CHECK(msrt_slot_eq(&(MsTypeDesc){.size = 24, .align = 8, .kind = MS_KIND_LIST, .inner0 = &LIST_OF_INT},
                       (const uint8_t *)&outer, (const uint8_t *)&copy) == 1);
    msrt_list_drop(&copy, &LIST_OF_INT);
    MsList shadow;
    msrt_list_shadow(&outer, &LIST_OF_INT, &shadow);
    CHECK(shadow.len == 1 && shadow.ptr != outer.ptr);
    msrt_list_free_raw(&shadow);
    msrt_list_drop(&outer, &LIST_OF_INT);
    MsList big;
    msrt_list_with_capacity(INT, 100, &big);
    CHECK(big.cap == 100 && big.len == 0);
    msrt_list_drop(&big, INT);
    CHECK(msrt_slot_hash(INT, (const uint8_t *)&(int64_t){5}) == msrt_slot_hash(INT, (const uint8_t *)&(int64_t){5}));
}

int main(void) {
    test_basic_edits();
    test_find_int_every_position();
    test_derived_lists();
    test_splice_fill_copy_within();
    test_pieces();
    test_strings();
    test_distinct_range_keys();
    test_faults();
    test_nested_and_shadow();
    puts("core_list: ok");
    return 0;
}
