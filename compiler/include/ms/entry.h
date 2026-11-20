/* Entry validation: the program's entry module declares a `main` the runtime can start. Port of
 * `check_entry` in crates/ms-driver/src/compile.rs. */
#ifndef MS_ENTRY_H
#define MS_ENTRY_H

#include "ms/tables.h"

/* Checks the `main` of module `entry` after the module checked without errors: a nongeneric,
 * parameterless function returning `Void`, `Void!`, `Int` or `Int?!` (a constant or a type named
 * `main` is refused with its own message). With `only_if_declared`, a module without `main` passes.
 * Returns false when `main` is fine; true with the diagnostic in *out (position, a type-phase
 * message allocated in the checker's arena). */
bool ms_check_entry(MsCheck *c, MsModId entry, bool only_if_declared, MsCheckDiag *out);

#endif
