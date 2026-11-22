/* Owns `ms bench` (bench_command.h): reads the arguments, checks the input with its bench files, selects and plans the
 * bench blocks, builds the executable and runs each bench in its own process. Port of the bench half of
 * crates/ms-cli/src/engine/testing.rs. Not yet ported: `--match` and `--exclude` (they need a regular-expression
 * engine) and fault records (a crash is reported by its status and standard error). */
#include "driver/bench_command.h"

#include <stdio.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/float_parse.h"
#include "base/message.h"
#include "base/path.h"
#include "base/process.h"
#include "driver/checked_input.h"
#include "driver/invocation.h"
#include "driver/json_value.h"
#include "driver/pipeline.h"
#include "driver/test_document.h"
#include "driver/test_options.h"
#include "driver/watch.h"

enum { STATUS_FAILED = 1, STATUS_NOT_IMPLEMENTED = 70, DEFAULT_BENCH_TIMEOUT_MS = 600000, NANOS_PER_MS = 1000000 };

/* The counters a baseline compares: work done, not time, so a loaded machine does not flake. */
static const char *const WORK_COUNTERS[] = {"mir_ops",   "allocations",  "allocated_bytes",   "list_copies",
                                            "list_copy_bytes", "string_clones", "string_clone_bytes"};

static void print_line(MsArena *arena, const char *format, MsSpan a, MsSpan b) {
  test_print(stdout, ms_message_format(arena, format, a, b));
}

/* The number at `key` of an object, or NaN. */
static double number_of(const MsJson *object, const char *key) {
  const MsJson *member = ms_json_member(object, key);
  double value = 0;
  if (member != NULL && member->kind == MS_JSON_NUMBER && ms_parse_float(member->text, &value) == MS_PARSE_FLOAT_OK) {
    return value;
  }
  return __builtin_nan("");
}

/* A whole-number member, or 0. */
static int64_t whole_of(const MsJson *object, const char *key) {
  const double value = number_of(object, key);
  return value == value && value == (double)(int64_t)value ? (int64_t)value : 0;
}

/* A duration given in nanoseconds with a fitting unit: `12.3 ns`, `4.56 µs`, `7.89 ms`, `1.23 s`. */
static void format_ns(MsStrBuild *out, double nanos) {
  const char *unit = "s";
  double value = nanos / 1e9;
  if (nanos != nanos) {
    ms_strbuild_append_text(out, "NaN s");
    return;
  }
  if (nanos < 1e3) {
    value = nanos;
    unit = "ns";
  } else if (nanos < 1e6) {
    value = nanos / 1e3;
    unit = "\xC2\xB5s";
  } else if (nanos < 1e9) {
    value = nanos / 1e6;
    unit = "ms";
  }
  char text[64];
  (void)snprintf(text, sizeof text, "%.3f %s", value, unit);
  ms_strbuild_append_text(out, text);
}

/* A per-operation count: whole numbers print as integers, fractions with two decimals. */
static void count_text(MsStrBuild *out, double value) {
  char text[64];
  (void)snprintf(text, sizeof text, value == (double)(long long)value ? "%.0f" : "%.2f", value);
  ms_strbuild_append_text(out, text);
}

