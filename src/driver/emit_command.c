/* driver/emit_command.c: `ms emit <file.ms> [--ir]`. A single file or a project entry: loaded, checked, lowered,
 * and printed as MIR text or as LLVM IR. Status 0 is printed, 1 a diagnostic or a back-end failure, 2 usage. */
#include "driver/emit_command.h"

#include <stdio.h>

#include "base/cstr.h"
#include "compiler/check/program.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_pipeline.h"
#include "compiler/mir/mir_print.h"
#include "compiler/own/own.h"
#include "compiler/project/project.h"
#include "driver/backend.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2 };

static void print_builder(FILE *stream, MsStrBuild *text) {
  const MsSpan span = ms_strbuild_span(text);
  (void)fwrite(span.ptr, 1, span.len, stream);
}

/* The module index of the graph's entry, or the last user module. */
static uint32_t entry_module(const MsCheckProgram *program, const MsGraph *graph) {
  for (uint32_t index = 0; index < program->user_modules; index++) {
    const MsSpan file = ms_names_span(program->names, program->modules.ptr[index].file);
    if (ms_span_equal(file, graph->entry)) {
      return index;
    }
  }
  return program->user_modules > 0 ? program->user_modules - 1 : 0;
}

static int print_diagnostics(const MsCheckProgram *program) {
  for (size_t index = 0; index < program->diagnostics.len; index++) {
    const MsCheckDiag *issue = &program->diagnostics.ptr[index];
    const MsSpan file = ms_names_span(program->names, program->modules.ptr[issue->module].file);
    (void)fprintf(stderr, "%.*s:%u:%u: ", (int)file.len, (const char *)file.ptr, issue->pos.line, issue->pos.column);
    const MsSpan message = ms_string_span(&issue->message);
    (void)fprintf(stderr, "%.*s\n", (int)message.len, (const char *)message.ptr);
  }
  return STATUS_FAILED;
}

/* Lowers and prints MIR after elaboration, so what is shown is what the later passes read. */
static bool print_mir(MsCheckProgram *program, uint32_t entry, MsStrBuild *out, MsStrBuild *why) {
  MirModule module;
  mir_module_init(&module);
  bool ok = ms_lower_program(program, entry, &module, why);
  if (ok) {
    mir_print_module(&module, out);
  }
  mir_module_free(&module);
  return ok;
}

static int emit_program(MsCheckProgram *program, uint32_t entry, bool ir) {
  MsStrBuild out = ms_strbuild_new();
  MsStrBuild why = ms_strbuild_new();
  const BackendOptions options = {.optimize = false, .verify = true};
  const bool ok = ir ? ms_backend_ir(program, entry, &options, &out, &why) : print_mir(program, entry, &out, &why);
  if (ok) {
    print_builder(stdout, &out);
  } else {
    print_builder(stderr, &why);
  }
  ms_strbuild_free(&out);
  ms_strbuild_free(&why);
  return ok ? 0 : STATUS_FAILED;
}

int ms_emit_command(int argc, char **argv) {
  const char *target = NULL;
  bool ir = false;
  for (int index = 0; index < argc; index++) {
    if (ms_cstr_equal(argv[index], "--ir")) {
      ir = true;
    } else if (target == NULL && argv[index][0] != '-') {
      target = argv[index];
    } else {
      (void)fprintf(stderr, "usage: ms emit <file.ms> [--ir]\n");
      return STATUS_USAGE;
    }
  }
  if (target == NULL) {
    (void)fprintf(stderr, "usage: ms emit <file.ms> [--ir]\n");
    return STATUS_USAGE;
  }
  MsArena arena = ms_arena_new();
  MsNames names;
  ms_names_init(&names);
  MsGraph graph = {0};
  const MsLoadOptions load = {0};
  ms_project_load(&arena, &names, ms_span_of_text(target), &load, &graph);
  MsCheckProgram program = {0};
  int status = STATUS_FAILED;
  if (graph.diagnostic_count == 0) {
    ms_check_graph(&program, &names, &graph);
    ms_own_check(&program);
    status = program.diagnostics.len != 0 ? print_diagnostics(&program)
                                          : emit_program(&program, entry_module(&program, &graph), ir);
    ms_check_program_free(&program);
  } else {
    (void)fprintf(stderr, "ms emit: %s could not be loaded\n", target);
  }
  ms_names_free(&names);
  ms_arena_free(&arena);
  return status;
}
