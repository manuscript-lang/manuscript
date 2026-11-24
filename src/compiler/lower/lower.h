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

/* Lowers the program's tests under a test entry instead of `main`: one runner per test file of the program's own
 * modules (not the bundled standard library, no `bench` blocks), in module order, handed to `run_test_files` of
 * src/stdlib/internal/test_runner.ms. A test's index is its position among the tests in module order and then
 * declaration order. Needs the runner module in `program`. */
bool ms_lower_tests(MsCheckProgram *program, MirModule *module, MsStrBuild *error);

/* The same for the program's `bench` blocks: each runs as a test whose body is `run_bench_block(body, operations)`
 * of src/stdlib/test/bench.ms, which repeats and times it. Needs the runner and the bench driver modules in `program`. */
bool ms_lower_benches(MsCheckProgram *program, MirModule *module, MsStrBuild *error);

#endif
