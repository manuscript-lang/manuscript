/* compiler/lower/lower_match.c: `match`. An alternative or an Optional is switched on its tag; a number, text or
 * boolean is compared with each literal arm in turn. An arm's bindings read the case's payload in place, and its
 * value joins the other arms' through a variable. */
#include "compiler/check/properties.h"
#include "compiler/lower/lower_fn.h"

typedef struct Match {
  MirValue scrutinee;
  MsTy checked; /* the scrutinee's checked type */
  MirTy ty;
  uint8_t kind; /* MK_ALT, MK_OPT, or MK_INT and the like for literals */
  MirVar result;
  bool has_result;
  bool borrows; /* every arm names a place: the result views it, and nothing owns it */
  MirBlock join;
  bool joined; /* an arm falls through to the join */
  bool consumed; /* the scrutinee is a name the match moves: its arms own the payload they bind */
  bool owned_resource; /* ... a scope-owned value holding a resource: only an arm that binds every field takes them */
  const MsRef *last_ref; /* the name's reference when the match reads it for the last time: each arm takes it from its slot */
} Match;

static bool is_literal(const MsExpr *path) {
  return path != NULL && (path->kind == MS_E_NUMBER || path->kind == MS_E_BOOL || path->kind == MS_E_TEXT ||
                          (path->kind == MS_E_UNARY && path->op == MS_U_NEG));
}

/* The case number an arm names: the facts' case for an alternative, `null` 0 and `some` 1 for an Optional. False
 * for the wildcard (and for a literal). */
static bool arm_case(const LowerFn *fn, const Match *match, const MsArm *arm, uint32_t *index) {
  if (match->kind == MK_OPT) {
    if (arm->bare) {
      *index = 1;
      return true;
    }
    const MsExpr *path = arm->path;
    const MsName name = path == NULL ? 0 : path->kind == MS_E_MEMBER ? path->u.member.name : path->u.sym;
    if (path == NULL || (path->kind != MS_E_NAME && path->kind != MS_E_MEMBER)) {
      return false;
    }
    const MsSpan text = ms_names_span(fn->cx->program->names, name);
    if (ms_span_is_text(text, "null") || ms_span_is_text(text, "some")) {
      *index = ms_span_is_text(text, "some") ? 1 : 0;
      return true;
    }
    return false;
  }
  const MsRef *ref = ms_facts_ref(fn->facts, arm->id);
  if (ref == NULL || ref->kind != MS_REF_CASE) {
    return false;
  }
  *index = ref->index;
  return true;
}

/* The checked type of what binding `at` of an arm over the case `kase` binds. */
static MsTy payload_type(const LowerFn *fn, const Match *match, uint32_t kase, uint32_t at) {
  MsCheckProgram *program = fn->cx->program;
  const MsTyTable *types = &program->types;
  const bool result = ms_ty_is(types, match->checked, MS_BUILTIN_Result);
  if (result || ms_ty_is(types, match->checked, MS_BUILTIN_Optional)) {
    const uint32_t which = result ? kase : 0;
    return at == 0 && ms_ty_arg_count(types, match->checked) > which ? ms_ty_args(types, match->checked)[which] : MS_TY_NONE;
  }
  const MsDef *def = ms_check_def_of(program, match->checked);
  if (def == NULL || ms_ty_kind(types, match->checked) != MS_TY_ALTERNATIVE || kase >= def->cases.len ||
      at >= def->cases.ptr[kase].fields.len) {
    return MS_TY_NONE;
  }
  return ms_check_part_type(program, match->checked, def, def->cases.ptr[kase].fields.ptr[at].ty);
}

/* Whether the arm's closer names binding `at`, whose checked type is `payload`. */
static bool closes_binding(LowerFn *fn, const MsArm *arm, uint32_t at, MsTy payload) {
  const MsRef *ref = ms_facts_ref(fn->facts, arm->id);
  const MsCloser *closer = ms_facts_closer(fn->facts, arm->id);
  return payload != MS_TY_NONE && closer != NULL && ref != NULL && closer->local == ref->local + at &&
         fn_closer_for(fn, closer, payload);
}

/* An arm over a consumed scrutinee owns the payload it binds: the scrutinee is released but for the bound fields,
 * which the arm drops unless it moves them on. */