/* The one-line summary of a bench's statistics. */
static MsSpan describe_stats(MsArena *arena, const MsJson *stats) {
  MsStrBuild out = ms_strbuild_new();
  format_ns(&out, number_of(stats, "median_ns"));
  ms_strbuild_append_text(&out, "/op median (min ");
  format_ns(&out, number_of(stats, "min_ns"));
  ms_strbuild_append_text(&out, ", mean ");
  format_ns(&out, number_of(stats, "mean_ns"));
  ms_strbuild_append_text(&out, ", max ");
  format_ns(&out, number_of(stats, "max_ns"));
  ms_strbuild_append_text(&out, ", stddev ");
  format_ns(&out, number_of(stats, "stddev_ns"));
  ms_strbuild_printf(&out, "; %lld iterations x %lld samples; cpu ", (long long)whole_of(stats, "iterations"),
                     (long long)whole_of(stats, "samples"));
  format_ns(&out, number_of(stats, "cpu_ns"));
  ms_strbuild_append_text(&out, "/op");
  const double ops = number_of(stats, "mir_ops");
  if (ops > 0) {
    ms_strbuild_append_text(&out, "; ");
    count_text(&out, ops);
    ms_strbuild_append_text(&out, " MIR ops");
  }
  if (ms_json_member(stats, "allocations") != NULL) {
    ms_strbuild_append_text(&out, "; ");
    count_text(&out, number_of(stats, "allocations"));
    ms_strbuild_append_text(&out, " allocs, ");
    count_text(&out, number_of(stats, "allocated_bytes"));
    ms_strbuild_append_text(&out, " bytes, ");
    count_text(&out, number_of(stats, "list_copies"));
    ms_strbuild_append_text(&out, " list copies, ");
    count_text(&out, number_of(stats, "string_clones"));
    ms_strbuild_append_text(&out, " string clones per op");
  }
  ms_strbuild_append_byte(&out, ')');
  const MsSpan text = ms_arena_copy(arena, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return text;
}

/* The statistics object of the last `MSBENCH` line, or NULL. */
static const MsJson *measurement(MsArena *arena, MsSpan printed) {
  MsSpan found = {0};
  size_t at = 0;
  while (at < printed.len) {
    size_t end = at;
    while (end < printed.len && printed.ptr[end] != '\n') {
      end++;
    }
    const MsSpan line = ms_span_of(printed.ptr + at, end - at);
    if (ms_span_starts_with(line, ms_span_of_text("MSBENCH "))) {
      found = ms_span_of(line.ptr + 8, line.len - 8);
    }
    at = end + 1;
  }
  return found.len == 0 ? NULL : ms_json_parse(arena, found);
}

static MsSpan read_text(MsArena *arena, MsSpan path) {
  MsBytes bytes = {0};
  MsSpan text = {0};
  if (ms_file_read(path, &bytes)) {
    text = ms_arena_copy(arena, ms_bytes_span(&bytes));
  }
  ms_bytes_free(&bytes);
  return text;
}

static MsSpan trim_end(MsSpan text) {
  while (text.len > 0 && (text.ptr[text.len - 1] == '\n' || text.ptr[text.len - 1] == '\r')) {
    text.len--;
  }
  return text;
}

/* A limit as Rust prints a `Duration`: `600s`, `100ms`, `1.5s`. */
static MsSpan describe_limit(MsArena *arena, int64_t ms) {
  if (ms < 1000) {
    return ms_message_format(arena, "%zms", (size_t)ms);
  }
  char text[32];
  int length = snprintf(text, sizeof text, "%lld.%03lld", (long long)(ms / 1000), (long long)(ms % 1000));
  while (text[length - 1] == '0') {
    length--;
  }
  if (text[length - 1] == '.') {
    length--;
  }
  text[length++] = 's';
  return ms_arena_copy(arena, ms_span_of((const uint8_t *)text, (size_t)length));
}

/* What one bench's process did. */
typedef struct Outcome {
  bool measured;
  MsSpan message;
  const MsJson *stats;
} Outcome;

typedef struct Limit {
  uint64_t began_ms, limit_ms;
  bool expired;
} Limit;

static bool past_limit(void *context) {
  Limit *limit = context;
  limit->expired = limit->expired || (limit->limit_ms > 0 && watch_now_ms() - limit->began_ms >= limit->limit_ms);
  return limit->expired;
}

/* Runs bench `index` in its own process: only its statistics are kept, since its own output would repeat once per
 * iteration. */
static Outcome run_one(MsArena *arena, MsSpan executable, MsSpan working, const MsTestOptions *options, size_t index,
                       MsSpan folder, size_t round) {
  const MsSpan printed = ms_message_format(arena, "%S/bench-stdout-%z", folder, round);
  const MsSpan errors = ms_message_format(arena, "%S/bench-stderr-%z", folder, round);
  const MsSpan results = ms_message_format(arena, "%S/bench-results-%z", folder, round);
  MsSpanList env = {0};
  ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_SELECT=%z", index));
  ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_RESULTS=%S", results, (MsSpan){0}));
  if (options->runs > 0) {
    ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_RUNS=%z", (size_t)options->runs));
  }
  if (options->has_seed) {
    ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_SEED=%z", (size_t)options->seed));
  }
  if (options->fuzz_ms > 0) {
    ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_FUZZ_MS=%z", (size_t)options->fuzz_ms));
  }
  if (options->bench_time_ms > 0) {
    ms_span_list_push(&env, ms_message_format(arena, "MS_BENCH_TIME_MS=%z", (size_t)options->bench_time_ms));
  }
  if (options->bench_samples > 0) {
    ms_span_list_push(&env, ms_message_format(arena, "MS_BENCH_SAMPLES=%z", (size_t)options->bench_samples));
  }
  if (options->bench_iterations > 0) {
    ms_span_list_push(&env, ms_message_format(arena, "MS_BENCH_ITERATIONS=%z", (size_t)options->bench_iterations));
  }
  MsSpanList argv = {0};
  ms_span_list_push(&argv, executable);
  for (size_t i = 0; i < options->program_count; i++) {
    ms_span_list_push(&argv, options->program[i]);
  }
  Limit limit = {.began_ms = watch_now_ms(), .limit_ms = (uint64_t)options->timeout_ms};
  const MsProcessSpec spec = {.argv = argv.ptr, .argc = argv.len, .directory = working, .env = env.ptr, .envc = env.len,
                              .log_path = printed, .error_path = errors, .supervise = past_limit,
                              .supervise_context = &limit};
  MsStrBuild why = ms_strbuild_new();
  int status = 0;
  (void)fflush(stdout);
  Outcome outcome = {0};
  const bool started = ms_process_run(&spec, &status, &why);
  const MsSpan text = trim_end(read_text(arena, errors));
  if (!started) {
    outcome.message = ms_arena_copy(arena, ms_strbuild_span(&why));
  } else if (limit.expired) {
    outcome.message = ms_message_format(arena, "timed out after %S; the test was cancelled (use --timeout to change the "
                                               "limit, 0 disables it)", describe_limit(arena, options->timeout_ms));
  } else if (status == 0) {
    if (text.len > 0) {
      test_print(stderr, ms_message_format(arena, "%S\n", text));
    }
    outcome.stats = measurement(arena, read_text(arena, results));
    outcome.measured = outcome.stats != NULL;
    if (!outcome.measured) {
      outcome.message = ms_span_of_text("the bench reported no statistics");
    }
  } else if (text.len > 0) {
    outcome.message = text;
  } else {
    outcome.message = status < 0 ? ms_span_of_text("test process was terminated by a signal")
                                 : ms_message_format(arena, "test process exited with status %z", (size_t)status);
  }
  ms_strbuild_free(&why);
  ms_span_list_free(&env);
  ms_span_list_free(&argv);
  return outcome;
}

/* Compares the work counters of every measured bench with the `--baseline` result and reports each one that rose by
 * more than `--fail-over` percent. `*regressed` says whether any did; false when the baseline cannot be read. */
static bool check_baseline(MsArena *arena, const MsTestOptions *options, const DocumentCase *cases, size_t count,
                           bool *regressed) {
  const MsSpan path = options->baseline;
  MsBytes bytes = {0};
  if (!ms_file_read(path, &bytes)) {
    test_print(stderr, ms_message_format(arena, "cannot read --baseline %S: No such file or directory (os error 2)\n", path,
                                         (MsSpan){0}));
    return false;
  }
  const MsJson *baseline = ms_json_parse(arena, ms_arena_copy(arena, ms_bytes_span(&bytes)));
  ms_bytes_free(&bytes);
  if (baseline == NULL) {
    test_print(stderr, ms_message_format(arena, "--baseline %S is not the JSON that `ms bench --json` writes\n", path,
                                         (MsSpan){0}));
    return false;
  }
  const MsJson *earlier = ms_json_member(baseline, "benches");
  if (earlier == NULL || earlier->kind != MS_JSON_ARRAY) {
    test_print(stderr, ms_message_format(arena, "--baseline %S has no benches; save `ms bench --json` output\n", path,
                                         (MsSpan){0}));
    return false;
  }
  const double bound = options->fail_over;
  for (size_t c = 0; c < count; c++) {
    const DocumentCase *now = &cases[c];
    if (now->stats == NULL) {
      continue;
    }
    const MsJson *before = NULL;
    for (size_t i = 0; i < earlier->count && before == NULL; i++) {
      const MsJson *name = ms_json_member(earlier->items[i], "name");
      if (name != NULL && name->kind == MS_JSON_STRING && ms_span_equal(name->text, now->name)) {
        before = ms_json_member(earlier->items[i], "stats");
      }
    }
    if (before == NULL) {
      print_line(arena, "NEW %S: not in the baseline\n", now->name, (MsSpan){0});
      continue;
    }
    for (size_t k = 0; k < sizeof WORK_COUNTERS / sizeof WORK_COUNTERS[0]; k++) {
      const double was = number_of(before, WORK_COUNTERS[k]);
      const double is = number_of(now->stats, WORK_COUNTERS[k]);
      if (was != was || is != is) {
        continue;
      }
      /* A counter that was zero may rise by up to one before it counts. */
      const double allowed = was * (1.0 + bound / 100.0) + (was == 0.0 ? 1.0 : 0.0);
      if (is > allowed) {
        *regressed = true;
        MsStrBuild line = ms_strbuild_new();
        ms_strbuild_printf(&line, "REGRESSED %.*s: %s ", (int)now->name.len, (const char *)now->name.ptr, WORK_COUNTERS[k]);
        count_text(&line, was);
        ms_strbuild_append_text(&line, " -> ");
        count_text(&line, is);
        char shown[64];
        (void)snprintf(shown, sizeof shown, bound == (double)(long long)bound ? " (over the %.0f%% bound)\n"
                                                                              : " (over the %g%% bound)\n", bound);
        ms_strbuild_append_text(&line, shown);
        test_print(stdout, ms_strbuild_span(&line));
        ms_strbuild_free(&line);
      }
    }
  }
  return true;
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

typedef struct Run {
  MsArena *arena;
  MsCheckedInput *checked;
  const MsInvocation *invocation;
  const MsSpanList *names;
  const TestPlan *plan;
  TestDocument *document;
  MsSpan working, executable, folder;
} Run;

/* Runs each planned bench in turn and prints its result; returns how many failed. */
static size_t run_plan(const Run *run, const MsTestOptions *options, size_t repeat, const char **reason) {
  size_t failed = 0;
  MsArena *arena = run->arena;
  for (size_t p = 0; p < run->plan->count * repeat; p++) {
    const size_t index = run->plan->selected[p % run->plan->count];
    const MsSpan name = run->names->ptr[index];
    DocumentCase *row = &run->document->cases[p];
    print_line(arena, "RUN %S\n", name, (MsSpan){0});
    const uint64_t began = watch_now_ms();
    const Outcome outcome = run_one(arena, run->executable, run->working, options, index, run->folder, p);
    row->nanos = (int64_t)(watch_now_ms() - began) * NANOS_PER_MS;
    if (outcome.measured) {
      print_line(arena, "BENCH %S: ", name, (MsSpan){0});
      print_line(arena, "%S\n", describe_stats(arena, outcome.stats), (MsSpan){0});
      row->status = "passed";
      row->stats = outcome.stats;
    } else {
      failed++;
      print_line(arena, "FAIL %S: ", name, (MsSpan){0});
      print_line(arena, "%S\n", outcome.message, (MsSpan){0});
      row->status = "failed";
      row->failure = outcome.message;
    }
    if (failed > 0 && options->fail_fast) {
      *reason = "fail_fast";
      break;
    }
  }
  return failed;
}

/* Builds the bench executable and runs the plan. */
static int build_and_run(Run *run, const MsTestOptions *options, MsSpan input, int *status) {
  MsArena *arena = run->arena;
  const MsString temp = ms_temp_dir();
  MsString directory = ms_string_empty();
  const MsSpan root = run->document->source_root;
  if (!ms_dir_make_temp(ms_string_span(&temp), ms_span_of_text("manuscript-bench-"), &directory)) {
    *status = test_fail_early(arena, root, input, true, "execution", ms_span_of_text("cannot create a temporary directory"));
    return 0;
  }
  run->folder = ms_arena_copy(arena, ms_string_span(&directory));
  run->executable = ms_message_format(arena, MS_TEMP_PROGRAM, run->folder, (MsSpan){0});
  const MsInvocation *invocation = run->invocation;
  const MsLinkRequest request = {.program = &run->checked->program, .entry = run->checked->entry,
                                 .build_type = invocation->build_type, .output = run->executable,
                                 .link = invocation->link.ptr, .link_count = invocation->link.len,
                                 .static_libc = invocation->static_libc, .tests = true, .bench = true,
                                 .count_ops = options->ops};
  MsSpan error = {0};
  if (!ms_pipeline_link(&request, &error)) {
    *status = test_fail_early(arena, root, input, true, "build", error);
    ms_path_remove_tree(run->folder);
    ms_string_release(&directory);
    return 0;
  }
  const char *reason = "";
  const uint64_t began = watch_now_ms();
  const size_t failed = run_plan(run, options, options->repeat, &reason);
  run->document->nanos = (int64_t)(watch_now_ms() - began) * NANOS_PER_MS;
  run->document->reason = ms_span_of_text(reason);
  ms_path_remove_tree(run->folder);
  ms_string_release(&directory);
  *status = failed > 0 ? STATUS_FAILED : 0;
  return 1;
}

/* The summary line: how many benches ran, failed and did not run. */
static void print_summary(MsArena *arena, const TestDocument *document) {
  size_t failed = 0;
  size_t not_run = 0;
  size_t skipped = 0;
  for (size_t i = 0; i < document->count; i++) {
    const char *status = document->cases[i].status;
    failed += ms_span_is_text(ms_span_of_text(status), "failed");
    skipped += ms_span_is_text(ms_span_of_text(status), "skipped");
    not_run += ms_span_is_text(ms_span_of_text(status), "not_run");
  }
  MsStrBuild line = ms_strbuild_new();
  ms_strbuild_printf(&line, "%zu benches, %zu failed", document->count - not_run, failed);
  if (skipped > 0) {
    ms_strbuild_printf(&line, ", %zu skipped", skipped);
  }
  if (not_run > 0) {
    ms_strbuild_printf(&line, ", %zu not run", not_run);
  }
  ms_strbuild_append_byte(&line, '\n');
  test_print(stdout, ms_strbuild_span(&line));
  ms_strbuild_free(&line);
  (void)arena;
}

static int bench_input(MsArena *arena, const MsInvocation *invocation) {
  const MsSpan input = invocation->filename;
  MsCheckedInput checked = {0};
  if (!ms_checked_input_load(arena, &checked, input, MS_INPUT_TESTS)) {
    int status = 0;
    if (test_capturing()) {
      TestDocument document = {.bench = true, .source_root = source_root(arena, &checked, input), .exit_code = STATUS_FAILED,
                               .reason = ms_span_of_text("compile_error"),
                               .diagnostics = ms_checked_input_diagnostics_json(arena, &checked)};
      test_document_finish(&document);
      status = STATUS_FAILED;
    } else {
      status = ms_checked_input_report(&checked);
    }
    ms_checked_input_free(&checked);
    return status;
  }
  MsTestOptions options;
  ms_test_options_parse(&invocation->arguments, &options);
  if (options.ops) {
    /* The counter slows the program, so run once: the count does not need more. */
    options.bench_iterations = options.bench_iterations > 0 ? options.bench_iterations : 1;
    options.bench_samples = options.bench_samples > 0 ? options.bench_samples : 1;
  }
  if (!options.timeout_set) {
    options.timeout_ms = DEFAULT_BENCH_TIMEOUT_MS;
  }
  MsSpanList names = {0};
  ms_checked_input_test_names(arena, &checked, true, &names);
  const MsSpan root = source_root(arena, &checked, input);
  TestPlan plan = {0};
  MsSpan selection_error = {0};
  int status = STATUS_FAILED;
  if (!test_plan_select(arena, &names, &options, "bench", &plan, &selection_error)) {
    test_print(stderr, ms_message_format(arena, "%S\n", selection_error));
    if (test_capturing()) {
      MsStrBuild entry = ms_strbuild_new();
      test_document_diagnostic(&entry, "execution", selection_error, ms_span_of_text(""), 0);
      TestDocument document = {.bench = true, .source_root = root, .exit_code = STATUS_FAILED,
                               .reason = ms_span_of_text("no_match"),
                               .diagnostics = ms_arena_copy(arena, ms_strbuild_span(&entry))};
      ms_strbuild_free(&entry);
      test_document_finish(&document);
    }
  } else {
    if (options.shuffled) {
      test_plan_shuffle(&plan, options.shuffle_seed);
      test_print(stdout, ms_message_format(arena, "shuffle seed: %z\n", (size_t)options.shuffle_seed));
    }
    const size_t repeat = options.list ? 1 : options.repeat;
    TestDocument document = {.bench = true, .repeat = repeat, .has_shuffle = options.shuffled,
                             .shuffle_seed = options.shuffle_seed, .source_root = root, .available = names.len,
                             .count = plan.count * repeat, .exit_code = STATUS_FAILED, .listed = options.list};
    document.cases = MS_ARENA_NEW_ARRAY(arena, DocumentCase, document.count + 1);
    for (size_t p = 0; p < document.count; p++) {
      document.cases[p] = (DocumentCase){.name = names.ptr[plan.selected[p % plan.count]], .status = "not_run"};
    }
    const bool filtered = options.filter.len > 0 || options.names.len > 0;
    if (plan.count == 0 && filtered) {
      test_print(stdout, ms_message_format(arena, "no benches match selection (%z benches available); use --list to find "
                                                  "full module::name identities\n", names.len));
      document.reason = ms_span_of_text("no_match");
      document.completed = true;
      test_document_finish(&document);
    } else if (options.list) {
      for (size_t p = 0; p < document.count; p++) {
        print_line(arena, "%S\n", document.cases[p].name, (MsSpan){0});
      }
      document.reason = ms_span_of_text("listed");
      document.completed = true;
      document.exit_code = 0;
      test_document_finish(&document);
      status = 0;
    } else {
      Run run = {.arena = arena, .checked = &checked, .invocation = invocation, .names = &names, .plan = &plan,
                 .document = &document, .working = working_directory(arena, &checked, input)};
      if (plan.count == 0 || build_and_run(&run, &options, input, &status)) {
        if (plan.count == 0) {
          test_print(stdout, ms_span_of_text("no bench blocks found: add bench blocks to bench.ms or *_bench.ms files in "
                                             "the project, or pass a .ms file\n"));
          document.reason = ms_span_of_text("no_benches");
          status = 0;
        }
        print_summary(arena, &document);
        bool regressed = false;
        if (status == 0 && options.baseline.len > 0 && !check_baseline(arena, &options, document.cases, document.count, &regressed)) {
          status = 2;
        } else if (regressed) {
          status = STATUS_FAILED;
        }
        document.exit_code = status;
        document.completed = true;
        test_document_finish(&document);
      }
    }
  }
  ms_span_list_free(&names);
  ms_test_options_free(&options);
  ms_checked_input_free(&checked);
  return status;
}

int ms_bench_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "bench", argc, argv, &invocation);
  MsTestOptions options;
  ms_test_options_parse(&invocation.arguments, &options);
  MsStrBuild captured = ms_strbuild_new();
  if (status == 0 && (options.matching.len > 0 || options.exclude.len > 0)) {
    test_print(stderr, ms_span_of_text("ms bench: --match and --exclude need a regular-expression engine, which the "
                                       "driver does not have yet\n"));
    status = STATUS_NOT_IMPLEMENTED;
  } else if (status == 0) {
    test_output_capture(invocation.json ? &captured : NULL);
    status = bench_input(&arena, &invocation);
    test_output_capture(NULL);
  }
  ms_strbuild_free(&captured);
  ms_test_options_free(&options);
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
