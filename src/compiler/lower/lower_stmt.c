/* compiler/lower/lower_stmt.c: statements: bindings, assignment, calls, return, if, while, break, continue. */
#include "compiler/syntax/walk.h"
#include "compiler/check/properties.h"
#include "compiler/lower/lower_fn.h"
#include "compiler/own/closers.h"
#include "compiler/own/result_borrows.h"
#include "compiler/mir/mir_analysis.h"


/* Whether `local` is an Optional that a later read narrows (`v != null` then `v`): the read may take its payload on one
 * path only, so the binding is a variable the scope tracks across paths. */
typedef struct NarrowedScan {
  const LowerFn *fn;
  uint32_t local;
  bool found;
} NarrowedScan;

static void narrowed_expr(void *ctx, const MsExpr *expr) {
  NarrowedScan *scan = ctx;
  if (expr->kind != MS_E_NAME || scan->found) {
    return;
  }
  const MsRef *ref = ms_facts_ref(scan->fn->facts, expr->id);
  if (ref == NULL || ref->kind != MS_REF_LOCAL || ref->local != scan->local) {
    return;
  }
  const MsConversion *list = scan->fn->facts->conversions.ptr;
  for (size_t at = 0; at < scan->fn->facts->conversions.len; at++) {
    scan->found |= list[at].node == expr->id && list[at].kind == MS_CONV_NARROW;
  }
}

static bool narrowed_local(const LowerFn *fn, uint32_t local, MirTy ty) {
  if (mir_ty_data(fn->cx->module, ty)->kind != MK_OPT) {
    return false;
  }
  NarrowedScan scan = {.fn = fn, .local = local};
  const MsVisitor visitor = {.ctx = &scan, .expr = narrowed_expr};
  if (fn->func != NULL) {
    ms_walk_block(&visitor, fn->func->body);
  } else if (fn->lambda != NULL) {
    ms_walk_block(&visitor, fn->lambda->expr->u.lambda.body);
  }
  return scan.found;
}

static MirValue take_value(LowerFn *fn, const MsExpr *expr) {
  const MirValue value = fn_expr(fn, expr, LW_MOVE);
  return value;
}

/* A `var` local of a type that needs a drop owns its current value: assignment moves the new value in and drops
 * the old one, and the scope that declared it owns what it holds where the scope ends. */
static bool var_owns(const LowerFn *fn, MirVar var) {
  return fn->b.vars.ptr[var].mode == MM_MOVE;
}

/* Whether a call reads a value that dies with the statement (`make().get()`): a result that borrows from it
 * cannot outlive the statement. */
static bool call_reads_temporary(const MsFacts *facts, const MsExpr *call) {
  const MsExpr *callee = fn_call_callee(call);
  if (callee->kind == MS_E_MEMBER && callee->u.member.left->kind == MS_E_CALL) {
    return true;
  }
  if (callee->kind == MS_E_MEMBER && callee->u.member.left->kind == MS_E_NAME && facts != NULL &&
      facts->last != NULL && facts->last[callee->u.member.left->id] != 0) {
    return true; /* an owner at its last use dies with the call */
  }
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    if (call->u.call.args.ptr[index].value->kind == MS_E_CALL) {
      return true;
    }
  }
  return false;
}

/* Whether `value` is the `none` just built: it holds nothing, so the binding that takes it owns all of it. */
static bool is_empty_optional(const LowerFn *fn, MirValue value) {
  const MirInstList *insts = &fn->b.func.blocks.ptr[fn->b.cur].insts;
  if (insts->len == 0 || insts->ptr[insts->len - 1].res != value) {
    return false;
  }
  const MirOp op = (MirOp)insts->ptr[insts->len - 1].op;
  return op == MOP_OptNone;
}

/* The parameters of the method a binding's value is, whose defaults a call through the name may leave out (a lambda applies
 * its own defaults in its body). */
static const MsParams *bound_value_params(LowerFn *fn, const MsExpr *value) {
  const bool member = value->kind == MS_E_MEMBER || (value->kind == MS_E_APPLY && value->u.apply.left->kind == MS_E_MEMBER);
  const MsRef *ref = member ? ms_facts_ref(fn->facts, value->id) : NULL;
  const MsMethodEntry *entry = ref != NULL && ref->kind == MS_REF_METHOD ? fn_method_entry(fn->cx, ref->decl.module, ref->decl.node) : NULL;
  return entry != NULL ? &entry->source->func.params : NULL;
}

/* `b := m.get(k)` over a resource: an Optional that views the entry in place, `none` when the key is absent, so the
 * binding borrows what the map keeps instead of copying it. MIR_NONE (nothing emitted) for any other call. */