static void take_payload(LowerFn *fn, const Match *match, const MsArm *arm, uint32_t kase, bool closes_rest) {
  const MirModule *module = fn->cx->module;
  const MsRef *ref = ms_facts_ref(fn->facts, arm->id);
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &match->scrutinee, 1, (MirImm){0}, MIR_NONE);
  if (match->kind == MK_OPT) {
    const MirTy elem = mir_ty_data(module, match->ty)->elem;
    const MirValue item = mir_b_emit(&fn->b, MOP_OptUnbox, &match->scrutinee, 1, (MirImm){0}, elem);
    const MsTy payload = payload_type(fn, match, 1, 0);
    if (closes_binding(fn, arm, 0, payload)) {
      (void)fn_bind_closing(fn, ref->local, payload, item, false); /* the arm closes it where it ends */
      return;
    }
    if (mir_needs_drop(module, elem)) {
      fn_own(fn, fn_scope(fn), item);
    }
    mir_b_def_var(&fn->b, fn_local(fn, ref->local, elem), item);
    return;
  }
  const uint32_t id = mir_ty_data(module, match->ty)->id;
  const MirCaseDef *def = &module->alts.ptr[id].cases[kase];
  uint32_t mask = 0;
  for (uint32_t at = 0; at < arm->bindings.len && at < def->nfields; at++) {
    if (closes_rest && ms_span_is_text(ms_names_span(fn->cx->program->names, arm->bindings.ptr[at].name), "_")) {
      continue; /* left out: closed below with the other fields the arm does not name */
    }
    const MirImm imm = {.tag = MI_ALTFIELD, .a = id, .b = kase, .c = at};
    const MirValue field = mir_b_emit(&fn->b, MOP_AltTake, &match->scrutinee, 1, imm, def->fields[at].ty);
    const MsTy payload = payload_type(fn, match, kase, at);
    mask |= UINT32_C(1) << at;
    const bool names_resource = closes_rest && payload != MS_TY_NONE && fn_temp_closes(fn, payload) &&
                                lower_part_close(fn->cx, payload) != MIR_NONE;
    if (names_resource || closes_binding(fn, arm, at, payload)) {
      (void)fn_bind_closing(fn, ref->local + at, payload, field, false); /* the arm closes it where it ends */
      continue;
    }
    const uint32_t local = ref->local + at;
    if (payload != MS_TY_NONE && fn_leaves_fields(fn, local, def->fields[at].ty) && fn->vars[local] == 0 &&
        mir_needs_drop(module, def->fields[at].ty)) {
      /* A field of the binding moves on at its last use: the variable keeps the rest, released with the arm's scope. */
      fn->vars[local] = mir_b_declare_var(&fn->b, def->fields[at].ty, MM_MOVE) + 1;
      mir_b_def_var(&fn->b, fn->vars[local] - 1, field);
      (void)fn_scope_own_var_in(fn, fn_scope(fn), fn->vars[local] - 1, payload);
      continue;
    }
    if (mir_needs_drop(module, def->fields[at].ty)) {
      fn_own(fn, fn_scope(fn), field);
    }
    mir_b_def_var(&fn->b, fn_local(fn, local, def->fields[at].ty), field);
  }
  for (uint32_t index = def->nfields; closes_rest && index > 0; index--) { /* what the arm leaves out closes now, last field first */
    const uint32_t at = index - 1;
    const MsTy payload = payload_type(fn, match, kase, at);
    if ((mask & (UINT32_C(1) << at)) != 0 || payload == MS_TY_NONE || !fn_temp_closes(fn, payload) ||
        lower_part_close(fn->cx, payload) == MIR_NONE) {
      continue;
    }
    const MirImm imm = {.tag = MI_ALTFIELD, .a = id, .b = kase, .c = at};
    const MirValue field = mir_b_emit(&fn->b, MOP_AltTake, &match->scrutinee, 1, imm, def->fields[at].ty);
    mask |= UINT32_C(1) << at;
    lower_close_check(&fn->b, mir_b_call(&fn->b, lower_part_close(fn->cx, payload), &field, 1));
  }
  const MirImm taken = {.tag = MI_ALTMASK, .a = id, .b = kase, .c = mask};
  (void)mir_b_emit(&fn->b, MOP_AltRelease, &match->scrutinee, 1, taken, MIR_NONE);
}

