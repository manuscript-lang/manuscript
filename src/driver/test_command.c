/* Owns `ms test` (test_command.h): reads and validates the arguments, checks each input with its test files, builds
 * the test executable, plans which tests run and prints their results. Port of crates/ms-cli/src/engine/testing.rs
 * for tests. Not yet ported: --watch, `--match`/`--exclude` (they need a regular-expression engine the
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
#include "driver/test_document.h"
#include "driver/test_options.h"
#include "driver/test_run.h"
#include "driver/watch.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2, STATUS_NOT_IMPLEMENTED = 70 };

typedef TestPlan Plan;

#define print_text test_print

static void print_line(MsArena *arena, const char *format, MsSpan a, MsSpan b) {
  print_text(stdout, ms_message_format(arena, format, a, b));
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

typedef struct Totals {
  size_t failed, skipped, not_run, planned, passed;
  DocumentCase *rows; /* each planned test, in plan order, one run after another for `--repeat` */
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
  totals.rows = MS_ARENA_NEW_ARRAY(arena, DocumentCase, plan->count * repeat + 1);
  for (size_t p = 0; p < plan->count * repeat; p++) {
    totals.rows[p] = (DocumentCase){.name = names->ptr[plan->selected[p % plan->count]], .status = "not_run"};
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
      totals.rows[round * plan->count + p] = (DocumentCase){.name = names->ptr[index], .failure = outcome->message, .fault = outcome->fault,
                                                            .status = status_name(outcome->kind), .nanos = outcome->nanos};
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

/* The document of a run that did not execute anything: the cases are listed or none were selected. */
static void finish_unrun(const TestJob *job, const Plan *plan, const char *reason, int status) {
  DocumentCase *rows = MS_ARENA_NEW_ARRAY(job->arena, DocumentCase, plan->count + 1);
  for (size_t p = 0; p < plan->count; p++) {
    rows[p] = (DocumentCase){.name = job->names->ptr[plan->selected[p]], .status = "not_run"};
  }
  TestDocument document = {.listed = job->options->list, .repeat = 1, .has_shuffle = job->options->shuffled,
                           .shuffle_seed = job->options->shuffle_seed, .source_root = job->source_root, .cases = rows,
                           .count = plan->count, .available = job->names->len, .reason = ms_span_of_text(reason),
                           .exit_code = status, .completed = true};
  test_document_finish(&document);
}

static int run_plan(MsArena *arena, const TestJob *job, Plan *plan) {
  const MsTestOptions *options = job->options;
  if (options->shuffled) {
    test_plan_shuffle(plan, options->shuffle_seed);
    print_text(stdout, ms_message_format(arena, "shuffle seed: %z\n", (size_t)options->shuffle_seed));
  }
  const bool filtered = options->filter.len > 0 || options->names.len > 0 || options->matching.len > 0 || options->exclude.len > 0;
  if (plan->count == 0 && filtered) {
    print_text(stdout, ms_message_format(arena, "no tests match selection (%z tests available); use --list to find full "
                                                "module::name identities\n",
                                         (size_t)job->names->len));
    finish_unrun(job, plan, "no_match", STATUS_FAILED);
    return STATUS_FAILED;
  }
  if (options->list) {
    for (size_t p = 0; p < plan->count; p++) {
      print_line(arena, "%S\n", job->names->ptr[plan->selected[p]], (MsSpan){0});
    }
    finish_unrun(job, plan, "listed", 0);
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
  const char *reason = totals.planned == 0 ? "no_tests" : totals.failed > 0 && options->fail_fast ? "fail_fast" : "";
  TestDocument document = {.repeat = options->repeat, .has_shuffle = options->shuffled,
                           .shuffle_seed = options->shuffle_seed, .source_root = job->source_root, .cases = totals.rows,
                           .count = plan->count * options->repeat, .available = totals.available, .exit_code = status,
                           .reason = ms_span_of_text(reason), .nanos = totals.nanos, .completed = true};
  test_document_finish(&document);
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
  const bool here = directory.len == 1 && directory.ptr[0] == '.';
  const MsSpan absolute = here ? ms_arena_copy(arena, ms_string_span(&current))
                               : ms_message_format(arena, "%S/%S", ms_string_span(&current), directory);
  ms_string_release(&current);
  return absolute;
}

/* Checks `input`, builds its tests and runs the plan. */
static int test_input(MsArena *arena, const MsInvocation *invocation, MsSpan input, const MsSpanList *extras,
                      MsSpanList *watched) {
  MsCheckedInput checked = {0};
  int status = 0;
  const MsLoadOptions load = {.extra_files = extras == NULL ? NULL : extras->ptr, .extra_count = extras == NULL ? 0 : extras->len};
  if (!ms_checked_input_load_with(arena, &checked, input, MS_INPUT_TESTS, &load)) {
    if (watched != NULL) {
      watch_add_inputs(arena, input, &checked.graph, watched);
    }
    if (!test_capturing()) {
      status = ms_checked_input_report(&checked);
    } else {
      TestDocument document = {.source_root = source_root(arena, &checked, input), .exit_code = STATUS_FAILED,
                               .reason = ms_span_of_text("compile_error"),
                               .diagnostics = ms_checked_input_diagnostics_json(arena, &checked)};
      test_document_finish(&document);
      status = STATUS_FAILED;
    }
    ms_checked_input_free(&checked);
    return status;
  }
  if (watched != NULL) {
    watch_add_inputs(arena, input, &checked.graph, watched);
  }
  MsTestOptions options;
  ms_test_options_parse(&invocation->arguments, &options);
  MsSpanList names = {0};
  ms_checked_input_test_names(arena, &checked, false, &names);
  Plan plan = {0};
  MsSpan selection_error = {0};
  if (!test_plan_select(arena, &names, &options, "test", &plan, &selection_error)) {
    print_text(stderr, ms_message_format(arena, "%S\n", selection_error));
    status = STATUS_FAILED;
    if (test_capturing()) {
      MsStrBuild entry = ms_strbuild_new();
      test_document_diagnostic(&entry, "execution", selection_error, ms_span_of_text(""), 0);
      TestDocument document = {.source_root = source_root(arena, &checked, input),
                               .exit_code = STATUS_FAILED, .reason = ms_span_of_text("no_match"),
                               .diagnostics = ms_arena_copy(arena, ms_strbuild_span(&entry))};
      ms_strbuild_free(&entry);
      test_document_finish(&document);
    }
  } else if (options.list || plan.count == 0) {
    TestJob job = {.arena = arena, .names = &names, .options = &options, .source_root = source_root(arena, &checked, input)};
    status = run_plan(arena, &job, &plan);
  } else {
    const MsString temp = ms_temp_dir();
    MsString directory = ms_string_empty();
    MsSpan error = {0};
    if (!ms_dir_make_temp(ms_string_span(&temp), ms_span_of_text("manuscript-test-"), &directory)) {
      return test_fail_early(arena, source_root(arena, &checked, input), input, false, "execution",
                        ms_span_of_text("cannot create a temporary directory"));
    }
    const MsSpan folder = ms_arena_copy(arena, ms_string_span(&directory));
    const MsSpan executable = ms_message_format(arena, MS_TEMP_PROGRAM, folder, (MsSpan){0});
    if (!build_tests(&checked, invocation, executable, &error)) {
      status = test_fail_early(arena, source_root(arena, &checked, input), input, false, "build", error);
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

static int test_targets(MsArena *arena, const MsInvocation *invocation, MsSpanList *watched) {
  const MsSpanList *targets = &invocation->targets;
  bool members = targets->len > 1;
  for (size_t i = 0; i < targets->len; i++) {
    members = members && is_manifest(targets->ptr[i]);
  }
  if (targets->len > 1 && !members) {
    /* Several files: the first is the input, and the rest are built into the same executable. */
    const MsSpanList more = {.ptr = targets->ptr + 1, .len = targets->len - 1};
    return test_input(arena, invocation, targets->ptr[0], &more, watched);
  }
  int status = 0;
  for (size_t i = 0; i < targets->len; i++) {
    if (members) {
      print_text(stderr, ms_message_format(arena, "ms: testing %S\n", targets->ptr[i], (MsSpan){0}));
    }
    const int result = test_input(arena, invocation, targets->ptr[i], NULL, watched);
    status = result > status ? result : status;
  }
  return status;
}

/* False, with the message on stderr, when `--match` or `--exclude` is not a regular expression. */
static bool selection_valid(MsArena *arena, const MsTestOptions *options) {
  TestFilters filters = {0};
  MsSpan error = {0};
  const bool valid = test_filters_compile(arena, options, &filters, &error);
  test_filters_free(&filters);
  if (!valid) {
    print_text(stderr, ms_message_format(arena, "%S\n", error));
  }
  return valid;
}

/* `--watch`: runs the tests, waits for a change, and runs them again; a failing run keeps watching. */
static int watch_tests(const MsInvocation *invocation, const MsTestOptions *options) {
  for (;;) {
    MsArena arena = ms_arena_new();
    if (!selection_valid(&arena, options)) {
      ms_arena_free(&arena);
      return STATUS_USAGE;
    }
    MsSpanList watched = {0};
    const uint64_t started = watch_now_ms();
    MsStrBuild captured = ms_strbuild_new();
    test_output_capture(invocation->json ? &captured : NULL);
    (void)test_targets(&arena, invocation, &watched);
    test_output_capture(NULL);
    ms_strbuild_free(&captured);
    print_text(stderr, ms_span_of_text("ms: waiting for changes\n"));
    (void)fflush(stdout);
    watch_wait(&watched, started);
    ms_span_list_free(&watched);
    ms_arena_free(&arena);
  }
}

int ms_test_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "test", argc, argv, &invocation);
  MsTestOptions options;
  ms_test_options_parse(&invocation.arguments, &options);
  MsStrBuild captured = ms_strbuild_new();
  if (status == 0 && invocation.watch) {
    status = watch_tests(&invocation, &options);
  } else if (status == 0 && !selection_valid(&arena, &options)) {
    status = STATUS_USAGE;
  } else if (status == 0) {
    test_output_capture(invocation.json ? &captured : NULL);
    status = test_targets(&arena, &invocation, NULL);
    test_output_capture(NULL);
  }
  ms_strbuild_free(&captured);
  ms_test_options_free(&options);
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
