/* compiler/lower/lower_internal.h: the state the lowering files share. */
#ifndef MS_COMPILER_LOWER_LOWER_INTERNAL_H
#define MS_COMPILER_LOWER_LOWER_INTERNAL_H

#include "compiler/lower/lower.h"
#include "compiler/mir/mir_builder.h"

MS_MAP_DEFINE(LowerTyMap, lower_ty_map, uint32_t, uint32_t, ms_hash_u32_key, ms_equal_u32_key)

/* One function to lower: a declaration with the type arguments of one use, and the MIR function reserved
 * for it so calls can name it before its body exists. */
/* A function that can be lowered: a module-level function or a method, in the module that declares it. */
typedef struct LowerTarget {
  uint32_t module;
  uint32_t node;                 /* the declaration or method node id: the key, and the index of its locals */
  const MsFunc *func;
  MsName name;
  MsTy ty;                       /* the signature, receiver first for a method */
  MsTypeParams outer;            /* the type parameters of the enclosing `impl`, before the function's own */
  const MsTy *variables;         /* when not NULL: the type variables, in order, as the method table holds them */
  uint32_t nvariables;
  MsTy receiver;                 /* a method's receiver type (the first parameter), else MS_TY_NONE */
  uint8_t receiver_flags;        /* MS_PARAM_VAR for a mutating method, MS_PARAM_MOVE for a consuming one */
  bool entry;                    /* the program's `main`: it returns an Int status even when declared Void */
} LowerTarget;

typedef struct LowerInstance {
  LowerTarget target;
  const MsTy *args; /* in the program arena */
  uint32_t nargs;
  uint32_t func;    /* the reserved MIR function */
  bool lowered;
} LowerInstance;

MS_LIST_DEFINE(LowerInstanceList, lower_instance_list, LowerInstance)

/* The type variables being replaced while one instance is lowered, and what replaces them. */
typedef struct LowerSubst {
  const MsTy *vars;
  const MsTy *args;
  size_t count;
} LowerSubst;

/* A value a closure takes from the function that makes it: a parameter or a local, by its index there and the
 * name written at its first use (parameters of nested functions share indices). */
typedef struct LowerCapture {
  uint8_t kind; /* MS_REF_PARAM or MS_REF_LOCAL */
  uint32_t index;
  MsName name;
  const MsExpr *use; /* the first use, which the maker lowers to read the value */
  MirTy ty;
} LowerCapture;

/* A lambda whose body is lowered after the function that makes it. */
typedef struct LowerLambda {
  const MsExpr *expr;
  uint32_t module;
  uint32_t func; /* the reserved MIR closure function */
  uint32_t nvars; /* the locals of the function that holds the lambda; its body shares their numbering */
  LowerSubst subst;
  LowerCapture *captures;
  uint32_t ncaptures;
  bool lowered;
} LowerLambda;

MS_LIST_DEFINE(LowerLambdaList, lower_lambda_list, LowerLambda)

typedef struct Lower {
  MsCheckProgram *program;
  MirModule *module;
  MsStrBuild *error;
  LowerTyMap types;            /* type (after substitution) -> MIR type */
  MsNames instance_keys;       /* instance key text -> dense id, the index into `instances` */
  LowerInstanceList instances;
  LowerLambdaList lambdas;
  MsNames vtable_keys;         /* receiver and interface type text -> dense id, the index into `vtables` */
  MirIdList vtables;           /* the MIR vtable of each key */
  MirIdList files; /* checker module index -> MIR file id, MIR_NONE until first used */
} Lower;

#define lower_fail(cx, ...) (ms_strbuild_printf((cx)->error, __VA_ARGS__), ms_strbuild_append_byte((cx)->error, '\n'), false)

/* ---- instances and the driver (lower_func.c) ---- */

/* The driver steps (lower_func.c): set up, lower every function reached so far (and their lambdas), tear down. */
void lower_init(Lower *cx, MsCheckProgram *program, MirModule *module, MsStrBuild *error);
bool lower_pending(Lower *cx);
void lower_release(Lower *cx);
/* The process entry: `main` wrapped to return the exit status (lower_entry.c). */
uint32_t lower_entry_status(Lower *cx, uint32_t main_func);
/* The target of a module-level function symbol. */
LowerTarget lower_symbol_target(const Lower *cx, MsSymbolId symbol);

/* The MIR function for `target` instantiated with `args` (type arguments of the use, in the caller's
 * terms; `caller` replaces the caller's variables in them). It is reserved at once and its body lowered later. */
uint32_t lower_instance(Lower *cx, const LowerTarget *target, const MsTy *args, uint32_t nargs, const LowerSubst *caller);

/* The vtable that shows `receiver` as the interface `iface`, made on first use with every operation's method
 * instantiated; MIR_NONE after reporting when a method is missing. */
uint32_t lower_vtable(Lower *cx, const LowerSubst *subst, MsTy receiver, MsTy iface);

/* The MIR file id of checker module `module`. */
uint32_t lower_file(Lower *cx, uint32_t module);

/* ---- types (lower_types.c) ---- */

/* The MIR type of `ty` once `subst` is applied; MIR_VOID after reporting when the type has no MIR form. */
MirTy lower_type(Lower *cx, const LowerSubst *subst, MsTy ty);

/* The source text of `ty` after substitution, as MIR names it (`Box[Int]`). */
void lower_type_text(Lower *cx, const LowerSubst *subst, MsTy ty, MsStrBuild *out);

#endif