/* A binding that only views the scrutinee's payload: handing it on copies it. */
static void view_binding(LowerFn *fn, uint32_t local, MirTy ty) {
  if (fn->local_owns != NULL && local < fn->nvars && mir_needs_drop(fn->cx->module, ty)) {
    fn->local_owns[local] = 2;
  }
}

static void bind_payload(LowerFn *fn, const Match *match, const MsArm *arm, uint32_t kase) {
  const MirModule *module = fn->cx->module;
  const MsRef *ref = ms_facts_ref(fn->facts, arm->id);
  if (match->kind == MK_OPT) {
    if (arm->bindings.len > 0 && kase == 1) {
      MirTy elem = mir_ty_data(module, match->ty)->elem;
      MirValue item;
      const MsTyTable *types = &fn->cx->program->types;
      const bool whole = match->checked != MS_TY_NONE && ms_ty_arg_count(types, match->checked) == 1 &&
                         fn_type(fn, ms_ty_args(types, match->checked)[0]) == match->ty;
      if (whole) { /* `T?` of a nullable `T` is `T`: the value is its own payload */
        elem = match->ty;
        item = match->scrutinee;
      } else {
        item = mir_b_emit(&fn->b, MOP_OptGet, &match->scrutinee, 1, (MirImm){0}, elem);
      }
      mir_b_def_var(&fn->b, fn_local(fn, ref->local, elem), item);
      view_binding(fn, ref->local, elem);
    }
    return;
  }
  const uint32_t id = mir_ty_data(module, match->ty)->id;
  const MirCaseDef *def = &module->alts.ptr[id].cases[kase];
  for (uint32_t at = 0; at < arm->bindings.len && at < def->nfields; at++) {
    const MirImm imm = {.tag = MI_ALTFIELD, .a = id, .b = kase, .c = at};
    const MirValue field = mir_b_emit(&fn->b, MOP_AltGet, &match->scrutinee, 1, imm, def->fields[at].ty);
    mir_b_def_var(&fn->b, fn_local(fn, ref->local + at, def->fields[at].ty), field);
    view_binding(fn, ref->local + at, def->fields[at].ty);
  }
}

/* Whether an arm over an interface value names a type: the arm the value's own type selects. */
static bool is_type_arm(const LowerFn *fn, const MsArm *arm) {
  const MsRef *ref = ms_facts_ref(fn->facts, arm->id);
  return ref != NULL && ref->kind == MS_REF_TYPE;
}

/* The arm's binding: the interface value's payload read as the type the arm names, a view of what the value holds. */
static void bind_concrete(LowerFn *fn, const Match *match, const MsArm *arm) {
  const MsRef *ref = ms_facts_ref(fn->facts, arm->id);
  const MirTy ty = fn_type(fn, ms_facts_type(fn->facts, arm->id));
  const MirValue data = mir_b_emit(&fn->b, MOP_IfaceData, &match->scrutinee, 1, (MirImm){0}, MIR_PTR);
  const MirValue value = mir_b_emit(&fn->b, MOP_Load, &data, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
  mir_b_def_var(&fn->b, fn_local(fn, ref->local, ty), value);
}

static bool lower_arm(LowerFn *fn, Match *match, const MsArm *arm) {
  uint32_t kase = 0;
  const bool named = match->kind == MK_IFACE ? false : arm_case(fn, match, arm, &kase);
  (void)fn_scope_begin(fn);
  if (match->kind == MK_IFACE && is_type_arm(fn, arm)) {
    bind_concrete(fn, match, arm);
  }
  const MirValue viewed = match->scrutinee;
  MirValue owned = MIR_NONE;
  const bool last = !match->borrows && match->last_ref != NULL && fn_closing_take(fn, match->last_ref, viewed, &owned);
  if (last) {
    /* The last read of a resource-holding name: the arm takes the value from its slot and closes what it does not
     * name, in this order, before its body runs. */
    match->scrutinee = owned;
    if (named && arm->bindings.len > 0 && !(match->kind == MK_OPT && kase != 1)) {
      take_payload(fn, match, arm, kase, true);
    } else {
      lower_close_check(&fn->b, mir_b_call(&fn->b, lower_part_close(fn->cx, match->checked), &owned, 1));
    }
  } else if (named && arm->bindings.len > 0) {
    const bool takes_all = match->owned_resource && (match->kind == MK_OPT ||
                           arm->bindings.len == fn->cx->module->alts.ptr[mir_ty_data(fn->cx->module, match->ty)->id].cases[kase].nfields);
    if (!match->borrows && (match->consumed || takes_all) && !(match->kind == MK_OPT && kase != 1)) {
      take_payload(fn, match, arm, kase, false);
    } else {
      bind_payload(fn, match, arm, kase);
    }
  }
  match->scrutinee = viewed;
  bool ok = fn_stmts(fn, arm->body);
  if (!fn->terminated && arm->value != NULL) {
    const MirValue value = fn_expr(fn, arm->value, match->borrows ? LW_BORROW : LW_MOVE);
    ok = ok && value != MIR_NONE;
    if (match->has_result && value != MIR_NONE) {
      if (!match->borrows && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value))) {
        (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, (MirImm){0}, MIR_NONE);
      }
      mir_b_def_var(&fn->b, match->result, value);
    }
  }
  if (fn->terminated) {
    fn->nopen--;
    return ok;
  }
  fn_scope_end(fn);
  mir_b_br(&fn->b, match->join, NULL, 0);
  match->joined = true;
  return ok;
}

