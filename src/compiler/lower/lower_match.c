/* compiler/lower/lower_match.c: `match` over an alternative. The tag selects the arm; an arm's bindings read the
 * case's payload fields in place, and its value joins the other arms' through a variable. */
#include "compiler/lower/lower_fn.h"

typedef struct MatchArms {
  MirBlock *blocks; /* by arm */
  MirCase *cases;
  uint32_t ncases;
  MirBlock fallback;
  bool has_fallback;
} MatchArms;

/* The case number the arm names, or false for the wildcard. */
static bool arm_case(const LowerFn *fn, const MsArm *arm, uint32_t *index) {
  const MsRef *ref = ms_facts_ref(fn->facts, arm->id);
  if (ref == NULL || ref->kind != MS_REF_CASE) {
    return false;
  }
  *index = ref->index;
  return true;
}

static bool lower_arm(LowerFn *fn, const MsArm *arm, MirValue scrutinee, MirTy alt_ty, MirVar result,
                      bool has_result, MirBlock join) {
  const MirModule *module = fn->cx->module;
  const MirAltDef *alt = &module->alts.ptr[mir_ty_data(module, alt_ty)->id];
  uint32_t kase = 0;
  const bool named = arm_case(fn, arm, &kase);
  (void)fn_scope_begin(fn);
  if (named && arm->bindings.len > 0) {
    const MsRef *ref = ms_facts_ref(fn->facts, arm->id);
    for (uint32_t at = 0; at < arm->bindings.len && at < alt->cases[kase].nfields; at++) {
      const MirImm imm = {.tag = MI_ALTFIELD, .a = mir_ty_data(module, alt_ty)->id, .b = kase, .c = at};
      const MirTy ty = alt->cases[kase].fields[at].ty;
      const MirValue field = mir_b_emit(&fn->b, MOP_AltGet, &scrutinee, 1, imm, ty);
      mir_b_def_var(&fn->b, fn_local(fn, ref->local + at, ty), field);
    }
  }
  bool ok = fn_stmts(fn, arm->body);
  if (!fn->terminated && arm->value != NULL) {
    const MirValue value = fn_expr(fn, arm->value, LW_MOVE);
    ok = ok && value != MIR_NONE;
    if (has_result && value != MIR_NONE) {
      const MirImm none = {0};
      (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &value, 1, none, MIR_NONE);
      mir_b_def_var(&fn->b, result, value);
    }
  }
  if (fn->terminated) {
    fn->nopen--;
    return ok;
  }
  fn_scope_end(fn);
  mir_b_br(&fn->b, join, NULL, 0);
  return ok;
}

MirValue fn_match(LowerFn *fn, const MsExpr *expr) {
  const MirValue scrutinee = fn_expr(fn, expr->u.match.scrutinee, LW_BORROW);
  if (scrutinee == MIR_NONE) {
    return MIR_NONE;
  }
  const MirTy alt_ty = mir_b_ty(&fn->b, scrutinee);
  if (mir_ty_data(fn->cx->module, alt_ty)->kind != MK_ALT) {
    (void)fn_fail(fn, "`match` over this type is not lowered yet");
    return MIR_NONE;
  }
  const uint32_t narms = expr->u.match.arms.len;
  MsArena *arena = &fn->cx->module->arena;
  MatchArms arms = {.blocks = MS_ARENA_NEW_ARRAY(arena, MirBlock, narms + 1),
                    .cases = MS_ARENA_NEW_ARRAY(arena, MirCase, narms + 1)};
  const MirTy result_ty = fn_type(fn, ms_facts_type(fn->facts, expr->id));
  const bool has_result = result_ty != MIR_VOID;
  const MirVar result = has_result ? mir_b_declare_var(&fn->b, result_ty, MM_MOVE) : 0;
  const MirBlock join = mir_b_new_block(&fn->b);
  for (uint32_t index = 0; index < narms; index++) {
    uint32_t kase = 0;
    arms.blocks[index] = mir_b_new_block(&fn->b);
    if (arm_case(fn, expr->u.match.arms.ptr[index], &kase)) {
      arms.cases[arms.ncases++] = (MirCase){(int64_t)kase, {arms.blocks[index], NULL, 0}};
    } else if (!arms.has_fallback) {
      arms.fallback = arms.blocks[index];
      arms.has_fallback = true;
    }
  }
  const MirValue tag = mir_b_emit(&fn->b, MOP_AltTag, &scrutinee, 1, (MirImm){0}, MIR_INT);
  const MirBlock none = arms.has_fallback ? MIR_NONE : mir_b_new_block(&fn->b);
  mir_b_switch(&fn->b, tag, arms.cases, arms.ncases, arms.has_fallback ? arms.fallback : none);
  bool ok = true;
  for (uint32_t index = 0; index < narms; index++) {
    mir_b_seal_block(&fn->b, arms.blocks[index]);
    mir_b_switch_to(&fn->b, arms.blocks[index]);
    fn->terminated = false;
    ok = lower_arm(fn, expr->u.match.arms.ptr[index], scrutinee, alt_ty, result, has_result, join) && ok;
  }
  if (!arms.has_fallback) {
    mir_b_seal_block(&fn->b, none);
    mir_b_switch_to(&fn->b, none);
    mir_b_unreachable(&fn->b);
  }
  mir_b_seal_block(&fn->b, join);
  mir_b_switch_to(&fn->b, join);
  fn->terminated = false;
  if (!ok) {
    return MIR_NONE;
  }
  return has_result ? mir_b_use_var(&fn->b, result) : mir_b_unit(&fn->b);
}
