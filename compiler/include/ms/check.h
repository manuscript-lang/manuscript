/* Name resolution of a module's top level: what its code can name before any body is read.
 *
 * `ms_module_declare` fills `MsModuleRow.names` with the primitives, the prelude, the module's
 * imports and its own declarations, and appends to `MsModuleRow.diags` what is wrong with them
 * (a declaration that reuses a prelude name, two imports of one name, an import the standard
 * library cannot satisfy). The Rust checker's `begin_module`, `import_symbols` and
 * `declare_symbols`. */
#ifndef MS_CHECK_H
#define MS_CHECK_H

#include "ms/tables.h"

/* The row of the module with this path, or MS_NONE. */
MsModId ms_module_find(const MsCheck *c, MsSym path);

/* Declares the module's names once; later calls do nothing. Imports of `@std/` modules declare
 * the source module they read first. Imports of other modules are not resolved yet and leave no
 * name behind. */
void ms_module_declare(MsCheck *c, MsModId module);

#endif
