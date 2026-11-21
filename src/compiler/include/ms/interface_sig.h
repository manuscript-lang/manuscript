/* The rule that an interface of a program declares an operation. Port of `check_defaults` in
 * crates/ms-check/src/checker.rs. */
#ifndef MS_INTERFACE_SIG_H
#define MS_INTERFACE_SIG_H

#include "ms/tables.h"

/* Reports each interface without operations in a module outside the standard library; only the
 * library declares a property such as `Data`. */
void ms_module_check_interfaces(MsCheck *c, MsModId module);

#endif
