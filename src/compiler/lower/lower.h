/* compiler/lower/lower.h: lowering, the entry point of the lower layer.
 *
 * Turns a checked program into one MirModule. The program's functions are lowered on demand from its entry
 * function: each reached function, with each distinct set of type arguments, becomes one MIR function
 * (generics are instantiated here, so MIR holds no type variable). The checker's facts (compiler/check/
 * facts.h) say what every name, call, conversion, constant and use means; the syntax tree says the shape. */
#ifndef MS_COMPILER_LOWER_LOWER_H
#define MS_COMPILER_LOWER_LOWER_H

#include "base/strbuild.h"
#include "compiler/check/program.h"
#include "compiler/mir/mir.h"

/* Lowers the program whose entry module is `entry_module` (the module declaring `main`). `module` must be
 * initialised with mir_module_init and is filled in. On failure `error` holds the reason and the module is
 * unusable. */
bool ms_lower_program(MsCheckProgram *program, uint32_t entry_module, MirModule *module, MsStrBuild *error);

#endif
