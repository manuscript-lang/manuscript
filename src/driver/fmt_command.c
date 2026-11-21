/* Driver: `ms fmt <files> [--check] [--json]`. Formats each file in place, or with --check only reports
 * which files differ. With --json the report is `{format, files, diagnostics}` on stdout; without it
 * problems go to stderr. Status 0 is clean, 1 an error or a file needing formatting, 2 a usage error. */
#include "driver/fmt_command.h"

#include <stdio.h>
#include <stdlib.h>

#include "base/arena.h"
#include "base/file.h"
#include "base/list.h"
#include "base/strbuild.h"
#include "base/sort.h"
#include "compiler/syntax/diag_json.h"
#include "compiler/syntax/format.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2, STATUS_NOT_IMPLEMENTED = 70 };

typedef struct FmtOptions {
  bool check, json;
} FmtOptions;

MS_LIST_DEFINE(TargetList, target_list, MsSpan)

/* One file's result: its display name and state, and the diagnostic text it adds to the report. */
typedef struct FmtOutcome {
  MsSpan display;
  const char *state;
  MsStrBuild diagnostic; /* JSON object, empty when there is none */
  MsStrBuild console;    /* terminal text, empty when there is none */
} FmtOutcome;

static void print_span(FILE *stream, MsSpan text) {
  (void)fwrite(text.ptr, 1, text.len, stream);
}

static int64_t order_targets(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsSpan *x = (const void *)a;
  const MsSpan *y = (const void *)b;
  const size_t common = x->len < y->len ? x->len : y->len;
  for (size_t index = 0; index < common; index++) {
    if (x->ptr[index] != y->ptr[index]) {
      return x->ptr[index] < y->ptr[index] ? -1 : 1;
    }
  }
  return x->len == y->len ? 0 : (x->len < y->len ? -1 : 1);
}

/* The path as shown in reports: without a leading "./". */
static MsSpan display_of(MsSpan path) {
  while (ms_span_starts_with(path, ms_span_of_text("./"))) {
    path = ms_span_of(path.ptr + 2, path.len - 2);
  }
  return path;
}

/* Drops repeated targets from the sorted list. */
static size_t unique_targets(MsSpan *targets, size_t count) {
  size_t kept = 0;
  for (size_t index = 0; index < count; index++) {
    if (kept == 0 || !ms_span_equal(targets[kept - 1], targets[index])) {
      targets[kept++] = targets[index];
    }
  }
  return kept;
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
      (void)fprintf(stderr, "ms fmt: --drop-labels is not implemented yet\n");
      return STATUS_NOT_IMPLEMENTED;
    } else if (!positional && text.len > 0 && text.ptr[0] == '-') {
      (void)fprintf(stderr, "unknown option %s for ms fmt; run 'ms help fmt' for its options\n", argument);
      return STATUS_USAGE;
    } else if (text.len == 0) {
      return usage_error("ms fmt: an input argument is empty; pass a .ms file, directory, or ms.toml");
    } else {
      target_list_push(targets, text);
    }
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
  if (!ms_format(&arena, source, &formatted, &diag)) {
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

/* The `--json` document: the files with their states and every diagnostic. */
static void write_report(MsStrBuild *out, const FmtOutcome *outcomes, size_t count) {
  ms_strbuild_append_text(out, "{\n  \"format\": 1,\n  \"files\": [");
  for (size_t index = 0; index < count; index++) {
    ms_strbuild_append_text(out, index == 0 ? "\n    {\n      \"path\": " : ",\n    {\n      \"path\": ");
    ms_json_string(out, outcomes[index].display);
    ms_strbuild_append_text(out, ",\n      \"status\": ");
    ms_json_string(out, ms_span_of_text(outcomes[index].state));
    ms_strbuild_append_text(out, "\n    }");
  }
  ms_strbuild_append_text(out, count > 0 ? "\n  ],\n  \"diagnostics\": [" : "],\n  \"diagnostics\": [");
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

int ms_fmt_command(int argc, char **argv) {
  FmtOptions options = {0};
  TargetList targets = {0};
  int status = parse_arguments(argc, argv, &options, &targets);
  if (status != 0) {
    target_list_free(&targets);
    return status;
  }
  for (size_t index = 0; index < targets.len; index++) {
    targets.ptr[index] = display_of(targets.ptr[index]);
  }
  ms_sort((uint8_t *)targets.ptr, targets.len, sizeof targets.ptr[0], order_targets, NULL);
  const size_t count = unique_targets(targets.ptr, targets.len);
  FmtOutcome *outcomes = calloc(count, sizeof *outcomes);
  if (outcomes == NULL) {
    (void)fprintf(stderr, "ms fmt: out of memory\n");
    return STATUS_FAILED;
  }
  for (size_t index = 0; index < count; index++) {
    outcomes[index].display = targets.ptr[index];
    format_file(targets.ptr[index], &options, &outcomes[index]);
    if (outcomes[index].console.bytes.len != 0) {
      status = STATUS_FAILED;
      if (!options.json) {
        print_span(stderr, ms_strbuild_span(&outcomes[index].console));
        (void)fputc('\n', stderr);
      }
    }
  }
  if (options.json) {
    MsStrBuild report = ms_strbuild_new();
    write_report(&report, outcomes, count);
    print_span(stdout, ms_strbuild_span(&report));
    ms_strbuild_free(&report);
  }
  for (size_t index = 0; index < count; index++) {
    ms_strbuild_free(&outcomes[index].diagnostic);
    ms_strbuild_free(&outcomes[index].console);
  }
  free(outcomes);
  target_list_free(&targets);
  return status;
}