MirValue fn_map_get_view(LowerFn *fn, const MsExpr *call) {
  if (ms_own_native_get(fn->cx->program, fn->facts, call) != MS_NATIVE_GET_MAP ||
      !ms_check_holds_resource(fn->cx->program, ms_facts_type(fn->facts, call->id))) {
    return MIR_NONE;
  }
  const MsExpr *receiver = call->u.call.callee->u.member.left;
  const MirValue map = fn_expr(fn, receiver, LW_BORROW);
  MirTy entry_ty = MIR_VOID;
  const MirValue address = map == MIR_NONE ? MIR_NONE : fn_entry_address(fn, map, call->u.call.args.ptr[0].value, &entry_ty);
  if (address == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy opt_ty = fn_type(fn, ms_facts_type(fn->facts, call->id));
  const MirValue absent = mir_b_emit(&fn->b, MOP_PtrIsNull, &address, 1, (MirImm){0}, MIR_BOOL);
  const MirBlock hit = mir_b_new_block(&fn->b);
  const MirBlock miss = mir_b_new_block(&fn->b);
  const MirBlock join = mir_b_new_block(&fn->b);
  const MirValue result = mir_b_add_block_param(&fn->b, join, opt_ty, MM_BORROW);
  mir_b_br_if(&fn->b, absent, miss, NULL, 0, hit, NULL, 0);
  mir_b_seal_block(&fn->b, hit);
  mir_b_seal_block(&fn->b, miss);
  mir_b_switch_to(&fn->b, hit);
  const MirValue entry = mir_b_emit(&fn->b, MOP_Load, &address, 1, (MirImm){.tag = MI_TY, .a = entry_ty}, entry_ty);
  const MirValue some = mir_b_emit(&fn->b, MOP_OptView, &entry, 1, (MirImm){0}, opt_ty);
  mir_b_br(&fn->b, join, &some, 1);
  mir_b_switch_to(&fn->b, miss);
  const MirValue none = mir_b_emit(&fn->b, MOP_OptNone, NULL, 0, (MirImm){0}, opt_ty);
  mir_b_br(&fn->b, join, &none, 1);
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  return result;
}

static bool lower_bind(LowerFn *fn, const MsStmt *stmt) {
  const MsPattern *pattern = stmt->u.bind.pattern;
  if (pattern->kind != MS_P_NAME) {
    MirValue source = fn_expr(fn, stmt->u.bind.value, LW_BORROW);
    MirVar owner = 0;
    MirValue taken = MIR_NONE;
    if (source != MIR_NONE && stmt->u.bind.value->kind == MS_E_NAME &&
        fn_closing_move(fn, stmt->u.bind.value, source, &taken)) {
      /* A record destructured out of a closing slot hands its parts to the names: the slot gives the record up. */
      return fn_bind_parts(fn, pattern, taken, true, NULL, stmt->u.bind.is_mutable, false, ms_facts_type(fn->facts, stmt->u.bind.value->id));
    }
    const bool from_var = source != MIR_NONE && !stmt->u.bind.is_mutable && fn_owned_local(fn, stmt->u.bind.value, &owner);
    /* A `var` pattern takes its parts out of a record that is given up (a fresh result, or a name read for the last time)
     * instead of copying them: a resource part has no copy. */
    const bool gives_up = fn_fresh_owner(fn, source) ||
                          (stmt->u.bind.value->kind == MS_E_NAME && ms_facts_use(fn->facts, stmt->u.bind.value->id) == MS_USE_MOVE);
    /* A record of resources that holds nothing to drop is still given up when it is a temporary: its parts close here. */
    const MsExprKind kind = (MsExprKind)stmt->u.bind.value->kind;
    const bool temporary = source != MIR_NONE && kind != MS_E_NAME && kind != MS_E_MEMBER && kind != MS_E_INDEX &&
                           fn_temp_closes(fn, ms_facts_type(fn->facts, stmt->u.bind.value->id)) && fn_owns_result(fn, source);
    return source != MIR_NONE &&
           fn_bind_parts(fn, pattern, source, stmt->u.bind.is_mutable ? (!from_var && gives_up) : (from_var || fn_fresh_owner(fn, source) || temporary),
                      from_var ? &owner : NULL, stmt->u.bind.is_mutable, false,
                      ms_facts_type(fn->facts, stmt->u.bind.value->id));
  }
  if (stmt->u.bind.is_mutable && fn->closing != NULL) {
    /* `var x = xs[i]` and `var x = m[k]` borrow the entry exclusively, unless it is a number: `x` names the entry, so what is
     * changed through `x` changes the entry, whatever happens to the index or key afterwards. */
    MsExpr *container = NULL;
    MsExpr *key = NULL;
    const MsRef *ref = ms_facts_ref(fn->facts, pattern->id);
    const MirTy entry = fn_type(fn, ms_facts_type(fn->facts, pattern->id));
    if (ref != NULL && ref->kind == MS_REF_LOCAL && ref->local < fn->nvars && fn_entry_read_parts(fn, stmt->u.bind.value, &container, &key) &&
        mir_ty_data(fn->cx->module, entry)->kind != MK_VOID && !mir_is_scalar(fn->cx->module, entry)) {
      MirValue address = MIR_NONE;
      MirTy ty = MIR_VOID;
      if (fn_place_address(fn, stmt->u.bind.value, &address, &ty)) {
        fn->closing[ref->local] = address;
        fn->closing_var[ref->local] = true;
        fn->closing_types[ref->local] = ty;
        if (fn->shared != NULL) {
          fn->shared[ref->local] = LOWER_SHARED_BORROWED; /* the entry's owner holds it: a change here replaces it there */
        }
        return !fn->failed;
      }
      if (fn->failed) {
        return false;
      }
    }
  }
  /* A name bound to another name borrows it unless the checker marked the read a move (the source is assigned while
   * the binding lives); anything else, and every `var`, is a new owner. */
  const MsExprKind kind = (MsExprKind)stmt->u.bind.value->kind;
  MsExpr *index_container = NULL;
  MsExpr *index_key = NULL;
  /* A field of a call's result (`name := make().field`) leaves the temporary that dies with the statement. */
  const bool of_temporary = kind == MS_E_MEMBER && stmt->u.bind.value->u.member.left->kind == MS_E_CALL;
  bool borrow = !stmt->u.bind.is_mutable && !of_temporary &&
                (kind == MS_E_NAME || kind == MS_E_MEMBER || ms_expr_index(stmt->u.bind.value, &index_container, &index_key)) &&
                ms_facts_use(fn->facts, stmt->u.bind.value->id) != MS_USE_MOVE;
  const bool from_call = !stmt->u.bind.is_mutable && kind == MS_E_CALL;
  /* A function bound to a name may take the type that lets its omittable parameters be left out. */
  const MsTy bound_ty = ms_facts_type(fn->facts, pattern->id);
  const MirTy saved_hint = fn->hint;
  if (kind == MS_E_NAME && bound_ty != MS_TY_NONE && ms_ty_kind(&fn->cx->program->types, bound_ty) == MS_TY_FUNCTION) {
    fn->hint = fn_type(fn, bound_ty);
  }
  fn->moving_field = !borrow && !stmt->u.bind.is_mutable && kind == MS_E_MEMBER ? stmt->u.bind.value : NULL;
  fn->has_last_receiver = false;
  MirValue value = from_call ? fn_map_get_view(fn, stmt->u.bind.value) : MIR_NONE;
  if (value != MIR_NONE) {
    borrow = true;
  } else if (!fn->failed) {
    value = borrow || from_call ? fn_expr(fn, stmt->u.bind.value, LW_BORROW) : take_value(fn, stmt->u.bind.value);
  }
  fn->moving_field = NULL;
  const MsRef *bound_ref = value != MIR_NONE ? ms_facts_ref(fn->facts, pattern->id) : NULL;
  const MsParams *bound_params = bound_ref != NULL ? bound_value_params(fn, stmt->u.bind.value) : NULL;
  if (bound_params != NULL && fn->nbound_self < MS_COUNT_OF(fn->bound_self)) {
    /* A lambda or method value keeps the defaults of its parameters; one that reads `self` reads the receiver it captured. */
    fn->bound_self[fn->nbound_self].local = bound_ref->local;
    fn->bound_self[fn->nbound_self].params = bound_params;
    fn->bound_self[fn->nbound_self].vars = fn->has_last_receiver ? fn->last_vars : (LowerSubst){0};
    fn->bound_self[fn->nbound_self++].receiver = fn->has_last_receiver ? fn->last_receiver : MIR_NONE;
  }
  fn->has_last_receiver = false;
  if (from_call && value != MIR_NONE && fn_is_borrowed_view(fn, value)) { /* a call whose result borrows */
    if (call_reads_temporary(fn->facts, stmt->u.bind.value) &&
        fn_closer_for(fn, ms_facts_closer(fn->facts, pattern->id), ms_facts_type(fn->facts, pattern->id))) {
      /* A temporary resource closes where its statement ends: a part kept past it is taken out of the temporary. */
      const MirValue owned = fn_take_from_temporary(fn, stmt->u.bind.value, value);
      value = owned != MIR_NONE ? owned : fn_implicit_clone(fn, value, true);
    } else {
      borrow = true;
    }
  }
  fn->hint = saved_hint;
  if (value == MIR_NONE) {
    return false;
  }
  const MirTy ty = mir_b_ty(&fn->b, value);
  const uint32_t local = ms_facts_ref(fn->facts, pattern->id)->local;
  const MsCloser *closer = ms_facts_closer(fn->facts, pattern->id);
  /* A name that converts to a new value (a type to its Optional) owns that value, though it reads another name. */
  MirVar read = 0;
  /* A name read as the owning `var`'s current value is not a new value, whatever op wrote the `var` last. */
  const bool reads_var = borrow && kind == MS_E_NAME && fn_owned_local(fn, stmt->u.bind.value, &read) && var_owns(fn, read) &&
                         mir_b_use_var(&fn->b, read) == value;
  const bool fresh = !reads_var && (fn_fresh_owner(fn, value) || is_empty_optional(fn, value));
  const bool shared = stmt->u.bind.is_mutable && fn->shared != NULL && local < fn->nvars && fn->shared[local] != 0 &&
                      fn->closing != NULL;
  if (shared || ((!borrow || fresh) && fn_closer_for(fn, closer, ms_facts_type(fn->facts, pattern->id)) &&
                 (!mir_needs_drop(fn->cx->module, ty) || fresh))) {
    return fn_bind_closing_in(fn, fn->bind_scope != 0 ? fn->bind_scope - 1 : fn_scope(fn), local,
                              ms_facts_type(fn->facts, pattern->id), value, stmt->u.bind.is_mutable);
  }
  if ((stmt->u.bind.is_mutable || ((!borrow || fresh) && narrowed_local(fn, local, ty))) && mir_needs_drop(fn->cx->module, ty)) {
    if (local >= fn->nvars) {
      return fn_fail(fn, "a local binding is outside the function's locals");
    }
    fn->vars[local] = mir_b_declare_var(&fn->b, ty, MM_MOVE) + 1;
    fn_disown(fn, value);
    mir_b_def_var(&fn->b, fn->vars[local] - 1, value);
    return fn_scope_own_var(fn, fn->vars[local] - 1) && !fn->failed;
  }
  if (fn->local_owns != NULL && local < fn->nvars && (!borrow || fresh) && !stmt->u.bind.is_mutable &&
      mir_needs_drop(fn->cx->module, ty)) {
    fn->local_owns[local] = 1; /* a value the scope owns: an escaping closure may take it */
  } else if (fn->local_owns != NULL && local < fn->nvars && borrow && !fresh && !stmt->u.bind.is_mutable &&
             mir_needs_drop(fn->cx->module, ty)) {
    fn->local_owns[local] = 2; /* a view of another owner's value: moving it out copies it */
  }
  if (!stmt->u.bind.is_mutable && local < fn->nvars && fn->vars[local] == 0 && mir_needs_drop(fn->cx->module, ty)) {
    /* An owned binding that is never assigned again has one value everywhere it is read: no loop or join carries it
     * as a block parameter, which would hide the owner from a later move. */
    fn->vars[local] = mir_b_declare_single(&fn->b, ty, MM_BORROW) + 1;
  }
  if (!stmt->u.bind.is_mutable && local < fn->nvars && fn->vars[local] == 0 && mir_needs_drop(fn->cx->module, ty)) {
    /* An owned binding that is never assigned again has one value everywhere it is read: no loop or join carries it
     * as a block parameter, which would hide the owner from a later move. */
    fn->vars[local] = mir_b_declare_single(&fn->b, ty, MM_BORROW) + 1;
  }
  if (fn->bind_scope != 0 && fresh && !stmt->u.bind.is_mutable && mir_needs_drop(fn->cx->module, ty)) {
    /* The statement's temporaries close where it ends; the name it binds outlives them, so the scope outside owns it. */
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
    fn_own(fn, fn->bind_scope - 1, value);
  }
  mir_b_def_var(&fn->b, fn_local(fn, local, ty), value);
  return !fn->failed;
}

/* The variable a name place assigns to: a `var` local or a `var` parameter; false for any other place. */
bool fn_owned_local(LowerFn *fn, const MsExpr *place, MirVar *out) {
  const MsRef *ref = place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  if (ref == NULL) {
    return false;
  }
  if (fn_closing_at(fn, ref, place->u.sym) != UINT32_MAX) {
    return false; /* it lives in a slot: `closing_local` has it */
  }
  if (ref->kind == MS_REF_LOCAL && ref->local < fn->nvars && fn->vars[ref->local] != 0) {
    *out = fn->vars[ref->local] - 1;
    return true;
  }
  if (ref->kind != MS_REF_PARAM || fn->default_call != NULL || fn->param_vars == NULL) { /* a default's parameters are the callee's, a field default's are the record's: not this function's */
    return false;
  }
  if (fn->lambda != NULL) { /* a captured parameter is a variable of the closure body */
    for (uint32_t at = 0; at < fn->lambda->ncaptures; at++) {
      const LowerCapture *capture = &fn->lambda->captures[at];
      if (capture->kind == MS_REF_PARAM && capture->index == ref->local && capture->name == place->u.sym && !capture->shared) {
        *out = fn->cap_vars[at];
        return true;
      }
    }
  }
  if (var_owns(fn, fn->param_vars[ref->local])) {
    *out = fn->param_vars[ref->local]; /* a `move` parameter the body assigns into */
    return true;
  }
  for (uint32_t at = 0; at < fn->nvar_params; at++) {
    if (fn->var_params[at].var == fn->param_vars[ref->local]) {
      *out = fn->var_params[at].var;
      return true;
    }
  }
  return false;
}

/* A resource parameter lives in a slot its scope owns, and its variable is a view of that slot: the slot and
 * variable of the parameter `place` names, or false. */
bool fn_closing_param(const LowerFn *fn, const MsExpr *place, MirValue *slot, MirVar *var) {
  const MsRef *ref = place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  if (ref == NULL || ref->kind != MS_REF_PARAM || fn->closing == NULL ||
      fn->nvars + ref->local >= fn->nvars + LOWER_MAX_CLOSING_PARAMS || fn->closing[fn->nvars + ref->local] == MIR_NONE) {
    return false;
  }
  *slot = fn->closing[fn->nvars + ref->local];
  *var = fn->param_vars[ref->local];
  return true;
}

/* The slot of the `var` resource local a name place assigns in, or false. */
bool fn_closing_local(const LowerFn *fn, const MsExpr *place, MirValue *slot, MirTy *ty) {
  const MsRef *ref = place->kind == MS_E_NAME ? ms_facts_ref(fn->facts, place->id) : NULL;
  const uint32_t at = fn_closing_at(fn, ref, place->u.sym);
  if (at == UINT32_MAX) {
    return false;
  }
  *slot = fn->closing[at];
  *ty = fn->closing_types[at];
  return true;
}

/* Whether `expr` is a List (an index into one is an element place; a Map's entry is read out as a copy). */
bool fn_is_list(LowerFn *fn, const MsExpr *expr) {
  MsTyTable *types = &fn->cx->program->types;
  const MsTy owner = ms_ty_subst(types, ms_facts_type(fn->facts, expr->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  return ms_ty_is(types, owner, MS_BUILTIN_List);
}

/* Whether `place` is a `var` local, a `var` parameter or a member path rooted in one: the places `fn_put_place` stores into. */
bool fn_place_changeable(LowerFn *fn, const MsExpr *place) {
  MirVar var;
  MirValue slot;
  MirTy ty;
  if (place == NULL) {
    return false;
  }
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (ms_expr_index(place, &container, &key)) { /* an element of a changeable place changes with it */
    return fn_place_changeable(fn, container);
  }
  return fn_owned_local(fn, place, &var) || fn_closing_local(fn, place, &slot, &ty) || fn_closing_param(fn, place, &slot, &var) ||
         (place->kind == MS_E_MEMBER && fn_place_changeable(fn, place->u.member.left));
}

bool fn_try_place_changeable(LowerFn *fn, const MsExpr *place) {
  if (fn_place_changeable(fn, place)) {
    return true;
  }
  const MsExpr *base = place != NULL && place->kind == MS_E_MEMBER ? place->u.member.left : NULL;
  return base != NULL && base->kind == MS_E_UNARY && base->op == MS_U_TRY && fn_try_place_changeable(fn, base->u.bin.left);
}

bool fn_place_owns(LowerFn *fn, const MsExpr *place) {
  MirVar var;
  MirValue slot;
  MirTy ty;
  if (place->kind == MS_E_MEMBER) {
    return fn_place_owns(fn, place->u.member.left);
  }
  return fn_closing_local(fn, place, &slot, &ty) ? mir_needs_drop(fn->cx->module, ty) : fn_owned_local(fn, place, &var) && var_owns(fn, var);
}

/* The owned value of `base`, a place a part of it is assigned in: an owning local's value is taken out (stored
 * back by `fn_put_place`), a member or element path's value is copied. */
bool fn_take_place(LowerFn *fn, const MsExpr *base, MirValue *out) {
  uint32_t position;
  if (fn_default_param_place(fn, base, &position)) {
    *out = fn->default_args[position]; /* the value the call passes: the default changes it and `fn_put_place` hands the change back */
    return true;
  }
  MirVar var;
  if (fn_owned_local(fn, base, &var)) {
    *out = mir_b_use_var(&fn->b, var);
    return true;
  }
  MirValue slot;
  MirTy slot_ty;
  if (fn_closing_local(fn, base, &slot, &slot_ty)) {
    if (mir_needs_drop(fn->cx->module, slot_ty)) {
      /* The value is lent out: its owner now is whoever holds it, and the slot closes it again once `fn_put_place`
       * refills it. A cancellation while it is out must not close the bytes the borrower is changing. */
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &slot, 1, (MirImm){0}, MIR_NONE);
    }
    *out = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slot_ty) ? MOP_Take : MOP_Load, &slot, 1,
                      (MirImm){.tag = MI_TY, .a = slot_ty}, slot_ty);
    return true;
  }
  if (fn_closing_param(fn, base, &slot, &var)) {
    const MirTy ty = fn->b.vars.ptr[var].ty; /* the declared type: reading the variable would carry it through every loop */
    *out = mir_b_emit(&fn->b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
    return true;
  }
  MsExpr *index_left = NULL;
  MsExpr *index_key = NULL;
  if (base->kind != MS_E_MEMBER && !ms_expr_index(base, &index_left, &index_key)) {
    return fn_fail(fn, "assignment into this place is not lowered yet (expression kind %d at %u:%u)", (int)base->kind, base->pos.line, base->pos.column);
  }
  const MirValue inner = fn_expr(fn, base, LW_BORROW);
  if (inner == MIR_NONE) {
    return false;
  }
  *out = fn_implicit_clone(fn, inner, true);
  fn_disown(fn, *out);
  return true;
}

/* `base.field = value` where `base` is an owning local or a member path: the record is taken out of its place
 * (a path's inner record is copied), the old field is dropped, `type.set` makes the updated record and that is
 * stored back into the place of `base`. `value` is owned and held by no scope. */
static bool set_member(LowerFn *fn, const MsExpr *place, MirValue value) {
  const MsRef *ref = ms_facts_ref(fn->facts, place->id);
  const MsExpr *base = place->u.member.left;
  if (ref == NULL || ref->kind != MS_REF_FIELD) {
    return fn_fail(fn, "this member is not a record field");
  }
  MirValue record = MIR_NONE;
  if (!fn_take_place(fn, base, &record)) {
    return false;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, record));
  if (data->kind != MK_TYPE) {
    return fn_fail(fn, "a field is assigned in a record (found MIR kind %d)", (int)data->kind);
  }
  const MirImm imm = {.tag = MI_FIELD, .a = data->id, .b = ref->index};
  const MirTy field_ty = fn_type(fn, ms_facts_type(fn->facts, place->id));
  bool moved_out = false; /* an earlier bind took the field: there is nothing to drop */
  for (uint32_t at = 0; at < fn->nmoved_fields; at++) {
    if (fn_same_member_path(fn, fn->moved_fields[at], place)) {
      moved_out = true;
      fn->moved_fields[at] = fn->moved_fields[--fn->nmoved_fields];
      break;
    }
  }
  if (!moved_out && mir_needs_drop(fn->cx->module, field_ty)) {
    /* The field's old value leaves the record before it is dropped or closed: `type.set` fills the hole. */
    const MirValue view = mir_b_emit(&fn->b, MOP_TypeGet, &record, 1, imm, field_ty);
    const MirValue old = mir_b_emit(&fn->b, MOP_MoveOut, &view, 1, (MirImm){0}, field_ty);
    const MsTy checked = ms_facts_type(fn->facts, place->id);
    if (fn_closer_for(fn, ms_facts_closer(fn->facts, place->id), checked)) {
      if (!fn_close_replaced(fn, checked, old)) { /* a resource the assignment replaces closes, it is not dropped */
        return false;
      }
    } else {
      (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
    }
  }
  const MirValue operands[2] = {record, value};
  const MirValue updated = mir_b_emit(&fn->b, MOP_TypeSet, operands, 2, imm, mir_b_ty(&fn->b, record));
  return fn_put_place(fn, base, updated);
}

/* `container[key] = value` for an element of a list or map the enclosing assignment took a copy of: the container's
 * own `set` (a list) or `add` (a map) stores it. */
static bool set_element(LowerFn *fn, const MsExpr *container, const MsExpr *key, MirValue value) {
  MsTyTable *types = &fn->cx->program->types;
  const MsTy owner = ms_ty_subst(types, ms_facts_type(fn->facts, container->id), fn->subst.vars, fn->subst.args, fn->subst.count);
  const MirValue receiver = fn_expr(fn, container, LW_BORROW);
  const MirValue at = receiver == MIR_NONE ? MIR_NONE : fn_expr(fn, key, LW_BORROW);
  if (at == MIR_NONE) {
    return false;
  }
  const bool map = ms_ty_is(types, owner, MS_BUILTIN_Map);
  /* A map stores its key as well: the key is the container's own copy, not the borrow the statement read. */
  const MirValue stored_key = map && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, at)) ? fn_implicit_clone(fn, at, true) : at;
  if (stored_key == MIR_NONE) {
    return false;
  }
  const MirValue args[3] = {receiver, stored_key, value};
  MirValue out = MIR_NONE;
  const MsSpan operation = ms_span_of_text(map ? "add" : "set");
  fn->native_arg_moves = (map && stored_key != at ? 1u << 1 : 0u) | (1u << 2); /* the stored value (and key) are owned and held by no scope: the container takes them */
  const bool done = fn_native_on(fn, container, owner, operation, 3, args, MIR_VOID, &out);
  fn->native_arg_moves = 0;
  if (!done) {
    return fn_fail(fn, "an element of this container cannot be assigned yet");
  }
  return !fn->failed;
}

