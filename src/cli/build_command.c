/* Owns `ms build` (build_command.h): checks the input, builds the executable through the pipeline and reports the
 * result as text or as the versioned JSON document. Port of crates/ms-cli/src/engine/build.rs. */
#include "cli/build_command.h"

#include <stdio.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/strbuild.h"
#include "compiler/syntax/diag_json.h"
#include "cli/checked_input.h"
#include "cli/invocation.h"
#include "cli/pipeline.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2 };

#ifndef MS_VERSION
#define MS_VERSION "unknown"
#endif

typedef struct BuildReport {
  MsArena *arena;
  const MsInvocation *invocation;
  MsSpan display;     /* the output as the user wrote it */
  MsSpan output;      /* absolute */
  MsSpan source_root;
} BuildReport;

/* How a build ended: a compile failure carries diagnostics; a failure of the build step itself carries a message. */
typedef struct BuildOutcome {
  bool completed;
  const char *phase;       /* "compile" or the build step's phase; unused on success */
  const FindingList *findings;
  MsSpan message;          /* a failure that is not a diagnostic of the source */
} BuildOutcome;

static void print_span(FILE *stream, MsSpan text) {
  (void)fwrite(text.ptr, 1, text.len, stream);
}

static MsSpan absolute(MsArena *arena, MsSpan path) {
  MsString cwd = ms_string_empty();
  MsStrBuild joined = ms_strbuild_new();
  if (ms_path_is_absolute(path) || !ms_dir_current(&cwd)) {
    ms_strbuild_append(&joined, path);
  } else {
    ms_path_append_joined(&joined, ms_string_span(&cwd), path);
  }
  ms_string_release(&cwd);
  MsStrBuild cleaned = ms_strbuild_new();
  ms_path_clean(&cleaned, ms_strbuild_span(&joined));
  const MsSpan result = ms_arena_copy(arena, ms_strbuild_span(&cleaned));
  ms_strbuild_free(&joined);
  ms_strbuild_free(&cleaned);
  return result;
}

/* What the file system says of an artifact: built now, or the one a failed build left behind. */
static const char *artifact_state(bool built, MsSpan path) {
  if (built) {
    return "verified";
  }
  const MsPathKind kind = ms_path_kind(path);
  return kind == MS_PATH_FILE ? "preserved" : (kind == MS_PATH_MISSING ? "missing" : "unavailable");
}

static void write_artifact(MsStrBuild *out, const char *kind, MsSpan path, bool built, bool last) {
  ms_strbuild_printf(out, "    {\n      \"kind\": \"%s\",\n      \"path\": ", kind);
  ms_json_string(out, path);
  ms_strbuild_printf(out, ",\n      \"state\": \"%s\"\n    }%s\n", artifact_state(built, path), last ? "" : ",");
}

/* A failure of the build step: code MSN001, at the input's first byte. */
static void write_plain_diagnostic(MsStrBuild *out, const BuildReport *report, const BuildOutcome *outcome) {
  ms_strbuild_append_text(out, "\n    {\n      \"code\": \"MSN001\",\n      \"phase\": ");
  ms_json_string(out, ms_span_of_text(outcome->phase));
  ms_strbuild_append_text(out, ",\n      \"message\": ");
  ms_json_string(out, outcome->message);
  ms_strbuild_append_text(out, ",\n      \"position\": ");
  ms_json_position(out, report->invocation->filename, (MsPos){.line = 1, .column = 1}, 3);
  ms_strbuild_append_text(out, "\n    }\n  ]\n}\n");
}

static void write_document(MsStrBuild *out, const BuildReport *report, const BuildOutcome *outcome) {
  const bool plain = outcome->message.len > 0;
  ms_strbuild_printf(out, "{\n  \"format\": 1,\n  \"command\": \"build\",\n  \"build_type\": \"%s\",\n  \"source_root\": ",
                     ms_build_type_name(report->invocation->build_type));
  ms_json_string(out, report->source_root);
  ms_strbuild_append_text(out, ",\n  \"output\": ");
  ms_json_string(out, report->output);
  ms_strbuild_printf(out, ",\n  \"completed\": %s,\n  \"exit_code\": %d,\n", outcome->completed ? "true" : "false",
                     outcome->completed ? 0 : STATUS_FAILED);
  if (!outcome->completed) {
    ms_strbuild_printf(out, "  \"reason\": \"%s_error\",\n", plain ? outcome->phase : "compile");
  }
  ms_strbuild_append_text(out, "  \"artifacts\": [\n");
  write_artifact(out, "executable", report->output, outcome->completed, false);
  write_artifact(out, "build_metadata", ms_message_format(report->arena, "%S.ms-build.json", report->output),
                 outcome->completed, true);
  ms_strbuild_append_text(out, "  ],\n  \"stdout\": \"\",\n  \"diagnostics\": [");
  if (plain) {
    write_plain_diagnostic(out, report, outcome);
    return;
  }
  const FindingList *findings = outcome->findings;
  for (size_t i = 0; findings != NULL && i < findings->len; i++) {
    ms_strbuild_append_text(out, i == 0 ? "\n" : ",\n");
    ms_json_diag(out, findings->ptr[i].file, findings->ptr[i].phase, &findings->ptr[i].diag);
  }
  ms_strbuild_append_text(out, findings != NULL && findings->len > 0 ? "\n  ]\n}\n" : "]\n}\n");
}

