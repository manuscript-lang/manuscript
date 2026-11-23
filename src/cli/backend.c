/* cli/backend.c: lowering, the MIR passes, the optimiser and the emitter, in order, over one in-memory
 * module. */
#include "cli/backend.h"

#include "compiler/emit/emit.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_pipeline.h"
#include "compiler/opt/opt.h"

/* The passes from lowered MIR to a finished module; `glue` and `data` are the caller's to free. */
static bool run_passes(MirModule *module, const BackendOptions *options, MirGlue *glue, MirData *data,
                       MsStrBuild *why) {
  const MirPipelineOptions pipeline = {.verify = options->verify, .checks = true,
                                       .count_ops = options->count_ops};
  if (!mir_pipeline_prepare(module, &pipeline, why)) {
    return false;
  }
  if ((options->optimize && !mir_optimize(module, options->compact, options->verify, why)) ||
      !mir_pipeline_finish(module, &pipeline, glue, why)) {
    return false;
  }
  mir_pipeline_backend(module, glue, data);
  return true;
}

/* With `kept`, the fault tables are wanted: the table info is read before the functions are renamed, every
 * function is exported and every instruction carries its source place. */
static bool emit_program(MirModule *module, const MirData *data, const MirGlue *glue, BackendProgram *kept,
                         const BackendOptions *options, MsStrBuild *ir, MsStrBuild *why) {
  if (kept != NULL) {
    emit_table_info(&kept->arena, module, &kept->tables);
  }
  emit_name_symbols(module);
  const EmitOptions emit = {.export_all = kept != NULL, .places = kept != NULL,
                          .wide_leaves = options->wide_leaves, .wide_hide = options->wide_hide,
                          .poison_slots = options->poison_slots};
  if (!emit_module(module, data, glue, &emit, ir, why)) {
    return false;
  }
  emit_entry_main(module, kept != NULL, ir);
  return true;
}

#define INTERNAL_PREFIX "internal compiler error: "

/* Says where to take a compiler bug. */
static void append_report_advice(MsStrBuild *why) {
  ms_strbuild_append_text(why, "\nThis is a bug in ms, not in your program. Please report it at "
                               "https://github.com/manuscript-lang/manuscript/issues with the code that triggers it.\n");
}

/* Runs the stages after lowering into a scratch buffer so a failure there is labelled as a compiler bug. */
static bool compile_stages(MirModule *module, const BackendOptions *options, MirGlue *glue, MirData *data,
                           BackendProgram *kept, MsStrBuild *ir, MsStrBuild *why) {
  MsStrBuild detail = ms_strbuild_new();
  bool ok = run_passes(module, options, glue, data, &detail) && emit_program(module, data, glue, kept, options, ir, &detail);
  if (!ok) {
    ms_strbuild_append_text(why, INTERNAL_PREFIX);
    ms_strbuild_append(why, ms_strbuild_span(&detail));
    append_report_advice(why);
  }
  ms_strbuild_free(&detail);
  return ok;
}

static bool compile(MsCheckProgram *program, uint32_t entry_module, const BackendOptions *options, MirModule *module,
                    BackendProgram *kept, MsStrBuild *ir, MsStrBuild *why) {
  MirGlue glue = {0};
  MirData data = {0};
  bool ok = false;
  if (options->tests) {
    ok = options->bench ? ms_lower_benches(program, module, why) : ms_lower_tests(program, module, why);
  } else {
    ok = ms_lower_program(program, entry_module, module, why);
  }
  if (!ok) {
    /* A lowering failure is a program error, unless the lowerer labelled it internal. */
    const MsSpan text = ms_strbuild_span(why);
    size_t at = 0;
    if (ms_span_find(text, ms_span_of_text(INTERNAL_PREFIX), &at)) {
      append_report_advice(why);
    }
  }
  ok = ok && compile_stages(module, options, &glue, &data, kept, ir, why);
  mir_data_free(&data);
  mir_glue_free(&glue);
  return ok;
}

bool ms_backend_ir(MsCheckProgram *program, uint32_t entry_module, const BackendOptions *options, MsStrBuild *ir,
                   MsStrBuild *why) {
  MirModule module;
  mir_module_init(&module);
  const bool ok = compile(program, entry_module, options, &module, NULL, ir, why);
  mir_module_free(&module);
  return ok;
}

bool ms_backend_compile(MsCheckProgram *program, uint32_t entry_module, const BackendOptions *options,
                        MsStrBuild *ir, BackendProgram *out, MsStrBuild *why) {
  mir_module_init(&out->module);
  out->arena = ms_arena_new();
  out->tables = (EmitTableInfo){0};
  return compile(program, entry_module, options, &out->module, out, ir, why);
}

void ms_backend_program_free(BackendProgram *program) {
  mir_module_free(&program->module);
  ms_arena_free(&program->arena);
}
