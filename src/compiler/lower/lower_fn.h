/* compiler/lower/lower_fn.h: the state of the function being lowered, and what its statement, expression and
 * call code share. */
#ifndef MS_COMPILER_LOWER_LOWER_FN_H
#define MS_COMPILER_LOWER_LOWER_FN_H

#include "compiler/lower/lower_internal.h"

/* How the consumer takes an expression's value: it reads it in place, or it takes ownership. */
typedef enum LowerWant { LW_BORROW, LW_MOVE } LowerWant;

enum { LOWER_MAX_SCOPES = 64, LOWER_MAX_LOOPS = 32, LOWER_MAX_OWNED_VARS = 256 };

/* A `var` local that owns its current value: the scope that declared it owns that value where the scope ends. */
typedef struct LowerOwnedVar {
  uint32_t scope;
  MirVar var;
} LowerOwnedVar;

/* Where `break` and `continue` go, and how many scopes were open outside the loop. */
typedef struct LowerLoop {
  MirBlock break_to, continue_to;
  uint32_t depth;
} LowerLoop;

/* A `var` parameter: the callee takes its value out of the caller's slot at entry and puts it back at every return. */
typedef struct LowerVarParam {
  MirVar var;
  MirValue slot;
  MirTy ty;
} LowerVarParam;

enum { LOWER_MAX_VAR_PARAMS = 8, LOWER_MAX_CLOSING_PARAMS = 32 };

typedef struct LowerFn {
  Lower *cx;
  MirBuilder b;
  const MsFacts *facts;
  const MsFunc *func;
  uint32_t module_index;
  uint32_t file; /* the MIR file id of the module */
  LowerSubst subst;
  MirVar *vars;       /* by checker local id */
  MirValue *closing;  /* the slot a closed resource lives in, else MIR_NONE: by local id, then by parameter index */
  bool *closing_var;  /* the same index: the binding is `var`, so every read loads the slot */
  MirTy *closing_types; /* the same index: the type of the value in the slot */
  uint32_t nvars;
  MirVar *param_vars; /* by parameter index */
  MirTy ret;
  uint32_t next_scope;               /* the next scope id to hand out */
  uint32_t open[LOWER_MAX_SCOPES];   /* the scopes open now, outermost first */
  uint32_t nopen;
  LowerOwnedVar owned_vars[LOWER_MAX_OWNED_VARS];
  uint32_t nowned_vars;
  LowerVarParam var_params[LOWER_MAX_VAR_PARAMS];
  uint32_t nvar_params;
  bool failed;
  MirTy hint; /* the type a default expression is wanted as, for an expression the checker left untyped */
  bool decl_void; /* declared to return Void, though the MIR function returns an Int status (the entry) */
  bool terminated;
  uint32_t nloops;
  LowerLoop loops[LOWER_MAX_LOOPS]; /* the loops open now, outermost first */
  const LowerLambda *lambda; /* the lambda whose body this is, or NULL */
  MirVar *cap_vars;           /* a lambda body: the variable holding each capture */
  uint32_t local_count; /* the current block ended in a return: the statements after it are unreachable */
} LowerFn;

#define fn_fail(fn, ...) ((fn)->failed = true, lower_fail((fn)->cx, __VA_ARGS__))

/* ---- scopes (lower_scope.c) ---- */

/* Opens a scope inside the current one and returns its id. */
uint32_t fn_scope_begin(LowerFn *fn);
/* Closes the innermost scope: its owners are dropped or closed where it ends. */
void fn_scope_end(LowerFn *fn);
/* Emits the `scope.end` of every open scope from the innermost down to (not including) depth `keep`, without
 * popping them: the code after it leaves the function or the loop. */
void fn_scope_unwind(LowerFn *fn, uint32_t keep);
/* The innermost open scope. */
uint32_t fn_scope(const LowerFn *fn);
/* Registers `var`, which holds an owned value that is not owned by any scope, with the innermost scope. */
bool fn_scope_own_var(LowerFn *fn, MirVar var);
/* Makes the scope `scope` own `value` (kind 0 drops it). */
void fn_own(LowerFn *fn, uint32_t scope, MirValue value);

