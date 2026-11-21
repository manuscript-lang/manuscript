/* compiler/lower/lower_fn.h: the state of the function being lowered, and what its statement, expression and
 * call code share. */
#ifndef MS_COMPILER_LOWER_LOWER_FN_H
#define MS_COMPILER_LOWER_LOWER_FN_H

#include "compiler/lower/lower_internal.h"

/* How the consumer takes an expression's value: it reads it in place, or it takes ownership. */
typedef enum LowerWant { LW_BORROW, LW_MOVE } LowerWant;

enum { LOWER_MAX_SCOPES = 64, LOWER_MAX_LOOPS = 32 };

/* Where `break` and `continue` go, and how many scopes were open outside the loop. */
typedef struct LowerLoop {
  MirBlock break_to, continue_to;
  uint32_t depth;
} LowerLoop;

typedef struct LowerFn {
  Lower *cx;
  MirBuilder b;
  const MsFacts *facts;
  const MsDecl *decl;
  uint32_t module_index;
  uint32_t file; /* the MIR file id of the module */
  LowerSubst subst;
  MirVar *vars;       /* by checker local id */
  uint32_t nvars;
  MirVar *param_vars; /* by parameter index */
  MirTy ret;
  uint32_t next_scope;               /* the next scope id to hand out */
  uint32_t open[LOWER_MAX_SCOPES];   /* the scopes open now, outermost first */
  uint32_t nopen;
  bool failed;
  bool terminated;
  uint32_t nloops;
  LowerLoop loops[LOWER_MAX_LOOPS]; /* the loops open now, outermost first */
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
/* Makes the scope `scope` own `value` (kind 0 drops it). */
void fn_own(LowerFn *fn, uint32_t scope, MirValue value);

/* Emits an instruction; when its result is an owned value the innermost scope owns it. */
MirValue fn_emit(LowerFn *fn, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty);
/* Makes the innermost scope own `result`, the result of the instruction just emitted, when it is owned. */
void fn_own_result(LowerFn *fn, MirValue result);

/* ---- statements, expressions and calls ---- */

bool fn_stmts(LowerFn *fn, MsStmts stmts);
MirValue fn_expr(LowerFn *fn, const MsExpr *expr, LowerWant want);
MirValue fn_call(LowerFn *fn, const MsExpr *expr, LowerWant want);

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
