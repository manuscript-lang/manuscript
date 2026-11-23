/* compiler/lower/lower_iflet.c: `if x := value:`. The test says whether the value holds a payload (an Optional is
 * some, a Result is ok); the then branch binds the payload to the pattern's local. */
#include "compiler/lower/lower_fn.h"

/* The alternative case that holds the payload: a Result's `ok`, which is its first case. */
enum { OK_CASE = 0 };

/* The scrutinee's MIR type kind, after reporting a failure for one that holds no payload. */
static bool holds_payload(LowerFn *fn, MirValue value) {
  const MirModule *module = fn->cx->module;
  const MirTyData *data = mir_ty_data(module, mir_b_ty(&fn->b, value));
  if (data->kind == MK_OPT) {
    return true;
  }
  if (data->kind == MK_ALT && module->alts.ptr[data->id].std == MSTD_RESULT) {
    return true;
  }
  return fn_fail(fn, "`if` with a binding tests an Optional or a Result");
}

MirValue fn_iflet_test(LowerFn *fn, MirValue value) {
  if (!holds_payload(fn, value)) {
    return MIR_NONE;
  }
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, value));
  if (data->kind == MK_OPT) {
    return mir_b_emit(&fn->b, MOP_OptIsSome, &value, 1, (MirImm){0}, MIR_BOOL);
  }
  const MirValue tag = mir_b_emit(&fn->b, MOP_AltTag, &value, 1, (MirImm){0}, MIR_INT);
  return mir_b_icmp(&fn->b, MCC_EQ, tag, mir_b_iconst(&fn->b, OK_CASE));
}

bool fn_iflet_owns(LowerFn *fn, const MsStmt *stmt) {
  const MsExpr *cond = stmt->u.branch.cond;
  /* A call's result, or a name the statement moves, is the binding's to own: the payload leaves the temporary. */
  const bool fresh = cond->kind == MS_E_CALL ||
                     (cond->kind == MS_E_NAME && (ms_facts_use(fn->facts, cond->id) == MS_USE_MOVE ||
                                                  (fn->facts->last != NULL && fn->facts->last[cond->id] != 0)));
  /* A `var` binding of a name writes back to what it names; a call's result has nothing to write back to. */
  const bool writes_back = stmt->u.branch.is_mutable && cond->kind != MS_E_CALL;
  return fresh && !writes_back && stmt->u.branch.binding->kind == MS_P_NAME;
}

/* The payload of the Optional or Result `value`, taken out of it: `value` is released but for the payload. */
MirValue fn_take_payload(LowerFn *fn, MirValue value, MirTy *ty) {
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, value));
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
  if (data->kind == MK_OPT) {
    *ty = data->elem;
    return mir_b_emit(&fn->b, MOP_OptUnbox, &value, 1, (MirImm){0}, *ty);
  }
  *ty = fn->cx->module->alts.ptr[data->id].cases[OK_CASE].fields[0].ty;
  const MirImm field = {.tag = MI_ALTFIELD, .a = data->id, .b = OK_CASE, .c = 0};
  const MirValue payload = mir_b_emit(&fn->b, MOP_AltTake, &value, 1, field, *ty);
  const MirImm taken = {.tag = MI_ALTMASK, .a = data->id, .b = OK_CASE, .c = 1};
  (void)mir_b_emit(&fn->b, MOP_AltRelease, &value, 1, taken, MIR_NONE);
  return payload;
}

