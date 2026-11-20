/* Type algebra that reads only the type table: the pure helpers of crates/ms-check/src/contracts.rs.
 * Interface satisfaction and implementation checks build on them once the method table exists. */
#ifndef MS_TY_ALGEBRA_H
#define MS_TY_ALGEBRA_H

#include "ms/tables.h"

/* Whether `ty` mentions a type variable anywhere, through arguments, parameters and results. A
 * type built by repeated doubling (`Pair[T, T]` nested n times) is a DAG of n nodes but a tree of
 * 2^n paths, so every node is visited once. `scratch` holds the visit marks. */
bool ms_ty_has_variable(const MsTyTable *t, MsArena *scratch, MsTy ty);

/* Whether two implementations could apply to one receiver and contract: `a` with `x` and `b` with
 * `y` unify, binding only the variables `vars`. */
bool ms_ty_overlap(const MsTyTable *t, MsArena *scratch, MsTy a, MsTy b, MsTy x, MsTy y,
                   const MsTy *vars, uint32_t nvars);

/* Whether `ty` is a member of the type set `set`, or a type parameter bounded by a set whose
 * members are all members of it. */
bool ms_type_set_admits(const MsCheck *c, MsTy ty, MsTy set);

/* Standard types whose native compare operation satisfies Comparable without an impl. */
bool ms_builtin_comparable(MsBuiltin builtin);

/* A structural property the language derives from a type's shape. */
typedef enum MsProperty { MS_PROP_EQUAL, MS_PROP_HASHABLE, MS_PROP_CLONABLE, MS_PROP_DATA } MsProperty;

/* The property a standard contract names, if it is one. */
bool ms_property_of(MsBuiltin contract, MsProperty *out);
MsBuiltin ms_property_builtin(MsProperty property);
const char *ms_property_name(MsProperty property);

#endif
