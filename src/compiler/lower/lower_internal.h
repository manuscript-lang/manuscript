/* compiler/lower/lower_internal.h: the state the lowering files share. */
#ifndef MS_COMPILER_LOWER_LOWER_INTERNAL_H
#define MS_COMPILER_LOWER_LOWER_INTERNAL_H

#include "compiler/lower/lower.h"
#include "compiler/check/properties.h"
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
/* `LowerFn.shared` of a local a lambda changes: it is bound in a slot (SHARED), whose slot has no owner when the
 * value is plain data (PLAIN), or is the maker's, borrowed through a closure's environment (BORROWED). */
enum { LOWER_SHARED = 1, LOWER_SHARED_PLAIN = 2, LOWER_SHARED_BORROWED = 3 };

typedef struct LowerCapture {
  uint8_t kind; /* MS_REF_PARAM or MS_REF_LOCAL */
  uint32_t index;
  MsName name;
  const MsExpr *use; /* the first use, which the maker lowers to read the value */
  MirTy ty;
  bool shared;  /* the lambda changes this local: it takes the address of the maker's slot, which holds a `elem` */
  MirTy elem;
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

/* A record field's default value, built by a function lowered after the one that needs the type. */
typedef struct LowerDefault {
  const MsExpr *expr;
  uint32_t module;
  uint32_t func; /* the reserved MIR function `fn(out, record) Void` */
  MirTy ty;      /* the field's type */
  MirTy record;  /* the record type, whose earlier fields the default may read */
  LowerSubst subst;
  bool lowered;
} LowerDefault;

MS_LIST_DEFINE(LowerDefaultList, lower_default_list, LowerDefault)

/* The equality and hash functions of a record or alternative type that a descriptor describes. */
typedef struct LowerGlue {
  MirTy ty;
  uint32_t eq, hash; /* the reserved MIR functions */
  bool lowered;
} LowerGlue;

MS_LIST_DEFINE(LowerGlueList, lower_glue_list, LowerGlue)

/* The checker type a record or alternative MIR type was made from, for the methods it declares. */
typedef struct LowerSource {
  MirTy mir;
  MsTy checked;
} LowerSource;

MS_LIST_DEFINE(LowerSourceList, lower_source_list, LowerSource)

typedef struct Lower {
  MsCheckProgram *program;
  MirModule *module;
  MsStrBuild *error;
  LowerTyMap types;            /* type (after substitution) -> MIR type */
  MsNames instance_keys;       /* instance key text -> dense id, the index into `instances` */
  LowerInstanceList instances;
  LowerLambdaList lambdas;
  LowerDefaultList defaults;
  LowerGlueList glues;
  LowerSourceList sources;
  MsNames vtable_keys;         /* receiver and interface type text -> dense id, the index into `vtables` */
  MirIdList vtables;           /* the MIR vtable of each key */
  MirIdList files; /* checker module index -> MIR file id, MIR_NONE until first used */
} Lower;

#define lower_fail(cx, ...) (ms_strbuild_printf((cx)->error, __VA_ARGS__), ms_strbuild_append_byte((cx)->error, '\n'), false)

/* ---- instances and the driver (lower_func.c) ---- */

/* The function that builds a record field's default `expr` (written in `module`) in place; its body is lowered
 * later (lower_default.c). */
uint32_t lower_field_default(Lower *cx, uint32_t module, const MsExpr *expr, MirTy ty, MirTy record, const LowerSubst *subst);
bool lower_default_bodies(Lower *cx, bool *progressed);
bool lower_glue_bodies(Lower *cx, bool *progressed);

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
/* The MIR function of the method with a body that operation `name` resolves to on the concrete `receiver`, or
 * MIR_NONE when the receiver type has none (a builtin or derived operation). */
uint32_t lower_operation_method(Lower *cx, MsTy receiver, MsName name);
/* The same for an operation named by text (`to_string`, `clone`). */
uint32_t lower_named_method(Lower *cx, MsTy receiver, const char *operation);
/* The MIR function of the own `equals(other: Self) Bool` (MS_PROPERTY_EQUAL) or `hash() Int` (MS_PROPERTY_HASHABLE) that
 * the concrete `receiver` declares, or MIR_NONE when it declares none or takes its argument by move. */
uint32_t lower_own_method(Lower *cx, MsTy receiver, MsProperty property);
/* The checker type that MIR record or alternative type `ty` was made from, or MS_TY_NONE. */
MsTy lower_source_type(const Lower *cx, MirTy ty);
uint32_t lower_vtable(Lower *cx, const LowerSubst *subst, MsTy receiver, MsTy iface);

/* A closure of type `fn_ty` without captures whose body calls the MIR function `callee` (MIR_NONE on failure). */
uint32_t lower_forwarding_closure(Lower *cx, MirTy fn_ty, uint32_t callee);

/* The MIR file id of checker module `module`. */
uint32_t lower_file(Lower *cx, uint32_t module);

/* ---- types (lower_types.c) ---- */

/* The MIR type of `ty` once `subst` is applied; MIR_VOID after reporting when the type has no MIR form. */
MirTy lower_type(Lower *cx, const LowerSubst *subst, MsTy ty);

/* The source text of `ty` after substitution, as MIR names it (`Box[Int]`). */
void lower_type_text(Lower *cx, const LowerSubst *subst, MsTy ty, MsStrBuild *out);

#endif
