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

/* Whether `call` builds a record whose field `index` holds a record that looks at something: the field is moved in,
 * and the result is still tied to what the inner record looks at. */
bool ms_own_look_carrier(const MsCheckProgram *program, const MsCall *call, uint32_t index);

/* Whether `member` (`record.field`) names a field written `&T`: it looks at a value the record does not own. */
bool ms_own_look_member(const MsCheckProgram *program, const MsFacts *facts, const MsExpr *member);

/* Whether a record type has a `&` field, so a value of it looks at what its fields were built from. */
bool ms_own_look_record(const MsCheckProgram *program, MsTy ty);

#endif
