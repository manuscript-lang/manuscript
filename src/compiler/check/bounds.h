/* compiler/check/bounds.h: whether a type argument meets the bounds of its type variable.
 *
 * A variable's bounds are interfaces, standard properties (Equal, Hashable, Clonable, Data), or a type set. A
 * bound may name other variables of the same list (`T: Comparable[U]`); ms_check_bounds_hold_with reads them
 * as their arguments. */
#ifndef MS_COMPILER_CHECK_BOUNDS_H
#define MS_COMPILER_CHECK_BOUNDS_H

#include "compiler/check/properties.h"

/* Whether `arg` meets every bound of `variable`. When one fails and `why` is not NULL, it receives the first
 * failure's diagnostic text (owned by the caller). */
MS_NODISCARD bool ms_check_bounds_hold(MsCheckProgram *program, MsTy variable, MsTy arg, MsString *why);

/* The same, reading the bounds with each `vars[i]` replaced by `args[i]` (`count` entries). */
MS_NODISCARD bool ms_check_bounds_hold_with(MsCheckProgram *program, MsTy variable, MsTy arg, const MsTy *vars,
                                            const MsTy *args, size_t count, MsString *why);

/* Appends why `ty` does not satisfy `bound`, ending with `alternative` (what to do instead). */
void ms_check_unsatisfied_message(MsCheckProgram *program, MsTy ty, MsTy bound, const char *alternative,
                                  MsStrBuild *out);

#endif
