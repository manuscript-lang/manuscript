/* Driver: `ms emit <target> [-o file]`. Loads and checks the project, lowers it and prints the module as MIR text
 * to stdout or to the file. A project that does not load or check fails with the diagnostics `ms check` gives. */
#include "driver/emit_command.h"

#include <stdio.h>

#include "base/file.h"
#include "compiler/check/program.h"
#include "compiler/own/own.h"
#include "compiler/project/project.h"
#include "driver/backend.h"
#include "driver/check_command.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2 };

/* The module whose path is the program's entry, or the last one. */
static uint32_t entry_module(const MsCheckProgram *program, const MsNames *names, MsSpan entry) {
  for (uint32_t index = 0; index < program->modules.len; index++) {
    if (ms_span_equal(ms_names_span(names, program->modules.ptr[index].file), entry)) {
      return index;
    }
  }
  return (uint32_t)program->modules.len - 1;
}

static bool is_flag(const char *argument, const char *flag) {
  return ms_span_is_text(ms_span_of_text(argument), flag);
}

/* Whether loading and checking `target` found nothing to report. */
static bool accepted(MsArena *arena, MsNames *names, MsSpan target, MsGraph *graph, MsCheckProgram *program) {
  const MsLoadOptions load = {.project_sources = true};
  ms_project_load(arena, names, target, &load, graph);
  if (graph->diagnostic_count != 0) {
    return false;
  }
  ms_check_graph(program, names, graph);
  ms_own_check(program);
  return program->diagnostics.len == 0;
}

static int emit_target(MsSpan target, const char *output) {
  MsArena arena = ms_arena_new();
  MsNames names;
  ms_names_init(&names);
  MsGraph graph = {0};
  MsCheckProgram program = {0};
  int status = 0;
  if (!accepted(&arena, &names, target, &graph, &program)) {
    status = -1;
  } else {
    MsStrBuild text = ms_strbuild_new();
    MsStrBuild why = ms_strbuild_new();
    const BackendOptions options = {.optimize = false, .verify = true};
    if (!ms_backend_mir(&program, entry_module(&program, &names, graph.entry), &options, &text, &why)) {
      (void)fprintf(stderr, "ms emit: %.*s\n", (int)ms_strbuild_length(&why), (const char *)ms_strbuild_span(&why).ptr);
      status = STATUS_FAILED;
    } else if (output != NULL) {
      status = ms_file_write(ms_span_of_text(output), ms_strbuild_span(&text)) ? 0 : STATUS_FAILED;
    } else {
      const MsSpan out = ms_strbuild_span(&text);
      (void)fwrite(out.ptr, 1, out.len, stdout);
    }
    ms_strbuild_free(&why);
    ms_strbuild_free(&text);
  }
  if (program.names != NULL) {
    ms_check_program_free(&program);
  }
  ms_names_free(&names);
  ms_arena_free(&arena);
  return status;
}

int ms_emit_command(int argc, char **argv) {
  const char *target = NULL;
  int target_at = 0;
  const char *output = NULL;
  for (int index = 0; index < argc; index++) {
    if (is_flag(argv[index], "-o") && index + 1 < argc) {
      output = argv[++index];
    } else if (argv[index][0] == '-' || target != NULL) {
      (void)fprintf(stderr, "usage: ms emit <file.ms|project> [-o file]\n");
      return STATUS_USAGE;
    } else {
      target = argv[index];
      target_at = index;
    }
  }
  if (target == NULL) {
    (void)fprintf(stderr, "usage: ms emit <file.ms|project> [-o file]\n");
    return STATUS_USAGE;
  }
  const int status = emit_target(ms_span_of_text(target), output);
  /* The checker's diagnostics are the check command's to print, in its format. */
  if (status != -1) {
    return status;
  }
  char *check_args[1] = {argv[target_at]};
  return ms_check_command(1, check_args);
}
