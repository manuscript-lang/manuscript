/* Unit test of the profiler's folding (profile.c): samples of return addresses become named, counted stacks. */
#include <stdio.h>

#include "runtime/core/frames.h"
#include "runtime/entry/profile.h"

static int failures = 0;

#define CHECK(condition)                                                                                     \
  do {                                                                                                       \
    if (!(condition)) {                                                                                      \
      (void)fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);                                  \
      failures++;                                                                                            \
    }                                                                                                        \
  } while (0)

enum { MAIN = 0x1000, WORK = 0x1100, SAMPLE_WORDS = 4 };

/* A table of two functions: `main` at 0x1000..0x1100 and `work` at 0x1100..0x1200. */
static const MsFuncEntry functions[] = {{.address = MAIN, .size = 0x100, .name_offset = 0},
                                        {.address = WORK, .size = 0x100, .name_offset = 5}};
static const uint8_t names[] = "main\0work\0";
static const MsLineEntry lines[] = {{.pc = MAIN, .line = 1}, {.pc = WORK, .line = 2}};

static void install_tables(void) {
  static MsTables tables;
  tables = (MsTables){.abi_version = 2,
                      .funcs = functions,
                      .func_count = 2,
                      .lines = lines,
                      .line_count = 2,
                      .strings = names,
                      .strings_len = sizeof names};
  ms_frames_install(&tables);
}

static bool folded_is(const uintptr_t *samples, size_t count, const char *expected) {
  MsStrBuild out = ms_strbuild_new();
  ms_profile_fold(samples, count, SAMPLE_WORDS, &out);
  const bool same = ms_span_is_text(ms_strbuild_span(&out), expected);
  if (!same) {
    (void)fprintf(stderr, "folded:\n%.*s\n", (int)out.bytes.len, (const char *)out.bytes.ptr);
  }
  ms_strbuild_free(&out);
  return same;
}

int main(void) {
  install_tables();
  /* Words: frame count, then the pcs innermost first. The first is an exact pc, the rest return addresses; 0x9000 is
   * outside the table, as the program's start shim is. */
  const uintptr_t samples[] = {
      3, WORK + 4, MAIN + 0x20, 0x9000,       /* main;work, with the shim outermost dropped */
      3, WORK + 8, MAIN + 0x30, 0x9000,       /* the same stack: counted together */
      1, MAIN + 8, 0, 0,                      /* main alone */
      2, 0x8000, WORK + 0x10, 0,              /* inside the runtime, called from work */
      3, 0x8000, 0x8100, MAIN + 0x10,         /* two runtime frames in a row are one */
      0, 0, 0, 0,                             /* no frames at all */
  };
  CHECK(folded_is(samples, 6, "main 1\nmain;[runtime] 1\nmain;work 2\nwork;[runtime] 1\n"));
  CHECK(folded_is(samples, 0, ""));
  ms_frames_release();
  return failures == 0 ? 0 : 1;
}
