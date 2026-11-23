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
  bool written_fn; /* declared with a written function type (`f: fn(Int) Int`): its parameters have no labels */
  const MsParams *fn_params; /* the parameters of the lambda or method it was bound to: their names and defaults */
  uint32_t fn_module;       /* the module that declares fn_params */
  const MsParams *fn_names; /* the parameter names of a native method it was bound to, which has no source */
  MsNode site; /* the node that binds it: a reference to the local names it as its declaration */
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
  MsSpan source;  /* the module's text, for repairing edits; empty for a bundled module */
  bool quiet;      /* type without reporting (constant initializers have their own diagnostics) */
  const MsExpr *statement_match; /* the match being checked as a statement */
  bool saw_return; /* a return statement appeared in the current lambda body */
  MsTy hint;     /* a lambda's expected result that still names open variables: guides inference, not enforced */
  MsTy fixture_ty; /* the type `make_fixture` returns, or MS_TY_NONE: tests of the module see it as `fixture` */
  MsTy returned; /* the first returned value's type while the result is still unknown (lambdas) */
} Body;

/* ---- test_fixture.c ---- */

/* Checks the module's `make_fixture`, and sets `body->fixture_ty`. */
void ms_check_test_fixture(Body *body);

/* ---- bodies.c ---- */

/* Types every function, method, test and constant of `module`; fills its facts. */
void ms_check_bodies(MsCheckProgram *program, uint32_t module, MsSpan source);

void body_block(Body *body, MsStmts stmts); /* a nested scope */
size_t body_scope_mark(const Body *body);
void body_scope_reset(Body *body, size_t mark);
/* Declares a local or parameter in the current scope. */
/* Declares a local; `pos` is where it is written, kept in the program's binding table for `ms inspect`. */
MsLocal *body_declare(Body *body, MsName name, MsTy ty, MsRefKind kind, bool is_var, MsNode site, MsPos pos);

/* The reference a use of `local` records. */
MsRef body_local_ref(const Body *body, const MsLocal *local);
const MsLocal *body_find_local(const Body *body, MsName name);

/* ---- facts recording ---- */

void body_set_type(Body *body, MsNode node, MsTy ty);
void body_set_ref(Body *body, MsNode node, MsRef ref);

/* The primitive type `builtin`. */
MsTy body_primitive(Body *body, MsBuiltin builtin);

/* ---- exprs.c ---- */

MsTy body_expr(Body *body, const MsExpr *expr, MsTy expected);

/* Whether the body's module reports diagnostics: the program's own modules, and the bundled standard modules when
 * the program asks for them to be checked too. */
static inline bool body_reports(const Body *body) {
  return body->module < body->program->user_modules || body->program->check_std;
}
/* The type of a standard prelude or imported function, constant or type, when `name` denotes one. */
const MsSymbol *body_find_symbol(const Body *body, MsName name);

/* The definition of a nominal type, or NULL for any other type. */
const MsDef *body_def(const Body *body, MsTy ty);
/* The record field `name` of `receiver`: its type under the receiver's arguments and its index. */
bool body_field(Body *body, MsTy receiver, MsName name, MsTy *ty, uint32_t *index);
/* The case `name` of the enum `owner`, or NULL. */
const MsTyCase *body_case_of(Body *body, MsTy owner, MsName name, uint32_t *index);
/* A visible enum that has a case `name`; `expected` picks the instance when it is that enum. Two visible enums with the case are reported at `at` (when given), and none is found. */
bool body_find_case(Body *body, MsName name, MsTy expected, const MsPos *at, MsTy *owner, uint32_t *index);
/* The reference a use of `symbol` records. */
/* The reference a found method or operation gives its call: a native when the compiler or runtime provides it. */
MsRef body_method_ref(const MsMethodMatch *match, MsTy receiver);
/* The type of a function named as a value: its omittable parameters stay omittable. */
const MsParams *body_function_names(Body *body, const MsExpr *value, MsTy ty);
const MsParams *body_function_params(Body *body, const MsExpr *value, MsTy ty, uint32_t *module);
/* Whether `actual` is `expected` except that it only reads parameters `expected` may change or take. */
bool body_reads_where_var_expected(const MsTyTable *types, MsTy actual, MsTy expected);
MsTy body_lifted_function(Body *body, const MsExpr *value, MsTy ty);
/* The declared parameters of the lambda, function or method `value` names, or NULL; `module` is where they were written. */
MsRef body_symbol_ref(const Body *body, const MsSymbol *symbol);
/* A prelude type (`List`, `Map`, `Optional`, ...) applied to `count` arguments. */
MsTy body_std_type(Body *body, const char *name, const MsTy *args, size_t count);

