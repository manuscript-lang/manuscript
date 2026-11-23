/* Unit test of base/dylib.h: relative paths are refused, a missing file reports why, and a real library (the
 * probe library, `argv[1]`, exporting the function `argv[2]`) loads and yields its symbols. */
#include <stdio.h>

#include "base/dylib.h"

static int failures = 0;

#define CHECK(condition)                                                    \
  do {                                                                      \
    if (!(condition)) {                                                     \
      (void)fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition); \
      failures++;                                                           \
    }                                                                       \
  } while (0)

static void test_refusals(void) {
  MsDylib library = {0};
  MsStrBuild why = ms_strbuild_new();
  CHECK(!ms_dylib_open(ms_span_of_text("libm.so.6"), &library, &why));
  CHECK(ms_strbuild_span(&why).len != 0 && library.handle == NULL);
  ms_strbuild_free(&why);
  why = ms_strbuild_new();
  CHECK(!ms_dylib_open(ms_span_of_text("/no/such/directory/library.so"), &library, &why));
  CHECK(ms_strbuild_span(&why).len != 0 && library.handle == NULL);
  ms_strbuild_free(&why);
  CHECK(ms_dylib_symbol(&library, "anything") == NULL);
  ms_dylib_close(&library);
}

static void test_load(const char *path, const char *symbol) {
  MsDylib library = {0};
  MsStrBuild why = ms_strbuild_new();
  CHECK(ms_dylib_open(ms_span_of_text(path), &library, &why));
  CHECK(library.handle != NULL);
  CHECK(ms_dylib_symbol(&library, symbol) != NULL);
  CHECK(ms_dylib_symbol(&library, "ms_no_such_symbol_in_any_library") == NULL);
  ms_dylib_close(&library);
  CHECK(library.handle == NULL);
  ms_strbuild_free(&why);
}

int main(int argc, char **argv) {
  test_refusals();
  if (argc == 3) {
    test_load(argv[1], argv[2]);
  }
  return failures == 0 ? 0 : 1;
}
