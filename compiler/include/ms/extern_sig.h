/* The rules for a program's own `extern fn` and `extern type`: what may cross the native boundary
 * of ms_abi.h. Port of `check_extern_signature` and `declare_extern_type` in
 * crates/ms-check/src/checker.rs. */
#ifndef MS_EXTERN_SIG_H
#define MS_EXTERN_SIG_H

#include "ms/tables.h"

/* Reports the signature of every `extern fn` the module declares and every generic `extern type`.
 * A bundled module is exempt: the runtime defines a convention for any type it crosses.
 * Call after the module's types are resolved. */
void ms_module_check_externs(MsCheck *c, MsModId module);

#endif
