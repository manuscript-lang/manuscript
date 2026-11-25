/* Driver: `ms fmt <files> [--check] [--json] [--drop-labels]`. Formats each file in place, or with --check only reports
 * which files differ. With --json the report is `{format, files, diagnostics}` on stdout; without it
 * problems go to stderr. Status 0 is clean, 1 an error or a file needing formatting, 2 a usage error. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "cli/fmt_command.h"

#include <stdio.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <uv.h>

#include "base/arena.h"
#include "base/dir.h"
#include "base/file.h"
#include "base/list.h"
#include "base/strbuild.h"
#include "base/sort.h"
#include "compiler/project/project.h"
#include "compiler/syntax/diag_json.h"
#include "compiler/syntax/format.h"
#include "cli/fmt_labels.h"
#include "cli/fmt_targets.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2 };

typedef struct FmtOptions {
  bool check, json, drop_labels;
} FmtOptions;

MS_LIST_DEFINE(TargetList, target_list, MsSpan)

/* One file's result: its display name and state, and the diagnostic text it adds to the report. */
typedef struct FmtOutcome {
  MsSpan display;
  const char *state;
  MsStrBuild diagnostic; /* JSON object, empty when there is none */
  MsStrBuild console;    /* terminal text, empty when there is none */
  bool listed;           /* a file of the report, not only a problem with a target */
} FmtOutcome;

static int64_t order_targets(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsSpan *x = (const void *)a;
  const MsSpan *y = (const void *)b;
  return ms_span_compare(*x, *y);
}

static bool is_option(const char *argument, const char *name) {
  return ms_span_is_text(ms_span_of_text(argument), name);
}

static int usage_error(const char *message) {
  (void)fprintf(stderr, "%s\n", message);
  return STATUS_USAGE;
}

/* Reads the arguments; returns 0 to go on or the status to exit with. */
static int parse_arguments(int argc, char **argv, FmtOptions *options, TargetList *targets) {
  bool positional = false;
  for (int index = 0; index < argc; index++) {
    const char *argument = argv[index];
    const MsSpan text = ms_span_of_text(argument);
    if (!positional && is_option(argument, "--")) {
      positional = true;
    } else if (!positional && is_option(argument, "--check")) {
      options->check = true;
    } else if (!positional && is_option(argument, "--json")) {
      options->json = true;
    } else if (!positional && is_option(argument, "--drop-labels")) {
      options->drop_labels = true;
    } else if (!positional && text.len > 0 && text.ptr[0] == '-') {
      (void)fprintf(stderr, "unknown option %s for ms fmt; run 'ms help fmt' for its options\n", argument);
      return STATUS_USAGE;
    } else if (text.len == 0) {
      return usage_error("ms fmt: an input argument is empty; pass a .ms file, directory, or ms.toml");
    } else {
      target_list_push(targets, text);
    }
  }
  if (targets->len == 0 && ms_path_kind(ms_span_of_text("ms.toml")) == MS_PATH_FILE) {
    target_list_push(targets, ms_span_of_text("ms.toml")); /* no target: the project in this directory */
  }
  if (targets->len == 0) {
    return usage_error("ms fmt: missing a target; pass .ms files, directories, or ms.toml");
  }
  if (options->json && !options->check) {
    return usage_error("--json requires ms fmt --check; remove --json to format files in place");
  }
  return 0;
}

/* The plain diagnostic `{code, phase: "format", message, position: file:1:1}`. */
static void plain_diagnostic(MsStrBuild *out, const char *code, MsSpan message, MsSpan display) {
  ms_strbuild_append_text(out, "    {\n      \"code\": ");
  ms_json_string(out, ms_span_of_text(code));
  ms_strbuild_append_text(out, ",\n      \"phase\": \"format\",\n      \"message\": ");
  ms_json_string(out, message);
  ms_strbuild_append_text(out, ",\n      \"position\": ");
  ms_json_position(out, display, (MsPos){.offset = 0, .line = 1, .column = 1}, 3);
  ms_strbuild_append_text(out, "\n    }");
}

static void report_plain(FmtOutcome *outcome, const char *code, MsSpan message) {
  outcome->state = "error";
  plain_diagnostic(&outcome->diagnostic, code, message, outcome->display);
  ms_strbuild_append(&outcome->console, message);
}

static void report_syntax(FmtOutcome *outcome, const MsDiag *diag) {
  outcome->state = "error";
  ms_json_diag(&outcome->diagnostic, outcome->display, "parse", diag);
  ms_strbuild_append(&outcome->console, outcome->display);
  ms_strbuild_append_text(&outcome->console, ":");
  ms_strbuild_append_u64(&outcome->console, diag->pos.line);
  ms_strbuild_append_text(&outcome->console, ":");
  ms_strbuild_append_u64(&outcome->console, diag->pos.column);
  ms_strbuild_append_text(&outcome->console, ": parse: ");
  ms_strbuild_append(&outcome->console, diag->message);
  ms_strbuild_append_text(
      &outcome->console,
      "\nfmt only formats source that parses; fix the syntax error above, then re-run ms fmt ");
  ms_strbuild_append(&outcome->console, outcome->display);
}

