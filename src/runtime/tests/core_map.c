/* Unit test for src/runtime/core/map.c and map_api.c; `make c-test` builds it with ASan and UBSan. Faults and
 * strings come from support/rt_stubs.c. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/list.h"
#include "ms_rt/map.h"
#include "ms_rt/string.h"
#include "rt_calls.h"
#include "rt_stubs.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_map.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static const MsTypeDesc *const INT = &msrt_desc_int;
static const MsTypeDesc *const STR = &msrt_desc_string;
/* A 16-byte plain key: hashed and compared as bytes. */
static const MsTypeDesc PAIR = {.size = 16, .align = 8, .kind = MS_KIND_POD};

static MsStr make_string(const char *text) {
    MsStr s;
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &s);
    return s;
}

static void add_int(MsMap *m, int64_t key, int64_t value) { msrt_map_add(m, INT, INT, (uint8_t *)&key, (uint8_t *)&value); }

static bool get_int(const MsMap *m, int64_t key, int64_t *out) {
    return msrt_map_get(m, INT, INT, (const uint8_t *)&key, (uint8_t *)out) != 0;
}

static bool has_int(const MsMap *m, int64_t key) { return msrt_map_contains(m, INT, INT, (const uint8_t *)&key) != 0; }

static void remove_int(MsMap *m, int64_t key) { msrt_map_remove(m, INT, INT, (const uint8_t *)&key); }

static void add_name(MsMap *m, const char *name, int64_t value) {
    MsStr key = make_string(name);
    msrt_map_add(m, STR, INT, (uint8_t *)&key, (uint8_t *)&value);
}

static bool get_name(const MsMap *m, const char *name, int64_t *out) {
    MsStr key = make_string(name);
    const uint8_t *value = msrt_map_get_ptr(m, STR, INT, (const uint8_t *)&key);
    msrt_string_free(&key);
    if (value == NULL) {
        return false;
    }
    memcpy(out, value, sizeof *out);
    return true;
}

static void test_int_map_grows_replaces_and_removes(void) {
    MsMap m;
    msrt_map_new(&m);
    for (int64_t i = 0; i < 1000; i++) {
        add_int(&m, i * 7, i);
    }
    CHECK(msrt_map_length(&m) == 1000);
    add_int(&m, 70, -1); /* replaces in place */
    CHECK(msrt_map_length(&m) == 1000);
    int64_t v = 0;
    CHECK(get_int(&m, 70, &v) && v == -1);
    CHECK(get_int(&m, 6993, &v) && v == 999);
    CHECK(!has_int(&m, 5));
    for (int64_t i = 0; i < 1000; i += 2) {
        remove_int(&m, i * 7);
    }
    CHECK(msrt_map_length(&m) == 500);
    CHECK(!has_int(&m, 0) && has_int(&m, 7));
    for (int64_t i = 1000; i < 1100; i++) { /* reuses the holes and compacts */
        add_int(&m, i * 7, i);
    }
    CHECK(msrt_map_length(&m) == 600);
    for (int64_t i = 1; i < 1000; i += 2) {
        CHECK(get_int(&m, i * 7, &v) && (i == 10 ? v == -1 : v == i));
    }
    remove_int(&m, 12345); /* absent: nothing happens */
    msrt_map_drop(&m, INT, INT);
    CHECK(msrt_map_length(&m) == 0);
}

static void test_insertion_order_and_entry_ptrs(void) {
    MsMap m;
    msrt_map_new(&m);
    add_int(&m, 30, 3);
    add_int(&m, 10, 1);
    add_int(&m, 20, 2);
    remove_int(&m, 10);
    add_int(&m, 40, 4);
    MsList keys;
    msrt_map_keys(&m, INT, INT, &keys);
    int64_t expected[] = {30, 20, 40};
    CHECK(keys.len == 3 && memcmp(keys.ptr, expected, sizeof expected) == 0);
    msrt_list_drop(&keys, INT);
    const uint8_t *key = NULL;
    const uint8_t *value = NULL;
    size_t live = 0;
    for (int64_t i = 0; i < msrt_map_slot_count(&m); i++) {
        live += msrt_map_entry_ptrs(&m, INT, INT, i, &key, &value);
    }
    CHECK(live == 3);
    MsList values;
    msrt_map_values(&m, INT, INT, &values);
    int64_t expected_values[] = {3, 2, 4};
    CHECK(memcmp(values.ptr, expected_values, sizeof expected_values) == 0);
    msrt_list_drop(&values, INT);
    msrt_map_drop(&m, INT, INT);
}