/* Emits an instruction; when its result is an owned value the innermost scope owns it. */
MirValue fn_emit(LowerFn *fn, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty);
/* Makes the innermost scope own `result`, the result of the instruction just emitted, when it is owned. */
void fn_own_result(LowerFn *fn, MirValue result);

/* Whether `value` is the owned result of the instruction just emitted, held by the innermost scope. */
bool fn_fresh_owner(LowerFn *fn, MirValue value);

/* ---- resources closed at scope end (lower_close.c) ---- */

/* Whether lowering closes a binding with this closer (NULL for none), of checker type `checked`: a `move fn close`
 * that no use closes by hand, changes in place or splits. */
bool fn_closer_for(LowerFn *fn, const MsCloser *closer, MsTy checked);
/* Binds `local`, of checker type `checked`, to the fresh owned `value` in a slot its scope closes. */
bool fn_bind_closing(LowerFn *fn, uint32_t local, MsTy checked, MirValue value, bool is_var);
/* A read of the `var` resource `ref` names: the slot's current value, or false when it is not one. */
bool fn_closing_read(LowerFn *fn, const MsRef *ref, MirValue *view);
/* `name = value` where `name` is a `var` resource: the value it holds is closed, then `value` takes its place. */
bool fn_closing_assign(LowerFn *fn, const MsRef *ref, MirValue value, bool *done);
/* Binds the `move` parameter `index` of checker type `checked`, whose incoming value `value` the function owns, in a
 * slot its scope closes; `var` is the variable the body reads it through. */
bool fn_own_param(LowerFn *fn, uint32_t index, MsTy checked, MirValue value, MirVar var);
/* A moving read of the closed resource `name` (read as `view`): the slot is given up and its value taken. */
bool fn_closing_move(LowerFn *fn, const MsExpr *name, MirValue view, MirValue *taken);

/* ---- places (lower_stmt.c) ---- */

/* Whether `place` is an owning `var` local or a member path rooted in one. */
/* Whether `place` is an owning variable (or a path in one): a value a `var` call can change in place. */
bool fn_place_owns(LowerFn *fn, const MsExpr *place);
bool fn_place_changeable(LowerFn *fn, const MsExpr *place);
/* The owned value of an owning `var` local or a member or element path, for a change that `fn_put_place` stores back. */
bool fn_take_place(LowerFn *fn, const MsExpr *place, MirValue *out);
/* Stores the owned `value` (held by no scope) into `place`. */
bool fn_put_place(LowerFn *fn, const MsExpr *place, MirValue value);

/* ---- statements, expressions and calls ---- */

bool fn_stmts(LowerFn *fn, MsStmts stmts);
MirValue fn_default_result(LowerFn *fn);
/* The 64 bits of a number literal's spelling (decimal, 0x, 0b, 0o; `_` ignored); false when it has more. */
bool fn_number_bits(MsSpan text, uint64_t *out);
/* Whether `expr` is a text with no interpolation, a static string. */
bool fn_is_text_literal(const MsExpr *expr);
MirValue fn_expr(LowerFn *fn, const MsExpr *expr, LowerWant want);
MirValue fn_call(LowerFn *fn, const MsExpr *expr, LowerWant want);
/* A call of the runtime function `name` (borrowed arguments; a result that needs a drop is fresh). */
MirValue fn_runtime_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret);
/* A map literal: an empty map the entries are added to through `msrt_map_add`. */
MirValue fn_map_literal(LowerFn *fn, const MsExpr *expr);
MirValue fn_map_index(LowerFn *fn, MirValue map, const MsExpr *key, MirTy ty);
/* A call recorded with a bodiless standard operation as its callee. */
MirValue fn_native_call(LowerFn *fn, const MsExpr *expr, const MsCall *call, const MirValue *args, MirTy ret);

/* `left op right` on a BigInt through its runtime function; false when the operands are not a value object. */
bool fn_object_binary(LowerFn *fn, MsBinaryOp op, MirValue left, MirValue right, MirValue *out);

/* A call of the runtime function `name` that returns a Result from a status: the native returns a u8 status and
 * writes the ok payload (and the failure's text) through trailing addresses. False when `name` has no such
 * signature, and nothing was emitted. */
