/* Unit test of the folded-stack conversion of `ms profile` (profile_folded.c): reading, ranking, the text report and the
 * pprof encoding. The samples are the ones the Rust implementation's tests used. */
#include <stdio.h>

#include "cli/profile_folded.h"

static int failures = 0;

#define CHECK(condition)                                                                                     \
  do {                                                                                                       \
    if (!(condition)) {                                                                                      \
      (void)fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);                                  \
      failures++;                                                                                            \
    }                                                                                                        \
  } while (0)

static const char SAMPLE[] = "# hz=100\nmain;parse;read 40\nmain;parse 10\nmain;render 50\n\nmain;parse;read 10\n";

static bool parse(MsArena *arena, const char *text, MsFoldedProfile *profile) {
  MsSpan error = {0};
  return ms_folded_parse(arena, ms_span_of_text(text), profile, &error);
}

static bool is_function(const MsFoldedProfile *profile, const MsTopEntry *entry, const char *name) {
  return ms_span_is_text(ms_names_span(&profile->names, entry->function), name);
}

static void test_ranking(void) {
  MsArena arena = ms_arena_new();
  MsFoldedProfile profile;
  CHECK(parse(&arena, SAMPLE, &profile));
  CHECK(profile.hz == 100 && profile.total == 110 && profile.first.len == 3);
  CHECK(profile.counts.ptr[0] == 50); /* the repeated stack is summed into the first */
  MsTopList top = {0};
  ms_folded_top(&profile, &top);
  CHECK(top.len == 4);
  CHECK(is_function(&profile, &top.ptr[0], "read") && top.ptr[0].flat == 50 && top.ptr[0].cum == 50);
  CHECK(is_function(&profile, &top.ptr[1], "render") && top.ptr[1].flat == 50);
  CHECK(is_function(&profile, &top.ptr[2], "parse") && top.ptr[2].flat == 10 && top.ptr[2].cum == 60);
  CHECK(is_function(&profile, &top.ptr[3], "main") && top.ptr[3].flat == 0 && top.ptr[3].cum == 110);
  ms_top_list_free(&top);
  ms_folded_free(&profile);
  ms_arena_free(&arena);
}

static void test_recursion_counts_once(void) {
  MsArena arena = ms_arena_new();
  MsFoldedProfile profile;
  CHECK(parse(&arena, "f;f;f 4\n", &profile));
  MsTopList top = {0};
  ms_folded_top(&profile, &top);
  CHECK(top.len == 1 && top.ptr[0].flat == 4 && top.ptr[0].cum == 4);
  ms_top_list_free(&top);
  ms_folded_free(&profile);
  ms_arena_free(&arena);
}

static void test_report(void) {
  MsArena arena = ms_arena_new();
  MsFoldedProfile profile;
  CHECK(parse(&arena, SAMPLE, &profile));
  MsTopList top = {0};
  ms_folded_top(&profile, &top);
  MsStrBuild report = ms_strbuild_new();
  ms_folded_render_top(&profile, &top, 2, &report);
  const char *const expected =
      "Showing top 2 of 4 functions (110 samples, 100 Hz, 1.10s)\n    flat   flat%      cum    cum%  function\n      50  "
      "45.45%       50  45.45%  read\n      50  45.45%       50  45.45%  render\n";
  CHECK(ms_span_is_text(ms_strbuild_span(&report), expected));
  ms_strbuild_free(&report);
  ms_top_list_free(&top);
  ms_folded_free(&profile);
  ms_arena_free(&arena);
}

static void test_few_samples_say_so(void) {
  MsArena arena = ms_arena_new();
  MsFoldedProfile profile;
  CHECK(parse(&arena, "main;work 3\n# period 10\n", &profile));
  MsTopList top = {0};
  ms_folded_top(&profile, &top);
  MsStrBuild report = ms_strbuild_new();
  ms_folded_render_top(&profile, &top, 5, &report);
  size_t at = 0;
  CHECK(ms_span_find(ms_strbuild_span(&report), ms_span_of_text("note: 3 samples is too few to rank functions"), &at));
  ms_strbuild_free(&report);
  ms_top_list_free(&top);
  ms_folded_free(&profile);
  ms_arena_free(&arena);
}

static void test_bad_lines(void) {
  static const char *const bad[] = {"main", "main x", "main 0", "main;;x 1", "# hz=0\nmain 1"};
  for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
    MsArena arena = ms_arena_new();
    MsFoldedProfile profile;
    CHECK(!parse(&arena, bad[i], &profile));
    ms_arena_free(&arena);
  }
}

/* The field numbers of the top-level fields of a protobuf message, in order; `count` of them. */
static size_t top_level_fields(MsSpan bytes, uint64_t *fields, size_t capacity) {
  size_t at = 0;
  size_t count = 0;
  while (at < bytes.len && count < capacity) {
    uint64_t tag = 0;
    for (unsigned shift = 0; at < bytes.len; shift += 7) {
      const uint8_t byte = bytes.ptr[at++];
      tag |= (uint64_t)(byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        break;
      }
    }
    fields[count++] = tag >> 3;
    uint64_t length = 0;
    for (unsigned shift = 0; at < bytes.len; shift += 7) {
      const uint8_t byte = bytes.ptr[at++];
      length |= (uint64_t)(byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        break;
      }
    }
    if ((tag & 7) == 2) {
      at += length; /* a length-delimited field: `length` was its size */
    }
  }
  return count;
}

static size_t occurrences(const uint64_t *fields, size_t count, uint64_t field) {
  size_t found = 0;
  for (size_t i = 0; i < count; i++) {
    found += fields[i] == field ? 1 : 0;
  }
  return found;
}

static void test_pprof_structure(void) {
  MsArena arena = ms_arena_new();
  MsFoldedProfile profile;
  CHECK(parse(&arena, "a;b 3\n", &profile));
  MsStrBuild bytes = ms_strbuild_new();
  ms_folded_encode_pprof(&profile, 42, &bytes);
  uint64_t fields[64];
  const size_t count = top_level_fields(ms_strbuild_span(&bytes), fields, 64);
  /* sample_type twice, one sample, two locations, two functions, the string table, time, duration, period type, period */
  CHECK(occurrences(fields, count, 1) == 2 && occurrences(fields, count, 2) == 1);
  CHECK(occurrences(fields, count, 4) == 2 && occurrences(fields, count, 5) == 2);
  CHECK(occurrences(fields, count, 6) == 7);
  for (uint64_t field = 9; field <= 12; field++) {
    CHECK(occurrences(fields, count, field) == 1);
  }
  ms_strbuild_free(&bytes);
  ms_folded_free(&profile);
  ms_arena_free(&arena);
}

int main(void) {
  test_ranking();
  test_recursion_counts_once();
  test_report();
  test_few_samples_say_so();
  test_bad_lines();
  test_pprof_structure();
  return failures == 0 ? 0 : 1;
}
