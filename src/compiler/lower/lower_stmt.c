/* compiler/lower/lower_stmt.c: statements: bindings, assignment, calls, return, if, while, break, continue. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"

static MirValue take_value(LowerFn *fn, const MsExpr *expr) {
  const MirValue value = fn_expr(fn, expr, LW_MOVE);
  return value;
}

static bool lower_bind(LowerFn *fn, const MsStmt *stmt) {
  const MsPattern *pattern = stmt->u.bind.pattern;
  if (pattern->kind != MS_P_NAME) {
    return fn_fail(fn, "only a name can be bound for now");
  }
  const MirValue value = take_value(fn, stmt->u.bind.value);
  if (value == MIR_NONE) {
    return false;
  }
  const MirVar var = fn_local(fn, ms_facts_ref(fn->facts, pattern->id)->local, mir_b_ty(&fn->b, value));
  mir_b_def_var(&fn->b, var, value);
  return !fn->failed;
}

static bool lower_assign(LowerFn *fn, const MsStmt *stmt) {
  if (stmt->u.assign.member_target) {
    return fn_fail(fn, "assignment to a member is not lowered yet");
  }
  const MsRef *ref = ms_facts_ref(fn->facts, stmt->id);
  if (ref == NULL || ref->kind != MS_REF_LOCAL || ref->local >= fn->nvars || fn->vars[ref->local] == 0) {
    return fn_fail(fn, "an assignment does not name a local");
  }
  const MirVar var = fn->vars[ref->local] - 1;
  MirValue value = take_value(fn, stmt->u.assign.value);
  if (value == MIR_NONE) {
    return false;
  }
  if (stmt->u.assign.has_compound) {
    const MirValue old = mir_b_use_var(&fn->b, var);
    const MirOp op = (MsBinaryOp)stmt->u.assign.compound == MS_B_ADD ? MOP_IAddChk
                     : (MsBinaryOp)stmt->u.assign.compound == MS_B_SUB ? MOP_ISubChk : MOP_IMulChk;
    value = mir_b_binop(&fn->b, op, old, value);
  }
  mir_b_def_var(&fn->b, var, value);
  return !fn->failed;
}

static bool lower_return(LowerFn *fn, const MsStmt *stmt) {
  MirValue value = MIR_NONE;
  if (stmt->u.expr != NULL) {
    value = take_value(fn, stmt->u.expr);
    if (value == MIR_NONE) {
      return false;
    }
    const MirImm none = {0};
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, none, MIR_NONE);
  }
  fn_scope_unwind(fn, 0);
  mir_b_ret(&fn->b, value);
  fn->terminated = true;
  return !fn->failed;
}

/* Lowers a block of statements in a scope of its own. */
static bool lower_block(LowerFn *fn, MsStmts stmts) {
  (void)fn_scope_begin(fn);
  const bool ok = fn_stmts(fn, stmts);
  if (!fn->terminated) {
    fn_scope_end(fn);
  } else {
    fn->nopen--;
  }
  return ok;
}

/* Starts `block` as the current block, sealed once its predecessors are known. */
static void enter(LowerFn *fn, MirBlock block) {
  mir_b_switch_to(&fn->b, block);
  fn->terminated = false;
}

static bool lower_if(LowerFn *fn, const MsStmt *stmt) {
  if (stmt->u.branch.binding != NULL) {
    return fn_fail(fn, "`if` with a binding is not lowered yet");
  }
  const MirValue cond = fn_expr(fn, stmt->u.branch.cond, LW_BORROW);
  if (cond == MIR_NONE) {
    return false;
  }
  const MirBlock then = mir_b_new_block(&fn->b);
  const MirBlock otherwise = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  mir_b_br_if(&fn->b, cond, then, NULL, 0, otherwise, NULL, 0);
  mir_b_seal_block(&fn->b, then);
  mir_b_seal_block(&fn->b, otherwise);
  enter(fn, then);
  bool ok = lower_block(fn, stmt->u.branch.body);
  const bool then_ended = fn->terminated;
  if (!then_ended) {
    mir_b_br(&fn->b, join, NULL, 0);
  }
  enter(fn, otherwise);
  ok = lower_block(fn, stmt->u.branch.else_body) && ok;
  const bool else_ended = fn->terminated;
  if (!else_ended) {
    mir_b_br(&fn->b, join, NULL, 0);
  }
  mir_b_seal_block(&fn->b, join);
  enter(fn, join);
  fn->terminated = then_ended && else_ended;
  if (fn->terminated) {
    mir_b_unreachable(&fn->b);
  }
  return ok;
}

static bool lower_while(LowerFn *fn, const MsStmt *stmt) {
  if (fn->nloops == LOWER_MAX_LOOPS) {
    return fn_fail(fn, "loops nest too deeply");
  }
  const MirBlock head = mir_b_new_block(&fn->b);
  const MirBlock body = mir_b_new_block(&fn->b);
  const MirBlock done = mir_b_new_block(&fn->b);
  mir_b_br(&fn->b, head, NULL, 0);
  enter(fn, head);
  const MirValue cond = fn_expr(fn, stmt->u.loop.cond, LW_BORROW);
  if (cond == MIR_NONE) {
    return false;
  }
  mir_b_br_if(&fn->b, cond, body, NULL, 0, done, NULL, 0);
  mir_b_seal_block(&fn->b, body);
  enter(fn, body);
  fn->loops[fn->nloops++] = (LowerLoop){done, head, fn->nopen};
  const bool ok = lower_block(fn, stmt->u.loop.body);
  fn->nloops--;
  if (!fn->terminated) {
    mir_b_br(&fn->b, head, NULL, 0);
  }
  mir_b_seal_block(&fn->b, head);
  mir_b_seal_block(&fn->b, done);
  enter(fn, done);
  return ok;
}

static bool lower_jump(LowerFn *fn, bool is_break) {
  if (fn->nloops == 0) {
    return fn_fail(fn, "`break` or `continue` outside a loop");
  }
  const LowerLoop loop = fn->loops[fn->nloops - 1];
  fn_scope_unwind(fn, loop.depth);
  mir_b_br(&fn->b, is_break ? loop.break_to : loop.continue_to, NULL, 0);
  fn->terminated = true;
  return !fn->failed;
}

static bool lower_stmt(LowerFn *fn, const MsStmt *stmt) {
  mir_b_set_loc(&fn->b, fn_loc(fn, stmt->pos));
  switch ((MsStmtKind)stmt->kind) {
    case MS_S_BIND: return lower_bind(fn, stmt);
    case MS_S_ASSIGN: return lower_assign(fn, stmt);
    case MS_S_CALL: return fn_expr(fn, stmt->u.expr, LW_BORROW) != MIR_NONE || !fn->failed;
    case MS_S_RETURN: return lower_return(fn, stmt);
    case MS_S_BREAK: return lower_jump(fn, true);
    case MS_S_CONTINUE: return lower_jump(fn, false);
    case MS_S_IF: return lower_if(fn, stmt);
    case MS_S_WHILE: return lower_while(fn, stmt);
    case MS_S_FOR: return fn_for(fn, stmt);
  }
  return fn_fail(fn, "unknown statement");
}

bool fn_stmts(LowerFn *fn, MsStmts stmts) {
  for (uint32_t index = 0; index < stmts.len && !fn->terminated; index++) {
    if (!lower_stmt(fn, stmts.ptr[index])) {
      return false;
    }
  }
  return true;
}