bool fn_status_call(LowerFn *fn, MsName name, const MirValue *args, uint32_t nargs, MirTy ret, MirValue *out);
/* A call of a function the standard library declares without a body: the runtime function `msrt_<name>`. */
MirValue fn_builtin_call(LowerFn *fn, const MsCall *call, const MirValue *args, MirTy ret);

/* The expression's value after the conversion the checker recorded on it (an interface view, ...). */
MirValue fn_convert(LowerFn *fn, const MsExpr *expr, MirValue value);
/* `for x in <list or range>` (lower_for.c) and interpolated text (lower_text.c). */
bool fn_for(LowerFn *fn, const MsStmt *stmt);
MirValue fn_text(LowerFn *fn, const MsExpr *expr);
/* The text of `value` of MIR type `ty` through the type's shape (`msstd_value_text`). */
MirValue fn_value_text(LowerFn *fn, MirValue value, MirTy ty);
/* Unary operators, `try`, and the Result of a failable function (lower_result.c). */
MirValue fn_unary(LowerFn *fn, const MsExpr *expr);
MirValue fn_try(LowerFn *fn, const MsExpr *expr);
/* `value` (MIR_NONE for a Void ok) as the function's Result; other functions' values pass through. */
MirValue fn_result_wrap(LowerFn *fn, MirValue value);
/* Lambdas and calls of function values (lower_closure.c). */
MirValue fn_lambda(LowerFn *fn, const MsExpr *expr);
/* Reserves the closure function of function type `fn_ty` with `count` captures (their types in `captures`). */
uint32_t lower_closure_func(Lower *cx, MirTy fn_ty, const LowerCapture *captures, uint32_t count);
MirValue fn_call_value(LowerFn *fn, const MsExpr *expr, const MsRef *callee);

/* A `var` argument: the place's value moved into a slot whose address is passed, and put back after the call. */
typedef struct VarSlot {
  const MsExpr *place;
  MirValue slot;
  MirTy ty;
} VarSlot;
MirValue fn_var_slot(LowerFn *fn, const MsExpr *place, VarSlot *out);
bool fn_var_slots_back(LowerFn *fn, const VarSlot *slots, uint32_t count);
MsSymbolId fn_symbol_at(const Lower *cx, MsNodeRef decl);
const MsMethodEntry *fn_method_entry(const Lower *cx, uint32_t module, MsNode node);
MirValue fn_function_value(LowerFn *fn, const MsRef *ref, MirTy fn_ty);
MirValue fn_name_ref(LowerFn *fn, const MsExpr *expr, const MsRef *ref);
const MsCall *fn_find_call(const MsFacts *facts, MsNode node);
/* A parameter name inside a lambda body that is one of its captures: its value in `out`. */
bool fn_lambda_name(LowerFn *fn, const MsExpr *expr, const MsRef *ref, MirValue *out);
/* Lowers the bodies of the lambdas made so far; `*progressed` is set when it lowered any. */
bool lower_lambda_bodies(Lower *cx, bool *progressed);
/* A list literal (lower_list.c). */
MirValue fn_index(LowerFn *fn, const MsExpr *expr, LowerWant want);
MirValue fn_list(LowerFn *fn, const MsExpr *expr);
/* `if x := value:` (lower_iflet.c): whether the value holds a payload, and binding the payload. */
MirValue fn_iflet_test(LowerFn *fn, MirValue value);
bool fn_iflet_bind(LowerFn *fn, const MsPattern *pattern, MirValue value);
/* `match` over an alternative (lower_match.c). */
MirValue fn_match(LowerFn *fn, const MsExpr *expr);

/* The value of a variable, and a new one for local `local` of the function. */
MirVar fn_local(LowerFn *fn, uint32_t local, MirTy ty);
bool fn_cond_branch(LowerFn *fn, const MsExpr *cond, MirBlock then, MirBlock otherwise);

/* The MIR type of the checker's type `ty` in this function (its variables replaced). */
static inline MirTy fn_type(LowerFn *fn, MsTy ty) {
  return lower_type(fn->cx, &fn->subst, ty);
}

static inline MirLoc fn_loc(const LowerFn *fn, MsPos pos) {
  return (MirLoc){fn->file, pos.line, pos.column, 0};
}

#endif
