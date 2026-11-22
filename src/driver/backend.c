/* driver/backend.c: lowering, the MIR passes, the optimiser and the emitter, in order, over one in-memory
 * module. */
#include "driver/backend.h"

#include "compiler/emit/emit.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_pipeline.h"
#include "compiler/opt/opt.h"

/* The passes from lowered MIR to a finished module; `glue` and `data` are the caller's to free. */
static bool run_passes(MirModule *module, const BackendOptions *options, MirGlue *glue, MirData *data,
                       MsStrBuild *why) {
  const MirPipelineOptions pipeline = {.verify = options->verify};
  if (!mir_pipeline_prepare(module, &pipeline, why)) {
    return false;
  }
  const MirOptLevel level = options->optimize ? MIR_OPT_SPEED : MIR_OPT_NONE;
  if (!mir_optimize(module, level, options->verify, why) || !mir_pipeline_finish(module, &pipeline, glue, why)) {
    return false;
  }
  mir_pipeline_backend(module, glue, data);
  return true;
}

/* With `kept`, the fault tables are wanted: the table info is read before the functions are renamed, every
 * function is exported and every instruction carries its source place. */
static bool emit_program(MirModule *module, const MirData *data, const MirGlue *glue, BackendProgram *kept,
                         MsStrBuild *ir, MsStrBuild *why) {
  if (kept != NULL) {
    emit_table_info(&kept->arena, module, &kept->tables);
  }
  emit_name_symbols(module);
  const EmitOptions emit = {.export_all = kept != NULL, .places = kept != NULL};
  if (!emit_module(module, data, glue, &emit, ir, why)) {
    return false;
  }
  emit_entry_main(module, kept != NULL, ir);
  return true;
}

static bool compile(MsCheckProgram *program, uint32_t entry_module, const BackendOptions *options, MirModule *module,
                    BackendProgram *kept, MsStrBuild *ir, MsStrBuild *why) {
  MirGlue glue = {0};
  MirData data = {0};
  bool ok = options->tests ? ms_lower_tests(program, module, why) : ms_lower_program(program, entry_module, module, why);
  ok = ok && run_passes(module, options, &glue, &data, why);
  ok = ok && emit_program(module, &data, &glue, kept, ir, why);
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
