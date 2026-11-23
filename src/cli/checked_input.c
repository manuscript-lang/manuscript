/* Owns checked_input.h. */
#include "cli/checked_input.h"

#include <stdio.h>

#include "base/message.h"
#include "base/sort.h"
#include "compiler/own/own.h"
#include "compiler/syntax/diag_json.h"

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

/* The entry module must declare a usable `main`; with `declared_only`, a module that declares none is left alone
 * (`ms check` of a library). */
void ms_require_main(MsArena *arena, const MsCheckProgram *program, uint32_t entry, bool declared_only,
                     FindingList *findings) {
  const MsModuleInfo *module = &program->modules.ptr[entry];
  const MsSpan file = ms_names_span(program->names, module->file);
  MsName name = 0;
  const MsSymbolId *found = ms_names_find(program->names, ms_span_of_text("main"), &name)
                                ? ms_scope_get(&module->scope, name)
                                : NULL;
  if (found == NULL && declared_only) {
    return;
  }
  MsPos pos = {.line = 1, .column = 1};
  MsSpan problem = ms_span_of_text("no main function is declared, so add 'fn main() Void:' with an indented body");
  if (found != NULL) {
    problem = main_problem(arena, program, &program->symbols.ptr[*found], &pos);
    if (problem.len == 0) {
      return;
    }
  }
  add_finding(arena, findings, file, "type", pos,
              ms_message_format(arena, "entry must declare fn main; %S", problem, (MsSpan){0}));
}

uint32_t ms_entry_module(const MsCheckProgram *program, const MsGraph *graph) {
  for (uint32_t i = 0; i < program->user_modules; i++) {
    if (ms_span_equal(ms_names_span(program->names, program->modules.ptr[i].file), graph->entry)) {
      return i;
    }
  }
  return program->user_modules > 0 ? program->user_modules - 1 : 0;
}

bool ms_checked_input_load(MsArena *arena, MsCheckedInput *checked, MsSpan filename, MsInputTarget target) {
  const MsLoadOptions none = {0};
  return ms_checked_input_load_with(arena, checked, filename, target, &none);
}

bool ms_checked_input_load_with(MsArena *arena, MsCheckedInput *checked, MsSpan filename, MsInputTarget target,
                                const MsLoadOptions *extra) {
  ms_names_init(&checked->names);
  MsLoadOptions load = *extra;
  load.tests = target == MS_INPUT_TESTS;
  ms_project_load(arena, &checked->names, filename, &load, &checked->graph);
  const MsGraph *graph = &checked->graph;
  if (target == MS_INPUT_PROGRAM && graph->project_root.len > 0 && graph->library && graph->diagnostic_count == 0) {
    library_failure(arena, graph, &checked->findings);
    return false;
  }
  finding_add_graph(graph, &checked->findings);
  if (checked->findings.len > 0 && !(extra->recover && graph->count > 0)) {
    return false;
  }
  ms_check_graph(&checked->program, &checked->names, graph);
  ms_own_check(&checked->program);
  checked->checked = true;
  finding_add_check(&checked->program, &checked->names, &checked->findings);
  checked->entry = ms_entry_module(&checked->program, graph);
  if (checked->findings.len == 0 && target == MS_INPUT_PROGRAM) {
    ms_require_main(arena, &checked->program, checked->entry, false, &checked->findings);
  }
  return checked->findings.len == 0;
}

void ms_checked_input_test_names(MsArena *arena, const MsCheckedInput *checked, bool benches, MsSpanList *names) {
  const MsCheckProgram *program = &checked->program;
  for (uint32_t m = 0; m < program->user_modules; m++) {
    const MsModuleInfo *module = &program->modules.ptr[m];
    const MsSpan file = ms_names_span(program->names, module->file);
    for (uint32_t d = 0; d < module->tree->ndecls; d++) {
      const MsDecl *decl = module->tree->decls[d];
      if (decl->kind == MS_D_TEST && decl->u.test.bench == benches) {
        ms_span_list_push(names, ms_message_format(arena, "%S::%S", file, decl->u.test.name));
      }
    }
  }
}

int ms_checked_input_report(const MsCheckedInput *checked) {
  FindingList sorted = {0};
  for (size_t i = 0; i < checked->findings.len; i++) {
    finding_list_push(&sorted, checked->findings.ptr[i]);
  }
  MsStrBuild err = ms_strbuild_new();
  finding_terminal_text(&err, checked->graph.source_root, &sorted, false);
  const MsSpan text = ms_strbuild_span(&err);
  (void)fwrite(text.ptr, 1, text.len, stderr);
  ms_strbuild_free(&err);
  finding_list_free(&sorted);
  return 1;
}

MsSpan ms_checked_input_diagnostics_json(MsArena *arena, const MsCheckedInput *checked) {
  MsStrBuild out = ms_strbuild_new();
  for (size_t i = 0; i < checked->findings.len; i++) {
    ms_strbuild_append_text(&out, i == 0 ? "" : ",\n");
    ms_json_diag(&out, checked->findings.ptr[i].file, checked->findings.ptr[i].phase, &checked->findings.ptr[i].diag);
  }
  const MsSpan entries = ms_arena_copy(arena, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return entries;
}

int ms_checked_input_report_json(const MsCheckedInput *checked) {
  MsArena arena = ms_arena_new();
  const MsSpan entries = ms_checked_input_diagnostics_json(&arena, checked);
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_text(&out, "{\n  \"format\": 1,\n  \"diagnostics\": [");
  if (entries.len > 0) {
    ms_strbuild_append_byte(&out, '\n');
    ms_strbuild_append(&out, entries);
    ms_strbuild_append_text(&out, "\n  ]\n}\n");
  } else {
    ms_strbuild_append_text(&out, "]\n}\n");
  }
  const MsSpan text = ms_strbuild_span(&out);
  (void)fwrite(text.ptr, 1, text.len, stdout);
  ms_strbuild_free(&out);
  ms_arena_free(&arena);
  return 1;
}

void ms_checked_input_free(MsCheckedInput *checked) {
  finding_list_free(&checked->findings);
  if (checked->checked) {
    ms_check_program_free(&checked->program);
  }
  ms_names_free(&checked->names);
}
