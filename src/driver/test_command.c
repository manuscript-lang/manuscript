/* Owns `ms test` (test_command.h): reads and validates the arguments, checks each input with its test files, builds
 * the test executable, plans which tests run and prints their results. Port of crates/ms-cli/src/engine/testing.rs
 * for tests. Not yet ported: --json, --watch, `--match`/`--exclude` (they need a regular-expression engine the
 * driver does not have), several test files in one executable, fault records and benches. */
#include "driver/test_command.h"

#include <stdio.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "driver/checked_input.h"
#include "compiler/syntax/diag_json.h"
#include "driver/invocation.h"
#include "driver/pipeline.h"
#include "driver/test_options.h"
#include "driver/test_run.h"

enum { STATUS_FAILED = 1, STATUS_NOT_IMPLEMENTED = 70 };

typedef struct Plan {
  size_t *selected; /* indices, in execution order */
  size_t count;
} Plan;

/* With `--json` the command's standard output is the document's `stdout` member, not the terminal. */
static MsStrBuild *capture;

static void print_text(FILE *stream, MsSpan text) {
  if (stream == stdout && capture != NULL) {
    ms_strbuild_append(capture, text);
    return;
  }
  (void)fwrite(text.ptr, 1, text.len, stream);
}

static void print_line(MsArena *arena, const char *format, MsSpan a, MsSpan b) {
  print_text(stdout, ms_message_format(arena, format, a, b));
}

/* Seeded Fisher-Yates, as the Rust CLI does it. */
static void shuffle(size_t *items, size_t count, int64_t seed) {
  uint64_t state = (uint64_t)seed ^ 0x9E3779B97F4A7C15ULL;
  for (size_t i = count; i-- > 1;) {
    state += 0x9E3779B97F4A7C15ULL;
    uint64_t z = state;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    z ^= z >> 31;
    const size_t at = (size_t)(z % (i + 1));
    const size_t held = items[i];
    items[i] = items[at];
    items[at] = held;
  }
}

static bool contains(MsSpan text, MsSpan part) {
  size_t at = 0;
  return part.len == 0 || ms_span_find(text, part, &at);
}

/* The tests the options select. False, with the message printed, when a `--test` names none. */
static bool select_tests(MsArena *arena, const MsSpanList *names, const MsTestOptions *options, Plan *plan) {
  plan->selected = MS_ARENA_NEW_ARRAY(arena, size_t, names->len + 1);
  bool *found = MS_ARENA_NEW_ARRAY(arena, bool, options->names.len + 1);
  for (size_t i = 0; i < names->len; i++) {
    bool exact = options->names.len == 0;
    for (size_t n = 0; n < options->names.len; n++) {
      if (ms_span_equal(options->names.ptr[n], names->ptr[i])) {
        exact = true;
        found[n] = true;
      }
    }
    if (exact && contains(names->ptr[i], options->filter)) {
      plan->selected[plan->count++] = i;
    }
  }
  for (size_t n = 0; n < options->names.len; n++) {
    if (!found[n]) {
      print_text(stderr, ms_message_format(arena, "unknown test \"%S\"; use --list to find full module::name identities\n",
                                           ms_span_of(options->names.ptr[n].ptr, options->names.ptr[n].len),
                                           (MsSpan){0}));
      return false;
    }
  }
  return true;
}

static void print_outcome(MsArena *arena, MsSpan name, const TestOutcome *outcome) {
  print_text(stdout, outcome->output);
  switch (outcome->kind) {
  case TEST_PASSED:
    print_line(arena, "PASS %S\n", name, (MsSpan){0});
    break;
  case TEST_SKIPPED:
    print_line(arena, "SKIP %S: %S\n", name, outcome->message);
    break;
  case TEST_NOT_RUN:
    print_line(arena, "NOT RUN %S: %S\n", name, outcome->message);
    break;
  case TEST_FAILED:
    print_line(arena, "FAIL %S: %S\n", name, outcome->message);
    break;
  }
}

/* One planned test as the `--json` document lists it. */
typedef struct CaseRow {
  MsSpan name, message;
  const char *status;
  int64_t nanos;
} CaseRow;

typedef struct Totals {
  size_t failed, skipped, not_run, planned, passed;
  CaseRow *rows; /* the first run of each selected test, in plan order */
  size_t available;
  int64_t nanos;
} Totals;

static const char *status_name(TestKind kind) {
  switch (kind) {
  case TEST_PASSED: return "passed";
  case TEST_SKIPPED: return "skipped";
  case TEST_NOT_RUN: return "not_run";
  case TEST_FAILED: return "failed";
  }
  return "failed";
}

