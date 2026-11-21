/* Lowering: the checked syntax tree to Raw-phase MIR (crates/ms-lower). The output is compared
 * function by function with the Rust lowering's (src/compiler/tests/lower-diff.sh).
 *
 * The pass grows with the checker. A function is lowered only when the checker recorded its body
 * (`MsFacts.body_checked`) and every construct in it is one this pass handles; any other function
 * is left out of the module and stays with the Rust lowering. See lower_body.c for the handled set. */
#ifndef MS_LOWER_H
#define MS_LOWER_H

#include "ms/mir.h"
#include "ms/tables.h"

/* Lowers the functions of `module` the pass supports into `out` (initialised with
 * mir_module_init; the caller frees it). Returns how many functions were added. The checker must
 * have run `ms_module_check_bodies` on the module. */
uint32_t ms_lower_module(MsCheck *c, MsModId module, MirModule *out);

/* The same for every module of the checked program, into one MIR module: a call reaches a function
 * another module declares, and a generic function is copied from its own module's facts. `entry` is
 * the module that holds `main`: its source file is file 0, then the project modules in the order its
 * imports reach them, then the standard library's. */
uint32_t ms_lower_program(MsCheck *c, MsModId entry, MirModule *out);

/* The same, listing in `why` each function whose body the checker recorded and the lowering refused:
 * one line `name<TAB>module:line:col<TAB>reason`, where the place is the statement it stopped at and
 * the reason is the lowering source line that refused (`lower_body.c:123`), `signature`, or
 * `unhandled`. A caller of a refused function is listed too, at its call. */
uint32_t ms_lower_program_why(MsCheck *c, MsModId entry, MirModule *out, MsBuf *why);

/* The test build: `modules` (the checked program's, project modules first) lowered with each `test` block of a project
 * module (a `bench` block, with `bench`) a function and the entry a runner over them. `names` receives each test's
 * `module::name` identity, one per line, in index order. The entry is MIR_NONE when a test or the runner did not
 * lower; `why` lists what did not. */
uint32_t ms_lower_tests_why(MsCheck *c, const MsModId *modules, uint32_t nmodules, bool bench, MirModule *out, MsBuf *names,
                            MsBuf *why);

#endif
