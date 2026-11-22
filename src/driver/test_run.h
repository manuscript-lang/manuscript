/* driver/test_run.h: running the test executable and reading its records. Port of `Runner`, `RecordReader` and
 * `run_all_together` in crates/ms-cli/src/engine/testing.rs. The protocol is documented in
 * stdlib/internal/test_runner.ms. */
#ifndef MS_DRIVER_TEST_RUN_H
#define MS_DRIVER_TEST_RUN_H

#include "base/arena.h"
#include "base/intern.h"
#include "base/list.h"
#include "driver/test_options.h"

typedef enum TestKind { TEST_PASSED, TEST_NOT_RUN, TEST_SKIPPED, TEST_FAILED } TestKind;

/* How one test ended, what it printed and how long it took. */
typedef struct TestOutcome {
  TestKind kind;
  MsSpan message; /* the failure (with its site), the skip reason, or why it did not run */
  MsSpan output;
  int64_t nanos;
} TestOutcome;

/* What to run: the executable, where, and which tests (`indices`) of the `names` (`file::name`). */
typedef struct TestJob {
  MsArena *arena;
  MsSpan executable, working;
  const MsSpanList *names;
  const MsTestOptions *options;
} TestJob;

typedef struct TestEntry {
  size_t index;
  TestOutcome outcome;
  bool taken;
} TestEntry;

MS_LIST_DEFINE(TestEntryList, test_entry_list, TestEntry)

/* The outcomes of running `indices`, one run of the executable after another until each test has one. The standard
 * output the program wrote outside the tests goes to stdout. */
void test_run_all(const TestJob *job, const size_t *indices, size_t count, TestEntryList *results);

/* The first outcome of test `index` not yet taken, or NULL. */
TestEntry *test_entry_take(TestEntryList *results, size_t index);

#endif
