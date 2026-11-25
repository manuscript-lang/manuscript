/* Unit test of base/safe.h: checked sizes and spans (a pure data structure, so it has a C test). */
#include <stdio.h>

#include "base/safe.h"

static int failures = 0;

#define CHECK(condition)                                                                                     \
  do {                                                                                                       \
    if (!(condition)) {                                                                                      \
      (void)fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);                                  \
      failures++;                                                                                            \
    }                                                                                                        \
  } while (0)

static void test_sizes(void) {
  size_t out = 7;
  CHECK(ms_size_add(1, 2, &out) && out == 3);
  CHECK(!ms_size_add(SIZE_MAX, 1, &out) && out == 3);
  CHECK(ms_size_mul(4, 5, &out) && out == 20);
  CHECK(!ms_size_mul(SIZE_MAX, 2, &out) && out == 20);
  CHECK(ms_size_sub(5, 5, &out) && out == 0);
  CHECK(!ms_size_sub(1, 2, &out));
}

static void test_spans(void) {
  const MsSpan hello = ms_span_of_text("hello world");
  MsSpan part = {0};
  size_t at = 0;
  uint8_t byte = 0;
  CHECK(ms_span_slice(hello, 6, 11, &part) && ms_span_is_text(part, "world"));
  CHECK(!ms_span_slice(hello, 6, 12, &part));
  CHECK(!ms_span_slice(hello, 7, 6, &part));
  CHECK(ms_span_get(hello, 0, &byte) && byte == 'h');
  CHECK(!ms_span_get(hello, 11, &byte));
  CHECK(ms_span_find(hello, ms_span_of_text("o w"), &at) && at == 4);
  CHECK(!ms_span_find(hello, ms_span_of_text("xyz"), &at));
  CHECK(ms_span_starts_with_text(hello, "hell"));
  CHECK(ms_span_ends_with_text(hello, "world"));
  CHECK(!ms_span_ends_with(ms_span_of_text("d"), hello));
}

static void test_copy(void) {
  uint8_t buffer[4] = {0};
  CHECK(ms_span_copy(ms_span_mut_of(buffer, 4), ms_span_of_text("abcd")));
  CHECK(ms_span_is_text(ms_span_of(buffer, 4), "abcd"));
  CHECK(!ms_span_copy(ms_span_mut_of(buffer, 3), ms_span_of_text("abcd")));
  CHECK(MS_COUNT_OF(buffer) == 4);
}

int main(void) {
  test_sizes();
  test_spans();
  test_copy();
  return failures == 0 ? 0 : 1;
}
