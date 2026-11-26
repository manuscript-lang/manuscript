/* Unit test of base/search.h: every search agrees with a byte-by-byte one over many short and medium texts, across
 * the thresholds where the search changes method. */
#include <stdio.h>

#include "base/search.h"

static int failures = 0;

#define CHECK(condition)                                                    \
  do {                                                                      \
    if (!(condition)) {                                                     \
      (void)fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition); \
      failures++;                                                           \
    }                                                                       \
  } while (0)

static size_t naive_find(const uint8_t *hay, size_t n, const uint8_t *needle, size_t m) {
  if (m == 0) {
    return 0;
  }
  for (size_t i = 0; i + m <= n; i++) {
    size_t k = 0;
    while (k < m && hay[i + k] == needle[k]) {
      k++;
    }
    if (k == m) {
      return i;
    }
  }
  return SIZE_MAX;
}

static uint64_t seed = 88172645463325252ULL;

static uint64_t next_random(void) {
  seed ^= seed << 13;
  seed ^= seed >> 7;
  seed ^= seed << 17;
  return seed;
}

/* A text over a small alphabet, so a needle matches often and at every alignment. */
static void fill(uint8_t *bytes, size_t n, unsigned alphabet) {
  for (size_t i = 0; i < n; i++) {
    bytes[i] = (uint8_t)('a' + next_random() % alphabet);
  }
}

static void test_agrees_with_naive_search(void) {
  uint8_t hay[200];
  uint8_t needle[24];
  for (int round = 0; round < 40000; round++) {
    const unsigned alphabet = 2 + (unsigned)(next_random() % 5);
    const size_t n = (size_t)(next_random() % 200);
    const size_t m = 1 + (size_t)(next_random() % 23);
    fill(hay, n, alphabet);
    fill(needle, m, alphabet);
    if (next_random() % 2 == 0 && n >= m) { /* plant the needle at a random offset */
      const size_t at = (size_t)(next_random() % (n - m + 1));
      for (size_t k = 0; k < m; k++) {
        hay[at + k] = needle[k];
      }
    }
    const size_t expected = naive_find(hay, n, needle, m);
    CHECK(ms_find(hay, n, needle, m) == expected);
    const MsNeedle prepared = ms_needle_for((MsSpan){.ptr = needle, .len = m}, n);
    CHECK(ms_needle_find(&prepared, (MsSpan){.ptr = hay, .len = n}) == expected);
  }
}

int main(void) {
  test_agrees_with_naive_search();
  if (failures != 0) {
    (void)fprintf(stderr, "%d failures\n", failures);
    return 1;
  }
  return 0;
}