/* Stores the owned `value` (held by no scope) into `place`, the place of an earlier `fn_take_place`. */
bool fn_put_place(LowerFn *fn, const MsExpr *place, MirValue value) {
  uint32_t position;
  if (fn_default_param_place(fn, place, &position)) {
    fn->default_args[position] = value;
    return true;
  }
  MirVar var;
  if (place->kind == MS_E_MEMBER) {
    return set_member(fn, place, value);
  }
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  if (ms_expr_index(place, &container, &key)) {
    return set_element(fn, container, key, value);
  }
  MirValue slot;
  MirTy slot_ty;
  if (fn_closing_local(fn, place, &slot, &slot_ty)) {
    const MirValue stored[2] = {slot, value};
    if (mir_needs_drop(fn->cx->module, slot_ty)) {
      const MirImm refill = {.tag = MI_INT, .i = 3}; /* the lent value comes back */
      (void)mir_b_emit(&fn->b, MOP_ScopeMark, &slot, 1, refill, MIR_NONE);
    }
    (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, slot_ty) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
    return !fn->failed;
  }
  if (fn_closing_param(fn, place, &slot, &var)) {
    const MirTy ty = mir_b_ty(&fn->b, value);
    const MirValue stored[2] = {slot, value};
    (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
    mir_b_def_var(&fn->b, var, mir_b_emit(&fn->b, MOP_Load, &slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty));
    return !fn->failed;
  }
  if (!fn_owned_local(fn, place, &var)) {
    return fn_fail(fn, "an assignment does not name an owning local");
  }
  mir_b_def_var(&fn->b, var, value);
  return !fn->failed;
}

/* `m[key] op= value` on a map: the compound assignment read the entry, so it exists and the new value replaces the
 * old one at the entry's address; the key is not stored again, so it is not copied. False when `place` is not a map entry. */
static bool update_map_entry(LowerFn *fn, const MsExpr *place, MirValue value, bool *done) {
  MsExpr *container = NULL;
  MsExpr *key = NULL;
  *done = false;
  if (!ms_expr_index(place, &container, &key)) {
    return true;
  }
  const MirValue map = fn_expr(fn, container, LW_BORROW);
  if (map == MIR_NONE) {
    return false;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, map));
  if (data->kind != MK_OBJ || data->obj_class != MIR_OBJ_COLLECTION || data->nargs < 2) {
    return true;
  }
  MirTy entry_ty = MIR_VOID;
  const MirValue address = fn_entry_address(fn, map, key, &entry_ty);
  if (address == MIR_NONE) {
    return false;
  }
  const bool owns = mir_needs_drop(fn->cx->module, entry_ty);
  if (owns) {
    const MirValue old = mir_b_emit(&fn->b, MOP_Take, &address, 1, (MirImm){.tag = MI_TY, .a = entry_ty}, entry_ty);
    (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
  }
  const MirValue stored[2] = {address, value};
  (void)mir_b_emit(&fn->b, owns ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
  *done = true;
  return !fn->failed;
}

/* Whether `view` is the result of a call that borrows `owner` (`n := cur.get()` views the payload of `cur`). */
static bool is_load_of(const LowerFn *fn, MirValue value, MirValue slot) {
  for (size_t block = 0; block < fn->b.func.blocks.len; block++) {
    const MirInstList *insts = &fn->b.func.blocks.ptr[block].insts;
    for (size_t at = 0; at < insts->len; at++) {
      if (insts->ptr[at].res == value) {
        return insts->ptr[at].op == MOP_Load && insts->ptr[at].nargs == 1 && insts->ptr[at].args[0] == slot;
      }
    }
  }
  return false;
}

/* `owner` is the value itself, or (`slot` set) any load of the slot that holds it. */
static bool views_payload_in(const LowerFn *fn, MirValue view, MirValue owner, MirValue slot) {
  for (size_t block = 0; block < fn->b.func.blocks.len; block++) {
    const MirInstList *insts = &fn->b.func.blocks.ptr[block].insts;
    for (size_t at = 0; at < insts->len; at++) {
      const MirInst *inst = &insts->ptr[at];
      if (inst->res == view) {
        MirMode mode = MM_MOVE;
        return inst->nargs != 0 && (inst->args[0] == owner || (slot != MIR_NONE && is_load_of(fn, inst->args[0], slot))) &&
               mir_result_mode(fn->cx->module, &fn->b.func, inst, &mode) && mode == MM_BORROW;
      }
    }
  }
  return false;
}

static bool views_payload_of(const LowerFn *fn, MirValue view, MirValue owner) {
  return views_payload_in(fn, view, owner, MIR_NONE);
}

/* `cur = n.next` where `n` views the payload of the owning Optional `cur`: the old payload leaves `cur`, its field
 * moves into the new value and the rest of it is released, so a walk along a list does not copy what is left of it.
 * `value` is the new value, or MIR_NONE when the assignment is not that shape. */
static MirValue take_field_of_old(LowerFn *fn, const MsStmt *stmt, MirVar var) {
  const MsExpr *member = stmt->u.assign.value;
  const MsRef *ref = member->kind == MS_E_MEMBER ? ms_facts_ref(fn->facts, member->id) : NULL;
  if (ref == NULL || ref->kind != MS_REF_FIELD || ms_facts_use(fn->facts, member->id) != MS_USE_MOVE || !var_owns(fn, var)) {
    return MIR_NONE;
  }
  const MirValue old = mir_b_use_var(&fn->b, var);
  const MirTyData *old_data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, old));
  if (old_data->kind != MK_OPT || !mir_needs_drop(fn->cx->module, old_data->elem)) {
    return MIR_NONE;
  }
  const MirValue view = fn_expr(fn, member->u.member.left, LW_BORROW);
  if (view == MIR_NONE || !views_payload_of(fn, view, old)) {
    return MIR_NONE;
  }
  const MirTy elem = old_data->elem;
  const MirTyData *record = mir_ty_data(fn->cx->module, elem);
  if (record->kind != MK_TYPE) {
    return MIR_NONE;
  }
  const MirImm imm = {.tag = MI_FIELD, .a = record->id, .b = ref->index};
  const MirValue item = mir_b_emit(&fn->b, MOP_OptUnbox, &old, 1, (MirImm){0}, elem);
  const MirTy field_ty = fn_type(fn, ms_facts_type(fn->facts, member->id));
  const MirValue field = mir_b_emit(&fn->b, MOP_TypeGet, &item, 1, imm, field_ty);
  const MirValue taken = mir_b_emit(&fn->b, MOP_MoveOut, &field, 1, (MirImm){0}, field_ty);
  const MirImm mask = {.tag = MI_TYPEMASK, .a = record->id, .b = ref->index < 32 ? UINT32_C(1) << ref->index : 0};
  (void)mir_b_emit(&fn->b, MOP_TypeRelease, &item, 1, mask, MIR_NONE);
  return taken;
}

