/* Whether a type meets an interface bound. The Rust checker's `implements` and `satisfies`,
 * answering three ways: a type the C tables do not model yet is UNKNOWN, never a guess, so a
 * caller that needs the answer leaves the function to the Rust checker. */
#ifndef MS_IMPLEMENTS_H
#define MS_IMPLEMENTS_H

#include "ms/methods.h"

typedef enum MsFit {
    MS_FIT_YES,
    MS_FIT_NO,
    MS_FIT_UNKNOWN,
} MsFit;

/* Whether `receiver` meets `contract`: the same type, a type variable bounded by it, a type-set
 * member, a primitive for a built-in property, an `impl` that names the interface, or a type whose
 * own methods supply each operation with the exact signature. Generic impls, structural
 * properties of composite types and generic interfaces are UNKNOWN. */
MsFit ms_implements(MsCheck *c, const MsMethodTable *table, MsTy receiver, MsTy contract);
/* Whether `==` accepts two values of `ty`: the Equal property, derived from its parts and a variable's bounds. */
MsFit ms_implements_equal(MsCheck *c, const MsMethodTable *table, MsTy ty);

#endif