/* ---- mismatch.c ---- */

/* Types `expr` against `expected` and reports "expected X, found Y (in <context>)" when it does not fit; an
 * empty `context` names none. Returns the expression's own type. */
bool body_expr_is_atomic(const MsExpr *expr);
/* Whether `ty` is the type of a bare `none` with no target, and the report that it cannot be inferred. */
bool body_is_none_type(const Body *body, MsTy ty);
void body_report_uninferred_none(Body *body, MsPos pos);
MsTy body_expect(Body *body, const MsExpr *expr, MsTy expected, MsSpan context);
/* The check alone, for an expression typed by the caller. */
void body_check_assignable(Body *body, const MsExpr *expr, MsTy actual, MsTy expected, MsSpan context);

/* ---- match.c ---- */

MsTy body_match(Body *body, const MsExpr *expr, MsTy expected);

/* Whether `ty` names a type variable the enclosing body does not own: an open variable of a call being inferred. */
bool body_has_foreign_variable(const Body *body, MsTy ty);

/* ---- calls.c ---- */

MsTy body_call(Body *body, const MsExpr *expr, MsTy expected);

/* ---- conversions.c ---- */

/* Records the implicit conversion (interface view, optional wrap, function value) an expression of type `actual`
 * needs where `expected` is wanted; nothing when none applies or the types already agree. */
void body_convert(Body *body, const MsExpr *expr, MsTy actual, MsTy expected);

/* ---- exprs_ops.c ---- */

/* Literals (number, bool, void, text) and the unary and binary operators. */
void body_report_decimal_literals(Body *body, const MsExpr *expr);
MsTy body_literal(Body *body, const MsExpr *expr, MsTy expected);
MsTy body_unary(Body *body, const MsExpr *expr, MsTy expected);
MsTy body_binary(Body *body, const MsExpr *expr, MsTy expected);

/* bodies.c: the type of a module constant, computed once. */
MsTy body_constant_type(const Body *body, const MsSymbol *symbol);

/* ---- exprs_mismatch.c ---- */

/* Reports binary operands that cannot share a type (`Int + String`, `Int + Int?`); false when they can. */
/* Whether `ty` is unknown or holds an invalid type, to depth `depth` (mismatch.c). */
bool holds_invalid(const MsTyTable *types, MsTy ty, int depth);

/* members.c: a member the receiver does not have. */
bool body_report_type_member(Body *body, MsPos pos, MsTy owner, MsName name, bool call);
void body_report_unknown_member(Body *body, const MsExpr *member, MsTy receiver);

/* externs.c: the signature of a user `extern fn`. */
void body_check_extern(Body *body, const MsDecl *decl, MsTy fn_ty);

/* operands.c: operands that cannot work whatever their values. */
void body_check_not(Body *body, const MsExpr *expr, MsTy operand);
void body_check_literal_range(Body *body, const MsExpr *number, bool negated, MsTy ty);
/* An Int literal must fit a signed 64-bit integer (a negated one may reach the minimum): a larger one is a BigInt. */
void body_check_int64_literal(Body *body, const MsExpr *number, bool negated);
/* A float literal must be finite in its type: binary32 when `ty` is Float32, else binary64. */
void body_check_float_literal(Body *body, const MsExpr *number, MsTy ty);
void body_check_try(Body *body, const MsExpr *expr, MsTy operand);
/* Reports `what` when `ty` is an opaque type declared in another module; true when it did. */
bool body_opaque_denied(Body *body, MsPos pos, MsTy ty, MsSpan what);
void body_check_call_statement(Body *body, const MsStmt *stmt, MsTy value);
void body_check_logical(Body *body, const MsExpr *expr, MsTy left, MsTy right);
/* A constant index outside a list literal always faults. */
void body_check_constant_index(Body *body, const MsExpr *expr, const MsExpr *list, const MsExpr *index);
void body_check_constant_arithmetic(Body *body, const MsExpr *expr, MsTy ty);
bool body_report_operand_mismatch(Body *body, const MsExpr *expr, MsTy left, MsTy right);

#endif