static void print_summary(MsArena *arena, const Totals *t, bool filtered) {
  if (t->planned == 0 && !filtered) {
    print_line(arena, "no test blocks found: add test blocks to test.ms or *_test.ms files in the project, or pass a "
                      ".ms file\n",
               (MsSpan){0}, (MsSpan){0});
  }
  MsStrBuild summary = ms_strbuild_new();
  ms_strbuild_printf(&summary, "%zu tests, %zu failed", t->planned - t->not_run, t->failed);
  if (t->skipped > 0) {
    ms_strbuild_printf(&summary, ", %zu skipped", t->skipped);
  }
  if (t->not_run > 0) {
    ms_strbuild_printf(&summary, ", %zu not run", t->not_run);
  }
  ms_strbuild_append_byte(&summary, '\n');
  print_text(stdout, ms_strbuild_span(&summary));
  ms_strbuild_free(&summary);
}

/* Prints each planned test in order with its outcome; `--fail-fast` stops at the first failure. */
static Totals report(MsArena *arena, const MsSpanList *names, const Plan *plan, size_t repeat, bool fail_fast,
                     TestEntryList *results) {
  Totals totals = {.planned = plan->count * repeat, .available = names->len};
  totals.rows = MS_ARENA_NEW_ARRAY(arena, CaseRow, plan->count + 1);
  for (size_t p = 0; p < plan->count; p++) {
    totals.rows[p] = (CaseRow){.name = names->ptr[plan->selected[p]], .status = "not_run"};
  }
  for (size_t round = 0; round < repeat; round++) {
    for (size_t p = 0; p < plan->count; p++) {
      const size_t index = plan->selected[p];
      print_line(arena, "RUN %S\n", names->ptr[index], (MsSpan){0});
      TestEntry *entry = test_entry_take(results, index);
      const TestOutcome missing = {.kind = TEST_FAILED, .message = ms_span_of_text("the test reported no result")};
      const TestOutcome *outcome = entry != NULL ? &entry->outcome : &missing;
      print_outcome(arena, names->ptr[index], outcome);
      totals.passed += outcome->kind == TEST_PASSED;
      totals.nanos += outcome->nanos;
      if (round == 0) {
        totals.rows[p] = (CaseRow){.name = names->ptr[index], .message = outcome->message,
                                   .status = status_name(outcome->kind), .nanos = outcome->nanos};
      }
      totals.failed += outcome->kind == TEST_FAILED;
      totals.skipped += outcome->kind == TEST_SKIPPED;
      totals.not_run += outcome->kind == TEST_NOT_RUN;
      if (totals.failed > 0 && fail_fast) {
        totals.not_run += (plan->count - p - 1) + (repeat - round - 1) * plan->count;
        return totals;
      }
    }
  }
  return totals;
}

/* The position `file:line:column` that ends a failure's text (`\n  at f.ms:30:5`), or false. */
static bool failure_position(MsSpan message, MsSpan *file, int64_t *line, int64_t *column) {
  size_t at = message.len;
  int64_t numbers[2] = {0, 0};
  for (int part = 1; part >= 0; part--) {
    size_t end = at;
    while (at > 0 && message.ptr[at - 1] >= '0' && message.ptr[at - 1] <= '9') {
      at--;
    }
    if (at == end || at == 0 || message.ptr[at - 1] != ':') {
      return false;
    }
    for (size_t i = at; i < end; i++) {
      numbers[part] = numbers[part] * 10 + (message.ptr[i] - '0');
    }
    at--;
  }
  const size_t file_end = at;
  size_t start = file_end;
  while (start > 0 && message.ptr[start - 1] != ' ') {
    start--;
  }
  if (start < 4 || start == file_end || !ms_span_starts_with(ms_span_of(message.ptr + start - 5, 5), ms_span_of_text("\n  at"))) {
    return false;
  }
  *file = ms_span_of(message.ptr + start, file_end - start);
  *line = numbers[0];
  *column = numbers[1];
  return true;
}

static void write_json_case(MsStrBuild *out, size_t index, const CaseRow *row) {
  ms_strbuild_printf(out, "%s    {\n      \"index\": %zu,\n      \"duration_ns\": %lld,\n      \"name\": ", index == 0 ? "" : ",\n",
                     index, (long long)row->nanos);
  ms_json_string(out, row->name);
  ms_strbuild_printf(out, ",\n      \"status\": \"%s\"", row->status);
  if (row->message.len > 0) {
    ms_strbuild_append_text(out, ",\n      \"failure\": ");
    ms_json_string(out, row->message);
    MsSpan file;
    int64_t line, column;
    if (failure_position(row->message, &file, &line, &column)) {
      ms_strbuild_append_text(out, ",\n      \"position\": {\n        \"file\": ");
      ms_json_string(out, file);
      ms_strbuild_printf(out, ",\n        \"line\": %lld,\n        \"column\": %lld,\n        \"offset\": 0\n      }",
                         (long long)line, (long long)column);
    }
  }
  ms_strbuild_append_text(out, "\n    }");
}

