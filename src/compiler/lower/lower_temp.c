/* compiler/lower/lower_temp.c: temporaries that are resources. A call result passed borrowed to another call (`open().read()`,
 * `look(Door("x"))`) has no name, so nothing closes it at a scope end; it closes where its statement ends. A
 * statement with such a temporary gets a scope of its own, and the temporary lives in a slot that scope owns. */
#include "compiler/check/properties.h"
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/syntax/walk.h"

typedef struct Consumed {
  const MsFacts *facts;
  uint32_t param;
  bool found;
} Consumed;

static void note_consumed(void *ctx, const MsExpr *expr) {
  Consumed *state = ctx;
  const MsRef *ref = expr->kind == MS_E_NAME ? ms_facts_ref(state->facts, expr->id) : NULL;
  state->found |= ref != NULL && ref->kind == MS_REF_PARAM && ref->local == state->param &&
                  ms_facts_use(state->facts, expr->id) == MS_USE_MOVE;
}

/* A parameter bound to a name, assigned, or returned is handed on, though a bind only borrows it in the source. */
static void note_handed_on(void *ctx, const MsStmt *stmt) {
  const MsExpr *value = stmt->kind == MS_S_BIND ? stmt->u.bind.value : stmt->kind == MS_S_ASSIGN ? stmt->u.assign.value
                        : stmt->kind == MS_S_RETURN ? stmt->u.expr : NULL;
  if (value != NULL) {
    note_consumed(ctx, value);
    Consumed *state = ctx;
    const MsRef *ref = value->kind == MS_E_NAME ? ms_facts_ref(state->facts, value->id) : NULL;
    state->found |= ref != NULL && ref->kind == MS_REF_PARAM && ref->local == state->param;
  }
}

/* Whether the callee's body moves parameter `index` somewhere (into a field, a collection, its result): the
 * callee then owns what it was passed, and the caller must not close it too. */
static bool callee_consumes(LowerFn *fn, const MsCall *call, uint32_t index) {
  LowerTarget target;
  if (!fn_callee_target(fn, call, &target)) {
    return false;
  }
  Consumed state = {&fn->cx->program->modules.ptr[target.module].facts, index, false};
  const MsVisitor visitor = {.ctx = &state, .expr = note_consumed, .stmt = note_handed_on};
  ms_walk_block(&visitor, target.func->body);
  return state.found;
}

/* The type the borrowed argument `index` (written as `written`) has once the callee gets it: the Optional it is
 * converted to, else its own. False when the argument is not a borrowed call result, or the call may hand a part of it
 * on in its result (it then owns what it took). */
