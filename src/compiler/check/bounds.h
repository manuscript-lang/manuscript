/* compiler/check/bounds.h: whether a type argument meets the bounds of its type variable.
 *
 * A variable's bounds are interfaces, standard properties (Equal, Hashable, Clonable, Data), or a type set. A
 * bound may name other variables of the same list (`T: Comparable[U]`); ms_check_bounds_hold_with reads them
 * as their arguments. */
#ifndef MS_COMPILER_CHECK_BOUNDS_H
#define MS_COMPILER_CHECK_BOUNDS_H

#include "compiler/check/properties.h"

/* Appends `resolved`, written as `written`, to the bounds of `variable`, noting a `&` argument (`Iterator[&T]`): the
 * type bound to it must lend, and a record holding it is a look. */
void ms_check_push_bound(MsTyVariable *variable, MsTy resolved, const MsTypeRef *written);

/* The same, reading the bounds with each `vars[i]` replaced by `args[i]` (`count` entries). */
MS_NODISCARD bool ms_check_bounds_hold_with(MsCheckProgram *program, MsTy variable, MsTy arg, const MsTy *vars,
                                            const MsTy *args, size_t count, const char *alternative,
                                            MsString *why);

/* Appends why `ty` does not satisfy `bound`, ending with `alternative` (what to do instead). */
void ms_check_unsatisfied_message(MsCheckProgram *program, MsTy ty, MsTy bound, const char *alternative,
                                  MsStrBuild *out);

#endif
