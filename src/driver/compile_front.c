/* Owns compile_front.h. */
#include "driver/compile_front.h"

#include <stdio.h>

#include "base/message.h"
#include "base/sort.h"
#include "compiler/own/own.h"

static void add_finding(MsArena *arena, FindingList *findings, MsSpan file, const char *phase, MsPos pos,
                        MsSpan message) {
  finding_list_push(findings, (Finding){.file = ms_arena_copy(arena, file), .phase = phase,
                                        .diag = {.pos = pos, .message = ms_arena_copy(arena, message)}});
}

/* A library project has no program to build. */
static void library_failure(MsArena *arena, const MsGraph *graph, FindingList *findings) {
  const MsPos pos = graph->manifest_position.line == 0 ? (MsPos){.line = 1, .column = 1} : graph->manifest_position;
  add_finding(arena, findings, graph->manifest_file, "resolution", pos,
              ms_span_of_text("library project has no executable entry; add entry = \"src/main.ms\" under [project] and "
                              "fn main() from that file, or use check, lint, or test for the library"));
}

static bool is_status_result(const MsTyTable *types, MsTy ty) {
  return ms_ty_is(types, ty, MS_BUILTIN_Result) && ms_ty_arg_count(types, ty) == 2 &&
         ms_ty_is(types, ms_ty_args(types, ty)[0], MS_BUILTIN_Optional) &&
         ms_ty_is(types, ms_ty_args(types, ty)[1], MS_BUILTIN_Error) &&
         ms_ty_is(types, ms_ty_args(types, ms_ty_args(types, ty)[0])[0], MS_BUILTIN_Int);
}

static bool is_close_result(const MsTyTable *types, MsTy ty) {
  return ms_ty_is(types, ty, MS_BUILTIN_Result) && ms_ty_arg_count(types, ty) == 2 &&
         ms_ty_is(types, ms_ty_args(types, ty)[0], MS_BUILTIN_Void) &&
         ms_ty_is(types, ms_ty_args(types, ty)[1], MS_BUILTIN_Error);
}

static bool main_result_ok(const MsTyTable *types, MsTy result) {
  return result == MS_TY_NONE || ms_ty_is(types, result, MS_BUILTIN_Int) || ms_ty_is(types, result, MS_BUILTIN_Void) ||
         is_close_result(types, result) || is_status_result(types, result);
}

/* Why `main` is not a usable entry, or empty text when it is. */
static MsSpan main_problem(MsArena *arena, const MsCheckProgram *program, const MsSymbol *main, MsPos *pos) {
  const MsTyTable *types = &program->types;
  *pos = main->decl != NULL ? main->decl->pos : (MsPos){.line = 1, .column = 1};
  if (main->decl != NULL && main->decl->kind == MS_D_CONST) {
    return ms_span_of_text("main is a constant, so rename it and declare 'fn main() Void:'");
  }
  if (main->kind != MS_SYMBOL_FN || (main->decl != NULL && main->decl->kind != MS_D_FN)) {
    return ms_span_of_text("main is declared as a type, so rename it and declare 'fn main() Void:'");
  }
  if (main->var_count > 0) {
    return ms_span_of_text("main cannot be generic, so remove its type parameters");
  }
  if (main->ty != MS_TY_NONE && ms_ty_param_count(types, main->ty) > 0) {
    return ms_span_of_text("main takes no parameters, so remove them (read program arguments through the standard cli "
                           "module)");
  }
  const MsTy result = main->ty == MS_TY_NONE ? MS_TY_NONE : ms_ty_result(types, main->ty);
  if (main_result_ok(types, result)) {
    return (MsSpan){0};
  }
  MsStrBuild shown = ms_strbuild_new();
  ms_ty_show(&shown, program->names, types, result);
  const MsSpan text = ms_message_format(arena, "main returns %S, so return Void, Void! (an error prints and exits 1), "
                                               "Int?!, or an Int exit status",
                                        ms_strbuild_span(&shown), (MsSpan){0});
  ms_strbuild_free(&shown);
  return text;
}

/* The entry module must declare a usable `main`. */
static void require_main(MsArena *arena, MsFront *front) {
  const MsCheckProgram *program = &front->program;
  const MsModuleInfo *module = &program->modules.ptr[front->entry];
  const MsSpan file = ms_names_span(program->names, module->file);
  MsName name = 0;
  const MsSymbolId *found = ms_names_find(program->names, ms_span_of_text("main"), &name)
                                ? ms_scope_get(&module->scope, name)
                                : NULL;
  MsPos pos = {.line = 1, .column = 1};
  MsSpan problem = ms_span_of_text("no main function is declared, so add 'fn main() Void:' with an indented body");
  if (found != NULL) {
    problem = main_problem(arena, program, &program->symbols.ptr[*found], &pos);
    if (problem.len == 0) {
      return;
    }
  }
  add_finding(arena, &front->findings, file, "type", pos,
              ms_message_format(arena, "entry must declare fn main; %S", problem, (MsSpan){0}));
}

static uint32_t entry_module(const MsCheckProgram *program, const MsGraph *graph) {
  for (uint32_t i = 0; i < program->user_modules; i++) {
    if (ms_span_equal(ms_names_span(program->names, program->modules.ptr[i].file), graph->entry)) {
      return i;
    }
  }
  return program->user_modules > 0 ? program->user_modules - 1 : 0;
}

bool ms_front_compile(MsArena *arena, MsFront *front, MsSpan filename, MsFrontTarget target) {
  ms_names_init(&front->names);
  const bool tests = target == MS_FRONT_TESTS;
  const MsLoadOptions load = {.tests = tests};
  ms_project_load(arena, &front->names, filename, &load, &front->graph);
  const MsGraph *graph = &front->graph;
  if (!tests && graph->project_root.len > 0 && graph->library && graph->diagnostic_count == 0) {
    library_failure(arena, graph, &front->findings);
    return false;
  }
  finding_add_graph(graph, &front->findings);
  if (front->findings.len > 0) {
    return false;
  }
  ms_check_graph(&front->program, &front->names, graph);
  ms_own_check(&front->program);
  front->checked = true;
  finding_add_check(&front->program, &front->names, &front->findings);
  front->entry = entry_module(&front->program, graph);
  if (front->findings.len == 0 && !tests) {
    require_main(arena, front);
  }
  return front->findings.len == 0;
}

int ms_front_report(const MsFront *front) {
  FindingList sorted = {0};
  for (size_t i = 0; i < front->findings.len; i++) {
    finding_list_push(&sorted, front->findings.ptr[i]);
  }
  ms_sort((uint8_t *)sorted.ptr, sorted.len, sizeof(Finding), finding_compare, NULL);
  MsStrBuild err = ms_strbuild_new();
  finding_terminal_text(&err, front->graph.source_root, &sorted);
  const MsSpan text = ms_strbuild_span(&err);
  (void)fwrite(text.ptr, 1, text.len, stderr);
  ms_strbuild_free(&err);
  finding_list_free(&sorted);
  return 1;
}

void ms_front_free(MsFront *front) {
  finding_list_free(&front->findings);
  if (front->checked) {
    ms_check_program_free(&front->program);
  }
  ms_names_free(&front->names);
}
