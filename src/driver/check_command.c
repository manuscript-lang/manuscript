/* Driver: `ms check <file.ms> [--json [--with-text]]`. Loads the module graph of one file, checks it and
 * reports the diagnostics as terminal text or as the JSON document of crates/ms-cli. Directories, ms.toml
 * projects, several targets and the --each, --fix, --watch and --deny-warnings options are not implemented.
 * Status 0 is accepted, 1 a diagnostic, 2 a usage error, 70 not implemented. */
#include "driver/check_command.h"

#include <stdio.h>

#include "base/file.h"
#include "base/path.h"
#include "compiler/check/program.h"
#include "compiler/project/project.h"
#include "compiler/syntax/diag_json.h"
#include "driver/snippet.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2, STATUS_NOT_IMPLEMENTED = 70 };

typedef struct CheckOptions {
  bool json, with_text;
  const char *target;
} CheckOptions;

/* One diagnostic ready to print: the file it is in, its phase and its text. */
typedef struct Finding {
  MsSpan file;
  const char *phase;
  MsDiag diag;
} Finding;

MS_LIST_DEFINE(FindingList, finding_list, Finding)

static void print_span(FILE *stream, MsSpan text) {
  (void)fwrite(text.ptr, 1, text.len, stream);
}

static bool is_option(const char *argument, const char *name) {
  return ms_span_is_text(ms_span_of_text(argument), name);
}

static int refuse(const char *message, int status) {
  (void)fprintf(stderr, "%s\n", message);
  return status;
}

static int parse_arguments(int argc, char **argv, CheckOptions *options) {
  for (int index = 0; index < argc; index++) {
    const char *argument = argv[index];
    if (is_option(argument, "--json")) {
      options->json = true;
    } else if (is_option(argument, "--with-text")) {
      options->with_text = true;
    } else if (is_option(argument, "--each") || is_option(argument, "--fix") || is_option(argument, "--watch") ||
               is_option(argument, "--deny-warnings")) {
      return refuse("ms check: this option is not implemented yet", STATUS_NOT_IMPLEMENTED);
    } else if (argument[0] == '-') {
      (void)fprintf(stderr, "unknown option %s for ms check; run 'ms help check' for its options\n", argument);
      return STATUS_USAGE;
    } else if (options->target != NULL) {
      return refuse("ms check: several targets are not implemented yet", STATUS_NOT_IMPLEMENTED);
    } else if (argument[0] == '\0') {
      return refuse("ms check: an input argument is empty; pass a .ms file, directory, or ms.toml", STATUS_USAGE);
    } else {
      options->target = argument;
    }
  }
  if (options->target == NULL) {
    return refuse("ms check: missing a target; pass .ms files, directories, or ms.toml", STATUS_USAGE);
  }
  if (options->with_text && !options->json) {
    return refuse("ms check: --with-text requires --json", STATUS_USAGE);
  }
  return 0;
}

static bool is_directory_or_manifest(const char *target) {
  const MsSpan path = ms_span_of_text(target);
  return ms_dir_exists(path) || ms_span_is_text(ms_path_file_name(path), "ms.toml");
}

static void add_graph_findings(const MsGraph *graph, FindingList *findings) {
  for (size_t i = 0; i < graph->diagnostic_count; i++) {
    const MsGraphDiag *diag = &graph->diagnostics[i];
    const char *phase = diag->phase == MS_GRAPH_PARSE ? "parse" : "resolution";
    finding_list_push(findings, (Finding){.file = diag->file, .phase = phase, .diag = diag->diag});
  }
}

static void add_check_findings(const MsCheckProgram *program, const MsNames *names, FindingList *findings) {
  for (size_t i = 0; i < program->diagnostics.len; i++) {
    const MsCheckDiag *issue = &program->diagnostics.ptr[i];
    const MsSpan file = ms_names_span(names, program->modules.ptr[issue->module].file);
    const char *phase = issue->phase == MS_CHECK_RESOLUTION ? "resolution" : "type";
    const MsDiag diag = {.pos = issue->pos, .message = ms_string_span(&issue->message)};
    finding_list_push(findings, (Finding){.file = file, .phase = phase, .diag = diag});
  }
}

