/* Driver: `ms check <targets> [--json [--with-text [--each]]]`. Loads the module graph of each input, checks it
 * and reports the diagnostics as terminal text or as the JSON document of crates/ms-cli. Several targets, a
 * directory without ms.toml and --each check each input on its own; --fix applies fixes and --watch reruns after each
 * saved change. Status 0 is accepted, 1 a diagnostic, 2 a usage error. */
#include "driver/check_command.h"

#include <stdio.h>

#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/sort.h"
#include "compiler/check/program.h"
#include "compiler/own/own.h"
#include "compiler/project/project.h"
#include "compiler/syntax/diag.h"
#include "compiler/syntax/diag_json.h"
#include "driver/check_fix.h"
#include "driver/check_inputs.h"
#include "driver/display.h"
#include "driver/findings.h"
#include "driver/snippet.h"
#include "driver/watch.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2, STATUS_NOT_IMPLEMENTED = 70 };

MS_LIST_DEFINE(TargetList, target_list, MsSpan)

typedef struct CheckOptions {
  bool json, with_text, each, fix, watch;
  TargetList targets;
} CheckOptions;


/* What checking the inputs found: their diagnostics, and the `Checked` lines of the inputs that passed. */
typedef struct Analysis {
  FindingList findings;
  MsStrBuild summaries;
  CheckFixList fixes;
  MsSpan root;       /* a lone file: the directory its diagnostics are relative to */
  bool no_inputs;
  MsSpanList watched; /* the files and directories a rerun depends on */
} Analysis;

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
    } else if (is_option(argument, "--each")) {
      options->each = true;
    } else if (is_option(argument, "--fix")) {
      options->fix = true;
    } else if (is_option(argument, "--watch")) {
      options->watch = true;
    } else if (is_option(argument, "--deny-warnings")) {
      return refuse("--deny-warnings requires lint, not check; use ms lint <file> --deny-warnings", STATUS_USAGE);
    } else if (argument[0] == '-') {
      (void)fprintf(stderr, "unknown option %s for ms check; run 'ms help check' for its options\n", argument);
      return STATUS_USAGE;
    } else if (argument[0] == '\0') {
      return refuse("ms check: an input argument is empty; pass a .ms file, directory, or ms.toml", STATUS_USAGE);
    } else {
      target_list_push(&options->targets, ms_span_of_text(argument));
    }
  }
  if (options->targets.len == 0) {
    return refuse("ms check: missing a target; pass .ms files, directories, or ms.toml", STATUS_USAGE);
  }
  if (options->with_text && !options->json) {
    return refuse("ms check: --with-text requires --json", STATUS_USAGE);
  }
  if (options->each && (!(options->json && options->with_text) || options->fix || options->watch)) {
    return refuse("--each requires check --json --with-text without --watch or --fix; use ms check a.ms b.ms "
                  "--json --with-text --each",
                  STATUS_USAGE);
  }
  return 0;
}

