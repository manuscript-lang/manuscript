/* Owns `ms bench` (bench_command.h): reads the arguments, checks the input with its bench files, selects the bench
 * blocks and lists them or reports that none match. Running the selected benches needs bench lowering in the back end,
 * which the C compiler does not have yet: that step reports "not implemented" (status 70). */
#include "driver/bench_command.h"

#include <stdio.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/float_parse.h"
#include "base/message.h"
#include "base/path.h"
#include "base/process.h"
#include "driver/pipeline.h"
#include "driver/checked_input.h"
#include "driver/invocation.h"
#include "driver/test_options.h"

enum { STATUS_FAILED = 1, STATUS_NOT_IMPLEMENTED = 70, DEFAULT_BENCH_TIMEOUT_MS = 600000 };

static void print_text(FILE *stream, MsSpan text) {
  (void)fwrite(text.ptr, 1, text.len, stream);
}

/* The names `--bench` and `--filter` select, in declaration order. False, with the message printed, when a `--bench`
 * names none. */
static bool select_benches(MsArena *arena, const MsSpanList *names, const MsTestOptions *options, MsSpanList *selected) {
  bool *found = MS_ARENA_NEW_ARRAY(arena, bool, options->names.len + 1);
  for (size_t i = 0; i < names->len; i++) {
    bool exact = options->names.len == 0;
    for (size_t n = 0; n < options->names.len; n++) {
      if (ms_span_equal(options->names.ptr[n], names->ptr[i])) {
        exact = true;
        found[n] = true;
      }
    }
    size_t at = 0;
    if (exact && (options->filter.len == 0 || ms_span_find(names->ptr[i], options->filter, &at))) {
      ms_span_list_push(selected, names->ptr[i]);
    }
  }
  for (size_t n = 0; n < options->names.len; n++) {
    if (!found[n]) {
      print_text(stderr, ms_message_format(arena, "unknown test \"%S\"; use --list to find full module::name identities\n",
                                           options->names.ptr[n], (MsSpan){0}));
      return false;
    }
  }
  return true;
}

/* The number after `"key":` in the statistics object, or NaN. */
static double stat_number(MsSpan json, const char *key) {
  size_t klen = __builtin_strlen(key);
  for (size_t i = 0; i + klen + 3 < json.len; i++) {
    if (json.ptr[i] == '"' && ms_span_equal(ms_span_of(json.ptr + i + 1, klen), ms_span_of_text(key)) &&
        json.ptr[i + 1 + klen] == '"' && json.ptr[i + 2 + klen] == ':') {
      size_t at = i + 3 + klen;
      size_t end = at;
      while (end < json.len && json.ptr[end] != ',' && json.ptr[end] != '}') {
        end++;
      }
      double value = 0;
      if (ms_parse_float(ms_span_of(json.ptr + at, end - at), &value) == MS_PARSE_FLOAT_OK) {
        return value;
      }
      return __builtin_nan("");
    }
  }
  return __builtin_nan("");
}

static void format_ns(MsStrBuild *out, double nanos) {
  const char *unit = "ns";
  double value = nanos;
  if (nanos >= 1e9) {
    value = nanos / 1e9;
    unit = "s";
  } else if (nanos >= 1e6) {
    value = nanos / 1e6;
    unit = "ms";
  } else if (nanos >= 1e3) {
    value = nanos / 1e3;
    unit = "\xC2\xB5s";
  }
  char text[64];
  (void)snprintf(text, sizeof text, "%.3f %s", value, unit);
  ms_strbuild_append_text(out, text);
}

static void count_text(MsStrBuild *out, double value) {
  char text[64];
  if (value == (double)(long long)value) {
    (void)snprintf(text, sizeof text, "%.0f", value);
  } else {
    (void)snprintf(text, sizeof text, "%.2f", value);
  }
  ms_strbuild_append_text(out, text);
}

