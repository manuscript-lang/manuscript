/* compiler/lower/lower_match.c: `match`. An alternative or an Optional is switched on its tag; a number, text or
 * boolean is compared with each literal arm in turn. An arm's bindings read the case's payload in place, and its
 * value joins the other arms' through a variable. */
#include "compiler/check/properties.h"
#include "compiler/lower/lower_fn.h"

typedef struct Match {
  MirValue scrutinee;
  MirTy ty;
  uint8_t kind; /* MK_ALT, MK_OPT, or MK_INT and the like for literals */
  MirVar result;
  bool has_result;
  MirBlock join;
  bool joined; /* an arm falls through to the join */
  bool consumed; /* the scrutinee is a name the match moves: its arms own the payload they bind */
} Match;

static bool is_literal(const MsExpr *path) {
  return path != NULL && (path->kind == MS_E_NUMBER || path->kind == MS_E_BOOL ||
                          (path->kind == MS_E_UNARY && path->op == MS_U_NEG));
}

/* The case number an arm names: the facts' case for an alternative, `none` 0 and `some` 1 for an Optional. False
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
    if (ms_span_is_text(text, "none") || ms_span_is_text(text, "some")) {
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

/* An arm over a consumed scrutinee owns the payload it binds: the scrutinee is released but for the bound fields,
 * which the arm drops unless it moves them on. */
static void take_payload(LowerFn *fn, const Match *match, const MsArm *arm, uint32_t kase) {
  const MirModule *module = fn->cx->module;
  const MsRef *ref = ms_facts_ref(fn->facts, arm->id);
  (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &match->scrutinee, 1, (MirImm){0}, MIR_NONE);
  if (match->kind == MK_OPT) {
    const MirTy elem = mir_ty_data(module, match->ty)->elem;
    const MirValue item = mir_b_emit(&fn->b, MOP_OptUnbox, &match->scrutinee, 1, (MirImm){0}, elem);
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
    const MirImm imm = {.tag = MI_ALTFIELD, .a = id, .b = kase, .c = at};
    const MirValue field = mir_b_emit(&fn->b, MOP_AltTake, &match->scrutinee, 1, imm, def->fields[at].ty);
    if (mir_needs_drop(module, def->fields[at].ty)) {
      fn_own(fn, fn_scope(fn), field);
    }
    mir_b_def_var(&fn->b, fn_local(fn, ref->local + at, def->fields[at].ty), field);
    mask |= UINT32_C(1) << at;
  }
  const MirImm taken = {.tag = MI_ALTMASK, .a = id, .b = kase, .c = mask};
  (void)mir_b_emit(&fn->b, MOP_AltRelease, &match->scrutinee, 1, taken, MIR_NONE);
}

static void bind_payload(LowerFn *fn, const Match *match, const MsArm *arm, uint32_t kase) {
  const MirModule *module = fn->cx->module;
  const MsRef *ref = ms_facts_ref(fn->facts, arm->id);
  if (match->kind == MK_OPT) {
    if (arm->bindings.len > 0 && kase == 1) {
      const MirTy elem = mir_ty_data(module, match->ty)->elem;
      const MirValue item = mir_b_emit(&fn->b, MOP_OptGet, &match->scrutinee, 1, (MirImm){0}, elem);
      mir_b_def_var(&fn->b, fn_local(fn, ref->local, elem), item);
    }
    return;
  }
  const uint32_t id = mir_ty_data(module, match->ty)->id;
  const MirCaseDef *def = &module->alts.ptr[id].cases[kase];
  for (uint32_t at = 0; at < arm->bindings.len && at < def->nfields; at++) {
    const MirImm imm = {.tag = MI_ALTFIELD, .a = id, .b = kase, .c = at};
    const MirValue field = mir_b_emit(&fn->b, MOP_AltGet, &match->scrutinee, 1, imm, def->fields[at].ty);
    mir_b_def_var(&fn->b, fn_local(fn, ref->local + at, def->fields[at].ty), field);
  }
}

static bool lower_arm(LowerFn *fn, Match *match, const MsArm *arm) {
  uint32_t kase = 0;
  const bool named = arm_case(fn, match, arm, &kase);
  (void)fn_scope_begin(fn);
  if (named && arm->bindings.len > 0) {
    if (match->consumed && !(match->kind == MK_OPT && kase != 1)) {
      take_payload(fn, match, arm, kase);
    } else {
      bind_payload(fn, match, arm, kase);
    }
  }
  bool ok = fn_stmts(fn, arm->body);
  if (!fn->terminated && arm->value != NULL) {
    const MirValue value = fn_expr(fn, arm->value, LW_MOVE);
    ok = ok && value != MIR_NONE;
    if (match->has_result && value != MIR_NONE) {
      if (mir_needs_drop(fn->cx->module, mir_b_ty(&fn->b, value))) {
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
    const MirValue same = mir_b_icmp(&fn->b, MCC_EQ, match->scrutinee, literal);
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

MirValue fn_match(LowerFn *fn, const MsExpr *expr) {
  Match match = {.scrutinee = fn_expr(fn, expr->u.match.scrutinee, LW_BORROW)};
  if (match.scrutinee == MIR_NONE) {
    return MIR_NONE;
  }
  match.ty = mir_b_ty(&fn->b, match.scrutinee);
  match.kind = mir_ty_data(fn->cx->module, match.ty)->kind;
  const MsExpr *subject = expr->u.match.scrutinee;
  match.consumed = ((subject->kind == MS_E_NAME && ms_facts_use(fn->facts, subject->id) == MS_USE_MOVE) ||
                    (subject->kind == MS_E_CALL && fn_fresh_owner(fn, match.scrutinee))) &&
                   (match.kind == MK_ALT || match.kind == MK_OPT) &&
                   !ms_check_holds_resource(fn->cx->program, ms_facts_type(fn->facts, subject->id));
  MirValue taken = MIR_NONE;
  if (subject->kind == MS_E_NAME && (match.kind == MK_ALT || match.kind == MK_OPT) &&
      fn_closing_move(fn, subject, match.scrutinee, &taken)) {
    /* A resource in a slot that the match moves: the slot gives it up, and the arms own what they bind. */
    match.scrutinee = taken;
    match.consumed = true;
  }
  const bool literal = match.ty == MIR_INT || match.ty == MIR_BOOL;
  if (match.kind != MK_ALT && match.kind != MK_OPT && !literal) {
    (void)fn_fail(fn, "`match` over this type is not lowered yet");
    return MIR_NONE;
  }
  const uint32_t narms = expr->u.match.arms.len;
  MirBlock *blocks = MS_ARENA_NEW_ARRAY(&fn->cx->module->arena, MirBlock, narms + 1);
  /* A `match` used as a statement has no type, and so no result. */
  const MsTy result = ms_facts_type(fn->facts, expr->id);
  const MirTy result_ty = result == MS_TY_NONE ? MIR_VOID : fn_type(fn, result);
  match.has_result = result_ty != MIR_VOID;
  match.result = match.has_result ? mir_b_declare_var(&fn->b, result_ty, MM_MOVE) : 0;
  match.join = mir_b_new_block(&fn->b);
  for (uint32_t index = 0; index < narms; index++) {
    blocks[index] = mir_b_new_block(&fn->b);
  }
  bool ok = true;
  if (literal) {
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
  return match.has_result ? mir_b_use_var(&fn->b, match.result) : mir_b_unit(&fn->b);
}