static void test_string_map_and_fixed_shapes(void) {
    MsMap m;
    msrt_map_new(&m);
    char name[64];
    for (int64_t i = 0; i < 300; i++) {
        snprintf(name, sizeof name, "name-number-%lld-with-a-long-tail", (long long)i);
        add_name(&m, name, i);
    }
    add_name(&m, "short", 1);
    add_name(&m, "short", 2); /* the second key is dropped */
    int64_t v = 0;
    CHECK(msrt_map_length(&m) == 301);
    CHECK(get_name(&m, "short", &v) && v == 2);
    CHECK(get_name(&m, "name-number-299-with-a-long-tail", &v) && v == 299);
    CHECK(!get_name(&m, "missing", &v));

    MsStr probe = make_string("short");
    CHECK(msrt_map_contains_sw8(&m, STR, INT, (const uint8_t *)&probe) == 1);
    CHECK(msrt_map_get_sw8(&m, STR, INT, (const uint8_t *)&probe, (uint8_t *)&v) == 1 && v == 2);
    MsStr fresh = make_string("fresh-key");
    int64_t seven = 7;
    msrt_map_add_sw8(&m, STR, INT, (uint8_t *)&fresh, (uint8_t *)&seven);
    MsStr again = make_string("fresh-key");
    int64_t nine = 9;
    msrt_map_add_sw8(&m, STR, INT, (uint8_t *)&again, (uint8_t *)&nine);
    CHECK(get_name(&m, "fresh-key", &v) && v == 9);
    const uint8_t *ptr = msrt_map_get_ptr_sw8(&m, STR, INT, (const uint8_t *)&probe);
    CHECK(ptr != NULL);
    msrt_string_free(&probe);

    MsMap ints;
    msrt_map_new(&ints);
    for (int64_t i = 0; i < 100; i++) {
        int64_t key = i;
        int64_t value = i * i;
        msrt_map_add_w8(&ints, INT, INT, (uint8_t *)&key, (uint8_t *)&value);
    }
    int64_t key = 9;
    CHECK(msrt_map_contains_w8(&ints, INT, INT, (const uint8_t *)&key) == 1);
    CHECK(msrt_map_get_w8(&ints, INT, INT, (const uint8_t *)&key, (uint8_t *)&v) == 1 && v == 81);
    CHECK(msrt_map_get_ptr_w8(&ints, INT, INT, (const uint8_t *)&key) != NULL);
    key = 1000;
    CHECK(msrt_map_contains_w8(&ints, INT, INT, (const uint8_t *)&key) == 0);
    msrt_map_drop(&ints, INT, INT);
    msrt_map_drop(&m, STR, INT);
}

static void test_keys_and_values_views(void) {
    MsMap m;
    msrt_map_new(&m);
    add_name(&m, "tiny", 1);
    add_name(&m, "a-name-longer-than-fifteen-bytes", 2);
    MsList keys;
    msrt_map_keys_view(&m, STR, INT, &keys);
    CHECK(keys.len == 2);
    const MsStr *views = (const MsStr *)__builtin_assume_aligned(keys.ptr, _Alignof(MsStr));
    CHECK(ms_str_len(&views[0]) == 4 && memcmp(ms_str_data(&views[0]), "tiny", 4) == 0);
    CHECK(ms_str_len(&views[1]) == 32 && memcmp(ms_str_data(&views[1]), "a-name-longer-than-fifteen-bytes", 32) == 0);
    CHECK((views[1].tagged >> 62) == 3); /* a view of the map's string */
    msrt_list_free_raw(&keys);
    MsList copies;
    msrt_map_keys(&m, STR, INT, &copies);
    msrt_list_drop(&copies, STR);
    msrt_map_drop(&m, STR, INT);
}

static void test_copy_equality_and_clear(void) {
    MsMap a;
    msrt_map_new(&a);
    for (int64_t i = 0; i < 50; i++) {
        add_int(&a, i, i * 2);
    }
    remove_int(&a, 3);
    MsMap b;
    msrt_map_copy(&a, INT, INT, &b);
    CHECK(msrt_map_length(&b) == 49 && !has_int(&b, 3));
    MsTypeDesc map_desc = {.size = 56, .align = 8, .kind = MS_KIND_MAP, .inner0 = &msrt_desc_int, .inner1 = &msrt_desc_int};
    CHECK(msrt_slot_eq(&map_desc, (const uint8_t *)&a, (const uint8_t *)&b) != 0);
    add_int(&b, 7, 0);
    CHECK(msrt_slot_eq(&map_desc, (const uint8_t *)&a, (const uint8_t *)&b) == 0);
    msrt_map_clear(&b, INT, INT);
    CHECK(msrt_map_length(&b) == 0);
    add_int(&b, 1, 1); /* usable after a clear */
    CHECK(has_int(&b, 1));
    msrt_map_drop(&a, INT, INT);
    msrt_map_drop(&b, INT, INT);
}