/* `cur = n.next` where `cur` lives in a closing slot: as `take_field_of_old`, the payload leaves the slot, its field
 * is the new value and the rest of it is released. Returns whether the assignment was lowered. */
static bool take_field_into_slot(LowerFn *fn, const MsStmt *stmt, const MsRef *ref, MsName name, bool *done) {
  *done = false;
  const uint32_t at = fn_closing_at(fn, ref, name);
  const MsExpr *member = stmt->u.assign.value;
  const MsRef *field = member->kind == MS_E_MEMBER ? ms_facts_ref(fn->facts, member->id) : NULL;
  if (at == UINT32_MAX || field == NULL || field->kind != MS_REF_FIELD || stmt->u.assign.has_compound ||
      ms_facts_use(fn->facts, member->id) != MS_USE_MOVE ||
      (fn->shared != NULL && ref->kind == MS_REF_LOCAL && fn->shared[ref->local] != 0)) {
    return true;
  }
  const MirValue slot = fn->closing[at];
  const MirTy old_ty = fn->closing_types[at];
  const MirTyData *old_data = mir_ty_data(fn->cx->module, old_ty);
  if (old_data->kind != MK_OPT || !mir_needs_drop(fn->cx->module, old_data->elem) ||
      mir_ty_data(fn->cx->module, old_data->elem)->kind != MK_TYPE) {
    return true;
  }
  const MirValue view = fn_expr(fn, member->u.member.left, LW_BORROW);
  if (view == MIR_NONE || !views_payload_in(fn, view, MIR_NONE, slot)) {
    return !fn->failed;
  }
  const MirTy elem = old_data->elem;
  const MirTyData *record = mir_ty_data(fn->cx->module, elem);
  const MirImm imm = {.tag = MI_FIELD, .a = record->id, .b = field->index};
  const MirValue old = mir_b_emit(&fn->b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = old_ty}, old_ty);
  const MirValue item = mir_b_emit(&fn->b, MOP_OptUnbox, &old, 1, (MirImm){0}, elem);
  const MirTy field_ty = fn_type(fn, ms_facts_type(fn->facts, member->id));
  const MirValue got = mir_b_emit(&fn->b, MOP_TypeGet, &item, 1, imm, field_ty);
  const MirValue taken = mir_b_emit(&fn->b, MOP_MoveOut, &got, 1, (MirImm){0}, field_ty);
  const MirImm mask = {.tag = MI_TYPEMASK, .a = record->id, .b = field->index < 32 ? UINT32_C(1) << field->index : 0};
  (void)mir_b_emit(&fn->b, MOP_TypeRelease, &item, 1, mask, MIR_NONE);
  const MirValue stored[2] = {slot, taken};
  (void)mir_b_emit(&fn->b, MOP_Put, stored, 2, (MirImm){0}, MIR_NONE);
  *done = !fn->failed;
  return !fn->failed;
}

