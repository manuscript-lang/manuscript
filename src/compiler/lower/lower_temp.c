/* compiler/lower/lower_temp.c: temporaries that are resources. A call result passed borrowed to another call (`open().read()`,
 * `look(Door("x"))`) has no name, so nothing closes it at a scope end; it closes where its statement ends. A
 * statement with such a temporary gets a scope of its own, and the temporary lives in a slot that scope owns. */
#include "compiler/check/properties.h"
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/own/result_borrows.h"
#include "compiler/syntax/walk.h"

typedef struct Consumed {
  const MsFacts *facts;
  uint32_t param;
  bool found;
  bool moving; /* the parameter is `move`: a body that moves it owns it; a borrowed one is cloned where it is moved */
} Consumed;

static void note_consumed(void *ctx, const MsExpr *expr) {
  Consumed *state = ctx;
  const MsRef *ref = expr->kind == MS_E_NAME ? ms_facts_ref(state->facts, expr->id) : NULL;
  state->found |= state->moving && ref != NULL && ref->kind == MS_REF_PARAM && ref->local == state->param &&
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
  Consumed state = {&fn->cx->program->modules.ptr[target.module].facts, index, false,
                    index < target.func->params.len && target.func->params.ptr[index]->moving};
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
      callee_consumes(fn, call, index) ||
      ms_own_native_get(fn->cx->program, fn->facts, written) == MS_NATIVE_GET_MAP) { /* `m.get(k)` views the entry: its map closes it */
    return false;
  }
  const MsTy result = ms_ty_subst(types, ms_facts_type(fn->facts, expr->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  /* A result that holds a resource may be a part of the argument; one that borrows from another argument is not. */
  if (result == MS_TY_NONE || (ms_check_holds_resource(fn->cx->program, result) &&
                               ms_own_call_borrows(fn->cx->program, call, index))) {
    return false;
  }
  *checked = ms_ty_subst(types, ms_facts_type(fn->facts, written->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  const size_t declared = ms_ty_param_count(types, call->callee_ty);
  if (declared != 0 && index + declared >= call->arg_count) {
    const MsTy param = ms_ty_subst(types, ms_ty_params(types, call->callee_ty)[index + declared - call->arg_count].ty,
                                   fn->subst.vars, fn->subst.args, fn->subst.count);
    /* A resource handed over as an interface closes as itself: `view_as_interface` owns it for the statement. */
    const bool viewed = ms_ty_kind(types, param) == MS_TY_CONTRACT && ms_ty_kind(types, *checked) != MS_TY_CONTRACT &&
                        fn_temp_closes(fn, *checked);
    if (!viewed && ((ms_ty_is(types, param, MS_BUILTIN_Optional) && !ms_ty_is(types, *checked, MS_BUILTIN_Optional)) ||
                    ms_ty_kind(types, param) == MS_TY_CONTRACT)) {
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
  /* A resource field read in place (a method's receiver) leaves the record whole; one the statement moves does not. */
  const bool kept = !ms_check_holds_resource(fn->cx->program, field) || ms_facts_use(fn->facts, member->id) != MS_USE_MOVE;
  /* A call that answers a part of its arguments (`o.get().id`) leaves what it borrowed from to its owner. */
  const MsCall *call = ms_facts_call(fn->facts, base->id);
  const MsFunc *callee = call != NULL ? ms_own_find_func(fn->cx->program, &call->callee) : NULL;
  for (uint32_t index = 0; callee != NULL && index < callee->params.len; index++) {
    if (callee->params.ptr[index]->moving) {
      call = NULL; /* the callee owns a moved argument: its result is not a part of one the caller keeps */
      break;
    }
  }
  const MsExpr *callee_expr = base->u.call.callee;
  const bool has_receiver = callee_expr->kind == MS_E_MEMBER && call != NULL && call->callee.kind == MS_REF_METHOD;
  bool borrows_place = false;
  bool borrows_temporary = false;
  for (uint32_t position = 0; call != NULL && position <= base->u.call.args.len + (has_receiver ? 1u : 0u); position++) {
    if (!ms_own_call_borrows(fn->cx->program, call, position)) {
      continue;
    }
    /* A part of a temporary argument dies with the statement: that temporary closes it, so this one stays. */
    const MsExpr *source = has_receiver && position == 0 ? callee_expr->u.member.left
                           : position - (has_receiver ? 1u : 0u) < base->u.call.args.len
                               ? base->u.call.args.ptr[position - (has_receiver ? 1u : 0u)].value
                               : NULL;
    const MsNativeGet view = source != NULL && source->kind == MS_E_CALL ? ms_own_native_get(fn->cx->program, fn->facts, source) : MS_NATIVE_GET_NONE;
    if (source != NULL && source->kind == MS_E_CALL && view != MS_NATIVE_GET_LIST && view != MS_NATIVE_GET_MAP) {
      borrows_temporary = true;
    } else {
      borrows_place = true;
    }
  }
  if (borrows_place && !borrows_temporary) {
    return false;
  }
  return field != MS_TY_NONE && kept && *checked != MS_TY_NONE && fn_temp_closes(fn, *checked);
}

/* The type of the call result an element is read from (`doors()[1]`), which nothing else owns. A moved element leaves
 * the collection, which is a different path. */
static bool index_temp_type(LowerFn *fn, const MsExpr *index, MsTy *checked) {
  MsExpr *left = NULL;
  MsExpr *at = NULL;
  if (!ms_expr_index(index, &left, &at) || left->kind != MS_E_CALL || ms_facts_use(fn->facts, index->id) == MS_USE_MOVE) {
    return false;
  }
  MsTyTable *types = &fn->cx->program->types;
  *checked = ms_ty_subst(types, ms_facts_type(fn->facts, left->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  return *checked != MS_TY_NONE && ms_ty_is(types, *checked, MS_BUILTIN_List) && fn_temp_closes(fn, *checked);
}

MirValue fn_closing_indexed(LowerFn *fn, const MsExpr *index, MirValue list) {
  MsTy checked = MS_TY_NONE;
  if (!fn->temps || !index_temp_type(fn, index, &checked) || fn_type(fn, checked) != mir_b_ty(&fn->b, list) ||
      !fn_owns_result(fn, list)) {
    return list;
  }
  return fn_own_temporary(fn, checked, list);
}

MirValue fn_closing_base(LowerFn *fn, const MsExpr *member, MirValue base) {
  MsTy checked = MS_TY_NONE;
  if (!fn->temps || !member_temp_type(fn, member, &checked) || fn_type(fn, checked) != mir_b_ty(&fn->b, base) ||
      !fn_owns_result(fn, base)) {
    return base;
  }
  return fn_own_temporary(fn, checked, base);
}

MirValue fn_closing_temporary(LowerFn *fn, const MsExpr *expr, uint32_t index, const MsExpr *written, MirValue value) {
  MsTy checked = MS_TY_NONE;
  if (!fn->temps || !temp_type(fn, expr, index, written, &checked) || fn_type(fn, checked) != mir_b_ty(&fn->b, value) ||
      !fn_owns_result(fn, value)) {
    return value;
  }
  return fn_own_temporary(fn, checked, value);
}

/* `xs.remove(i)`, `xs.splice(..)`, `xs.set(i, v)`, `m.add(k, v)`, `m.remove(k)`, `m.clear()` over resources: the natives drop what they
 * take out of the collection, so the values come out and close where the statement ends. */
static bool drops_resources(LowerFn *fn, const MsExpr *callee) {
  MsTyTable *types = &fn->cx->program->types;
  const MsSpan name = ms_names_span(fn->cx->program->names, callee->u.member.name);
  if (!ms_span_is_text(name, "remove") && !ms_span_is_text(name, "splice") && !ms_span_is_text(name, "add") &&
      !ms_span_is_text(name, "clear") && !ms_span_is_text(name, "set")) {
    return false;
  }
  const MsTy owner = ms_ty_subst(types, ms_facts_type(fn->facts, callee->u.member.left->id), fn->subst.vars, fn->subst.args,
                                 fn->subst.count);
  if (owner == MS_TY_NONE) {
    return false;
  }
  const bool list = ms_ty_is(types, owner, MS_BUILTIN_List) && ms_ty_arg_count(types, owner) == 1;
  const bool map = ms_ty_is(types, owner, MS_BUILTIN_Map) && ms_ty_arg_count(types, owner) == 2;
  if (!list && !map) {
    return false;
  }
  const MsTy elem = ms_ty_subst(types, ms_ty_args(types, owner)[list ? 0 : 1], fn->subst.vars, fn->subst.args, fn->subst.count);
  return fn_temp_closes(fn, elem);
}

typedef struct TempScan {
  LowerFn *fn;
  uint32_t skip; /* open expressions whose parts run conditionally, or in another function */
  bool found;
  bool receiver; /* a list literal changed in place holds resources */
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
  scan->found |= expr->kind == MS_E_INDEX && scan->skip == 0 && index_temp_type(scan->fn, expr, &member);
  const MsCall *call = expr->kind == MS_E_CALL && scan->skip == 0 ? fn_find_call(scan->fn->facts, expr->id) : NULL;
  /* A list literal a method changes in place (`[Door(1)].append(Door(2))`) is a temporary that closes what it holds. */
  const MsExpr *callee = call != NULL ? fn_call_callee(expr) : NULL;
  if (callee != NULL && callee->kind == MS_E_MEMBER && callee->u.member.left->kind == MS_E_LIST) {
    const MsTy listed = ms_ty_subst(&scan->fn->cx->program->types, ms_facts_type(scan->fn->facts, callee->u.member.left->id),
                                    scan->fn->subst.vars, scan->fn->subst.args, scan->fn->subst.count);
    scan->receiver |= listed != MS_TY_NONE && fn_temp_closes(scan->fn, listed);
  }
  scan->found |= callee != NULL && callee->kind == MS_E_MEMBER && drops_resources(scan->fn, callee);
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

/* Whether the call `value` answers an owner independent of what it reads: a function whose results are not parts of its
 * parameters. A bodiless one (a native) is taken to borrow unless it says otherwise. */
static bool call_answers_owner(LowerFn *fn, const MsExpr *value) {
  const MsCall *call = value->kind == MS_E_CALL ? fn_find_call(fn->facts, value->id) : NULL;
  if (call == NULL || (call->callee.kind != MS_REF_FUNCTION && call->callee.kind != MS_REF_METHOD)) {
    return false;
  }
  const MsFunc *callee = ms_own_find_func(fn->cx->program, &call->callee);
  return callee != NULL && !callee->bodiless && !callee->external &&
         !ms_own_result_is_borrowed(fn->cx->program, call->callee.decl.module, call->callee.decl.node);
}

/* A case call (`ok(7)`) whose arguments own nothing: the value it builds cannot be a view of a temporary. */
static bool builds_plain_case(LowerFn *fn, const MsExpr *value) {
  const MsCall *call = value->kind == MS_E_CALL ? fn_find_call(fn->facts, value->id) : NULL;
  if (call == NULL || call->callee.kind != MS_REF_CASE) {
    return false;
  }
  for (uint32_t index = 0; index < call->arg_count; index++) {
    const MsTy ty = call->args[index].node.node == 0 ? MS_TY_NONE
                                                      : ms_facts_type(fn->facts, call->args[index].node.node);
    const MsTy concrete = ty == MS_TY_NONE ? ty
                                           : ms_ty_subst(&fn->cx->program->types, ty, fn->subst.vars, fn->subst.args,
                                                         fn->subst.count);
    if (concrete == MS_TY_NONE || mir_needs_drop(fn->cx->module, fn_type(fn, concrete))) {
      return false;
    }
  }
  return true;
}

bool fn_expr_has_temporary(LowerFn *fn, const MsExpr *expr) {
  if (fn->closing == NULL) {
    return false;
  }
  TempScan scan = {.fn = fn};
  const MsVisitor visitor = {.ctx = &scan, .expr = scan_enter, .leave_expr = scan_leave};
  ms_walk_expr(&visitor, expr);
  return scan.found || scan.receiver;
}

bool fn_stmt_has_temporary(LowerFn *fn, const MsStmt *stmt) {
  const MsExpr *value = stmt->kind == MS_S_CALL || stmt->kind == MS_S_RETURN ? stmt->u.expr
                        : stmt->kind == MS_S_BIND                                ? stmt->u.bind.value
                                                                                 : NULL;
  if (value == NULL || fn->closing == NULL) {
    return false;
  }
  TempScan scan = {.fn = fn};
  const MsVisitor visitor = {.ctx = &scan, .expr = scan_enter, .leave_expr = scan_leave};
  ms_walk_expr(&visitor, value);
  const MsPattern *target = stmt->kind == MS_S_BIND ? stmt->u.bind.pattern : NULL;
  const bool discarded = target != NULL && target->kind == MS_P_NAME && ms_span_is_text(ms_names_span(fn->cx->program->names, target->u.name), "_");
  if ((stmt->kind == MS_S_BIND && !discarded) || stmt->kind == MS_S_RETURN) {
    /* What the statement binds or returns outlives it, so only a value with nothing to own can leave. `void value` drops it. */
    const MsNode node = stmt->kind == MS_S_BIND ? stmt->u.bind.pattern->id : value->id;
    const MsTy bound = ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, node), fn->subst.vars,
                                   fn->subst.args, fn->subst.count);
    if (bound == MS_TY_NONE) {
      return false;
    }
    /* A name that closes is made in the scope outside the statement's own (`bind_scope`). */
    if (stmt->kind == MS_S_BIND && fn_temp_closes(fn, bound)) {
      return scan.receiver || scan.found;
    }
    /* An owned name that never changes moves to the scope outside the statement's own (`bind_scope`). */
    const bool outer = stmt->kind == MS_S_BIND && !stmt->u.bind.is_mutable && !fn_temp_closes(fn, bound) &&
                       call_answers_owner(fn, value);
    if (!outer && !(stmt->kind == MS_S_RETURN && builds_plain_case(fn, value)) && (mir_needs_drop(fn->cx->module, fn_type(fn, bound)) || fn_temp_closes(fn, bound))) {
      return false;
    }
  }
  return scan.found || scan.receiver;
}
