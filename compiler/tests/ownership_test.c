/* Unit test of the ownership pass's data: places, overlap and display. */
#include <stdio.h>
#include <string.h>

#include "ms/ownership.h"

static int failures;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

static MsStep field(MsNames *n, const char *name) {
    MsStep s = {MS_STEP_FIELD, ms_intern_cstr(n, name), 0};
    return s;
}

static MsStep index_step(uint64_t i) {
    MsStep s = {MS_STEP_INDEX, 0, i};
    return s;
}

static MsStep element(void) {
    MsStep s = {MS_STEP_ELEMENT, 0, 0};
    return s;
}

static bool shows(MsNames *n, MsPlace p, const char *want) {
    MsBuf b = {0};
    ms_place_show(&b, n, p, ms_intern_cstr(n, "b"));
    bool ok = b.len == strlen(want) && memcmp(b.data, want, b.len) == 0;
    ms_buf_free(&b);
    return ok;
}

int main(void) {
    MsNames names;
    MsArena arena = {0};
    ms_names_init(&names);

    MsPlace whole = ms_place_local(1);
    MsPlace items = ms_place_then(&arena, whole, field(&names, "items"));
    MsPlace count = ms_place_then(&arena, whole, field(&names, "count"));
    MsPlace first = ms_place_then(&arena, items, index_step(0));
    MsPlace second = ms_place_then(&arena, items, index_step(1));
    MsPlace any = ms_place_then(&arena, items, element());

    CHECK(whole.len == 0 && items.len == 1 && first.len == 2);
    CHECK(ms_place_overlaps(whole, items) && ms_place_overlaps(items, whole));
    CHECK(!ms_place_overlaps(items, count));
    CHECK(ms_place_overlaps(items, first) && ms_place_overlaps(first, first));
    CHECK(!ms_place_overlaps(first, second));
    CHECK(ms_place_overlaps(first, any) && ms_place_overlaps(any, second));
    CHECK(!ms_place_overlaps(items, ms_place_local(2)));
    CHECK(!ms_place_overlaps(ms_place_then(&arena, any, field(&names, "x")), ms_place_then(&arena, any, element())));

    MsStep more[2] = {field(&names, "a"), index_step(7)};
    MsPlace joined = ms_place_join(&arena, items, more, 2);
    CHECK(joined.len == 3 && items.len == 1);
    CHECK(shows(&names, whole, "b"));
    CHECK(shows(&names, joined, "b.items.a[7]"));
    CHECK(shows(&names, any, "b.items[..]"));

    MsBits a = ms_bits_new(&arena, 130);
    MsBits b = ms_bits_copy(&arena, a);
    ms_bits_add(a, 3);
    ms_bits_add(a, 129);
    ms_bits_add(b, 3);
    ms_bits_add(b, 64);
    CHECK(ms_bits_has(a, 129) && !ms_bits_has(a, 64) && !ms_bits_has(a, 500) && ms_bits_count(a) == 2);
    MsBits both = ms_bits_copy(&arena, a);
    ms_bits_meet(both, b);
    CHECK(ms_bits_count(both) == 1 && ms_bits_has(both, 3));
    ms_bits_union(both, b);
    CHECK(ms_bits_count(both) == 2 && ms_bits_has(both, 64));
    ms_bits_remove(both, 3);
    CHECK(!ms_bits_has(both, 3));
    ms_bits_clear(both);
    CHECK(ms_bits_count(both) == 0 && ms_bits_count(a) == 2);

    ms_arena_free(&arena);
    ms_names_free(&names);
    if (failures == 0) {
        puts("ownership: ok");
    }
    return failures != 0;
}
