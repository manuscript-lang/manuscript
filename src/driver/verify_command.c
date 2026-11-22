/* Driver: `ms verify` (see verify_command.h). Status 0 is every step passed or skipped, 1 a failed step, 2 a usage
 * error, 70 not implemented. */
#include "driver/verify_command.h"

#include <stdio.h>

#include "base/arena.h"
#include "base/file.h"
#include "base/path.h"
#include "base/strbuild.h"
#include "compiler/check/effects_scan.h"
#include "compiler/check/program.h"
#include "compiler/own/own.h"
#include "compiler/project/project.h"
#include "compiler/syntax/format.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2, STATUS_NOT_IMPLEMENTED = 70, FINDING_LIMIT = 8 };

typedef struct VerifyOptions {
  bool no_test, deny_warnings;
  const char *target;
} VerifyOptions;

/* One step's findings, as the text summary prints them. */
typedef struct Findings {
  MsStrBuild text;
  size_t count;
} Findings;

static int refuse(const char *message, int status) {
  (void)fprintf(stderr, "%s\n", message);
  return status;
}

static int parse_arguments(int argc, char **argv, VerifyOptions *options) {
  for (int index = 0; index < argc; index++) {
    const MsSpan argument = ms_span_of_text(argv[index]);
    if (ms_span_is_text(argument, "--no-test")) {
      options->no_test = true;
    } else if (ms_span_is_text(argument, "--deny-warnings")) {
      options->deny_warnings = true;
    } else if (ms_span_is_text(argument, "--json")) {
      return refuse("ms verify: --json is not implemented yet", STATUS_NOT_IMPLEMENTED);
    } else if (argument.len != 0 && argument.ptr[0] == '-') {
      (void)fprintf(stderr, "unknown option %s for ms verify; run 'ms help verify' for its options\n", argv[index]);
      return STATUS_USAGE;
    } else if (options->target != NULL) {
      return refuse("ms verify takes one target; pass a .ms file, directory, or ms.toml", STATUS_USAGE);
    } else {
      options->target = argv[index];
    }
  }
  if (options->target == NULL) {
    options->target = "ms.toml";
  }
  return options->no_test ? 0 : refuse("ms verify: the test step is not implemented yet; pass --no-test", STATUS_NOT_IMPLEMENTED);
}

static void add_finding(Findings *findings, MsSpan file, MsPos pos, MsSpan message) {
  if (findings->count < FINDING_LIMIT) {
    ms_strbuild_append_text(&findings->text, "  ");
    ms_strbuild_append(&findings->text, file);
    ms_strbuild_printf(&findings->text, ":%u:%u: ", pos.line, pos.column);
    ms_strbuild_append(&findings->text, message);
    ms_strbuild_append_byte(&findings->text, '\n');
  }
  findings->count++;
}

/* The text of the findings, with the "... N more" line past the limit. */
static void print_findings(Findings *findings) {
  (void)fwrite(ms_strbuild_span(&findings->text).ptr, 1, ms_strbuild_length(&findings->text), stderr);
  if (findings->count > FINDING_LIMIT) {
    (void)fprintf(stderr, "  ... %zu more\n", findings->count - FINDING_LIMIT);
  }
}

static void print_failure(const char *step, const char *target) {
  (void)fprintf(stderr, "%s failed; run ms %s %s for details (or ms verify %s --json for every step)\n", step, step,
                target, target);
}

/* A directory names the ms.toml inside it. */
static const char *manifest_of(MsArena *arena, const char *target) {
  const MsSpan path = ms_span_of_text(target);
  if (!ms_dir_exists(path)) {
    return target;
  }
  MsStrBuild joined = ms_strbuild_new();
  ms_path_append_joined(&joined, path, ms_span_of_text("ms.toml"));
  const MsSpan named = ms_arena_copy(arena, ms_strbuild_span(&joined));
  ms_strbuild_free(&joined);
  char *copy = ms_arena_alloc(arena, named.len + 1, 1);
  __builtin_memcpy(copy, named.ptr, named.len);
  copy[named.len] = '\0';
  return copy;
}

static void collect_graph_findings(const MsGraph *graph, Findings *findings) {
  for (size_t index = 0; index < graph->diagnostic_count; index++) {
    const MsGraphDiag *diag = &graph->diagnostics[index];
    add_finding(findings, diag->file, diag->diag.pos, diag->diag.message);
  }
}