static bool lower_assign(LowerFn *fn, const MsStmt *stmt) {
  if (stmt->u.assign.member_target) {
    fn_presolve_keys(fn, stmt->u.assign.target); /* the target's indices run before the value, once */
    const MirValue value = take_value(fn, stmt->u.assign.value);
    if (value == MIR_NONE) {
      return false;
    }
    if (mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value))) {
      fn_disown(fn, value);
    }
    bool done = false;
    if (stmt->u.assign.has_compound && (!update_map_entry(fn, stmt->u.assign.target, value, &done) || done)) {
      return done && !fn->failed;
    }
    return fn_put_place(fn, stmt->u.assign.target, value);
  }
  /* A name target records its local on the statement, a member target on its expression. */
  const MsRef *ref = ms_facts_ref(fn->facts, stmt->u.assign.target != NULL ? stmt->u.assign.target->id : stmt->id);
  MirVar var = 0;
  bool resource = false;
  const MsName assigned = stmt->u.assign.target != NULL && stmt->u.assign.target->kind == MS_E_NAME ? stmt->u.assign.target->u.sym : stmt->u.assign.name;
  if (fn_closing_at(fn, ref, assigned) != UINT32_MAX) {
    bool lowered = false;
    if (!take_field_into_slot(fn, stmt, ref, assigned, &lowered) || lowered) {
      return lowered;
    }
    const MirValue value = take_value(fn, stmt->u.assign.value);
    const uint32_t target_id = stmt->u.assign.target != NULL ? stmt->u.assign.target->id : stmt->id;
    return value != MIR_NONE && fn_closing_assign(fn, ref, assigned, ms_facts_type(fn->facts, target_id), value, &resource);
  }
  if (ref != NULL && ref->kind == MS_REF_LOCAL && ref->local < fn->nvars && fn->vars[ref->local] != 0) {
    var = fn->vars[ref->local] - 1;
  } else if (ref != NULL && ref->kind == MS_REF_PARAM) {
    var = fn->param_vars[ref->local];
  } else {
    return fn_fail(fn, "an assignment does not name a local");
  }
  fn->nmoved_names = 0;
  fn->refilling_var = var + 1;
  const MirValue advanced = take_field_of_old(fn, stmt, var);
  fn->refilling_var = advanced != MIR_NONE ? 0 : fn->refilling_var;
  if (advanced != MIR_NONE) { /* the old value is gone: nothing is left to drop */
    mir_b_def_var(&fn->b, var, advanced);
    return !fn->failed;
  }
  const MirValue value = take_value(fn, stmt->u.assign.value);
  fn->refilling_var = 0;
  if (value == MIR_NONE) {
    return false;
  }
  if (var_owns(fn, var)) {
    const MirValue old = mir_b_use_var(&fn->b, var);
    fn_disown(fn, value);
    bool handed_on = false; /* `x = f(x)` moved the old value into the new one */
    for (uint32_t at = 0; at < fn->nmoved_names; at++) {
      handed_on |= fn->moved_names[at] == old;
    }
    const uint32_t target_id = stmt->u.assign.target != NULL ? stmt->u.assign.target->id : stmt->id;
    const MsTy checked = ms_facts_type(fn->facts, target_id);
    if (handed_on) {
      /* nothing is left to release */
    } else if (checked != MS_TY_NONE && ms_own_closer_of(fn->cx->program, ms_ty_subst(&fn->cx->program->types, checked, fn->subst.vars,
                                                                                         fn->subst.args, fn->subst.count),
                                                         &(MsCloser){0})) {
      if (!fn_close_replaced(fn, checked, old)) { /* a resource the assignment replaces closes, it is not dropped */
        return false;
      }
    } else {
      (void)mir_b_emit(&fn->b, MOP_Drop, &old, 1, (MirImm){0}, MIR_NONE);
    }
  }
  /* A compound assignment's value already reads the target (`a += b` is `a = a + b`). */
  mir_b_def_var(&fn->b, var, value);
  return !fn->failed;
}