static bool temp_type(LowerFn *fn, const MsExpr *expr, uint32_t index, const MsExpr *written, MsTy *checked) {
  const MsCall *call = fn_find_call(fn->facts, expr->id);
  MsTyTable *types = &fn->cx->program->types;
  if (call == NULL || written->kind != MS_E_CALL || fn_arg_moves(fn, expr, call, index, written) ||
      callee_consumes(fn, call, index)) {
    return false;
  }
  const MsTy result = ms_ty_subst(types, ms_facts_type(fn->facts, expr->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  if (result == MS_TY_NONE || ms_check_holds_resource(fn->cx->program, result)) {
    return false;
  }
  *checked = ms_ty_subst(types, ms_facts_type(fn->facts, written->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  const size_t declared = ms_ty_param_count(types, call->callee_ty);
  if (declared != 0 && index + declared >= call->arg_count) {
    const MsTy param = ms_ty_subst(types, ms_ty_params(types, call->callee_ty)[index + declared - call->arg_count].ty,
                                   fn->subst.vars, fn->subst.args, fn->subst.count);
    if ((ms_ty_is(types, param, MS_BUILTIN_Optional) && !ms_ty_is(types, *checked, MS_BUILTIN_Optional)) ||
        ms_ty_kind(types, param) == MS_TY_CONTRACT) {
      *checked = param;
    }
  }
  return *checked != MS_TY_NONE && fn_temp_closes(fn, *checked);
}

/* The type of the call result a field is read from (`open().name`), which nothing else owns. */
static bool member_temp_type(LowerFn *fn, const MsExpr *member, MsTy *checked) {
  const MsExpr *base = member->u.member.left;
  MsTyTable *types = &fn->cx->program->types;
  const MsRef *ref = ms_facts_ref(fn->facts, member->id);
  if (base->kind != MS_E_CALL || ref == NULL || ref->kind != MS_REF_FIELD) {
    return false;
  }
  const MsTy field = ms_ty_subst(types, ms_facts_type(fn->facts, member->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  *checked = ms_ty_subst(types, ms_facts_type(fn->facts, base->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  return field != MS_TY_NONE && !ms_check_holds_resource(fn->cx->program, field) && *checked != MS_TY_NONE &&
         fn_temp_closes(fn, *checked);
}

MirValue fn_closing_base(LowerFn *fn, const MsExpr *member, MirValue base) {
  MsTy checked = MS_TY_NONE;
  if (!fn->temps || !member_temp_type(fn, member, &checked) || fn_type(fn, checked) != mir_b_ty(&fn->b, base) ||
      (mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, base)) && !fn_fresh_owner(fn, base))) {
    return base;
  }
  return fn_own_temporary(fn, checked, base);
}

MirValue fn_closing_temporary(LowerFn *fn, const MsExpr *expr, uint32_t index, const MsExpr *written, MirValue value) {
  MsTy checked = MS_TY_NONE;
  if (!fn->temps || !temp_type(fn, expr, index, written, &checked) || fn_type(fn, checked) != mir_b_ty(&fn->b, value) ||
      (mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value)) && !fn_fresh_owner(fn, value))) {
    return value;
  }
  return fn_own_temporary(fn, checked, value);
}

typedef struct TempScan {
  LowerFn *fn;
  uint32_t skip; /* open expressions whose parts run conditionally, or in another function */
  bool found;
} TempScan;

static bool conditional(const MsExpr *expr) {
  return expr->kind == MS_E_LAMBDA || expr->kind == MS_E_MATCH ||
         (expr->kind == MS_E_BINARY && (expr->op == MS_B_AND || expr->op == MS_B_OR));
}

static void scan_enter(void *ctx, const MsExpr *expr) {
  TempScan *scan = ctx;
  if (conditional(expr)) {
    scan->skip++;
  }
  MsTy member = MS_TY_NONE;
  scan->found |= expr->kind == MS_E_MEMBER && scan->skip == 0 && member_temp_type(scan->fn, expr, &member);
  const MsCall *call = expr->kind == MS_E_CALL && scan->skip == 0 ? fn_find_call(scan->fn->facts, expr->id) : NULL;
  for (uint32_t index = 0; call != NULL && !scan->found && index < call->arg_count; index++) {
    const MsExpr *written = call->args[index].source == MS_ARG_WRITTEN ? fn_written_arg(expr, call->args[index].node.node) : NULL;
    MsTy checked = MS_TY_NONE;
    scan->found = written != NULL && temp_type(scan->fn, expr, index, written, &checked);
  }
}

static void scan_leave(void *ctx, const MsExpr *expr) {
  TempScan *scan = ctx;
  if (conditional(expr)) {
    scan->skip--;
  }
}

bool fn_stmt_has_temporary(LowerFn *fn, const MsStmt *stmt) {
  const MsExpr *value = stmt->kind == MS_S_CALL || stmt->kind == MS_S_RETURN ? stmt->u.expr
                        : stmt->kind == MS_S_BIND                                ? stmt->u.bind.value
                                                                                 : NULL;
  if (value == NULL || fn->closing == NULL) {
    return false;
  }
  if (stmt->kind == MS_S_BIND || stmt->kind == MS_S_RETURN) {
    /* What the statement binds or returns outlives it, so only a value with nothing to own can leave. */
    const MsNode node = stmt->kind == MS_S_BIND ? stmt->u.bind.pattern->id : value->id;
    const MsTy bound = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, node), fn->subst.vars,
                                   fn->subst.args, fn->subst.count);
    if (bound == MS_TY_NONE || mir_needs_drop(fn->cx->module, fn_type(fn, bound)) || fn_temp_closes(fn, bound)) {
      return false;
    }
  }
  TempScan scan = {.fn = fn};
  const MsVisitor visitor = {.ctx = &scan, .expr = scan_enter, .leave_expr = scan_leave};
  ms_walk_expr(&visitor, value);
  return scan.found;
}
