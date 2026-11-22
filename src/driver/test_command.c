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
#include "driver/compile_front.h"
#include "driver/invocation.h"
#include "driver/pipeline.h"
#include "driver/test_options.h"
#include "driver/test_run.h"

enum { STATUS_FAILED = 1, STATUS_NOT_IMPLEMENTED = 70 };

typedef struct Plan {
  size_t *selected; /* indices, in execution order */
  size_t count;
} Plan;

static void print_text(FILE *stream, MsSpan text) {
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

typedef struct Totals {
  size_t failed, skipped, not_run, planned;
} Totals;

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
  Totals totals = {.planned = plan->count * repeat};
  for (size_t round = 0; round < repeat; round++) {
    for (size_t p = 0; p < plan->count; p++) {
      const size_t index = plan->selected[p];
      print_line(arena, "RUN %S\n", names->ptr[index], (MsSpan){0});
      TestEntry *entry = test_entry_take(results, index);
      const TestOutcome missing = {.kind = TEST_FAILED, .message = ms_span_of_text("the test reported no result")};
      const TestOutcome *outcome = entry != NULL ? &entry->outcome : &missing;
      print_outcome(arena, names->ptr[index], outcome);
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
  return totals.failed > 0 ? STATUS_FAILED : 0;
}

/* Builds the test executable into `path`. */
static bool build_tests(MsFront *front, const MsInvocation *invocation, MsSpan path, MsSpan *error) {
  const MsLinkRequest request = {.program = &front->program, .entry = front->entry,
                                 .build_type = invocation->build_type, .output = path,
                                 .link = invocation->link.ptr, .link_count = invocation->link.len,
                                 .static_libc = invocation->static_libc, .tests = true};
  return ms_pipeline_link(&request, error);
}

static MsSpan working_directory(MsArena *arena, const MsFront *front, MsSpan filename) {
  MsSpan directory = front->graph.project_root.len > 0 ? front->graph.project_root : ms_path_parent(filename);
  if (directory.len == 0) {
    directory = ms_span_of_text(".");
  }
  return ms_arena_copy(arena, directory);
}

/* Checks `input`, builds its tests and runs the plan. */
static int test_input(MsArena *arena, const MsInvocation *invocation, MsSpan input) {
  MsFront front = {0};
  int status = 0;
  if (!ms_front_compile(arena, &front, input, MS_FRONT_TESTS)) {
    status = ms_front_report(&front);
    ms_front_free(&front);
    return status;
  }
  MsTestOptions options;
  ms_test_options_parse(&invocation->arguments, &options);
  MsSpanList names = {0};
  ms_front_test_names(arena, &front, &names);
  Plan plan = {0};
  if (!select_tests(arena, &names, &options, &plan)) {
    status = STATUS_FAILED;
  } else if (options.list || plan.count == 0) {
    TestJob job = {.arena = arena, .names = &names, .options = &options};
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
    if (!build_tests(&front, invocation, executable, &error)) {
      print_text(stderr, ms_message_format(arena, "%S\n", error, (MsSpan){0}));
      status = STATUS_FAILED;
    } else {
      TestJob job = {.arena = arena, .executable = executable, .working = working_directory(arena, &front, input),
                     .names = &names, .options = &options};
      status = run_plan(arena, &job, &plan);
    }
    ms_path_remove_tree(folder);
    ms_string_release(&directory);
  }
  ms_span_list_free(&names);
  ms_test_options_free(&options);
  ms_front_free(&front);
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
  if (status == 0 && (invocation.watch || invocation.json)) {
    print_text(stderr, ms_message_format(&arena, "ms test: %s is not implemented yet\n",
                                         invocation.watch ? "--watch" : "--json"));
    status = STATUS_NOT_IMPLEMENTED;
  } else if (status == 0 && (options.matching.len > 0 || options.exclude.len > 0)) {
    print_text(stderr, ms_span_of_text("ms test: --match and --exclude need a regular-expression engine, which the "
                                       "driver does not have yet\n"));
    status = STATUS_NOT_IMPLEMENTED;
  } else if (status == 0) {
    status = test_targets(&arena, &invocation);
  }
  ms_test_options_free(&options);
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
