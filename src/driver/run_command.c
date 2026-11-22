/* Owns `ms run` (run_command.h): builds a temporary executable and runs it, with the program's own standard streams
 * or, with --json, captured into one document. Port of crates/ms-cli/src/engine/run.rs. Not yet ported: --watch and
 * the structured `fault` member of a document. */
#include "driver/run_command.h"

#include <stdio.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/process.h"
#include "compiler/syntax/diag_json.h"
#include "driver/checked_input.h"
#include "driver/invocation.h"
#include "driver/pipeline.h"
#include "driver/watch.h"

enum { STATUS_FAILED = 1, STATUS_NOT_IMPLEMENTED = 70 };

typedef struct RunContext {
  MsArena *arena;
  const MsInvocation *invocation;
  MsSpan source_root;
} RunContext;

static void print_span(FILE *stream, MsSpan text) {
  (void)fwrite(text.ptr, 1, text.len, stream);
}

/* The head of the document: format, source root, status and the captured output. */
static void begin_document(MsStrBuild *out, const RunContext *context, int status, MsSpan stdout_text, MsSpan stderr_text) {
  ms_strbuild_append_text(out, "{\n  \"format\": 1,\n  \"source_root\": ");
  ms_json_string(out, context->source_root);
  ms_strbuild_printf(out, ",\n  \"exit_code\": %d,\n  \"stdout\": ", status);
  ms_json_string(out, stdout_text);
  ms_strbuild_append_text(out, ",\n  \"stderr\": ");
  ms_json_string(out, stderr_text);
}