/* The one-line summary of a bench's statistics. */
static MsSpan describe_stats(MsArena *arena, MsSpan json) {
  MsStrBuild out = ms_strbuild_new();
  format_ns(&out, stat_number(json, "median_ns"));
  ms_strbuild_append_text(&out, "/op median (min ");
  format_ns(&out, stat_number(json, "min_ns"));
  ms_strbuild_append_text(&out, ", mean ");
  format_ns(&out, stat_number(json, "mean_ns"));
  ms_strbuild_append_text(&out, ", max ");
  format_ns(&out, stat_number(json, "max_ns"));
  ms_strbuild_append_text(&out, ", stddev ");
  format_ns(&out, stat_number(json, "stddev_ns"));
  ms_strbuild_append_text(&out, "; ");
  count_text(&out, stat_number(json, "iterations"));
  ms_strbuild_append_text(&out, " iterations x ");
  count_text(&out, stat_number(json, "samples"));
  ms_strbuild_append_text(&out, " samples; cpu ");
  format_ns(&out, stat_number(json, "cpu_ns"));
  ms_strbuild_append_text(&out, "/op");
  const double ops = stat_number(json, "mir_ops");
  const double allocations = stat_number(json, "allocations");
  if (ops > 0) {
    ms_strbuild_append_text(&out, "; ");
    count_text(&out, ops);
    ms_strbuild_append_text(&out, " MIR ops");
  }
  if (allocations == allocations) {
    ms_strbuild_append_text(&out, "; ");
    count_text(&out, allocations);
    ms_strbuild_append_text(&out, " allocs, ");
    count_text(&out, stat_number(json, "allocated_bytes"));
    ms_strbuild_append_text(&out, " bytes, ");
    count_text(&out, stat_number(json, "list_copies"));
    ms_strbuild_append_text(&out, " list copies, ");
    count_text(&out, stat_number(json, "string_clones"));
    ms_strbuild_append_text(&out, " string clones per op");
  }
  ms_strbuild_append_byte(&out, ')');
  const MsSpan text = ms_arena_copy(arena, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return text;
}

static MsSpan last_stats_line(MsSpan printed) {
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
  return found;
}

/* Runs one bench in its own process; the one-line result is printed. True when it measured. */
static bool run_one(MsArena *arena, MsSpan executable, MsSpan working, const MsTestOptions *options, size_t index, MsSpan name,
                    MsSpan folder) {
  print_text(stdout, ms_message_format(arena, "RUN %S\n", name, (MsSpan){0}));
  const MsSpan printed = ms_message_format(arena, "%S/bench-stdout", folder, (MsSpan){0});
  const MsSpan results = ms_message_format(arena, "%S/bench-results", folder, (MsSpan){0});
  MsSpanList env = {0};
  ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_SELECT=%z", index));
  ms_span_list_push(&env, ms_message_format(arena, "MS_TEST_RESULTS=%S", results, (MsSpan){0}));
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
  const MsProcessSpec spec = {.argv = argv.ptr, .argc = argv.len, .directory = working, .env = env.ptr, .envc = env.len,
                              .log_path = printed, .inherit_error = true};
  MsStrBuild why = ms_strbuild_new();
  int status = 0;
  (void)fflush(stdout);
  bool ok = false;
  if (!ms_process_run(&spec, &status, &why)) {
    print_text(stdout, ms_message_format(arena, "FAIL %S: %S\n", name, ms_strbuild_span(&why)));
  } else if (status != 0) {
    print_text(stdout, ms_message_format(arena, "FAIL %S: bench process exited with status %z\n", name, (size_t)(status < 0 ? 0 : status)));
  } else {
    /* The runner keeps a test's standard output in its results file. */
    MsBytes bytes = {0};
    MsSpan text = {0};
    if (ms_file_read(results, &bytes)) {
      text = ms_arena_copy(arena, ms_bytes_span(&bytes));
    }
    ms_bytes_free(&bytes);
    const MsSpan stats = last_stats_line(text);
    if (stats.len == 0) {
      print_text(stdout, ms_message_format(arena, "FAIL %S: the bench reported no statistics\n%S", name, text));
    } else {
      print_text(stdout, ms_message_format(arena, "BENCH %S: %S\n", name, describe_stats(arena, stats)));
      ok = true;
    }
  }
  ms_strbuild_free(&why);
  ms_span_list_free(&env);
  ms_span_list_free(&argv);
  return ok;
}

/* Builds the bench executable and runs each selected bench. */
static int run_benches(MsArena *arena, MsCheckedInput *checked, const MsInvocation *invocation, const MsSpanList *names,
                       const MsSpanList *selected, const MsTestOptions *options) {
  const MsString temp = ms_temp_dir();
  MsString directory = ms_string_empty();
  if (!ms_dir_make_temp(ms_string_span(&temp), ms_span_of_text("manuscript-bench-"), &directory)) {
    print_text(stderr, ms_span_of_text("cannot create a temporary directory\n"));
    return STATUS_FAILED;
  }
  const MsSpan folder = ms_arena_copy(arena, ms_string_span(&directory));
  const MsSpan executable = ms_message_format(arena, MS_TEMP_PROGRAM, folder, (MsSpan){0});
  const MsLinkRequest request = {.program = &checked->program, .entry = checked->entry, .build_type = invocation->build_type,
                                 .output = executable, .link = invocation->link.ptr, .link_count = invocation->link.len,
                                 .static_libc = invocation->static_libc, .tests = true, .bench = true};
  MsSpan error = {0};
  int status = 0;
  if (!ms_pipeline_link(&request, &error)) {
    print_text(stderr, ms_message_format(arena, "%S\n", error, (MsSpan){0}));
    status = STATUS_FAILED;
  } else {
    MsSpan working = checked->graph.project_root.len > 0 ? checked->graph.project_root : ms_path_parent(invocation->filename);
    if (working.len == 0) {
      working = ms_span_of_text(".");
    }
    size_t failed = 0;
    for (size_t s = 0; s < selected->len; s++) {
      size_t index = 0;
      while (index < names->len && !ms_span_equal(names->ptr[index], selected->ptr[s])) {
        index++;
      }
      if (!run_one(arena, executable, working, options, index, selected->ptr[s], folder)) {
        failed++;
        if (options->fail_fast) {
          break;
        }
      }
    }
    print_text(stdout, ms_message_format(arena, "%z benches, %z failed\n", selected->len, failed));
    status = failed > 0 ? STATUS_FAILED : 0;
  }
  ms_path_remove_tree(folder);
  ms_string_release(&directory);
  return status;
}

static int bench_input(MsArena *arena, const MsInvocation *invocation) {
  MsCheckedInput checked = {0};
  if (!ms_checked_input_load(arena, &checked, invocation->filename, MS_INPUT_TESTS)) {
    const int status = invocation->json ? ms_checked_input_report_json(&checked) : ms_checked_input_report(&checked);
    ms_checked_input_free(&checked);
    return status;
  }
  MsTestOptions options;
  ms_test_options_parse(&invocation->arguments, &options);
  MsSpanList names = {0};
  MsSpanList selected = {0};
  ms_checked_input_test_names(arena, &checked, true, &names);
  int status = STATUS_FAILED;
  const bool filtered = options.filter.len > 0 || options.names.len > 0;
  if (!select_benches(arena, &names, &options, &selected)) {
    status = STATUS_FAILED;
  } else if (selected.len == 0 && filtered) {
    print_text(stdout, ms_message_format(arena, "no benches match selection (%z benches available); use --list to find "
                                                "full module::name identities\n", names.len));
  } else if (options.list) {
    for (size_t i = 0; i < selected.len; i++) {
      print_text(stdout, ms_message_format(arena, "%S\n", selected.ptr[i], (MsSpan){0}));
    }
    status = 0;
  } else if (selected.len == 0) {
    print_text(stdout, ms_span_of_text("no bench blocks found: add bench blocks to bench.ms or *_bench.ms files in the "
                                       "project, or pass a .ms file\n0 benches, 0 failed\n"));
    status = 0;
  } else {
    if (invocation->json || options.ops || options.baseline.len > 0 || options.has_fail_over || options.repeat > 1) {
      print_text(stderr, ms_span_of_text("ms bench: --json, --ops, --baseline and --fail-over are not implemented yet\n"));
      status = STATUS_NOT_IMPLEMENTED;
    } else {
      if (!options.timeout_set) {
        options.timeout_ms = DEFAULT_BENCH_TIMEOUT_MS;
      }
      status = run_benches(arena, &checked, invocation, &names, &selected, &options);
    }
  }
  ms_span_list_free(&selected);
  ms_span_list_free(&names);
  ms_test_options_free(&options);
  ms_checked_input_free(&checked);
  return status;
}

int ms_bench_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "bench", argc, argv, &invocation);
  if (status == 0) {
    status = bench_input(&arena, &invocation);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
