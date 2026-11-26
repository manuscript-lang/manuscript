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
  bool ref_result; /* the result is a `&` view: returning the parameter lends it, the caller still owns it */
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
    state->found |= ref != NULL && ref->kind == MS_REF_PARAM && ref->local == state->param &&
                    !(state->ref_result && !state->moving && stmt->kind == MS_S_RETURN);
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
                    index < target.func->params.len && target.func->params.ptr[index]->moving, false};
  state.ref_result = ms_own_result_is_borrowed(fn->cx->program, target.module, target.node);
  const MsVisitor visitor = {.ctx = &state, .expr = note_consumed, .stmt = note_handed_on};
  ms_walk_block(&visitor, target.func->body);
  return state.found;
}

/* Whether the call `call` answers a part of a place that outlives the statement: a result that borrows from an argument
 * that is a place, or from a call that answers a part of one. */
static bool part_of_place(LowerFn *fn, const MsExpr *call, uint32_t depth) {
  const MsCall *fact = depth < 8 ? ms_facts_call(fn->facts, call->id) : NULL;
  if (fact == NULL || (fact->callee.kind != MS_REF_METHOD && fact->callee.kind != MS_REF_NATIVE && fact->callee.kind != MS_REF_FUNCTION)) {
    return false;
  }
  const MsExpr *callee = call->u.call.callee;
  const bool has_receiver = callee->kind == MS_E_MEMBER && fact->callee.kind != MS_REF_FUNCTION;
  for (uint32_t position = 0; position <= call->u.call.args.len + (has_receiver ? 1u : 0u); position++) {
    if (!ms_own_call_borrows(fn->cx->program, fact, position)) {
      continue;
    }
    const uint32_t arg = position - (has_receiver ? 1u : 0u);
    const MsExpr *source = has_receiver && position == 0 ? callee->u.member.left
                           : arg < call->u.call.args.len ? call->u.call.args.ptr[arg].value
                                                         : NULL;
    if (source == NULL) {
      continue;
    }
    if (source->kind != MS_E_CALL || part_of_place(fn, source, depth + 1)) {
      return true;
    }
  }
  return false;
}

/* A function with a body of its own: its parameters are the source of truth for what it keeps. A native may take a
 * written list's elements into its receiver (`xs.splice(i, j, [r])`), so the list is not a temporary there. */
static bool callee_has_body(LowerFn *fn, const MsCall *call) {
  if (call->callee.kind == MS_REF_NATIVE || call->callee.kind == MS_REF_OPERATION) {
    return false;
  }
  if (call->callee.kind != MS_REF_FUNCTION && call->callee.kind != MS_REF_METHOD) {
    return true; /* a function value: its callee is checked as a borrower or a consumer by the call itself */
  }
  const MsFunc *callee = ms_own_find_func(fn->cx->program, &call->callee);
  return callee != NULL && !callee->bodiless && !callee->external;
}

/* The type the borrowed argument `index` (written as `written`) has once the callee gets it: the Optional it is
 * converted to, else its own. False when the argument is not a borrowed call result, or the call may hand a part of it
 * on in its result (it then owns what it took). */