/* What a function returns when it ends without a value: nothing, except the entry declared Void, which returns
 * the status 0. */
MirValue fn_default_result(LowerFn *fn) {
  if (mir_ty_data(fn->cx->module, fn->ret)->kind == MK_OPT) {
    return mir_b_emit(&fn->b, MOP_OptNone, NULL, 0, (MirImm){0}, fn->ret); /* an Optional function that returns nothing returns none */
  }
  return fn->ret == MIR_INT && fn->b.func.ret == MIR_INT && fn->decl_void ? mir_b_iconst(&fn->b, 0) : MIR_NONE;
}

/* A view lender's `return`: the value is read where it lives, and a reference to an interface value somebody else owns
 * (a parameter, a field of one, an element) is boxed by `iface.own`, so the caller owns a box of its own and never the
 * payload. A moved name, a fresh value and another lender's result are already owned. */
static MirValue view_return(LowerFn *fn, const MsExpr *expr) {
  const bool place = expr->kind == MS_E_NAME || expr->kind == MS_E_MEMBER || expr->kind == MS_E_INDEX;
  if (place && ms_facts_use(fn->facts, expr->id) == MS_USE_MOVE) {
    return take_value(fn, expr);
  }
  const MirValue value = fn_expr(fn, expr, LW_BORROW);
  if (value == MIR_NONE || fn->terminated || fn_fresh_owner(fn, value)) {
    return value;
  }
  const MirTy ty = mir_b_ty(&fn->b, value);
  if (mir_ty_data(fn->cx->module, ty)->kind == MK_IFACE) {
    return fn_emit(fn, MOP_IfaceOwn, &value, 1, (MirImm){0}, ty);
  }
  /* An optional interface that is a reference is copied whole: the copy owns its payload. */
  return mir_needs_drop(fn->cx->module, ty) ? fn_implicit_clone(fn, value, true) : value;
}

