/* Unit test for src/runtime/core/desc.c and list.c; `make c-test` builds it with ASan and UBSan. Faults, strings
 * and maps come from support/rt_stubs.c. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/desc.h"
#include "ms_rt/list.h"
#include "rt_calls.h"
#include "rt_stubs.h"

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

/* ---- sorting ---- */

static int64_t compare_ints(uint8_t *env, const uint8_t *a, const uint8_t *b) {
    (void)env;
    int64_t x = 0;
    int64_t y = 0;
    memcpy(&x, a, 8);
    memcpy(&y, b, 8);
    return x < y ? -1 : x > y ? 1 : 0;
}

/* A pair (key, original position): sorting by key must keep the positions of equal keys in order. */
typedef struct Pair {
    int64_t key;
    int64_t position;
} Pair;

static int64_t compare_pair_keys(uint8_t *env, const uint8_t *a, const uint8_t *b) {
    (void)env;
    Pair x;
    Pair y;
    memcpy(&x, a, sizeof x);
    memcpy(&y, b, sizeof y);
    return x.key < y.key ? -1 : x.key > y.key ? 1 : 0;
}

static int64_t difference(uint8_t *env, const uint8_t *a, const uint8_t *b) {
    (void)env;
    int64_t x = 0;
    int64_t y = 0;
    memcpy(&x, a, 8);
    memcpy(&y, b, 8);
    return x - y;
}

static uint64_t next_random(uint64_t *state) {
    *state = *state * 6364136223846793005ull + 1442695040888963407ull;
    return *state >> 33;
}

static void test_sort_stable_pairs(void) {
    static const MsTypeDesc pair_desc = {.size = 16, .align = 8, .kind = MS_KIND_POD};
    for (size_t count = 0; count < 200; count += 7) {
        MsList l;
        msrt_list_new(&l);
        uint64_t seed = count + 1;
        for (size_t i = 0; i < count; i++) {
            Pair p = {.key = (int64_t)(next_random(&seed) % 5), .position = (int64_t)i};
            msrt_list_push(&l, &pair_desc, (const uint8_t *)&p);
        }
        msrt_list_sort_in_place(&l, &pair_desc, compare_pair_keys, NULL);
        for (size_t i = 1; i < count; i++) {
            Pair a;
            Pair b;
            memcpy(&a, l.ptr + (i - 1) * 16, 16);
            memcpy(&b, l.ptr + i * 16, 16);
            CHECK(a.key < b.key || (a.key == b.key && a.position < b.position));
        }
        msrt_list_drop(&l, &pair_desc);
    }
}

static void test_sort_ints(void) {
    uint64_t seed = 7;
    for (size_t count = 0; count < 600; count += 37) {
        MsList by_cmp;
        MsList by_radix;
        MsList by_diff;
        msrt_list_new(&by_cmp);
        for (size_t i = 0; i < count; i++) {
            int64_t v = (int64_t)(next_random(&seed) % 2001) - 1000;
            if (i % 50 == 3) {
                v = i % 100 == 3 ? INT64_MIN : INT64_MAX;
            }
            push_int(&by_cmp, v);
        }
        msrt_list_copy(&by_cmp, INT, &by_radix);
        msrt_list_sort_in_place(&by_cmp, INT, compare_ints, NULL);
        msrt_list_sort_ints(&by_radix, 0);
        CHECK(by_cmp.len == by_radix.len && (count == 0 || memcmp(by_cmp.ptr, by_radix.ptr, count * 8) == 0));
        msrt_list_sort_ints(&by_radix, 1);
        for (size_t i = 0; i < count; i++) {
            CHECK(int_at(&by_radix, i) == int_at(&by_cmp, count - 1 - i));
        }
        MsList sorted;
        msrt_list_sorted(&by_cmp, INT, compare_ints, NULL, &sorted);
        CHECK(sorted.len == count && (count == 0 || memcmp(sorted.ptr, by_cmp.ptr, count * 8) == 0));
        msrt_list_drop(&sorted, INT);
        msrt_list_sorted_by_difference(&by_cmp, INT, difference, NULL, 0, &by_diff);
        CHECK(by_diff.len == count && (count == 0 || memcmp(by_diff.ptr, by_cmp.ptr, count * 8) == 0));
        msrt_list_drop(&by_diff, INT);
        msrt_list_drop(&by_cmp, INT);
        msrt_list_drop(&by_radix, INT);
    }
}