static void test_lent_keys_and_defaults(void) {
    MsMap m;
    msrt_map_new(&m);
    MsStr key = make_string("counter");
    int64_t zero = 0;
    uint8_t *slot = msrt_map_slot_lent(&m, STR, INT, (const uint8_t *)&key, (uint8_t *)&zero);
    int64_t one = 1;
    memcpy(slot, &one, sizeof one);
    int64_t unused = 5;
    slot = msrt_map_slot_lent(&m, STR, INT, (const uint8_t *)&key, (uint8_t *)&unused);
    int64_t v = 0;
    memcpy(&v, slot, sizeof v);
    CHECK(v == 1 && msrt_map_length(&m) == 1);
    int64_t seven = 7;
    msrt_map_add_lent(&m, STR, INT, (const uint8_t *)&key, (uint8_t *)&seven);
    CHECK(get_name(&m, "counter", &v) && v == 7);
    int64_t eight = 8;
    msrt_map_add_default_lent(&m, STR, INT, (const uint8_t *)&key, (uint8_t *)&eight);
    CHECK(get_name(&m, "counter", &v) && v == 7);
    MsStr other = make_string("other");
    msrt_map_add_default_lent(&m, STR, INT, (const uint8_t *)&other, (uint8_t *)&eight);
    CHECK(get_name(&m, "other", &v) && v == 8);
    MsStr third = make_string("third");
    int64_t nine = 9;
    msrt_map_add_default(&m, STR, INT, (uint8_t *)&third, (uint8_t *)&nine);
    MsStr third_again = make_string("third");
    msrt_map_add_default(&m, STR, INT, (uint8_t *)&third_again, (uint8_t *)&eight);
    CHECK(get_name(&m, "third", &v) && v == 9 && msrt_map_length(&m) == 3);
    msrt_string_free(&key);
    msrt_string_free(&other);
    msrt_map_drop(&m, STR, INT);
}

static void test_merge_and_table(void) {
    MsMap a;
    MsMap b;
    msrt_map_new(&a);
    msrt_map_new(&b);
    add_int(&a, 1, 10);
    add_int(&a, 2, 20);
    add_int(&b, 2, 21);
    add_int(&b, 3, 30);
    msrt_map_merge(&a, &b, INT, INT);
    int64_t v = 0;
    CHECK(msrt_map_length(&a) == 3 && get_int(&a, 2, &v) && v == 21 && get_int(&a, 3, &v) && v == 30);
    msrt_map_drop(&a, INT, INT);
    msrt_map_drop(&b, INT, INT);

    /* A table: "x" -> 5, "y" -> 6, then "x" -> 7 (replaces). */
    const uint8_t table[] = {1, 1, 0, 0, 0, 'x', 0, 5, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 'y', 0, 6, 0, 0, 0, 0, 0, 0, 0,
                             1, 1, 0, 0, 0, 'x', 0, 7, 0, 0, 0, 0, 0, 0, 0};
    MsStr packed;
    msrt_string_from_bytes(table, sizeof table, &packed);
    MsMap m;
    msrt_map_new(&m);
    msrt_map_add_table(&m, STR, INT, &packed);
    CHECK(msrt_map_length(&m) == 2 && get_name(&m, "x", &v) && v == 7 && get_name(&m, "y", &v) && v == 6);
    msrt_string_free(&packed);
    msrt_map_drop(&m, STR, INT);
}

static MsMap int_set(size_t count, const int64_t *values) {
    MsMap s;
    msrt_map_new(&s);
    for (size_t i = 0; i < count; i++) {
        msrt_set_add_copy(&s, INT, (const uint8_t *)&values[i]);
    }
    return s;
}

static bool set_has(const MsMap *s, int64_t value) { return msrt_map_contains(s, INT, NULL, (const uint8_t *)&value) != 0; }

static bool set_is(const MsMap *s, size_t count, const int64_t *values) {
    if (s->len != count) {
        return false;
    }
    for (size_t i = 0; i < count; i++) {
        if (!set_has(s, values[i])) {
            return false;
        }
    }
    return true;
}