static void enter(LowerFn *fn, MirBlock block) {
  mir_b_seal_block(&fn->b, block);
  mir_b_switch_to(&fn->b, block);
  fn->terminated = false;
}

/* Switches on the scrutinee's tag to the arms' blocks. */
static void dispatch_tag(LowerFn *fn, const Match *match, const MsExpr *expr, const MirBlock *blocks) {
  MsArena *arena = &fn->cx->module->arena;
  const uint32_t narms = expr->u.match.arms.len;
  MirCase *cases = MS_ARENA_NEW_ARRAY(arena, MirCase, narms + 1);
  uint32_t ncases = 0;
  MirBlock fallback = MIR_NONE;
  for (uint32_t index = 0; index < narms; index++) {
    uint32_t kase = 0;
    if (arm_case(fn, match, expr->u.match.arms.ptr[index], &kase)) {
      cases[ncases++] = (MirCase){(int64_t)kase, {blocks[index], NULL, 0}};
    } else if (fallback == MIR_NONE) {
      fallback = blocks[index];
    }
  }
  MirValue tag = MIR_NONE;
  if (match->kind == MK_OPT) {
    const MirValue some = mir_b_emit(&fn->b, MOP_OptIsSome, &match->scrutinee, 1, (MirImm){0}, MIR_BOOL);
    tag = mir_b_select(&fn->b, some, mir_b_iconst(&fn->b, 1), mir_b_iconst(&fn->b, 0));
  } else {
    tag = mir_b_emit(&fn->b, MOP_AltTag, &match->scrutinee, 1, (MirImm){0}, MIR_INT);
  }
  const MirBlock none = fallback == MIR_NONE ? mir_b_new_block(&fn->b) : fallback;
  mir_b_switch(&fn->b, tag, cases, ncases, none);
  if (fallback == MIR_NONE) {
    enter(fn, none);
    mir_b_unreachable(&fn->b);
  }
}

/* Tests each type arm in turn against the interface value's vtable, then falls to the wildcard arm. */
static bool dispatch_types(LowerFn *fn, const Match *match, const MsExpr *expr, const MirBlock *blocks) {
  MirBlock fallback = MIR_NONE;
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsArm *arm = expr->u.match.arms.ptr[index];
    if (!is_type_arm(fn, arm)) {
      fallback = fallback == MIR_NONE ? blocks[index] : fallback;
      continue;
    }
    const uint32_t vtable = lower_vtable(fn->cx, &fn->subst, ms_facts_type(fn->facts, arm->id), match->checked);
    if (vtable == MIR_NONE) {
      return fn_fail(fn, "a value cannot be viewed as this interface: a method of the interface has no body for its type");
    }
    const MirImm imm = {.tag = MI_VTABLE, .a = vtable};
    const MirValue same = mir_b_emit(&fn->b, MOP_IfaceIs, &match->scrutinee, 1, imm, MIR_BOOL);
    const MirBlock next = mir_b_new_block(&fn->b);
    mir_b_br_if(&fn->b, same, blocks[index], NULL, 0, next, NULL, 0);
    enter(fn, next);
  }
  if (fallback == MIR_NONE) {
    mir_b_unreachable(&fn->b);
  } else {
    mir_b_br(&fn->b, fallback, NULL, 0);
  }
  return true;
}