/* Lists long enough to take the partitioned radix sort, in several distributions. */
static void test_sort_ints_large(void) {
    uint64_t seed = 99;
    for (unsigned shape = 0; shape < 6; shape++) {
        const size_t count = shape % 2 == 0 ? 20000 : 70001;
        MsList by_cmp;
        msrt_list_new(&by_cmp);
        for (size_t i = 0; i < count; i++) {
            const uint64_t r = next_random(&seed);
            int64_t v = 0;
            switch (shape) {
            case 0: v = (int64_t)(r % 2147483648U); break;           /* 31 bits */
            case 1: v = (int64_t)(r * 0x9e3779b97f4a7c15U); break;   /* all 64 bits, both signs */
            case 2: v = (int64_t)(r % 5) - 2; break;                 /* a handful of values */
            case 3: v = INT64_MIN + (int64_t)(r % 100000); break;    /* high bits equal, wide low range */
            case 4: v = (int64_t)i; break;                           /* already sorted */
            default: v = (int64_t)(count - i) * 1000003; break;      /* reversed */
            }
            push_int(&by_cmp, v);
        }
        MsList by_radix;
        msrt_list_copy(&by_cmp, INT, &by_radix);
        msrt_list_sort_in_place(&by_cmp, INT, compare_ints, NULL);
        msrt_list_sort_ints(&by_radix, 0);
        CHECK(memcmp(by_cmp.ptr, by_radix.ptr, count * 8) == 0);
        msrt_list_drop(&by_cmp, INT);
        msrt_list_drop(&by_radix, INT);
    }
}

/* A comparator that faults on its Nth call, to check the list is put back and nothing leaks. */
static size_t calls_left;

static int64_t compare_then_fault(uint8_t *env, const uint8_t *a, const uint8_t *b) {
    if (calls_left-- == 0) {
        static const char message[] = "comparator fault";
        msrt_fault((const uint8_t *)message, sizeof message - 1);
    }
    return compare_ints(env, a, b);
}

static void sort_fixture_with_fault(void) { msrt_list_sort_in_place(&fixture, INT, compare_then_fault, NULL); }

static void sorted_copy_with_fault(void) {
    MsList out;
    msrt_list_sorted(&fixture, INT, compare_then_fault, NULL, &out);
}

static void test_sort_rollback(void) {
    int64_t original[50];
    for (size_t i = 0; i < 50; i++) {
        original[i] = (int64_t)((i * 37) % 50);
    }
    for (size_t budget = 0; budget < 250; budget += 11) {
        fixture = ints(50, original);
        calls_left = budget;
        const bool faulted = faults(sort_fixture_with_fault);
        CHECK(!faulted || is_ints(&fixture, 50, original) || fixture.len == 50);
        if (faulted) { /* the slots are back in their original order */
            CHECK(is_ints(&fixture, 50, original));
        }
        msrt_list_drop(&fixture, INT);
        fixture = ints(50, original);
        calls_left = budget;
        (void)faults(sorted_copy_with_fault); /* the unpublished copy is dropped (LeakSanitizer checks) */
        CHECK(is_ints(&fixture, 50, original));
        msrt_list_drop(&fixture, INT);
        CHECK(ms_test_cleanups == 0);
    }
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
    test_sort_stable_pairs();
    test_sort_ints();
    test_sort_ints_large();
    test_sort_rollback();
    test_faults();
    test_nested_and_shadow();
    puts("core_list: ok");
    return 0;
}
