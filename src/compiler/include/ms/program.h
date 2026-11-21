/* A program as the checker sees it: the bundled modules, the project's modules and the method table
 * their impls make. The Rust checker's `Program.methods`, built in one place so every tool and the
 * driver check a module the same way. */
#ifndef MS_PROGRAM_H
#define MS_PROGRAM_H

#include "ms/tables.h"

/* Starts a new program over the loaded standard library: the method table is empty again and every
 * module's impls are to be added anew. Modules added since the library loaded stay in the tables;
 * a program that checks several files calls this before each. */
void ms_program_begin(MsCheck *c);

/* Desugars every bundled standard-library module once (inherent impls into methods). */
void ms_program_desugar_bundled(MsCheck *c);

/* Checks the bodies of module `module`, whose text is `text`: desugars its inherent methods, adds
 * the impls of the prelude's modules and of every module it imports (standard or project, through
 * `import_targets`) to the method table, resolves its own, then runs `ms_module_check_bodies_with`.
 * The first call also desugars the bundled modules. False when the module has an inherent error,
 * which the Rust checker reports and stops at: nothing is checked. */
bool ms_program_check_module(MsCheck *c, MsModId module, MsStr text);
/* Makes the bundled module `path` part of the program though no source imports it (the test runner a test build
 * calls), so ms_program_check_bundled checks it. */
void ms_program_reach_bundled(MsCheck *c, const char *path);

/* Checks the bodies, and runs the ownership walk, of every bundled module with source that the
 * program's imports reach, so a whole-program lowering (`ms_lower_program`) has their facts. Call it
 * after every project module is checked, when the method table is complete. Returns how many
 * modules it checked. */
uint32_t ms_program_check_bundled(MsCheck *c);

#endif
