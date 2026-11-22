/* compiler/check/resolve_internal.h: the type-reference resolver shared by the variables and signature passes.
 *
 * A Resolver turns a written type (MsTypeRef) into a MsTy in the scope of one module: the declaration's type
 * variables, `Self`, the module's own types, its imports, the primitives and the prelude. A name that none of
 * them gives a meaning is reported as `unknown type` when `report` is set (the program's own modules) and
 * resolves to the invalid type either way. */
#ifndef MS_COMPILER_CHECK_RESOLVE_INTERNAL_H
#define MS_COMPILER_CHECK_RESOLVE_INTERNAL_H

#include "compiler/check/program.h"

MS_LIST_DEFINE(MsNameList, ms_name_list, MsName)

typedef struct Resolver {
  MsCheckProgram *program;
  uint32_t module;
  bool report;
  MsNameList names; /* owned: type variable names in scope */
  MsTyList types;   /* owned: their types, in step with `names` */
  MsTy self;        /* the type `Self` denotes, or MS_TY_NONE */
} Resolver;

void resolver_init(Resolver *resolver, MsCheckProgram *program, uint32_t module);
void resolver_free(Resolver *resolver);

/* Brings the variables declared by `symbol` into scope, named by the declaration's type parameters. */
void resolver_enter_symbol(Resolver *resolver, const MsSymbol *symbol);

MsTy resolver_type(Resolver *resolver, const MsTypeRef *type);
void resolver_resolve_alias(Resolver *resolver, MsSymbol *symbol);
/* A written bound: an interface or a type set, else reported and MS_TY_NONE. */
MsTy resolver_bound(Resolver *resolver, const MsTypeRef *bound);

/* One parameter list as checked parameters (a lambda parameter without a type is invalid). */
void resolver_params(Resolver *resolver, MsParams params, MsTyParamList *out);

/* The function type of a parameter list and written result (none means Void). */
MsTy resolver_function(Resolver *resolver, MsParams params, const MsTypeRef *result);

/* The primitive type spelled `name`, interned. */
MsTy resolver_primitive(MsCheckProgram *program, MsBuiltin builtin);

/* The prelude type `name` names (`List`, `Optional`, ...), or 0. */
MsSymbolId resolver_prelude_symbol(const MsCheckProgram *program, MsName name);

/* The nominal type `base` applied to `count` type arguments; `base` itself when there are none. */
MsTy resolver_apply(MsCheckProgram *program, MsTy base, const MsTy *args, size_t count);

#endif