static bool temp_type(LowerFn *fn, const MsExpr *expr, uint32_t index, const MsExpr *written, MsTy *checked) {
  const MsCall *call = fn_find_call(fn->facts, expr->id);
  MsTyTable *types = &fn->cx->program->types;
  if (call == NULL || (written->kind != MS_E_CALL && !(written->kind == MS_E_LIST && callee_has_body(fn, call))) ||
      fn_arg_moves(fn, expr, call, index, written) || callee_consumes(fn, call, index) ||
      ms_own_native_get(fn->cx->program, fn->facts, written) == MS_NATIVE_GET_MAP ||  /* `m.get(k)` views the entry: its map closes it */
      part_of_place(fn, written, 0)) {                                                 /* `xs.first().get()` is a part of `xs`, which closes it */
    return false;
  }
  const MsTy result = ms_ty_subst(types, ms_facts_type(fn->facts, expr->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  /* A result that holds a resource may be a part of the argument; one that borrows from another argument is not. */
  if (result == MS_TY_NONE || (ms_check_holds_resource(fn->cx->program, result) && fn->temps_keep &&
                               ms_own_call_borrows(fn->cx->program, call, index))) {
    return false;
  }
  *checked = ms_ty_subst(types, fn_read_type(fn, written), fn->subst.vars, fn->subst.args, fn->subst.count);
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
  /* `(x or d).field`: the nullable `or` builds an owner of its own, which nothing else holds. */
  const bool nullable_or = base->kind == MS_E_BINARY && base->op == MS_B_OR &&
                           ms_ty_is(types, ms_facts_type(fn->facts, base->u.bin.left->id), MS_BUILTIN_Optional);
  if (nullable_or && ref != NULL && ref->kind == MS_REF_FIELD) {
    *checked = ms_ty_subst(types, ms_facts_type(fn->facts, base->id), fn->subst.vars, fn->subst.args, fn->subst.count);
    return *checked != MS_TY_NONE && fn_temp_closes(fn, *checked);
  }
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
      /* A call that is itself a part of a place (`xs.first().get()`) keeps its owner: only a fresh value is a temporary. */
      if (part_of_place(fn, source, 0)) {
        borrows_place = true;
      } else {
        borrows_temporary = true;
      }
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

/* The type of a call result a comparison reads (`open() != null`), which nothing else owns. */
static bool operand_temp_type(LowerFn *fn, const MsExpr *operand, MsTy *checked) {
  if (operand->kind != MS_E_CALL) {
    return false;
  }
  MsTyTable *types = &fn->cx->program->types;
  *checked = ms_ty_subst(types, ms_facts_type(fn->facts, operand->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  return *checked != MS_TY_NONE && fn_temp_closes(fn, *checked);
}

MirValue fn_closing_operand(LowerFn *fn, const MsExpr *operand, MirValue value) {
  MsTy checked = MS_TY_NONE;
  if (!fn->temps || !operand_temp_type(fn, operand, &checked) || fn_type(fn, checked) != mir_b_ty(&fn->b, value) ||
      !fn_owns_result(fn, value)) {
    return value;
  }
  return fn_own_temporary(fn, checked, value);
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
  const MsTy owner = ms_ty_subst(types, fn_read_type(fn, callee->u.member.left), fn->subst.vars, fn->subst.args,
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

/* A closure a call builds and the callee only borrows (`xs.ok_or_else(make())`): its captures close with the statement. */
static bool closure_temp(LowerFn *fn, const MsExpr *expr, const MsCall *call, uint32_t index, const MsExpr *written) {
  if (written->kind != MS_E_CALL || fn_arg_moves(fn, expr, call, index, written) || callee_consumes(fn, call, index)) {
    return false;
  }
  const MsTy ty = ms_ty_subst(&fn->cx->program->types, fn_read_type(fn, written), fn->subst.vars, fn->subst.args, fn->subst.count);
  return ty != MS_TY_NONE && ms_ty_kind(&fn->cx->program->types, ty) == MS_TY_FUNCTION && mir_needs_drop(fn->cx->module, fn_type(fn, ty));
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
  MsTy member = MS_TY_NONE;
  scan->found |= expr->kind == MS_E_MATCH && scan->skip == 0 && operand_temp_type(scan->fn, expr->u.match.scrutinee, &member);
  if (conditional(expr)) {
    scan->skip++;
  }
  if (expr->kind == MS_E_BINARY && (expr->op == MS_B_EQ || expr->op == MS_B_NE) && scan->skip == 0) {
    scan->found |= operand_temp_type(scan->fn, expr->u.bin.left, &member) || operand_temp_type(scan->fn, expr->u.bin.right, &member);
  }
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
    scan->found = written != NULL && (temp_type(scan->fn, expr, index, written, &checked) || closure_temp(scan->fn, expr, call, index, written));
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

/* Whether the statement binds (not to `_`) or returns a value that may hold a resource: it outlives the statement.
 * An assignment is not listed: the checker rejects a view of a temporary stored in a place. */
bool fn_stmt_keeps_resource(LowerFn *fn, const MsStmt *stmt) {
  const bool binds = stmt->kind == MS_S_BIND && !(stmt->u.bind.pattern->kind == MS_P_NAME &&
                     ms_span_is_text(ms_names_span(fn->cx->program->names, stmt->u.bind.pattern->u.name), "_"));
  if (!binds && stmt->kind != MS_S_RETURN) {
    return false;
  }
  const MsNode node = binds ? stmt->u.bind.pattern->id : stmt->u.expr != NULL ? stmt->u.expr->id : 0;
  const MsTy kept = node == 0 ? MS_TY_NONE : ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, node), fn->subst.vars,
                                                         fn->subst.args, fn->subst.count);
  return kept != MS_TY_NONE && ms_check_holds_resource(fn->cx->program, kept);
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
  fn->temps_keep = fn_stmt_keeps_resource(fn, stmt);
  ms_walk_expr(&visitor, value);
  fn->temps_keep = false;
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
    /* An owned name that never changes moves to the scope outside the statement's own (`bind_scope`); a returned
     * answer of such a call is its own value too, so the statement's temporaries close before the function leaves. */
    const bool outer = ((stmt->kind == MS_S_BIND && !stmt->u.bind.is_mutable) || stmt->kind == MS_S_RETURN) &&
                       !fn_temp_closes(fn, bound) && call_answers_owner(fn, value);
    if (!outer && !(stmt->kind == MS_S_RETURN && builds_plain_case(fn, value)) && (mir_needs_drop(fn->cx->module, fn_type(fn, bound)) || fn_temp_closes(fn, bound))) {
      return false;
    }
  }
  return scan.found || scan.receiver;
}

/* The record `base` loses the field `moved` to its new owner: the resources its other fields hold close with the
 * statement, last field first, instead of being released unclosed. Returns the mask of the fields taken out. */
uint32_t fn_close_rest(LowerFn *fn, const MsExpr *member, MirValue base, uint32_t type_id, uint32_t moved) {
  MsCheckProgram *program = fn->cx->program;
  const MsTy owner = ms_ty_subst(&program->types, ms_facts_type(fn->facts, member->u.member.left->id), fn->subst.vars, fn->subst.args,
                                 fn->subst.count);
  const MsDef *def = owner != MS_TY_NONE ? ms_check_def_of(program, owner) : NULL;
  const MirTypeDef *record = &fn->cx->module->type_defs.ptr[type_id];
  uint32_t taken = 0;
  for (uint32_t at = 0; def != NULL && at < record->nfields && at < 32 && at < def->fields.len; at++) {
    const MirTy field_ty = record->fields[at].ty;
    if (at == moved || !mir_needs_drop(fn->cx->module, field_ty)) {
      continue;
    }
    const MsTy checked = ms_check_part_type(program, owner, def, def->fields.ptr[at].ty);
    if (!fn_temp_closes(fn, checked)) {
      continue;
    }
    const MirImm imm = {.tag = MI_FIELD, .a = type_id, .b = at};
    const MirValue field = mir_b_emit(&fn->b, MOP_TypeGet, &base, 1, imm, field_ty);
    const MirValue out = fn_emit(fn, MOP_MoveOut, &field, 1, (MirImm){0}, field_ty);
    if (fn_pending_own(fn, checked, out) != MIR_NONE) {
      taken |= UINT32_C(1) << at;
    }
  }
  return taken;
}
