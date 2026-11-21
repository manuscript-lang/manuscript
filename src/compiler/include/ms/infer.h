/* Inferring the type arguments of a generic declaration: match the declared types, which mention
 * its type variables, against the types of the values supplied, then fill what is left from the
 * variables' defaults. The counterpart of the Rust checker's `specialize` and `infer_arguments`
 * without their diagnostics: this reports what happened and the caller words the error.
 *
 * Types are interned, so "the same type" is an integer compare, and the variables of one
 * declaration are a short array: a binding is a slot of `bound`, indexed like `vars`. */
#ifndef MS_INFER_H
#define MS_INFER_H

#include "ms/tables.h"

typedef struct MsInfer {
    MsCheck *c;
    MsArena *arena;
    const MsTy *vars; /* borrowed: the declaration's type variables, in declaration order */
    uint32_t nvars;
    MsTy *bound;      /* by variable: its argument, or MS_TY_NONE while unknown */
} MsInfer;

typedef enum MsMatch {
    MS_MATCH_OK,       /* the actual type fits; variables it met are bound */
    MS_MATCH_SHAPE,    /* a different type constructor, arity or parameter shape */
    MS_MATCH_CONFLICT, /* a variable would need two different types */
} MsMatch;

void ms_infer_init(MsInfer *in, MsCheck *c, MsArena *arena, const MsTy *vars, uint32_t nvars);

/* Takes explicit type arguments (`f[Int, String]`) for the first variables; false when there are
 * more arguments than variables. An argument of kind invalid binds nothing. */
MS_NODISCARD bool ms_infer_give(MsInfer *in, const MsTy *args, uint32_t count);

/* Matches `pattern` (which may mention the variables) against `actual` (which does not). A failed
 * match may leave the variables it met before the mismatch bound. Types of kind invalid match
 * anything: an earlier diagnostic already explained them. */
MS_NODISCARD MsMatch ms_infer_match(MsInfer *in, MsTy pattern, MsTy actual);

/* Gives every unbound variable its default, with earlier variables substituted into it. Returns
 * how many variables remain without a type; `*first` is the first of them. */
uint32_t ms_infer_defaults(MsInfer *in, uint32_t *first);

/* `ty` with the bound variables replaced; unbound ones stay. */
MsTy ms_infer_apply(MsInfer *in, MsTy ty);

#endif