/* The `--json` document of Rust's `Document::to_json`, for a run that finished. */
static void write_json_report(const TestJob *job, const Plan *plan, const Totals *totals, size_t repeat, int status,
                              MsStrBuild *std_out) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_printf(&out, "{\n  \"repeat\": %zu,\n  \"format\": 1,\n  \"source_root\": ", repeat);
  ms_json_string(&out, job->source_root);
  ms_strbuild_append_text(&out, ",\n  \"tests\": [");
  if (plan->count > 0) {
    ms_strbuild_append_byte(&out, '\n');
  }
  for (size_t p = 0; p < plan->count; p++) {
    write_json_case(&out, p, &totals->rows[p]);
  }
  ms_strbuild_append_text(&out, plan->count > 0 ? "\n  ]" : "]");
  const size_t not_run = totals->not_run > plan->count ? plan->count : totals->not_run;
  ms_strbuild_printf(&out,
                     ",\n  \"summary\": {\n    \"available\": %zu,\n    \"selected\": %zu,\n    \"passed\": %zu,\n    "
                     "\"failed\": %zu,\n    \"skipped\": %zu,\n    \"not_run\": %zu,\n    \"duration_ns\": %lld\n  },\n  "
                     "\"completed\": true,\n  \"exit_code\": %d,\n  \"stdout\": ",
                     totals->available, plan->count, totals->passed, totals->failed, totals->skipped, not_run,
                     (long long)totals->nanos, status);
  ms_json_string(&out, ms_strbuild_span(std_out));
  ms_strbuild_append_text(&out, ",\n  \"diagnostics\": []\n}\n");
  print_text(stdout, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
}

static int run_plan(MsArena *arena, const TestJob *job, Plan *plan) {
  const MsTestOptions *options = job->options;
  if (options->shuffled) {
    shuffle(plan->selected, plan->count, options->shuffle_seed);
    print_text(stdout, ms_message_format(arena, "shuffle seed: %z\n", (size_t)options->shuffle_seed));
  }
  const bool filtered = options->filter.len > 0 || options->names.len > 0;
  if (plan->count == 0 && filtered) {
    print_text(stdout, ms_message_format(arena, "no tests match selection (%z tests available); use --list to find full "
                                                "module::name identities\n",
                                         (size_t)job->names->len));
    return STATUS_FAILED;
  }
  if (options->list) {
    for (size_t p = 0; p < plan->count; p++) {
      print_line(arena, "%S\n", job->names->ptr[plan->selected[p]], (MsSpan){0});
    }
    return 0;
  }
  TestEntryList results = {0};
  for (size_t round = 0; round < options->repeat && plan->count > 0; round++) {
    test_run_all(job, plan->selected, plan->count, &results);
  }
  const Totals totals = report(arena, job->names, plan, options->repeat, options->fail_fast, &results);
  print_summary(arena, &totals, filtered);
  test_entry_list_free(&results);
  const int status = totals.failed > 0 ? STATUS_FAILED : 0;
  if (capture != NULL) {
    MsStrBuild *std_out = capture;
    capture = NULL;
    write_json_report(job, plan, &totals, options->repeat, status, std_out);
    capture = std_out;
  }
  return status;
}

/* Builds the test executable into `path`. */
static bool build_tests(MsCheckedInput *checked, const MsInvocation *invocation, MsSpan path, MsSpan *error) {
  const MsLinkRequest request = {.program = &checked->program, .entry = checked->entry,
                                 .build_type = invocation->build_type, .output = path,
                                 .link = invocation->link.ptr, .link_count = invocation->link.len,
                                 .static_libc = invocation->static_libc, .tests = true};
  return ms_pipeline_link(&request, error);
}

static MsSpan working_directory(MsArena *arena, const MsCheckedInput *checked, MsSpan filename) {
  MsSpan directory = checked->graph.project_root.len > 0 ? checked->graph.project_root : ms_path_parent(filename);
  if (directory.len == 0) {
    directory = ms_span_of_text(".");
  }
  return ms_arena_copy(arena, directory);
}