/* Modules of the program that are the project's own, not the bundled standard library. */
static size_t project_modules(const MsCheckProgram *program, const MsNames *names) {
  size_t count = 0;
  for (size_t i = 0; i < program->modules.len; i++) {
    const MsSpan file = ms_names_span(names, program->modules.ptr[i].file);
    count += ms_span_starts_with(file, ms_span_of_text("@std/")) ? 0 : 1;
  }
  return count;
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


/* `finding` copied out of the checker's memory, which the input's run frees. */
static Finding kept(MsArena *arena, Finding finding, MsSpan file) {
  finding.file = file;
  finding.diag.message = ms_arena_copy(arena, finding.diag.message);
  finding.diag.replacement = ms_arena_copy(arena, finding.diag.replacement);
  return finding;
}

/* A collection shows a file relative to the working directory. */
static MsSpan shown(MsArena *arena, const CheckSelection *selection, MsSpan root, MsSpan file) {
  if (!selection->collection || ms_span_starts_with(file, ms_span_of_text("@std/")) || finding_is_package_file(file)) {
    return ms_arena_copy(arena, file);
  }
  if (root.len != 0 && !ms_path_is_absolute(file)) {
    MsStrBuild joined = ms_strbuild_new();
    ms_path_append_joined(&joined, root, file);
    const MsSpan path = ms_message_from_builder(arena, &joined);
    ms_strbuild_free(&joined);
    return ms_display_of(arena, path);
  }
  return ms_display_of(arena, file);
}

static bool failed_import(MsSpan message) {
  return ms_span_starts_with(message, ms_span_of_text("module does not export")) ||
         ms_span_starts_with(message, ms_span_of_text("unknown standard module"));
}

/* The fixable diagnostics of one input with the path of the file each edits. A failed import leaves its names
 * unbound, so every other diagnostic in that file may only follow from it; only the import's own fix is trusted. */
static void collect_fixes(MsArena *arena, MsSpan root, const FindingList *found, CheckFixList *fixes) {
  for (size_t i = 0; i < found->len; i++) {
    const Finding *finding = &found->ptr[i];
    if (!finding->diag.has_fix || ms_span_starts_with(finding->file, ms_span_of_text("@std/"))) {
      continue;
    }
    bool broken = false;
    for (size_t j = 0; j < found->len; j++) {
      broken = broken || (ms_span_equal(found->ptr[j].file, finding->file) && failed_import(found->ptr[j].diag.message));
    }
    if (broken && !failed_import(finding->diag.message)) {
      continue;
    }
    MsStrBuild path = ms_strbuild_new();
    if (root.len == 0 || ms_path_is_absolute(finding->file)) {
      ms_strbuild_append(&path, finding->file);
    } else {
      ms_path_append_joined(&path, root, finding->file);
    }
    check_fix_list_push(fixes, (CheckFix){.path = ms_message_from_builder(arena, &path),
                                          .start = finding->diag.fix_pos.offset, .end = finding->diag.fix_end.offset,
                                          .replacement = ms_arena_copy(arena, finding->diag.replacement)});
    ms_strbuild_free(&path);
  }
}

/* The files a rerun depends on: the input, its manifest, every local module and the directory of each, where a new
 * file would appear. */
static void add_watched(MsArena *arena, MsSpan input, const MsGraph *graph, MsSpanList *watched) {
  ms_span_list_push(watched, input);
  if (graph->project_root.len != 0) {
    MsStrBuild manifest = ms_strbuild_new();
    ms_path_append_joined(&manifest, graph->project_root, ms_span_of_text("ms.toml"));
    ms_span_list_push(watched, ms_message_from_builder(arena, &manifest));
    ms_strbuild_free(&manifest);
  }
  if (graph->source_root.len != 0) {
    ms_span_list_push(watched, graph->source_root);
  }
  for (size_t i = 0; i < graph->count; i++) {
    const MsGraphModule *module = &graph->modules[i];
    if (!ms_span_starts_with(module->name, ms_span_of_text("@"))) {
      ms_span_list_push(watched, module->path);
      ms_span_list_push(watched, ms_path_parent(module->path));
    }
  }
}

/* Checks one input and adds what it found to `analysis`. */
static void check_input(MsArena *arena, const CheckSelection *selection, const CheckInput *input, bool fix,
                        bool watching, Analysis *analysis) {
  MsNames names;
  ms_names_init(&names);
  MsGraph graph = {0};
  const MsLoadOptions load = {.project_sources = true};
  ms_project_load(arena, &names, input->path, &load, &graph);
  FindingList found = {0};
  MsCheckProgram program = {0};
  finding_add_graph(&graph, &found);
  if (found.len == 0) {
    ms_check_graph(&program, &names, &graph);
    ms_own_check(&program);
    finding_add_check(&program, &names, &found);
  }
  if (!selection->collection) {
    analysis->root = ms_arena_copy(arena, graph.source_root);
  }
  if (watching) {
    add_watched(arena, input->path, &graph, &analysis->watched);
  }
  if (fix) {
    collect_fixes(arena, graph.source_root, &found, &analysis->fixes);
  }
  for (size_t i = 0; i < found.len; i++) {
    finding_list_push(&analysis->findings,
                      kept(arena, found.ptr[i], shown(arena, selection, graph.source_root, found.ptr[i].file)));
  }
  if (found.len == 0) {
    const size_t modules = program.names == NULL ? 0 : project_modules(&program, &names);
    ms_strbuild_printf(&analysis->summaries, "Checked %.*s", (int)input->display.len, (const char *)input->display.ptr);
    if (graph.project_root.len != 0) {
      ms_strbuild_printf(&analysis->summaries, " (%zu %s)", modules, modules == 1 ? "module" : "modules");
    }
    ms_strbuild_append_byte(&analysis->summaries, '\n');
  }
  finding_list_free(&found);
  if (program.names != NULL) {
    ms_check_program_free(&program);
  }
  ms_names_free(&names);
}

/* A collection drops repeats, then orders by position, code and message. */
static int64_t compare_collected(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  const int64_t order = finding_compare(env, left, right);
  if (order != 0) {
    return order;
  }
  const Finding *a = (const void *)left;
  const Finding *b = (const void *)right;
  const int code = __builtin_strcmp(ms_code_for(a->phase, a->diag.message), ms_code_for(b->phase, b->diag.message));
  if (code != 0) {
    return code < 0 ? -1 : 1;
  }
  const size_t common = a->diag.message.len < b->diag.message.len ? a->diag.message.len : b->diag.message.len;
  const int text = common == 0 ? 0 : __builtin_memcmp(a->diag.message.ptr, b->diag.message.ptr, common);
  if (text != 0) {
    return text < 0 ? -1 : 1;
  }
  return a->diag.message.len == b->diag.message.len ? 0 : (a->diag.message.len < b->diag.message.len ? -1 : 1);
}

static bool same_finding(const Finding *a, const Finding *b) {
  return ms_span_equal(a->file, b->file) && a->diag.pos.line == b->diag.pos.line &&
         a->diag.pos.column == b->diag.pos.column && __builtin_strcmp(a->phase, b->phase) == 0 &&
         ms_span_equal(a->diag.message, b->diag.message);
}

static void collect_findings(FindingList *findings) {
  ms_sort((uint8_t *)findings->ptr, findings->len, sizeof(Finding), compare_collected, NULL);
  size_t kept_count = 0;
  for (size_t i = 0; i < findings->len; i++) {
    if (kept_count == 0 || !same_finding(&findings->ptr[kept_count - 1], &findings->ptr[i])) {
      findings->ptr[kept_count++] = findings->ptr[i];
    }
  }
  findings->len = kept_count;
}

static void analyze(MsArena *arena, const MsSpan *targets, size_t count, bool fix, bool watching,
                    Analysis *analysis) {
  CheckSelection selection;
  check_select_inputs(arena, targets, count, &selection);
  for (size_t i = 0; i < selection.problems.len; i++) {
    finding_list_push(&analysis->findings,
                      (Finding){.file = selection.problems.ptr[i].display, .phase = "resolution",
                                .diag = {.pos = {.offset = 0, .line = 1, .column = 1},
                                         .message = selection.problems.ptr[i].message}});
  }
  analysis->no_inputs = selection.inputs.len == 0 && selection.problems.len == 0;
  for (size_t i = 0; i < selection.inputs.len; i++) {
    check_input(arena, &selection, &selection.inputs.ptr[i], fix, watching, analysis);
  }
  if (selection.collection) {
    collect_findings(&analysis->findings);
  } else if (analysis->findings.len > 1) {
    ms_sort((uint8_t *)analysis->findings.ptr, analysis->findings.len, sizeof(Finding), finding_compare, NULL);
  }
  check_selection_free(&selection);
}

/* The `ms check` text and document of an analysis: what it prints, and the status. */
static int render(const Analysis *analysis, const CheckOptions *options, const MsSpan *targets, size_t count,
                  MsStrBuild *out, MsStrBuild *err, MsStrBuild *document) {
  ms_strbuild_append(out, ms_strbuild_span(&analysis->summaries));
  if (analysis->no_inputs) {
    ms_strbuild_append_text(err, "ms check: no .ms files found in ");
    for (size_t i = 0; i < count; i++) {
      ms_strbuild_append_text(err, i == 0 ? "" : ", ");
      ms_strbuild_append(err, targets[i]);
    }
    ms_strbuild_append_byte(err, '\n');
  }
  finding_terminal_text(err, analysis->root, &analysis->findings);
  if (options->json) {
    write_document(document, &analysis->findings, options, out, err);
  }
  return analysis->findings.len == 0 ? 0 : STATUS_FAILED;
}

static void free_analysis(Analysis *analysis) {
  finding_list_free(&analysis->findings);
  check_fix_list_free(&analysis->fixes);
  ms_span_list_free(&analysis->watched);
  ms_strbuild_free(&analysis->summaries);
}

/* `--each`: every target is its own run, so its document, text and status match a separate
 * `ms check <target> --json --with-text`. */
static int check_each(MsArena *arena, const CheckOptions *options) {
  MsStrBuild result = ms_strbuild_new();
  ms_strbuild_append_text(&result, "{\n  \"results\": [");
  for (size_t i = 0; i < options->targets.len; i++) {
    Analysis analysis = {.summaries = ms_strbuild_new()};
    MsStrBuild out = ms_strbuild_new();
    MsStrBuild err = ms_strbuild_new();
    MsStrBuild document = ms_strbuild_new();
    analyze(arena, &options->targets.ptr[i], 1, false, false, &analysis);
    const int status = render(&analysis, options, &options->targets.ptr[i], 1, &out, &err, &document);
    ms_strbuild_append_text(&result, i == 0 ? "\n    {\n      \"target\": " : ",\n    {\n      \"target\": ");
    ms_json_string(&result, options->targets.ptr[i]);
    ms_strbuild_printf(&result, ",\n      \"exit_code\": %d,\n      \"document\": ", status);
    const MsSpan text = ms_strbuild_span(&document);
    for (size_t at = 0; at + 1 < text.len; at++) {
      ms_strbuild_append_byte(&result, text.ptr[at]);
      if (text.ptr[at] == '\n') {
        ms_strbuild_append_text(&result, "      ");
      }
    }
    ms_strbuild_append_text(&result, ",\n      \"stderr\": \"\"\n    }");
    ms_strbuild_free(&document);
    ms_strbuild_free(&err);
    ms_strbuild_free(&out);
    free_analysis(&analysis);
  }
  ms_strbuild_append_text(&result, "\n  ]\n}\n");
  print_span(stdout, ms_strbuild_span(&result));
  ms_strbuild_free(&result);
  return 0;
}

/* One run of the command: with --fix, rounds of fixing until no fix applies. */
static int check_targets(MsArena *arena, const CheckOptions *options, MsSpanList *watched) {
  CheckFixRun run = {0};
  Analysis analysis = {.summaries = ms_strbuild_new()};
  const size_t passes = 64;
  for (size_t pass = 0; pass < passes; pass++) {
    free_analysis(&analysis);
    analysis = (Analysis){.summaries = ms_strbuild_new()};
    const bool fixing = options->fix && pass + 1 < passes;
    analyze(arena, options->targets.ptr, options->targets.len, fixing, options->watch, &analysis);
    if (!fixing || check_apply_fixes(arena, &run, &analysis.fixes) == 0) {
      break;
    }
  }
  for (size_t i = 0; i < run.problems.len; i++) {
    finding_list_push(&analysis.findings,
                      (Finding){.file = ms_display_of(arena, run.problems.ptr[i].path), .phase = "resolution",
                                .diag = {.pos = {.offset = 0, .line = 1, .column = 1},
                                         .message = run.problems.ptr[i].message}});
  }
  MsStrBuild out = ms_strbuild_new();
  MsStrBuild err = ms_strbuild_new();
  MsStrBuild document = ms_strbuild_new();
  const int result = render(&analysis, options, options->targets.ptr, options->targets.len, &out, &err, &document);
  if (options->json) {
    print_span(stdout, ms_strbuild_span(&document));
  } else {
    print_span(stdout, ms_strbuild_span(&out));
    print_span(stderr, ms_strbuild_span(&err));
  }
  if (run.fixes > 0) {
    (void)fprintf(stderr, "ms: applied %zu %s in %zu %s\n", run.fixes, run.fixes == 1 ? "fix" : "fixes",
                  run.edited_count, run.edited_count == 1 ? "file" : "files");
  }
  ms_strbuild_free(&document);
  ms_strbuild_free(&err);
  ms_strbuild_free(&out);
  *watched = analysis.watched;
  analysis.watched = (MsSpanList){0};
  free_analysis(&analysis);
  check_fix_run_free(&run);
  return result;
}

int ms_check_command(int argc, char **argv) {
  CheckOptions options = {0};
  const int status = parse_arguments(argc, argv, &options);
  if (status != 0) {
    target_list_free(&options.targets);
    return status;
  }
  MsArena arena = ms_arena_new();
  int result = 0;
  MsSpanList watched = {0};
  if (options.each) {
    result = check_each(&arena, &options);
  }
  while (!options.each) {
    const uint64_t started = watch_now_ms();
    result = check_targets(&arena, &options, &watched);
    if (!options.watch) {
      break;
    }
    (void)fprintf(stderr, "ms: waiting for changes\n");
    (void)fflush(stdout);
    watch_wait(&watched, started);
    ms_span_list_free(&watched);
    ms_arena_free(&arena);
    arena = ms_arena_new();
  }
  ms_span_list_free(&watched);
  target_list_free(&options.targets);
  ms_arena_free(&arena);
  return result;
}