static void collect_check_findings(const MsCheckProgram *program, Findings *findings) {
  for (size_t index = 0; index < program->diagnostics.len; index++) {
    const MsCheckDiag *issue = &program->diagnostics.ptr[index];
    const MsSpan file = ms_names_span(program->names, program->modules.ptr[issue->module].file);
    add_finding(findings, file, issue->pos, ms_string_span(&issue->message));
  }
}

/* Whether every project module is already in the formatter's form. */
static bool formatted(const MsGraph *graph) {
  bool clean = true;
  for (size_t index = 0; index < graph->count; index++) {
    MsArena arena = ms_arena_new();
    MsStrBuild out = ms_strbuild_new();
    MsDiag diag = {0};
    const bool ok = ms_format(&arena, graph->modules[index].source, &out, &diag);
    clean = clean && ok && ms_span_equal(ms_strbuild_span(&out), graph->modules[index].source);
    ms_strbuild_free(&out);
    ms_arena_free(&arena);
  }
  return clean;
}

/* The effects findings of the project's callables, in the order the scan reports them. */
static void collect_effects(const MsCheckProgram *program, MsArena *arena, Findings *findings) {
  const MsReach reach = ms_check_effects(program, arena);
  for (uint32_t index = 0; index < reach.violation_count; index++) {
    const MsReachViolation *violation = &reach.violations[index];
    MsStrBuild message = ms_strbuild_new();
    ms_effect_message(&message, violation->path[0], violation);
    add_finding(findings, ms_names_span(program->names, violation->file), violation->pos, ms_strbuild_span(&message));
    ms_strbuild_free(&message);
  }
}

static void print_step(const char *name, const char *status) {
  (void)fprintf(stdout, "%-6s %s\n", name, status);
}

/* Prints the step table and findings once check has run. Returns the exit status. */
static int finish(const VerifyOptions *options, bool checked, bool fmt_ok, Findings *check, Findings *lint) {
  const bool lint_failed = checked && options->deny_warnings && lint->count != 0;
  print_step("check", checked ? "passed" : "failed");
  print_step("fmt", fmt_ok ? "passed" : "failed");
  print_step("lint", !checked ? "skipped" : (lint_failed ? "failed" : "passed"));
  print_step("test", "skipped");
  if (checked && !lint_failed && lint->count != 0) {
    print_findings(lint);
    (void)fprintf(stderr, "lint warnings do not fail verify; pass --deny-warnings to fail on them\n");
  }
  if (!checked) {
    print_findings(check);
    print_failure("check", options->target);
  }
  if (!fmt_ok) {
    print_failure("fmt", options->target);
  }
  if (lint_failed) {
    print_findings(lint);
    print_failure("lint", options->target);
  }
  return checked && fmt_ok && !lint_failed ? 0 : STATUS_FAILED;
}

int ms_verify_command(int argc, char **argv) {
  VerifyOptions options = {0};
  const int status = parse_arguments(argc, argv, &options);
  if (status != 0) {
    return status;
  }
  MsArena arena = ms_arena_new();
  MsNames names;
  ms_names_init(&names);
  MsGraph graph = {0};
  const MsLoadOptions load = {.project_sources = true};
  ms_project_load(&arena, &names, ms_span_of_text(manifest_of(&arena, options.target)), &load, &graph);
  Findings check = {.text = ms_strbuild_new()};
  Findings lint = {.text = ms_strbuild_new()};
  MsCheckProgram program = {0};
  collect_graph_findings(&graph, &check);
  if (check.count == 0) {
    ms_check_graph(&program, &names, &graph);
    ms_own_check(&program);
    collect_check_findings(&program, &check);
  }
  const bool checked = check.count == 0;
  if (checked) {
    collect_effects(&program, &arena, &lint);
  }
  const int result = finish(&options, checked, formatted(&graph), &check, &lint);
  ms_strbuild_free(&check.text);
  ms_strbuild_free(&lint.text);
  if (program.names != NULL) {
    ms_check_program_free(&program);
  }
  ms_names_free(&names);
  ms_arena_free(&arena);
  return result;
}