static void print_document(const BuildReport *report, const BuildOutcome *outcome) {
  MsStrBuild out = ms_strbuild_new();
  write_document(&out, report, outcome);
  print_span(stdout, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
}

/* The failure of the build step: the message on stderr, and with --json the document. */
static int fail(const BuildReport *report, const char *phase, MsSpan message) {
  print_span(stderr, ms_message_format(report->arena, "%S\n", message));
  if (report->invocation->json) {
    print_document(report, &(BuildOutcome){.phase = phase, .message = message});
  }
  return STATUS_FAILED;
}

/* The source or manifest an `-o` path would replace, or empty. */
static MsSpan protected_output(const BuildReport *report, MsSpan project_root) {
  const MsSpan base = ms_path_file_name(report->output);
  if (ms_span_ends_with(base, ms_span_of_text(".ms")) || ms_span_is_text(base, "ms.toml")) {
    return base;
  }
  MsStrBuild manifest = ms_strbuild_new();
  ms_path_append_joined(&manifest, project_root, ms_span_of_text("ms.toml"));
  const MsSpan candidates[2] = {absolute(report->arena, report->invocation->filename),
                                project_root.len > 0 ? ms_message_from_builder(report->arena, &manifest) : (MsSpan){0}};
  ms_strbuild_free(&manifest);
  for (size_t i = 0; i < 2; i++) {
    if (candidates[i].len > 0 && ms_span_equal(absolute(report->arena, candidates[i]), report->output)) {
      return ms_path_file_name(candidates[i]);
    }
  }
  return (MsSpan){0};
}

bool ms_build_metadata_write(MsArena *arena, MsSpan output, MsBuildType type) {
  const MsSpan path = ms_message_format(arena, "%S.ms-build.json", output, (MsSpan){0});
  const MsSpan text = ms_message_format(arena,
                                        "{\n  \"format\": 1,\n  \"version\": \"%s\",\n  \"backend\": \"llvm\",\n  "
                                        "\"build_type\": \"%s\"\n}\n",
                                        MS_VERSION, ms_build_type_name(type));
  return ms_file_write(path, text);
}

static int link_program(const BuildReport *report, MsCheckedInput *checked) {
  const MsInvocation *invocation = report->invocation;
  MsSpan error = {0};
  const MsLinkRequest request = {.program = &checked->program, .entry = checked->entry,
                                 .build_type = invocation->build_type, .output = report->output,
                                 .link = invocation->link.ptr, .link_count = invocation->link.len,
                                 .static_libc = invocation->static_libc};
  if (!ms_dir_make_all(ms_path_parent(report->output))) {
    return fail(report, "build",
                ms_message_format(report->arena, "cannot create the output directory %S; check that its parent is writable", ms_path_parent(report->output)));
  }
  if (!ms_pipeline_link(&request, &error)) {
    return fail(report, "build", error);
  }
  if (!ms_build_metadata_write(report->arena, report->output, invocation->build_type)) {
    return fail(report, "build",
                ms_message_format(report->arena,
                                  "cannot write build metadata %S.ms-build.json; choose an output path "
                                  "whose directory is writable",
                                  report->output, (MsSpan){0}));
  }
  return 0;
}

static int build(MsArena *arena, const MsInvocation *invocation) {
  BuildReport report = {.arena = arena, .invocation = invocation,
                        .display = invocation->output.len > 0 ? invocation->output : ms_span_of_text("program")};
  report.output = absolute(arena, report.display);
  MsCheckedInput checked = {0};
  int status = 0;
  if (!ms_checked_input_load(arena, &checked, invocation->filename, MS_INPUT_PROGRAM)) {
    report.source_root = checked.graph.source_root;
    if (invocation->json) {
      print_document(&report, &(BuildOutcome){.findings = &checked.findings});
    } else {
      (void)ms_checked_input_report(&checked);
    }
    status = STATUS_FAILED;
  } else if (ms_path_kind(report.output) == MS_PATH_DIRECTORY) {
    report.source_root = checked.graph.source_root;
    print_span(stderr, ms_message_format(arena, "-o %S is a directory; pass a file path (e.g. -o %S/program)\n",
                                         report.display, report.display));
    status = STATUS_USAGE;
  } else {
    report.source_root = checked.graph.source_root;
    const MsSpan protect = protected_output(&report, checked.graph.project_root);
    if (protect.len > 0) {
      print_span(stderr, ms_message_format(arena, "-o %S would overwrite %S; choose a different executable path\n",
                                           report.display, protect));
      status = STATUS_USAGE;
    } else {
      status = link_program(&report, &checked);
    }
  }
  if (status == 0 && invocation->json) {
    print_document(&report, &(BuildOutcome){.completed = true});
  } else if (status == 0) {
    print_span(stdout, ms_message_format(arena, "Built %S\n", report.display));
  }
  ms_checked_input_free(&checked);
  return status;
}

int ms_build_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "build", argc, argv, &invocation);
  if (status == 0) {
    status = build(&arena, &invocation);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