/* The absolute directory of the project, or of the file for a lone file. */
static MsSpan source_root(MsArena *arena, const MsCheckedInput *checked, MsSpan input) {
  const MsSpan directory = working_directory(arena, checked, input);
  if (ms_path_is_absolute(directory)) {
    return directory;
  }
  MsString current = ms_string_empty();
  if (!ms_dir_current(&current)) {
    return directory;
  }
  const MsSpan absolute = ms_message_format(arena, "%S/%S", ms_string_span(&current), directory);
  ms_string_release(&current);
  return absolute;
}

/* Checks `input`, builds its tests and runs the plan. */
static int test_input(MsArena *arena, const MsInvocation *invocation, MsSpan input) {
  MsCheckedInput checked = {0};
  int status = 0;
  if (!ms_checked_input_load(arena, &checked, input, MS_INPUT_TESTS)) {
    status = ms_checked_input_report(&checked);
    ms_checked_input_free(&checked);
    return status;
  }
  MsTestOptions options;
  ms_test_options_parse(&invocation->arguments, &options);
  MsSpanList names = {0};
  ms_checked_input_test_names(arena, &checked, &names);
  Plan plan = {0};
  if (!select_tests(arena, &names, &options, &plan)) {
    status = STATUS_FAILED;
  } else if (options.list || plan.count == 0) {
    TestJob job = {.arena = arena, .names = &names, .options = &options, .source_root = source_root(arena, &checked, input)};
    status = run_plan(arena, &job, &plan);
  } else {
    const MsString temp = ms_temp_dir();
    MsString directory = ms_string_empty();
    MsSpan error = {0};
    if (!ms_dir_make_temp(ms_string_span(&temp), ms_span_of_text("manuscript-test-"), &directory)) {
      print_text(stderr, ms_span_of_text("cannot create a temporary directory\n"));
      return STATUS_FAILED;
    }
    const MsSpan folder = ms_arena_copy(arena, ms_string_span(&directory));
    const MsSpan executable = ms_message_format(arena, "%S/program", folder, (MsSpan){0});
    if (!build_tests(&checked, invocation, executable, &error)) {
      print_text(stderr, ms_message_format(arena, "%S\n", error, (MsSpan){0}));
      status = STATUS_FAILED;
    } else {
      TestJob job = {.arena = arena, .executable = executable, .working = working_directory(arena, &checked, input),
                     .names = &names, .options = &options, .source_root = source_root(arena, &checked, input)};
      status = run_plan(arena, &job, &plan);
    }
    ms_path_remove_tree(folder);
    ms_string_release(&directory);
  }
  ms_span_list_free(&names);
  ms_test_options_free(&options);
  ms_checked_input_free(&checked);
  return status;
}

static bool is_manifest(MsSpan path) {
  return ms_span_is_text(ms_path_file_name(path), "ms.toml");
}

static int test_targets(MsArena *arena, const MsInvocation *invocation) {
  const MsSpanList *targets = &invocation->targets;
  bool members = targets->len > 1;
  for (size_t i = 0; i < targets->len; i++) {
    members = members && is_manifest(targets->ptr[i]);
  }
  if (targets->len > 1 && !members) {
    print_text(stderr, ms_span_of_text("ms test: several test files in one executable are not implemented yet\n"));
    return STATUS_NOT_IMPLEMENTED;
  }
  int status = 0;
  for (size_t i = 0; i < targets->len; i++) {
    if (members) {
      print_text(stderr, ms_message_format(arena, "ms: testing %S\n", targets->ptr[i], (MsSpan){0}));
    }
    const int result = test_input(arena, invocation, targets->ptr[i]);
    status = result > status ? result : status;
  }
  return status;
}

int ms_test_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "test", argc, argv, &invocation);
  MsTestOptions options;
  ms_test_options_parse(&invocation.arguments, &options);
  MsStrBuild captured = ms_strbuild_new();
  if (status == 0 && invocation.watch) {
    print_text(stderr, ms_span_of_text("ms test: --watch is not implemented yet\n"));
    status = STATUS_NOT_IMPLEMENTED;
  } else if (status == 0 && (options.matching.len > 0 || options.exclude.len > 0)) {
    print_text(stderr, ms_span_of_text("ms test: --match and --exclude need a regular-expression engine, which the "
                                       "driver does not have yet\n"));
    status = STATUS_NOT_IMPLEMENTED;
  } else if (status == 0) {
    capture = invocation.json ? &captured : NULL;
    status = test_targets(&arena, &invocation);
    capture = NULL;
  }
  ms_strbuild_free(&captured);
  ms_test_options_free(&options);
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
