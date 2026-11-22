/* compiler/check/body.h: checking the bodies of functions, methods, tests and constants.
 *
 * A Body holds what one walk over a function needs: the module's facts, the locals in scope (innermost last),
 * the type variables in scope, the function's result type and the dense local counter. An expression is
 * inferred with body_expr, which records the expression's type in the facts and returns it; MS_TY_NONE reads
 * as an invalid type (an error already reported, or one that later passes report). An expected type guides
 * literals, lambdas and generic calls; MS_TY_NONE means none.
 *
 * Who writes what: bodies.c walks declarations and statements; exprs.c infers names, members, applications,
 * lists and lambdas; calls.c types calls; exprs_ops.c types literals, text and operators. Each file adds its
 * expression kinds to the dispatch in exprs.c through the functions declared here. */
#ifndef MS_COMPILER_CHECK_BODY_H
#define MS_COMPILER_CHECK_BODY_H

#include "compiler/check/facts_build.h"
#include "compiler/check/resolve_internal.h"

typedef struct MsLocal {
  MsName name;
  MsTy ty;
  MsRefKind kind; /* MS_REF_LOCAL or MS_REF_PARAM */
  uint32_t id;    /* the dense local id, or the parameter's index */
  bool is_var;
} MsLocal;

MS_LIST_DEFINE(MsLocalList, ms_local_list, MsLocal)

typedef struct Body {
  MsCheckProgram *program;
  uint32_t module;
  MsFacts *facts;
  Resolver resolver;  /* the type variables and `Self` in scope */
  MsLocalList locals; /* owned */
  uint32_t next_local;
  MsTy result;  /* the enclosing function's result type; MS_TY_NONE inside no function */
  MsTy self_ty; /* the receiver type in a method, else MS_TY_NONE */
} Body;

/* ---- bodies.c ---- */

/* Types every function, method, test and constant of `module`; fills its facts. */
void ms_check_bodies(MsCheckProgram *program, uint32_t module);

void body_block(Body *body, MsStmts stmts); /* a nested scope */
size_t body_scope_mark(const Body *body);
void body_scope_reset(Body *body, size_t mark);
/* Declares a local or parameter in the current scope. */
MsLocal *body_declare(Body *body, MsName name, MsTy ty, MsRefKind kind, bool is_var);
const MsLocal *body_find_local(const Body *body, MsName name);

/* ---- facts recording ---- */

void body_set_type(Body *body, MsNode node, MsTy ty);
void body_set_ref(Body *body, MsNode node, MsRef ref);

/* The primitive type `builtin`. */
MsTy body_primitive(Body *body, MsBuiltin builtin);

/* ---- exprs.c ---- */

MsTy body_expr(Body *body, const MsExpr *expr, MsTy expected);
/* The type of a standard prelude or imported function, constant or type, when `name` denotes one. */
const MsSymbol *body_find_symbol(const Body *body, MsName name);

/* ---- calls.c ---- */

MsTy body_call(Body *body, const MsExpr *expr, MsTy expected);

/* ---- exprs_ops.c ---- */

/* Literals (number, bool, void, text) and the unary and binary operators. */
MsTy body_literal(Body *body, const MsExpr *expr, MsTy expected);
MsTy body_unary(Body *body, const MsExpr *expr, MsTy expected);
MsTy body_binary(Body *body, const MsExpr *expr, MsTy expected);

#endif