bool fn_iflet_bind(LowerFn *fn, const MsPattern *pattern, MirValue value, bool owns) {
  const MsRef *ref = ms_facts_ref(fn->facts, pattern->id);
  if (pattern->kind != MS_P_NAME || ref == NULL || ref->kind != MS_REF_LOCAL) {
    return fn_fail(fn, "only a name can be bound by `if` for now");
  }
  const MirModule *module = fn->cx->module;
  const MirTyData *data = mir_ty_data(module, mir_b_ty(&fn->b, value));
  MirValue payload = MIR_NONE;
  MirTy ty = MIR_VOID;
  if (owns) {
    payload = fn_take_payload(fn, value, &ty);
    const MsTy checked = ms_facts_type(fn->facts, pattern->id);
    if (fn_closer_for(fn, ms_facts_closer(fn->facts, pattern->id), checked)) {
      return fn_bind_closing(fn, ref->local, checked, payload, false);
    }
    if (mir_needs_drop(module, ty)) {
      fn_own(fn, fn_scope(fn), payload);
      if (fn->local_owns != NULL && ref->local < fn->nvars) {
        fn->local_owns[ref->local] = 1; /* a value the scope owns: an escaping closure may take it */
      }
    }
    mir_b_def_var(&fn->b, fn_local(fn, ref->local, ty), payload);
    return !fn->failed;
  }
  if (data->kind == MK_OPT) {
    ty = data->elem;
    payload = mir_b_emit(&fn->b, MOP_OptGet, &value, 1, (MirImm){0}, ty);
  } else {
    const MirCaseDef *ok = &module->alts.ptr[data->id].cases[OK_CASE];
    ty = ok->nfields > 0 ? ok->fields[0].ty : MIR_VOID;
    const MirImm imm = {.tag = MI_ALTFIELD, .a = data->id, .b = OK_CASE, .c = 0};
    payload = mir_b_emit(&fn->b, MOP_AltGet, &value, 1, imm, ty);
  }
  mir_b_def_var(&fn->b, fn_local(fn, ref->local, ty), payload);
  return !fn->failed;
}

/* The container and key an `if` that edits an entry names: `if var name = place[key]?:`, or `if var name =
 * place.operation(key):` where the operation is a native that answers the entry the key selects in a list or map (an
 * Optional of the container's value type, given the container's key type): its binding edits the entry itself. */
bool fn_probe_parts(const LowerFn *fn, const MsStmt *stmt, MsExpr **left, MsExpr **index) {
  const MsExpr *cond = stmt->u.branch.cond;
  if (stmt->u.branch.binding == NULL) {
    return false;
  }
  if (cond->kind == MS_E_PROBE) {
    return ms_expr_index(cond->u.bin.left, left, index);
  }
  const MsExpr *callee = cond->kind == MS_E_CALL ? cond->u.call.callee : NULL;
  const MsCall *call = callee != NULL ? fn_find_call(fn->facts, cond->id) : NULL;
  if (!stmt->u.branch.is_mutable || call == NULL || call->callee.kind != MS_REF_NATIVE || callee->kind != MS_E_MEMBER ||
      cond->u.call.args.len != 1) {
    return false;
  }
  const MsTyTable *types = &fn->cx->program->types;
  const MsTy held = ms_facts_type(fn->facts, callee->u.member.left->id);
  const MsTy result = ms_facts_type(fn->facts, cond->id);
  const MsTy key = ms_facts_type(fn->facts, cond->u.call.args.ptr[0].value->id);
  if (held == MS_TY_NONE || result == MS_TY_NONE || key == MS_TY_NONE || !ms_ty_is(types, result, MS_BUILTIN_Optional) ||
      ms_ty_arg_count(types, result) != 1) {
    return false;
  }
  const MsTy entry = ms_ty_args(types, result)[0];
  const bool map = ms_ty_is(types, held, MS_BUILTIN_Map) && ms_ty_arg_count(types, held) == 2 &&
                   ms_ty_args(types, held)[0] == key && ms_ty_args(types, held)[1] == entry;
  const bool list = ms_ty_is(types, held, MS_BUILTIN_List) && ms_ty_arg_count(types, held) == 1 &&
                    ms_ty_args(types, held)[0] == entry && ms_ty_is(types, key, MS_BUILTIN_Int);
  if (!map && !list) {
    return false;
  }
  *left = callee->u.member.left;
  *index = cond->u.call.args.ptr[0].value;
  return true;
}

/* `if var name = place[key]?:` tests whether the entry exists. `address` is the entry's address (null when absent) and
 * `cond` says it is not. */
