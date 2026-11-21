/* compiler/check/check.c: the checker's entry point; runs the passes over a module graph in order. */
#include "compiler/check/program.h"

void ms_check_graph(MsCheckProgram *program, MsNames *names, const MsGraph *graph) {
  ms_check_program_init(program, names);
  for (size_t index = 0; index < graph->count; index++) {
    const MsGraphModule *module = &graph->modules[index];
    const MsName file = ms_names_intern(names, module->name);
    (void)ms_check_add_module(program, file, &module->syntax);
  }
  for (uint32_t index = 0; index < program->modules.len; index++) {
    ms_check_declare(program, index);
  }
  for (uint32_t index = 0; index < program->modules.len; index++) {
    ms_check_resolve_types(program, index);
  }
}