static void test_set_algebra(void) {
    int64_t left_values[] = {1, 2, 3, 4, 2, 1};
    int64_t right_values[] = {3, 4, 5};
    MsMap a = int_set(6, left_values);
    MsMap b = int_set(3, right_values);
    CHECK(a.len == 4);
    MsMap out;
    msrt_set_union(&a, &b, INT, &out);
    CHECK(set_is(&out, 5, (int64_t[]){1, 2, 3, 4, 5}));
    msrt_map_drop(&out, INT, NULL);
    msrt_set_intersection(&a, &b, INT, &out);
    CHECK(set_is(&out, 2, (int64_t[]){3, 4}));
    msrt_map_drop(&out, INT, NULL);
    msrt_set_difference(&a, &b, INT, &out);
    CHECK(set_is(&out, 2, (int64_t[]){1, 2}));
    msrt_map_drop(&out, INT, NULL);
    msrt_set_symmetric_difference(&a, &b, INT, &out);
    CHECK(set_is(&out, 3, (int64_t[]){1, 2, 5}));
    msrt_map_drop(&out, INT, NULL);
    MsMap small = int_set(2, (int64_t[]){3, 4});
    CHECK(msrt_set_is_subset_of(&small, &a, INT) == 1 && msrt_set_is_subset_of(&b, &a, INT) == 0);
    CHECK(msrt_set_is_superset_of(&a, &small, INT) == 1 && msrt_set_is_superset_of(&small, &a, INT) == 0);
    MsMap apart = int_set(2, (int64_t[]){8, 9});
    CHECK(msrt_set_is_disjoint_from(&a, &apart, INT) == 1 && msrt_set_is_disjoint_from(&a, &b, INT) == 0);
    MsList values;
    msrt_set_values(&small, INT, NULL, &values);
    CHECK(values.len == 2);
    msrt_list_drop(&values, INT);
    int64_t word = 99;
    msrt_set_add_copy_w(&small, INT, (const uint8_t *)&word);
    msrt_set_add_copy_w(&small, INT, (const uint8_t *)&word);
    CHECK(small.len == 3 && msrt_set_contains_w(&small, INT, NULL, (const uint8_t *)&word) == 1);
    msrt_map_drop(&a, INT, NULL);
    msrt_map_drop(&b, INT, NULL);
    msrt_map_drop(&small, INT, NULL);
    msrt_map_drop(&apart, INT, NULL);
}

static void test_string_sets_and_plain_keys(void) {
    MsMap s;
    msrt_map_new(&s);
    const char *words[] = {"alpha", "beta", "alpha", "a-string-longer-than-fifteen"};
    for (size_t i = 0; i < 4; i++) {
        MsStr w = make_string(words[i]);
        msrt_set_add_copy(&s, STR, (const uint8_t *)&w);
        msrt_string_free(&w);
    }
    CHECK(s.len == 3);
    MsMap copy;
    msrt_set_union(&s, &s, STR, &copy);
    CHECK(copy.len == 3);
    msrt_map_drop(&copy, STR, NULL);
    msrt_map_drop(&s, STR, NULL);

    MsMap m;
    msrt_map_new(&m);
    for (int64_t i = 0; i < 40; i++) {
        int64_t key[2] = {i, i + 1};
        int64_t value = i;
        msrt_map_add(&m, &PAIR, INT, (uint8_t *)key, (uint8_t *)&value);
    }
    int64_t probe[2] = {7, 8};
    int64_t v = 0;
    CHECK(msrt_map_get(&m, &PAIR, INT, (const uint8_t *)probe, (uint8_t *)&v) == 1 && v == 7);
    probe[1] = 9;
    CHECK(msrt_map_get(&m, &PAIR, INT, (const uint8_t *)probe, (uint8_t *)&v) == 0);
    msrt_map_drop(&m, &PAIR, INT);
}

static void test_reserve_and_stamp(void) {
    MsMap m;
    msrt_map_new(&m);
    msrt_map_reserve(&m, INT, INT, 100);
    CHECK(m.cap >= 100);
    const size_t cap = m.cap;
    for (int64_t i = 0; i < 100; i++) {
        add_int(&m, i, i);
    }
    CHECK(m.cap == cap); /* no regrowth */
    msrt_map_stamp(&m, INT);
    CHECK(m.desc == INT);
    msrt_map_stamp(&m, STR);
    CHECK(m.desc == INT); /* the first creator stays */
    msrt_map_drop(&m, INT, INT);
    CHECK(m.desc == INT); /* and survives a drop */
}

int main(void) {
    test_int_map_grows_replaces_and_removes();
    test_insertion_order_and_entry_ptrs();
    test_string_map_and_fixed_shapes();
    test_keys_and_values_views();
    test_copy_equality_and_clear();
    test_lent_keys_and_defaults();
    test_merge_and_table();
    test_set_algebra();
    test_string_sets_and_plain_keys();
    test_reserve_and_stamp();
    puts("core_map ok");
    return 0;
}
