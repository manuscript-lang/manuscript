/* The visibility rule of exported declarations: a public signature names no private type. Port of
 * `public` and the export branches of `declaration_checks` in crates/ms-check/src/contracts.rs. */
#ifndef MS_PUBLIC_SIG_H
#define MS_PUBLIC_SIG_H

#include "ms/methods.h"

/* Reports `public signature exposes private type T` for every exported declaration of `module`
 * (its signature, fields, cases, operations, type-variable bounds and defaults) that names a type
 * the module declares without `export`. Call after the module's types and operations are resolved. */
void ms_module_check_public(MsCheck *c, MsModId module, const MsMethodTable *table);

#endif