/* Tests each literal arm in turn, then falls to the wildcard arm. */
static bool dispatch_literals(LowerFn *fn, const Match *match, const MsExpr *expr, const MirBlock *blocks) {
  MirBlock fallback = MIR_NONE;
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsExpr *path = expr->u.match.arms.ptr[index]->path;
    if (!is_literal(path)) {
      fallback = fallback == MIR_NONE ? blocks[index] : fallback;
      continue;
    }
    const MirValue literal = fn_expr(fn, path, LW_BORROW);
    if (literal == MIR_NONE) {
      return false;
    }
    const MirValue same = match->ty == MIR_STR ? fn_compare_values(fn, MS_B_EQ, match->scrutinee, literal)
                                               : mir_b_icmp(&fn->b, MCC_EQ, match->scrutinee, literal);
    const MirBlock next = mir_b_new_block(&fn->b);
    mir_b_br_if(&fn->b, same, blocks[index], NULL, 0, next, NULL, 0);
    enter(fn, next);
  }
  if (fallback == MIR_NONE) {
    mir_b_unreachable(&fn->b);
  } else {
    mir_b_br(&fn->b, fallback, NULL, 0);
  }
  return true;
}

/* Whether every arm of a `match` or `if` either leaves the function or yields a name or a field read in place, and one
 * yields: read as a borrow, the result views whichever place the arm names, a payload an arm binds included. */
bool fn_match_names_places(const LowerFn *fn, const MsExpr *expr) {
  bool yields = false;
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsArm *arm = expr->u.match.arms.ptr[index];
    if (arm->value == NULL) {
      const bool leaves = arm->body.len != 0 && arm->body.ptr[arm->body.len - 1]->kind == MS_S_RETURN;
      if (!leaves) {
        return false;
      }
      continue;
    }
    const MsExprKind kind = (MsExprKind)arm->value->kind;
    if (arm->body.len != 0 || (kind != MS_E_NAME && kind != MS_E_MEMBER) || ms_facts_use(fn->facts, arm->value->id) == MS_USE_MOVE) {
      return false; /* a name the arm gives up is moved out, not viewed */
    }
    yields = true;
  }
  return yields;
}

