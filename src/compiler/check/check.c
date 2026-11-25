/* compiler/check/check.c: the checker's entry point; runs the passes over a module graph in order. */
#include "compiler/check/fallthrough.h"
#include "compiler/check/message_fixes.h"
#include "compiler/check/order.h"
#include "compiler/check/body.h"
#include "compiler/check/constants.h"
#include "compiler/check/exports.h"
#include "compiler/check/methods.h"
#include "compiler/check/mutate.h"
#include "compiler/check/lazy_std.h"
#include "compiler/check/std_cache.h"
#include "compiler/check/names.h"
#include "compiler/check/returns.h"
#include "compiler/check/shadow.h"
#include "compiler/check/program.h"

static void check_graph(MsCheckProgram *program, MsNames *names, const MsGraph *graph, bool lazy_std, bool all_std,
                        const MsStdCache *cache) {
  ms_check_program_init(program, names);
  program->std_cache = cache;
  program->all_std = all_std;
  program->lazy_std = lazy_std;
  for (size_t index = 0; index < graph->count; index++) {
    const MsGraphModule *module = &graph->modules[index];
    const MsName file = ms_names_intern(names, module->name);
    const uint32_t added = ms_check_add_module(program, file, &module->syntax);
    program->modules.ptr[added].targets = module->targets;
    program->modules.ptr[added].source = module->source;
    program->modules.ptr[added].missing = module->missing;
    if (module->std_name.len != 0) {
      MsStrBuild id = ms_strbuild_new();
      ms_strbuild_append_text(&id, "@std/");
      ms_strbuild_append(&id, module->std_name);
      program->modules.ptr[added].id = ms_names_intern(names, ms_strbuild_span(&id));
      ms_strbuild_free(&id);
    }
  }
  program->user_modules = (uint32_t)program->modules.len;
  program->check_std = true; /* an error in the bundled standard library fails every build that loads it */
  ms_check_load_std(program);
  for (uint32_t index = 0; index < program->modules.len; index++) {
    ms_check_declare(program, index);
  }
  for (uint32_t index = 0; index < program->modules.len; index++) {
    ms_check_bind_imports(program, index);
  }
  /* The standard modules may import each other, so each pass runs over all of them before the next. */
  for (uint32_t index = 0; index < program->modules.len; index++) {
    if (!ms_check_is_user_module(program, index)) {
      ms_check_type_variables(program, index);
    }
  }
  for (uint32_t index = 0; index < program->modules.len; index++) {
    if (!ms_check_is_user_module(program, index)) {
      ms_check_signatures(program, index);
    }
  }
  for (uint32_t index = 0; index < program->modules.len; index++) {
    if (!ms_check_is_user_module(program, index)) {
      ms_check_methods(program, index);
    }
  }
  for (uint32_t index = 0; index < program->user_modules; index++) {
    if (!ms_check_is_user_module(program, index)) {
      continue;
    }
    program->stage = MS_STAGE_IMPORTS;
    ms_check_report_imports(program, index, graph->modules[index].source);
    program->stage = MS_STAGE_DECLARATIONS;
    ms_check_type_variables(program, index);
    ms_check_signatures(program, index);
    ms_check_methods(program, index);
    ms_check_constants(program, index);
    ms_check_exports(program, index);
    program->stage = MS_STAGE_SIDE;
    ms_check_mutation(program, index, graph->modules[index].source);
    ms_check_shadowing(program, index);
    const size_t before_names = program->diagnostics.len;
    ms_check_names(program, index);
    ms_check_defer(program, before_names);
    ms_check_returns(program, index);
    program->stage = MS_STAGE_DECLARATIONS;
  }
  program->stage = MS_STAGE_WALK;
  if (lazy_std) {
    ms_check_defer_std_bodies(program);
  }
  for (uint32_t index = 0; index < program->modules.len; index++) {
    ms_check_bodies(program, index, index < program->user_modules ? graph->modules[index].source : (MsSpan){0});
  }
  if (lazy_std) {
    ms_check_restore_reached(program);
  }
  ms_check_release_rest(program);
  ms_check_flush_pending_bounds(program);
  program->stage = MS_STAGE_FINAL; /* found once every body was walked: listed after them */
  ms_check_finite_types(program);
  ms_check_finite_functions(program);
  program->stage = MS_STAGE_WALK;
  for (uint32_t index = 0; index < program->user_modules; index++) {
    if (!ms_check_is_user_module(program, index)) {
      continue;
    }
    const MsModule *tree = program->modules.ptr[index].tree;
    for (uint32_t at = 0; at < tree->ndecls; at++) {
      ms_check_fallthrough(program, index, tree->decls[at]);
    }
  }
  ms_check_order_diagnostics(program);
  ms_check_attach_message_fixes(program);
}

void ms_check_graph(MsCheckProgram *program, MsNames *names, const MsGraph *graph) {
  check_graph(program, names, graph, false, false, NULL);
}

void ms_check_graph_analysis(MsCheckProgram *program, MsNames *names, const MsGraph *graph) {
  check_graph(program, names, graph, true, false, NULL);
}

void ms_check_graph_std(MsCheckProgram *program, MsNames *names, const MsGraph *graph) {
  check_graph(program, names, graph, false, true, NULL);
}

void ms_check_graph_cached(MsCheckProgram *program, MsNames *names, const MsGraph *graph, const MsStdCache *cache) {
  check_graph(program, names, graph, false, false, cache);
}