static void report_drift(FmtOutcome *outcome) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "Formatting needed: ");
  ms_strbuild_append(&message, outcome->display);
  ms_strbuild_append_text(&message, "; run ms fmt ");
  ms_strbuild_append(&message, outcome->display);
  ms_strbuild_append_text(&message, " to rewrite it");
  outcome->state = "needs_formatting";
  plain_diagnostic(&outcome->diagnostic, "MSF001", ms_strbuild_span(&message), outcome->display);
  ms_strbuild_append(&outcome->console, ms_strbuild_span(&message));
  ms_strbuild_free(&message);
}

/* Formats one file. The file is rewritten in place so it keeps its permissions. */
static void format_file(MsSpan path, const FmtOptions *options, FmtOutcome *outcome) {
  MsBytes bytes = {0};
  if (!ms_file_read(path, &bytes)) {
    MsStrBuild message = ms_strbuild_new();
    ms_strbuild_append_text(&message, "ms fmt: cannot read ");
    ms_strbuild_append(&message, outcome->display);
    report_plain(outcome, "MSF002", ms_strbuild_span(&message));
    ms_strbuild_free(&message);
    return;
  }
  MsArena arena = {0};
  MsStrBuild formatted = ms_strbuild_new();
  MsDiag diag = {0};
  const MsSpan source = ms_bytes_span(&bytes);
  MsSpan text = source;
  MsSpan problem = {0};
  if (options->drop_labels && !fmt_drop_labels(&arena, path, outcome->display, source, &text, &problem)) {
    report_plain(outcome, "MSF002", problem);
  } else if (!ms_format(&arena, text, &formatted, &diag)) {
    report_syntax(outcome, &diag);
  } else if (ms_span_equal(source, ms_strbuild_span(&formatted))) {
    outcome->state = "clean";
  } else if (options->check) {
    report_drift(outcome);
  } else if (ms_file_write(path, ms_strbuild_span(&formatted))) {
    outcome->state = "formatted";
  } else {
    MsStrBuild message = ms_strbuild_new();
    ms_strbuild_append_text(&message, "ms fmt: cannot write ");
    ms_strbuild_append(&message, outcome->display);
    report_plain(outcome, "MSF002", ms_strbuild_span(&message));
    ms_strbuild_free(&message);
  }
  ms_strbuild_free(&formatted);
  ms_arena_free(&arena);
  ms_bytes_free(&bytes);
}

/* Files are independent, so a few workers take them in turn; the console text is printed afterwards in file order. */
enum { MAX_WORKERS = 16 };

typedef struct FmtJob {
  const FmtFile *files;
  size_t count;
  const FmtOptions *options;
  FmtOutcome *outcomes;
  _Atomic size_t next;
} FmtJob;

static void format_worker(void *argument) {
  FmtJob *job = argument;
  for (size_t index = atomic_fetch_add(&job->next, 1); index < job->count; index = atomic_fetch_add(&job->next, 1)) {
    format_file(job->files[index].path, job->options, &job->outcomes[index]);
  }
}

static void format_files(const FmtFile *files, size_t count, const FmtOptions *options, FmtOutcome *outcomes) {
  FmtJob job = {.files = files, .count = count, .options = options, .outcomes = outcomes};
  atomic_init(&job.next, 0);
  size_t workers = uv_available_parallelism();
  workers = workers > MAX_WORKERS ? MAX_WORKERS : workers;
  workers = workers > count ? count : workers;
  uv_thread_t threads[MAX_WORKERS];
  size_t started = 0;
  /* The calling thread is a worker too; a thread that cannot start only leaves its share to the others. */
  for (; started + 1 < workers; started++) {
    if (uv_thread_create(&threads[started], format_worker, &job) != 0) {
      break;
    }
  }
  format_worker(&job);
  for (size_t index = 0; index < started; index++) {
    (void)uv_thread_join(&threads[index]);
  }
}

/* The `--json` document: the files with their states and every diagnostic. */
static void write_report(MsStrBuild *out, const FmtOutcome *outcomes, size_t count) {
  ms_strbuild_append_text(out, "{\n  \"format\": 1,\n  \"files\": [");
  size_t listed = 0;
  for (size_t index = 0; index < count; index++) {
    if (!outcomes[index].listed) {
      continue;
    }
    ms_strbuild_append_text(out, listed++ == 0 ? "\n    {\n      \"path\": " : ",\n    {\n      \"path\": ");
    ms_json_string(out, outcomes[index].display);
    ms_strbuild_append_text(out, ",\n      \"status\": ");
    ms_json_string(out, ms_span_of_text(outcomes[index].state));
    ms_strbuild_append_text(out, "\n    }");
  }
  ms_strbuild_append_text(out, listed > 0 ? "\n  ],\n  \"diagnostics\": [" : "],\n  \"diagnostics\": [");
  bool first = true;
  for (size_t index = 0; index < count; index++) {
    if (outcomes[index].diagnostic.bytes.len == 0) {
      continue;
    }
    ms_strbuild_append_text(out, first ? "\n" : ",\n");
    ms_strbuild_append(out, ms_strbuild_span(&outcomes[index].diagnostic));
    first = false;
  }
  ms_strbuild_append_text(out, first ? "]\n}\n" : "\n  ]\n}\n");
}