static bool lower_return(LowerFn *fn, const MsStmt *stmt) {
  MirValue value = MIR_NONE;
  if (stmt->u.expr != NULL) {
    value = fn->returns_borrow ? fn_expr(fn, stmt->u.expr, LW_BORROW) : fn->returns_view ? view_return(fn, stmt->u.expr) : take_value(fn, stmt->u.expr);
    if (fn->terminated) { /* the expression never returns: `return panic(...)` */
      return !fn->failed;
    }
    if (value == MIR_NONE) {
      return false;
    }
    const MirImm none = {0};
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, none, MIR_NONE);
  }
  value = fn_result_wrap(fn, value);
  /* `return x` over an owning `var` hands its value on: the unwind must not own it again. */
  MirVar returned = 0;
  const bool hands_on = stmt->u.expr != NULL && stmt->u.expr->kind == MS_E_NAME && value != MIR_NONE &&
                        ms_facts_use(fn->facts, stmt->u.expr->id) == MS_USE_MOVE && fn_owned_local(fn, stmt->u.expr, &returned) &&
                        mir_b_use_var(&fn->b, returned) == value;
  if (hands_on) {
    fn_scope_var_released(fn, returned, true);
  }
  fn_scope_unwind(fn, 0);
  if (hands_on) {
    fn_scope_var_released(fn, returned, false);
  }
  mir_b_ret(&fn->b, value == MIR_NONE ? fn_default_result(fn) : value);
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
  MsExpr *probe_left = NULL;
  MsExpr *probe_key = NULL;
  const bool probes = fn_probe_parts(fn, stmt, &probe_left, &probe_key);
  bool owns = !probes && stmt->u.branch.binding != NULL && fn_iflet_owns(fn, stmt);
  const bool from_call = stmt->u.branch.cond->kind == MS_E_CALL;
  MirValue entry = MIR_NONE;
  MirTy entry_ty = MIR_VOID;
  MirValue cond = MIR_NONE;
  if (probes) {
    if (!fn_probe_begin(fn, stmt, &cond, &entry, &entry_ty)) {
      return false;
    }
  } else {
    MirValue tested = fn_expr(fn, stmt->u.branch.cond, owns && !from_call ? LW_MOVE : LW_BORROW);
    if (owns && from_call && tested != MIR_NONE && fn_is_borrowed_view(fn, tested)) {
      /* A call that answers a part of something else is a view, unless it answers a temporary the binding can take. */
      const MirValue taken = fn_take_from_temporary(fn, stmt->u.branch.cond, tested);
      owns = taken != MIR_NONE;
      tested = owns ? taken : tested;
      if (owns && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, tested))) {
        fn_own(fn, fn_scope(fn), tested); /* the payload taken from the temporary is the scope's until the branch binds it */
      }
    }
    if (owns && stmt->u.branch.cond->kind == MS_E_NAME && tested != MIR_NONE) {
      fn_own_result(fn, tested); /* the payload leaves the taken value in the branch that binds it */
    }
    cond = stmt->u.branch.binding != NULL && tested != MIR_NONE ? fn_iflet_test(fn, tested) : tested;
    entry = tested;
  }
  if (fn->terminated) { /* the condition never returns (`if panic(...):`): nothing is tested and nothing follows */
    return !fn->failed;
  }
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
  (void)fn_scope_begin(fn);
  if (probes && !fn_probe_bind(fn, stmt, entry, entry_ty)) {
    return false;
  }
  if (!probes && stmt->u.branch.binding != NULL && !fn_iflet_bind(fn, stmt->u.branch.binding, entry, owns)) {
    return false;
  }
  bool ok = fn_stmts(fn, stmt->u.branch.body);
  if (probes) {
    fn_probe_end(fn, !fn->terminated);
  }
  if (!fn->terminated) {
    fn_scope_end(fn);
  } else {
    fn->nopen--;
  }
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
  /* What the condition makes (a constant list read, a copy) lives for one trip: it goes before the test branches. */
  (void)fn_scope_begin(fn);
  const bool saved_temps = fn->temps;
  fn->temps = saved_temps || fn_expr_has_temporary(fn, stmt->u.loop.cond); /* its temporaries close on each trip */
  const MirValue cond = fn_expr(fn, stmt->u.loop.cond, LW_BORROW);
  fn->temps = saved_temps;
  if (cond == MIR_NONE) {
    return false;
  }
  fn_scope_end(fn);
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

