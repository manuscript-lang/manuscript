/* Unit test of the terminal diagnostic report: an absolute file is a location already, so the source root
 * is not prefixed onto it. */
#include <stdio.h>
#include <string.h>

#include "base/file.h"
#include "base/path.h"
#include "base/strbuild.h"
#include "tooling/findings.h"

static int failures = 0;

#define CHECK(condition)                                                                                     \
  do {                                                                                                       \
    if (!(condition)) {                                                                                      \
      (void)fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #condition);                                  \
      failures++;                                                                                            \
    }                                                                                                        \
  } while (0)

static bool starts_with(MsSpan text, MsSpan prefix) {
  return text.len >= prefix.len && memcmp(text.ptr, prefix.ptr, prefix.len) == 0;
}

static Finding one(MsSpan file, const char *phase, const char *message) {
  return (Finding){.file = file, .phase = phase, .diag = {.pos = {.line = 1, .column = 1},
                                                          .message = ms_span_of_text(message)}};
}

static void test_absolute_file_is_not_prefixed(void) {
  MsString cwd = ms_string_empty();
  CHECK(ms_dir_current(&cwd));
  MsStrBuild missing = ms_strbuild_new();
  ms_path_join(ms_string_span(&cwd), ms_span_of_text("no-such-file.ms"), &missing);
  const MsSpan file = ms_strbuild_span(&missing);
  CHECK(ms_path_is_absolute(file));

  Finding stored = one(file, "resolution", "file not found");
  FindingList findings = {.ptr = &stored, .len = 1, .cap = 1};
  MsStrBuild err = ms_strbuild_new();
  finding_terminal_text(&err, ms_string_span(&cwd), &findings, false);
  const MsSpan text = ms_strbuild_span(&err);

  MsStrBuild doubled = ms_strbuild_new();
  ms_path_append_joined(&doubled, ms_string_span(&cwd), file);
  CHECK(!starts_with(text, ms_strbuild_span(&doubled)));
  CHECK(starts_with(text, file));
  CHECK(text.len > file.len && text.ptr[file.len] == ':');

  ms_strbuild_free(&doubled);
  ms_strbuild_free(&err);
  ms_strbuild_free(&missing);
  ms_string_release(&cwd);
}

static void test_relative_file_keeps_the_root(void) {
  Finding stored = one(ms_span_of_text("main.ms"), "type", "nope");
  stored.diag.pos.line = 2;
  stored.diag.pos.column = 3;
  FindingList findings = {.ptr = &stored, .len = 1, .cap = 1};
  MsStrBuild err = ms_strbuild_new();
  finding_terminal_text(&err, ms_span_of_text("/proj"), &findings, false);
  const MsSpan text = ms_strbuild_span(&err);
  const MsSpan expect = ms_span_of_text("/proj/main.ms:2:3: type: nope");
  CHECK(starts_with(text, expect));
  ms_strbuild_free(&err);
}

static void test_package_file_has_no_root(void) {
  Finding stored = one(ms_span_of_text("@pkg/lib.ms"), "resolution", "missing");
  FindingList findings = {.ptr = &stored, .len = 1, .cap = 1};
  MsStrBuild err = ms_strbuild_new();
  finding_terminal_text(&err, ms_span_of_text("/proj"), &findings, false);
  const MsSpan text = ms_strbuild_span(&err);
  CHECK(starts_with(text, ms_span_of_text("@pkg/lib.ms:1:1: resolution: missing")));
  ms_strbuild_free(&err);
}

int main(void) {
  test_absolute_file_is_not_prefixed();
  test_relative_file_keeps_the_root();
  test_package_file_has_no_root();
  return failures == 0 ? 0 : 1;
}
