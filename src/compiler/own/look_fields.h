/* compiler/own/look_fields.h: record fields written `&T`, which look at a value owned elsewhere.
 *
 * A constructor argument for such a field is not handed over: the record is tied to it, so the value stays with its
 * owner and the record's result borrows it (the same shape as a `hold` argument). The checker erases the `&`; this
 * reads it from the written field type. */
#ifndef MS_COMPILER_OWN_LOOK_FIELDS_H
#define MS_COMPILER_OWN_LOOK_FIELDS_H

#include <stdbool.h>

#include "compiler/check/program.h"

/* Whether `call` builds a record whose field `index` (declaration order) is written `&T`. */
bool ms_own_look_field(const MsCheckProgram *program, const MsCall *call, uint32_t index);

#endif