MirValue fn_match(LowerFn *fn, const MsExpr *expr, LowerWant want) {
  /* `match call()? { v => .. }`: the payload of a Result nothing else owns moves out into the match, so its arms own what
   * they bind (a binding handed on is moved, not copied). */
  const MsExpr *tried = expr->u.match.scrutinee;
  const bool takes = tried->kind == MS_E_UNARY && tried->op == MS_U_TRY && tried->u.bin.left->kind == MS_E_CALL;
  Match match = {.scrutinee = fn_expr(fn, expr->u.match.scrutinee, takes ? LW_MOVE : LW_BORROW)};
  if (match.scrutinee == MIR_NONE) {
    return MIR_NONE;
  }
  const MirInst *made = takes ? fn_just_made(fn, match.scrutinee) : NULL;
  if (made != NULL && made->op == MOP_AltTake && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, match.scrutinee))) {
    fn_own(fn, fn_scope(fn), match.scrutinee);
  }
  match.ty = mir_b_ty(&fn->b, match.scrutinee);
  match.checked = ms_facts_type(fn->facts, expr->u.match.scrutinee->id);
  if (match.checked != MS_TY_NONE) { /* inside a generic instance the scrutinee's type names its variables: use the instance's */
    match.checked = ms_ty_subst(&fn->cx->program->types, match.checked, fn->subst.vars, fn->subst.args, fn->subst.count);
  }
  match.kind = mir_ty_data(fn->cx->module, match.ty)->kind;
  const MsExpr *subject = expr->u.match.scrutinee;
  /* An owning local read for the last time gives its payloads to the arms: what an arm hands on moves, it is not a copy. */
  const MsRef *subject_ref = subject->kind == MS_E_NAME ? ms_facts_ref(fn->facts, subject->id) : NULL;
  const bool last_owner = subject_ref != NULL && subject_ref->kind == MS_REF_LOCAL && subject_ref->local < fn->nvars &&
                          fn->local_owns != NULL && fn->local_owns[subject_ref->local] == 1 && fn->facts->last != NULL &&
                          fn->facts->last[subject->id] != 0;
  match.consumed = ((subject->kind == MS_E_NAME && (ms_facts_use(fn->facts, subject->id) == MS_USE_MOVE || last_owner)) ||
                    ((subject->kind == MS_E_CALL || takes) && fn_fresh_owner(fn, match.scrutinee))) &&
                   (match.kind == MK_ALT || match.kind == MK_OPT) &&
                   (subject->kind == MS_E_CALL || takes || !ms_check_holds_resource(fn->cx->program, ms_facts_type(fn->facts, subject->id)));
  match.owned_resource = !match.consumed && subject->kind == MS_E_NAME && ms_facts_use(fn->facts, subject->id) == MS_USE_MOVE &&
                         (match.kind == MK_ALT || match.kind == MK_OPT);
  if (!match.consumed && subject->kind == MS_E_NAME && (match.kind == MK_ALT || match.kind == MK_OPT) &&
      fn->facts->last != NULL && fn->facts->last[subject->id] != 0 && match.checked != MS_TY_NONE &&
      ms_check_holds_resource(fn->cx->program, match.checked) && lower_part_close(fn->cx, match.checked) != MIR_NONE) {
    match.last_ref = ms_facts_ref(fn->facts, subject->id);
  }
  MirValue taken = MIR_NONE;
  if (subject->kind == MS_E_NAME && (match.kind == MK_ALT || match.kind == MK_OPT) &&
      fn_closing_move(fn, subject, match.scrutinee, &taken)) {
    /* A resource in a slot that the match moves: the slot gives it up, and the arms own what they bind. */
    match.scrutinee = taken;
    match.consumed = true;
  }
  const bool literal = match.ty == MIR_INT || match.ty == MIR_BOOL || match.ty == MIR_STR;
  if (match.kind != MK_ALT && match.kind != MK_OPT && match.kind != MK_IFACE && !literal) {
    (void)fn_fail(fn, "`match` over this type is not lowered yet");
    return MIR_NONE;
  }
  const uint32_t narms = expr->u.match.arms.len;
  MirBlock *blocks = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirBlock, narms + 1);
  /* A `match` used as a statement has no type, and so no result. */
  const MsTy result = ms_facts_type(fn->facts, expr->id);
  const MirTy result_ty = result == MS_TY_NONE ? MIR_VOID : fn_type(fn, result);
  match.has_result = result_ty != MIR_VOID;
  match.borrows = want == LW_BORROW && match.has_result && fn_match_names_places(fn, expr);
  match.result = match.has_result ? mir_b_declare_var(&fn->b, result_ty, match.borrows ? MM_BORROW : MM_MOVE) : 0;
  match.join = mir_b_new_block(&fn->b);
  for (uint32_t index = 0; index < narms; index++) {
    blocks[index] = mir_b_new_block(&fn->b);
  }
  bool ok = true;
  if (match.kind == MK_IFACE) {
    ok = dispatch_types(fn, &match, expr, blocks);
  } else if (literal) {
    ok = dispatch_literals(fn, &match, expr, blocks);
  } else {
    dispatch_tag(fn, &match, expr, blocks);
  }
  for (uint32_t index = 0; index < narms && ok; index++) {
    enter(fn, blocks[index]);
    ok = lower_arm(fn, &match, expr->u.match.arms.ptr[index]);
  }
  enter(fn, match.join);
  if (!ok) {
    return MIR_NONE;
  }
  if (!match.joined) {
    /* Every arm leaves: nothing reaches what follows. */
    const MirValue none = mir_b_unit(&fn->b);
    mir_b_unreachable(&fn->b);
    fn->terminated = true;
    return none;
  }
  if (!match.has_result) {
    return mir_b_unit(&fn->b);
  }
  const MirValue joined = mir_b_use_var(&fn->b, match.result);
  if (!match.borrows && mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, joined))) {
    fn_own(fn, fn_scope(fn), joined); /* the arms' values met in one owner: the enclosing scope drops it, or the one who takes it */
  }
  return joined;
}
