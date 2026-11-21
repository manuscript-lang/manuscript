/* The rule that optional parameters and fields come last. Port of `check_optionals_last` in
 * crates/ms-check/src/checker.rs. */
#ifndef MS_PARAM_ORDER_H
#define MS_PARAM_ORDER_H

#include "ms/tables.h"

/* Reports each required parameter of a function or method, and each required field of a type, that
 * follows one with a default. A module of the standard library is exempt. */
void ms_module_check_param_order(MsCheck *c, MsModId module);

#endif