bool fn_probe_begin(LowerFn *fn, const MsStmt *stmt, MirValue *cond, MirValue *address, MirTy *ty) {
  MsExpr *left = NULL;
  MsExpr *index = NULL;
  if (!fn_probe_parts(fn, stmt, &left, &index)) {
    return fn_fail(fn, "this bracket is not an index");
  }
  const MirValue container = fn_expr(fn, left, LW_BORROW);
  if (container == MIR_NONE) {
    return false;
  }
  *address = fn_entry_address(fn, container, index, ty);
  if (*address == MIR_NONE) {
    return false;
  }
  const MirValue absent = mir_b_emit(&fn->b, MOP_PtrIsNull, address, 1, (MirImm){0}, MIR_BOOL);
  *cond = mir_b_emit(&fn->b, MOP_Not, &absent, 1, (MirImm){0}, MIR_BOOL);
  return true;
}

/* Binds the name to the entry's current value and registers the store back to the entry. */
bool fn_probe_bind(LowerFn *fn, const MsStmt *stmt, MirValue address, MirTy ty) {
  const MsRef *ref = ms_facts_ref(fn->facts, stmt->u.branch.binding->id);
  if (stmt->u.branch.binding->kind != MS_P_NAME || ref == NULL || ref->kind != MS_REF_LOCAL) {
    return fn_fail(fn, "only a name can be bound by `if` for now");
  }
  if (fn->nwritebacks == LOWER_MAX_WRITEBACKS) {
    return fn_fail(fn, "`if var` entries nest too deeply");
  }
  const MirVar var = fn_local(fn, ref->local, ty);
  /* An entry that owns something is taken out of its place, and the writeback puts the changed value back. */
  const MirValue value = mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, ty) ? MOP_Take : MOP_Load, &address, 1,
                                    (MirImm){.tag = MI_TY, .a = ty}, ty);
  mir_b_def_var(&fn->b, var, value);
  fn->writebacks[fn->nwritebacks++] = (LowerWriteback){.var = var, .address = address, .ty = ty, .depth = fn->nopen};
  return !fn->failed;
}

/* `if var name = owner:` over an Optional `var` local: the binding changes the payload, so the owner is made again from
 * it wherever the body is left. Returns whether the writeback was registered. */
bool fn_iflet_writeback(LowerFn *fn, const MsStmt *stmt, MirValue entry) {
  MirVar owner = 0;
  const MsRef *ref = ms_facts_ref(fn->facts, stmt->u.branch.binding->id);
  const MirTyData *data = mir_ty_data(fn->cx->module, mir_b_ty(&fn->b, entry));
  if (data->kind != MK_OPT || ref == NULL || ref->kind != MS_REF_LOCAL || !fn_owned_local(fn, stmt->u.branch.cond, &owner)) {
    return false;
  }
  if (fn->nwritebacks == LOWER_MAX_WRITEBACKS) {
    return fn_fail(fn, "`if var` entries nest too deeply");
  }
  const MirVar var = fn_local(fn, ref->local, data->elem);
  fn->writebacks[fn->nwritebacks++] = (LowerWriteback){var, MIR_NONE, data->elem, fn->nopen, owner,
                                                       mir_b_ty(&fn->b, entry), true};
  return true;
}

static void put_writeback(LowerFn *fn, const LowerWriteback *back) {
  if (back->rewrap) {
    const MirValue payload = mir_b_use_var(&fn->b, back->var);
    mir_b_def_var(&fn->b, back->owner, mir_b_emit(&fn->b, MOP_OptSome, &payload, 1, (MirImm){0}, back->owner_ty));
    return;
  }
  const MirValue stored[2] = {back->address, mir_b_use_var(&fn->b, back->var)};
  (void)mir_b_emit(&fn->b, mir_needs_drop(fn->cx->module, back->ty) ? MOP_Put : MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
}

/* Stores each entry binding opened inside the scopes above `keep` back to its entry: a return, break or continue
 * leaving the body. */
void fn_writebacks_put(LowerFn *fn, uint32_t keep) {
  for (uint32_t at = fn->nwritebacks; at > 0; at--) {
    if (fn->writebacks[at - 1].depth > keep) {
      put_writeback(fn, &fn->writebacks[at - 1]);
    }
  }
}

/* The body is over: forget the newest binding, storing it back when the body falls out of its end. */
void fn_probe_end(LowerFn *fn, bool falls_out) {
  const LowerWriteback *back = &fn->writebacks[--fn->nwritebacks];
  if (falls_out) {
    put_writeback(fn, back);
  }
}
