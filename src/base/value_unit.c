/* Unit test of base/value pieces that are pure data structures: strings, builder, lists, arena, names. */
#include <stdio.h>

#include "base/arena.h"
#include "base/hash.h"
#include "base/intern.h"
#include "base/list.h"
#include "base/strbuild.h"
#include "base/string.h"

static int failures = 0;

#define CHECK(condition)                                                                                     \
  do {                                                                                                       \
    if (!(condition)) {                                                                                      \
      (void)fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);                                  \
      failures++;                                                                                            \
    }                                                                                                        \
  } while (0)

MS_LIST_DEFINE(IntList, int_list, int)

static void test_strings(void) {
  MsString small = ms_string_from_span(ms_span_of_text("hello"));
  MsString large = ms_string_from_span(ms_span_of_text("a string longer than fifteen bytes"));
  MsString copy = ms_string_clone(&large);
  const MsString view = ms_string_view(ms_span_of_text("hello"));
  CHECK(ms_string_is_inline(&small) && !ms_string_is_inline(&large));
  CHECK(ms_string_equal(&small, &view));
  CHECK(ms_string_hash(&small) == ms_string_hash(&view));
  CHECK(ms_string_equal(&large, &copy) && large.owned != copy.owned);
  CHECK(ms_string_compare(&small, &large) > 0);
  CHECK(ms_string_compare(&small, &view) == 0);
  CHECK(ms_string_length(&large) == 34);
  ms_string_release(&small);
  ms_string_release(&large);
  ms_string_release(&copy);
  CHECK(ms_string_is_empty(&large));
}

static void test_builder(void) {
  MsStrBuild builder = ms_strbuild_new();
  ms_strbuild_append_text(&builder, "n=");
  ms_strbuild_append_i64(&builder, -42);
  ms_strbuild_append_byte(&builder, ' ');
  ms_strbuild_append_u64_radix(&builder, 255, 16);
  ms_strbuild_append_utf8(&builder, 0xE9);
  MsString text = ms_strbuild_finish(&builder);
  CHECK(ms_span_is_text(ms_string_span(&text), "n=-42 ff\xC3\xA9"));
  CHECK(ms_strbuild_length(&builder) == 0);
  ms_strbuild_append_i64(&builder, INT64_MIN);
  CHECK(ms_span_is_text(ms_strbuild_span(&builder), "-9223372036854775808"));
  ms_string_release(&text);
  ms_strbuild_free(&builder);
}

static void test_list(void) {
  IntList list = {0};
  int value = 0;
  for (int i = 0; i < 100; i++) {
    int_list_push(&list, i);
  }
  CHECK(list.len == 100 && *int_list_at(&list, 99) == 99);
  CHECK(int_list_get(&list, 5, &value) && value == 5);
  CHECK(!int_list_get(&list, 100, &value));
  CHECK(int_list_pop(&list, &value) && value == 99 && list.len == 99);
  int_list_free(&list);
  CHECK(list.ptr == NULL && list.len == 0);
}

static void test_arena(void) {
  MsArena arena = ms_arena_new();
  uint64_t *numbers = MS_ARENA_NEW_ARRAY(&arena, uint64_t, 10);
  CHECK(numbers[9] == 0 && ((uintptr_t)numbers % _Alignof(uint64_t)) == 0);
  void *big = ms_arena_alloc(&arena, (size_t)1 << 20, 16);
  CHECK(big != NULL && ms_span_is_text(ms_arena_copy(&arena, ms_span_of_text("copy")), "copy"));
  ms_arena_reset(&arena);
  CHECK(ms_arena_alloc(&arena, 8, 8) != NULL);
  ms_arena_free(&arena);
}

static void test_names(void) {
  MsNames names;
  ms_names_init(&names);
  const MsName alpha = ms_names_intern(&names, ms_span_of_text("alpha"));
  CHECK(ms_names_intern(&names, ms_span_of_text("alpha")) == alpha);
  CHECK(ms_names_intern(&names, ms_span_of_text("")) == MS_NAME_EMPTY);
  MsName found = 0;
  CHECK(!ms_names_find(&names, ms_span_of_text("beta"), &found));
  for (uint64_t i = 0; i < 1000; i++) {
    MsStrBuild builder = ms_strbuild_new();
    ms_strbuild_append_u64(&builder, i);
    const MsName id = ms_names_intern(&names, ms_strbuild_span(&builder));
    CHECK(id == i + 2);
    ms_strbuild_free(&builder);
  }
  CHECK(ms_names_find(&names, ms_span_of_text("alpha"), &found) && found == alpha);
  CHECK(ms_span_is_text(ms_names_span(&names, alpha), "alpha"));
  CHECK(ms_names_count(&names) == 1002);
  ms_names_free(&names);
}

/* A table layered over a frozen base keeps the base's ids, numbers new texts after them, and leaves the base alone. */
static void test_names_over(void) {
  MsNames base;
  ms_names_init(&base);
  const MsName alpha = ms_names_intern(&base, ms_span_of_text("alpha"));
  const size_t base_count = ms_names_count(&base);
  MsNames over;
  ms_names_init_over(&over, &base);
  CHECK(ms_names_intern(&over, ms_span_of_text("alpha")) == alpha);
  CHECK(ms_names_intern(&over, ms_span_of_text("")) == MS_NAME_EMPTY);
  const MsName beta = ms_names_intern(&over, ms_span_of_text("beta"));
  CHECK(beta == base_count);
  for (uint64_t i = 0; i < 1000; i++) { /* growth rebuilds the table */
    MsStrBuild builder = ms_strbuild_new();
    ms_strbuild_append_u64(&builder, i);
    CHECK(ms_names_intern(&over, ms_strbuild_span(&builder)) == base_count + 1 + i);
    ms_strbuild_free(&builder);
  }
  MsName found = 0;
  CHECK(ms_names_intern(&over, ms_span_of_text("beta")) == beta);
  CHECK(ms_names_find(&over, ms_span_of_text("beta"), &found) && found == beta);
  CHECK(ms_names_find(&over, ms_span_of_text("alpha"), &found) && found == alpha);
  CHECK(ms_span_is_text(ms_names_span(&over, alpha), "alpha") && ms_span_is_text(ms_names_span(&over, beta), "beta"));
  CHECK(ms_names_count(&over) == base_count + 1001);
  CHECK(ms_names_count(&base) == base_count && !ms_names_find(&base, ms_span_of_text("beta"), &found));
  ms_names_free(&over);
  ms_names_free(&base);
}

int main(void) {
  test_strings();
  test_builder();
  test_list();
  test_arena();
  test_names();
  test_names_over();
  return failures == 0 ? 0 : 1;
}