static int print_compile_failure(const RunContext *context, const MsCheckedInput *checked) {
  if (!context->invocation->json) {
    return ms_checked_input_report(checked);
  }
  MsStrBuild out = ms_strbuild_new();
  begin_document(&out, context, STATUS_FAILED, (MsSpan){0}, (MsSpan){0});
  ms_strbuild_append_text(&out, ",\n  \"reason\": \"compile_error\",\n  \"diagnostics\": [");
  for (size_t i = 0; i < checked->findings.len; i++) {
    ms_strbuild_append_text(&out, i == 0 ? "\n" : ",\n");
    ms_json_diag(&out, checked->findings.ptr[i].file, checked->findings.ptr[i].phase, &checked->findings.ptr[i].diag);
  }
  ms_strbuild_append_text(&out, checked->findings.len == 0 ? "]\n}\n" : "\n  ]\n}\n");
  print_span(stdout, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return STATUS_FAILED;
}

/* A failure of the run itself (building the executable, starting it): code MSN001 at the input's first byte. */
static int report_error(const RunContext *context, const char *phase, MsSpan message) {
  if (!context->invocation->json) {
    print_span(stderr, ms_message_format(context->arena, "%S\n", message));
    return STATUS_FAILED;
  }
  MsStrBuild out = ms_strbuild_new();
  begin_document(&out, context, STATUS_FAILED, (MsSpan){0}, (MsSpan){0});
  ms_strbuild_printf(&out, ",\n  \"reason\": \"%s_error\",\n  \"diagnostics\": [\n    {\n      \"code\": \"MSN001\",\n"
                           "      \"phase\": \"%s\",\n      \"message\": ",
                     phase, phase);
  ms_json_string(&out, message);
  ms_strbuild_append_text(&out, ",\n      \"position\": ");
  ms_json_position(&out, context->invocation->filename, (MsPos){.line = 1, .column = 1}, 3);
  ms_strbuild_append_text(&out, "\n    }\n  ]\n}\n");
  print_span(stdout, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return STATUS_FAILED;
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

/* Starts the executable with the program's arguments; the process status is its own. */
static int execute(const RunContext *context, MsSpan executable, MsSpan directory) {
  const MsInvocation *invocation = context->invocation;
  MsSpanList argv = {0};
  ms_span_list_push(&argv, executable);
  for (size_t i = 0; i < invocation->arguments.len; i++) {
    ms_span_list_push(&argv, invocation->arguments.ptr[i]);
  }
  const MsSpan out_path = ms_message_format(context->arena, "%S/stdout", directory, (MsSpan){0});
  const MsSpan err_path = ms_message_format(context->arena, "%S/stderr", directory, (MsSpan){0});
  const MsProcessSpec spec = {.argv = argv.ptr, .argc = argv.len, .log_path = out_path, .error_path = err_path,
                              .inherit = !invocation->json};
  MsStrBuild why = ms_strbuild_new();
  int status = 0;
  (void)fflush(stdout);
  const bool started = ms_process_run(&spec, &status, &why);
  if (!started) {
    status = report_error(context, "execution", ms_arena_copy(context->arena, ms_strbuild_span(&why)));
  } else if (invocation->json) {
    MsStrBuild out = ms_strbuild_new();
    begin_document(&out, context, status, read_text(context->arena, out_path), read_text(context->arena, err_path));
    ms_strbuild_append_text(&out, ",\n  \"diagnostics\": []\n}\n");
    print_span(stdout, ms_strbuild_span(&out));
    ms_strbuild_free(&out);
  }
  ms_strbuild_free(&why);
  ms_span_list_free(&argv);
  return status;
}

static int build_and_run(MsArena *arena, const MsInvocation *invocation, MsCheckedInput *checked) {
  RunContext context = {.arena = arena, .invocation = invocation};
  const bool compiled = ms_checked_input_load(arena, checked, invocation->filename, MS_INPUT_PROGRAM);
  context.source_root = checked->graph.source_root;
  if (!compiled) {
    return print_compile_failure(&context, checked);
  }
  const MsString temp = ms_temp_dir();
  MsString directory = ms_string_empty();
  if (!ms_dir_make_temp(ms_string_span(&temp), ms_span_of_text("manuscript-run-"), &directory)) {
    return report_error(&context, "execution", ms_span_of_text("cannot create a temporary directory"));
  }
  const MsSpan folder = ms_arena_copy(arena, ms_string_span(&directory));
  const MsSpan executable = ms_message_format(arena, MS_TEMP_PROGRAM, folder, (MsSpan){0});
  MsSpan error = {0};
  const MsLinkRequest request = {.program = &checked->program, .entry = checked->entry,
                                 .build_type = invocation->build_type, .output = executable,
                                 .link = invocation->link.ptr, .link_count = invocation->link.len,
                                 .static_libc = invocation->static_libc};
  const int status = ms_pipeline_link(&request, &error) ? execute(&context, executable, folder)
                                                         : report_error(&context, "build", error);
  ms_path_remove_tree(folder);
  ms_string_release(&directory);
  return status;
}

/* What `--watch` polls while the program runs: a change to a watched file stops it so the next build can replace it. */
typedef struct WatchedRun {
  const MsSpanList *watched;
  MsStrBuild *signature;
  bool changed;
} WatchedRun;

static bool stop_on_change(void *context) {
  WatchedRun *run = context;
  run->changed = run->changed || watch_changed(run->watched, run->signature);
  return run->changed;
}

/* Builds and starts the program once; `*changed` says the run ended because a watched file changed. False when the
 * build failed. */
static bool watch_once(const MsInvocation *invocation, MsSpanList *watched, const char *reason, bool *changed) {
  MsArena arena = ms_arena_new();
  MsCheckedInput checked = {0};
  RunContext context = {.arena = &arena, .invocation = invocation};
  const uint64_t started = watch_now_ms();
  const bool compiled = ms_checked_input_load(&arena, &checked, invocation->filename, MS_INPUT_PROGRAM);
  context.source_root = checked.graph.source_root;
  watch_add_inputs(&arena, invocation->filename, &checked.graph, watched);
  bool built = false;
  *changed = false;
  if (!compiled) {
    (void)print_compile_failure(&context, &checked);
  } else {
    const MsString temp = ms_temp_dir();
    MsString directory = ms_string_empty();
    if (!ms_dir_make_temp(ms_string_span(&temp), ms_span_of_text("manuscript-watch-"), &directory)) {
      (void)report_error(&context, "execution", ms_span_of_text("cannot create a temporary directory"));
    } else {
      const MsSpan folder = ms_arena_copy(&arena, ms_string_span(&directory));
      const MsSpan executable = ms_message_format(&arena, MS_TEMP_PROGRAM, folder, (MsSpan){0});
      MsSpan error = {0};
      const MsLinkRequest request = {.program = &checked.program, .entry = checked.entry,
                                     .build_type = invocation->build_type, .output = executable,
                                     .link = invocation->link.ptr, .link_count = invocation->link.len,
                                     .static_libc = invocation->static_libc};
      if (!ms_pipeline_link(&request, &error)) {
        (void)report_error(&context, "build", error);
      } else {
        built = true;
        print_span(stderr, ms_message_format(&arena, "ms: %s run in %z ms\n", reason, (size_t)(watch_now_ms() - started)));
      }
      if (built) {
        MsSpanList argv = {0};
        ms_span_list_push(&argv, executable);
        for (size_t i = 0; i < invocation->arguments.len; i++) {
          ms_span_list_push(&argv, invocation->arguments.ptr[i]);
        }
        MsStrBuild signature = ms_strbuild_new();
        watch_snapshot(watched, &signature);
        WatchedRun run = {.watched = watched, .signature = &signature};
        const MsProcessSpec spec = {.argv = argv.ptr, .argc = argv.len, .inherit = true,
                                    .supervise = stop_on_change, .supervise_context = &run};
        MsStrBuild why = ms_strbuild_new();
        int status = 0;
        (void)fflush(stdout);
        if (!ms_process_run(&spec, &status, &why)) {
          print_span(stderr, ms_message_format(&arena, "%S\n", ms_strbuild_span(&why)));
        } else if (run.changed) {
          watch_settle(watched, &signature);
          *changed = true;
        } else {
          print_span(stderr, ms_message_format(&arena, "ms: exited with status %z; waiting for changes\n", (size_t)status));
        }
        ms_strbuild_free(&why);
        ms_strbuild_free(&signature);
        ms_span_list_free(&argv);
      }
      ms_path_remove_tree(folder);
      ms_string_release(&directory);
    }
  }
  ms_checked_input_free(&checked);
  ms_arena_free(&arena);
  return built;
}

/* `--watch`: runs the program, and after each saved change stops it and runs the new build. A build that fails only
 * reports its diagnostics; the loop ends with the process (Ctrl-C). */
static int watch_run(const MsInvocation *invocation) {
  const char *reason = "started";
  for (;;) {
    MsSpanList watched = {0};
    const uint64_t started = watch_now_ms();
    bool changed = false;
    const bool built = watch_once(invocation, &watched, reason, &changed);
    if (!built) {
      print_span(stderr, ms_span_of_text("ms: waiting for changes\n"));
    }
    if (!changed) {
      watch_wait(&watched, started);
    }
    ms_span_list_free(&watched);
    reason = "restarted";
  }
}

int ms_run_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "run", argc, argv, &invocation);
  if (status == 0 && invocation.watch) {
    status = watch_run(&invocation);
  } else if (status == 0) {
    MsCheckedInput checked = {0};
    status = build_and_run(&arena, &invocation, &checked);
    ms_checked_input_free(&checked);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