/* An expression statement discards its value; a fresh resource that value holds closes with the scope. */
static MsTy discarded_type(LowerFn *fn, const MsExpr *expr) {
  return ms_ty_subst(&fn->cx->program->types, ms_facts_type(fn->facts, expr->id), fn->subst.vars, fn->subst.args,
                     fn->subst.count);
}

static bool lower_call_stmt(LowerFn *fn, const MsStmt *stmt) {
  const MsExpr *expr = stmt->u.expr;
  const MirValue value = fn_expr(fn, expr, LW_BORROW);
  if (value == MIR_NONE) {
    return !fn->failed;
  }
  if (stmt == fn->sink_stmt && mir_b_ty(&fn->b, value) != MIR_VOID) {
    fn_bench_sink(fn, value);
  }
  const MsTy checked = discarded_type(fn, expr);
  const bool owned = fn_fresh_owner(fn, value) ||
                     (!mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value)) && !fn_is_borrowed_view(fn, value));
  if (expr->kind == MS_E_CALL && checked != MS_TY_NONE && owned && fn_temp_closes(fn, checked)) {
    fn_own_temporary(fn, checked, value);
  }
  return !fn->failed;
}

static bool lower_stmt(LowerFn *fn, const MsStmt *stmt) {
  fn->stmt_loc = fn_loc(fn, stmt->pos);
  mir_b_set_loc(&fn->b, fn->stmt_loc);
  fn->npresolved = 0;
  switch ((MsStmtKind)stmt->kind) {
    case MS_S_BIND: return lower_bind(fn, stmt);
    case MS_S_ASSIGN: return lower_assign(fn, stmt);
    case MS_S_CALL: return lower_call_stmt(fn, stmt);
    case MS_S_RETURN: return lower_return(fn, stmt);
    case MS_S_BREAK: return lower_jump(fn, true);
    case MS_S_CONTINUE: return lower_jump(fn, false);
    case MS_S_IF: return lower_if(fn, stmt);
    case MS_S_WHILE: return lower_while(fn, stmt);
    case MS_S_FOR: return fn_for(fn, stmt);
  }
  return fn_fail(fn, "unknown statement");
}

/* A statement whose calls borrow temporary resources lowers in a scope of its own: they close where it ends. */
static bool lower_scoped(LowerFn *fn, const MsStmt *stmt) {
  const bool discards = stmt->kind == MS_S_CALL && stmt->u.expr->kind == MS_E_CALL && fn->closing != NULL &&
                        discarded_type(fn, stmt->u.expr) != MS_TY_NONE && fn_temp_closes(fn, discarded_type(fn, stmt->u.expr));
  if (fn->temps || !(discards || fn_stmt_has_temporary(fn, stmt))) {
    return lower_stmt(fn, stmt);
  }
  fn->bind_scope = stmt->kind == MS_S_BIND ? fn_scope(fn) + 1 : 0;
  (void)fn_scope_begin(fn);
  fn->temps = true;
  const bool ok = lower_stmt(fn, stmt);
  fn->temps = false;
  fn->bind_scope = 0;
  if (!fn->terminated) {
    fn_scope_end(fn);
  } else {
    fn->nopen--;
  }
  return ok;
}

bool fn_stmts(LowerFn *fn, MsStmts stmts) {
  for (uint32_t index = 0; index < stmts.len && !fn->terminated; index++) {
    if (!lower_scoped(fn, stmts.ptr[index])) {
      return false;
    }
  }
  return true;
}
