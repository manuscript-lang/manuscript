/* driver/test_options.h: the selection options `ms test` forwards in the invocation's arguments. Port of
 * `parse_options` in crates/ms-cli/src/engine/testing.rs. */
#ifndef MS_DRIVER_TEST_OPTIONS_H
#define MS_DRIVER_TEST_OPTIONS_H

#include "base/intern.h"

enum { MS_TEST_DEFAULT_TIMEOUT_MS = 60000 };

typedef struct MsTestOptions {
  MsSpanList names;      /* --test: exact identities */
  MsSpan matching, exclude, filter;
  bool list, fail_fast;
  size_t repeat;         /* at least 1 */
  bool shuffled;
  int64_t shuffle_seed;
  int64_t timeout_ms;    /* 0 disables */
  bool timeout_set;
  int64_t runs, seed, fuzz_ms; /* 0 when unset (a seed of 0 is set when `has_seed`) */
  bool has_seed;
  MsSpan program[64];    /* the program's own arguments */
  size_t program_count;
} MsTestOptions;

/* Reads the arguments; the first unrecognised one starts the program's own. The values were validated by the
 * invocation, so a bad one reads as unset. */
void ms_test_options_parse(const MsSpanList *arguments, MsTestOptions *out);

void ms_test_options_free(MsTestOptions *options);

#endif