/* The excerpt under a diagnostic: the file is read again from `root`, as the Rust CLI does. */
static void append_excerpt(MsStrBuild *out, MsSpan root, const Finding *finding) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, root, finding->file);
  MsBytes bytes = {0};
  if (ms_file_read(ms_strbuild_span(&path), &bytes)) {
    ms_snippet_excerpt(out, ms_bytes_span(&bytes), finding->diag.pos, finding->diag.has_end, finding->diag.end);
  }
  ms_bytes_free(&bytes);
  ms_strbuild_free(&path);
}

static void append_terminal_text(MsStrBuild *err, MsSpan root, const FindingList *findings) {
  for (size_t i = 0; i < findings->len; i++) {
    const Finding *finding = &findings->ptr[i];
    ms_path_append_joined(err, root, finding->file);
    ms_strbuild_printf(err, ":%u:%u: %s: ", finding->diag.pos.line, finding->diag.pos.column, finding->phase);
    ms_strbuild_append(err, finding->diag.message);
    append_excerpt(err, root, finding);
    ms_strbuild_append_byte(err, '\n');
  }
  if (findings->len != 0) {
    ms_strbuild_printf(err, "%zu %s; fix them and re-run (ms check <file> --json gives the same diagnostics as "
                            "structured data)\n",
                       findings->len, findings->len == 1 ? "error" : "errors");
  }
}

static void write_text_member(MsStrBuild *out, MsStrBuild *std_out, MsStrBuild *std_err) {
  ms_strbuild_append_text(out, ",\n  \"text\": {\n    \"stdout\": ");
  ms_json_string(out, ms_strbuild_span(std_out));
  ms_strbuild_append_text(out, ",\n    \"stderr\": ");
  ms_json_string(out, ms_strbuild_span(std_err));
  ms_strbuild_append_text(out, "\n  }");
}

static void write_document(MsStrBuild *out, const FindingList *findings, const CheckOptions *options,
                           MsStrBuild *std_out, MsStrBuild *std_err) {
  ms_strbuild_append_text(out, "{\n  \"format\": 1,\n  \"diagnostics\": [");
  for (size_t i = 0; i < findings->len; i++) {
    ms_strbuild_append_text(out, i == 0 ? "\n" : ",\n");
    ms_json_diag(out, findings->ptr[i].file, findings->ptr[i].phase, &findings->ptr[i].diag);
  }
  ms_strbuild_append_text(out, findings->len == 0 ? "]" : "\n  ]");
  if (options->with_text) {
    write_text_member(out, std_out, std_err);
  }
  ms_strbuild_append_text(out, "\n}\n");
}

static void report(const FindingList *findings, const CheckOptions *options, MsSpan root) {
  MsStrBuild std_out = ms_strbuild_new();
  MsStrBuild std_err = ms_strbuild_new();
  if (findings->len == 0) {
    ms_strbuild_printf(&std_out, "Checked %s\n", options->target);
  }
  append_terminal_text(&std_err, root, findings);
  if (options->json) {
    MsStrBuild document = ms_strbuild_new();
    write_document(&document, findings, options, &std_out, &std_err);
    print_span(stdout, ms_strbuild_span(&document));
    ms_strbuild_free(&document);
  } else {
    print_span(stdout, ms_strbuild_span(&std_out));
    print_span(stderr, ms_strbuild_span(&std_err));
  }
  ms_strbuild_free(&std_out);
  ms_strbuild_free(&std_err);
}

int ms_check_command(int argc, char **argv) {
  CheckOptions options = {0};
  const int status = parse_arguments(argc, argv, &options);
  if (status != 0) {
    return status;
  }
  if (is_directory_or_manifest(options.target)) {
    return refuse("ms check: directories and ms.toml projects are not implemented yet", STATUS_NOT_IMPLEMENTED);
  }
  MsArena arena = ms_arena_new();
  MsNames names;
  ms_names_init(&names);
  MsGraph graph = {0};
  ms_project_load(&arena, &names, ms_span_of_text(options.target), NULL, &graph);
  FindingList findings = {0};
  MsCheckProgram program = {0};
  add_graph_findings(&graph, &findings);
  if (findings.len == 0) {
    ms_check_graph(&program, &names, &graph);
    add_check_findings(&program, &names, &findings);
  }
  report(&findings, &options, graph.source_root);
  const int result = findings.len == 0 ? 0 : STATUS_FAILED;
  finding_list_free(&findings);
  if (program.names != NULL) {
    ms_check_program_free(&program);
  }
  ms_names_free(&names);
  ms_arena_free(&arena);
  return result;
}
