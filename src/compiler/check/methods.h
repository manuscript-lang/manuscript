/* compiler/check/methods.h: the method table and what a type implements.
 *
 * A type's operations are its own methods (`fn Type.name(...)`); no declaration names the relationship to an
 * interface, a type satisfies an interface when its methods supply every operation with the interface's exact
 * signature (implements.c). ms_check_methods registers each module's methods; the table is read by the call
 * and conformance checks through ms_check_find_method and ms_check_implements.
 *
 * Ownership: the program owns the table and the variable lists of its entries. A match borrows from the table. */
#ifndef MS_COMPILER_CHECK_METHODS_H
#define MS_COMPILER_CHECK_METHODS_H

#include "base/strbuild.h"
#include "compiler/check/types.h"
#include "compiler/syntax/ast.h"

typedef struct MsCheckProgram MsCheckProgram;

/* One method of a type. `variables` are the receiver form's (the first `shared`) and then the method's own. */
typedef struct MsMethodEntry {
  MsName name;
  MsTy receiver; /* `Box[T]`, `Box[Int]`, `Point` */
  MsTy ty;       /* the signature, `Self` read as the receiver */
  MsTyList variables; /* owned */
  uint32_t shared;
  uint32_t module;
  const MsMethod *source;
} MsMethodEntry;

MS_LIST_DEFINE(MsMethodList, ms_method_list, MsMethodEntry)

/* A method found for a receiver: an implemented method, or an operation of an interface. */
typedef struct MsMethodMatch {
  MsTy ty;                      /* the signature with the receiver's arguments bound */
  MsTy contract;                /* the interface of an operation, else MS_TY_NONE */
  const MsMethodEntry *entry;   /* the method, NULL for an interface operation */
  const MsOperation *operation; /* the operation, NULL for a method */
  bool native;                  /* the compiler or runtime provides it: `to_string`, a primitive's operation */
} MsMethodMatch;

MS_LIST_DEFINE(MsMethodMatchList, ms_method_match_list, MsMethodMatch)

/* Registers the methods `module` declares, reporting the faulty ones. Runs after ms_check_signatures. */
void ms_check_methods(MsCheckProgram *program, uint32_t module);
void ms_methods_free(MsMethodList *methods);

/* Appends the methods named `name` that apply to `receiver` to `out`: its own methods whose receiver form
 * matches, the operation of an interface-typed receiver, and the operations of a type variable's bounds. */
void ms_check_find_method(MsCheckProgram *program, MsTy receiver, MsName name, MsMethodMatchList *out);

/* Appends the operations `receiver` has without declaring them (native.c). */
void ms_check_find_native(MsCheckProgram *program, MsTy receiver, MsName name, MsMethodMatchList *out);

/* Appends the names of a primitive's built-in operations (native.c). */
bool ms_check_standard_operation(const MsCheckProgram *program, MsName name);
void ms_check_native_names(MsCheckProgram *program, MsTy receiver, MsSpanList *out);

/* Matches `pattern` against `actual`, binding each of the `count` variables `vars[i]` to `bound[i]` (a slot
 * that holds MS_TY_NONE is free). A function type's parameter modes must agree. */
MS_NODISCARD bool ms_check_unify(const MsTyTable *types, MsTy pattern, MsTy actual, const MsTy *vars, size_t count,
                                 MsTy *bound);

/* Whether `receiver` satisfies `contract`: it is the contract, a type variable bounded by it, a member of a
 * type set, a built-in comparable, or supplies every operation by its own methods. */
MS_NODISCARD bool ms_check_implements(MsCheckProgram *program, MsTy receiver, MsTy contract);

/* Whether `receiver`'s own methods supply every operation of `contract`. When one is missing or differs, appends
 * why (the first such operation) to `why` and returns false; returns false appending nothing when shape does not
 * apply (a variable receiver, a contract with no operations). */
MS_NODISCARD bool ms_check_shape_gap(MsCheckProgram *program, MsTy receiver, MsTy contract, MsStrBuild *why);

/* Whether every operation of `contract` that `receiver` declares matches the interface; an operation the receiver
 * leaves out is not a gap (an interface whose operations all default, such as TestHooks). */
MS_NODISCARD bool ms_check_shape_optional(MsCheckProgram *program, MsTy receiver, MsTy contract);

/* The operation `name` of interface `contract`, or NULL. */
const MsOperation *ms_check_find_operation(const MsCheckProgram *program, MsTy contract, MsName name);

/* The operation's signature as called on a value of type `implementor`: `Self` is the implementor and the
 * interface's type arguments are bound. */
const MsMethod *ms_check_operation_declaration(const MsCheckProgram *program, MsTy contract, const MsOperation *operation);
MsTy ms_check_operation_type(MsCheckProgram *program, MsTy contract, const MsOperation *operation, MsTy implementor);

/* `ty` with each occurrence of `from` replaced by `to` (`Self` read as the implementing type). */
MsTy ms_check_replace_type(MsTyTable *types, MsTy ty, MsTy from, MsTy to);

#endif