/* A problem with a target: it adds a diagnostic and no file. */
static void report_problem(FmtOutcome *outcome, const FmtProblem *problem) {
  outcome->display = problem->display;
  outcome->state = "error";
  if (!problem->manifest) {
    plain_diagnostic(&outcome->diagnostic, "MSF002", problem->message, problem->display);
    ms_strbuild_append(&outcome->console, problem->message);
    return;
  }
  const MsDiag diag = {.pos = problem->position, .message = problem->message};
  ms_json_diag(&outcome->diagnostic, problem->display, "resolution", &diag);
  ms_strbuild_append(&outcome->console, problem->display);
  ms_strbuild_printf(&outcome->console, ":%u:%u: ", problem->position.line, problem->position.column);
  ms_strbuild_append(&outcome->console, problem->message);
}

static int print_console(const FmtOutcome *outcome, const FmtOptions *options) {
  if (outcome->console.bytes.len == 0) {
    return 0;
  }
  if (!options->json) {
    ms_span_write(stderr, ms_strbuild_span(&outcome->console));
    (void)fputc('\n', stderr);
  }
  return STATUS_FAILED;
}

static int64_t outcome_order(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const FmtOutcome *x = (const void *)a;
  const FmtOutcome *y = (const void *)b;
  return order_targets(env, (const uint8_t *)&x->display, (const uint8_t *)&y->display);
}

static void free_outcomes(FmtOutcome *outcomes, size_t count) {
  for (size_t index = 0; index < count; index++) {
    ms_strbuild_free(&outcomes[index].diagnostic);
    ms_strbuild_free(&outcomes[index].console);
  }
  free(outcomes);
}

int ms_fmt_command(int argc, char **argv) {
  FmtOptions options = {0};
  TargetList targets = {0};
  int status = parse_arguments(argc, argv, &options, &targets);
  if (status != 0) {
    target_list_free(&targets);
    return status;
  }
  ms_sort((uint8_t *)targets.ptr, targets.len, sizeof targets.ptr[0], order_targets, NULL);
  MsArena arena = ms_arena_new();
  FmtFileList files = {0};
  FmtProblemList problems = {0};
  fmt_resolve_targets(&arena, targets.ptr, targets.len, &files, &problems);
  const size_t count = problems.len + files.len;
  FmtOutcome *outcomes = calloc(count == 0 ? 1 : count, sizeof *outcomes);
  if (outcomes == NULL) {
    (void)fprintf(stderr, "ms fmt: out of memory\n");
    return STATUS_FAILED;
  }
  for (size_t index = 0; index < problems.len; index++) {
    report_problem(&outcomes[index], &problems.ptr[index]);
    status |= print_console(&outcomes[index], &options);
  }
  for (size_t index = 0; index < files.len; index++) {
    outcomes[problems.len + index].display = files.ptr[index].display;
    outcomes[problems.len + index].listed = true;
  }
  format_files(files.ptr, files.len, &options, outcomes + problems.len);
  for (size_t index = 0; index < files.len; index++) {
    status |= print_console(&outcomes[problems.len + index], &options);
  }
  if (files.len == 0 && status == 0 && !options.json) {
    (void)fprintf(stderr, "ms fmt: no .ms files found in ");
    for (size_t index = 0; index < targets.len; index++) {
      (void)fprintf(stderr, "%s%.*s", index == 0 ? "" : ", ", (int)targets.ptr[index].len,
                    (const char *)targets.ptr[index].ptr);
    }
    if (targets.len == 1) {
      MsArena scratch = ms_arena_new();
      ms_span_write(stderr, ms_project_nested_hint(&scratch, targets.ptr[0]));
      ms_arena_free(&scratch);
    }
    (void)fputc('\n', stderr);
    status = 1;
  }
  ms_sort((uint8_t *)outcomes, count, sizeof *outcomes, outcome_order, NULL);
  if (options.json) {
    MsStrBuild report = ms_strbuild_new();
    write_report(&report, outcomes, count);
    ms_span_write(stdout, ms_strbuild_span(&report));
    ms_strbuild_free(&report);
  }
  free_outcomes(outcomes, count);
  fmt_file_list_free(&files);
  fmt_problem_list_free(&problems);
  ms_arena_free(&arena);
  target_list_free(&targets);
  return status;
}
