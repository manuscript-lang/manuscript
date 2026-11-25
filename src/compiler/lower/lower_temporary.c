/* compiler/lower/lower_temporary.c: a call that answers its dying temporary argument hands the temporary's payload on. */
#include "compiler/lower/lower_fn.h"
#include "compiler/mir/mir_analysis.h"
#include "compiler/own/result_borrows.h"
#include "compiler/syntax/walk.h"

/* The callee's returns all name one parameter: the call answers that argument itself. */
typedef struct WholeReturn {
  const MsFacts *facts;
  uint32_t returns;
  uint32_t params; /* returns that name a parameter of the result type */
  uint32_t local;
  bool same;
  MsName payloads[8]; /* the names the arms of a match on the receiver bind */
  uint32_t npayloads;
  uint32_t payload_returns; /* returns that name one of them */
  const MsExpr *receiver; /* NULL until a match on it is found */
} WholeReturn;

static void note_payload_match(void *ctx, const MsExpr *expr) {
  WholeReturn *counts = ctx;
  if (expr->kind != MS_E_MATCH || expr->u.match.scrutinee->kind != MS_E_NAME) {
    return;
  }
  const MsRef *ref = ms_facts_ref(counts->facts, expr->u.match.scrutinee->id);
  if (ref == NULL || ref->kind != MS_REF_PARAM || ref->local != 0 || counts->receiver != NULL) {
    return;
  }
  counts->receiver = expr->u.match.scrutinee;
  for (uint32_t arm = 0; arm < expr->u.match.arms.len; arm++) {
    const MsArm *one = expr->u.match.arms.ptr[arm];
    for (uint32_t bound = 0; bound < one->bindings.len && counts->npayloads < 8; bound++) {
      counts->payloads[counts->npayloads++] = one->bindings.ptr[bound].name;
    }
  }
}

static void count_whole_returns(void *ctx, const MsStmt *stmt) {
  WholeReturn *counts = ctx;
  if (stmt->kind != MS_S_RETURN || stmt->u.expr == NULL) {
    return;
  }
  counts->returns++;
  const MsRef *ref = stmt->u.expr->kind == MS_E_NAME ? ms_facts_ref(counts->facts, stmt->u.expr->id) : NULL;
  if (ref != NULL && ref->kind == MS_REF_LOCAL) {
    for (uint32_t at = 0; at < counts->npayloads; at++) {
      counts->payload_returns += counts->payloads[at] == stmt->u.expr->u.sym ? 1u : 0u;
    }
  }
  if (ref == NULL || ref->kind != MS_REF_PARAM) {
    return;
  }
  counts->same = counts->params == 0 || counts->local == ref->local;
  counts->local = ref->local;
  counts->params++;
}

/* `var t = id(make())`, `make().get()`: a call that answers its dying temporary argument itself (`id`), or the payload
 * of a dying Optional or Result receiver (`get`), gives the new owner that temporary's value instead of a copy.
 * Returns the owned value, or MIR_NONE when the call answers something else. */
MirValue fn_take_from_temporary(LowerFn *fn, const MsExpr *expr, MirValue value) {
  const MsCall *call = ms_facts_call(fn->facts, expr->id);
  if (call == NULL || (call->callee.kind != MS_REF_FUNCTION && call->callee.kind != MS_REF_METHOD)) {
    return MIR_NONE;
  }
  const MsFunc *callee = ms_own_find_func(fn->cx->program, &call->callee);
  if (callee == NULL || callee->bodiless || callee->external) {
    return MIR_NONE;
  }
  WholeReturn counts = {.facts = &fn->cx->program->modules.ptr[call->callee.decl.module].facts, .same = true};
  const MsVisitor visitor = {.ctx = &counts, .stmt = count_whole_returns, .expr = note_payload_match};
  ms_walk_block(&visitor, callee->body);
  const bool whole = counts.returns != 0 && counts.returns == counts.params && counts.same;
  const bool payload = counts.returns != 0 && counts.returns == counts.payload_returns && call->callee.kind == MS_REF_METHOD;
  /* A call that answers the borrowing variant is read as the plain Result: the call made the variant. */
  const MirValue variant = fn_view_owner(fn, value);
  const MirInst *last = fn_just_made(fn, variant != MIR_NONE ? variant : value);
  for (size_t block = fn->b.func.blocks.len; variant != MIR_NONE && last == NULL && block > 0; block--) {
    const MirInstList *insts = &fn->b.func.blocks.ptr[block - 1].insts;
    for (size_t at = insts->len; last == NULL && at > 0; at--) {
      last = insts->ptr[at - 1].res == variant ? &insts->ptr[at - 1] : NULL;
    }
  }
  if (last == NULL) {
    return MIR_NONE;
  }
  const uint32_t position = whole ? counts.local + (call->callee.kind == MS_REF_METHOD ? 1u : 0u) : 0;
  if ((!whole && !payload) || position >= last->nargs) {
    return MIR_NONE;
  }
  /* A name read for the last time dies with the call too: its payload leaves it. */
  const MsExpr *dying = payload && !whole && fn_call_callee(expr)->kind == MS_E_MEMBER ? fn_call_callee(expr)->u.member.left : NULL;
  const MsRef *dying_ref = dying != NULL && dying->kind == MS_E_NAME ? ms_facts_ref(fn->facts, dying->id) : NULL;
  const bool name_dies = dying_ref != NULL && (dying_ref->kind == MS_REF_LOCAL || dying_ref->kind == MS_REF_PARAM) &&
                         fn_leaves_binding(fn, dying);
  if (!name_dies && !fn_fresh_owner(fn, last->args[position])) {
    return MIR_NONE;
  }
  MirValue temporary = last->args[position];
  if (whole) {
    if (mir_b_ty(&fn->b, temporary) != mir_b_ty(&fn->b, value)) {
        return MIR_NONE;
    }
    /* The answer is the temporary itself: it is taken out first, then the temporary's owner steps aside. */
    const MirValue answer = fn_emit(fn, MOP_MoveOut, &value, 1, (MirImm){0}, mir_b_ty(&fn->b, value));
    (void)mir_b_emit(&fn->b, MOP_ScopeDisown, &temporary, 1, (MirImm){0}, MIR_NONE);
    (void)mir_b_emit(&fn->b, MOP_Forget, &temporary, 1, (MirImm){0}, MIR_NONE);
    return answer;
  }
  const MsExpr *receiver = fn_call_callee(expr)->kind == MS_E_MEMBER ? fn_call_callee(expr)->u.member.left : NULL;
  const MsTyTable *types = &fn->cx->program->types;
  const MsTy held = receiver == NULL ? MS_TY_NONE : ms_facts_type(fn->facts, receiver->id);
  if (held == MS_TY_NONE || (!ms_ty_is(types, held, MS_BUILTIN_Optional) && !ms_ty_is(types, held, MS_BUILTIN_Result))) {
    return MIR_NONE;
  }
  if (ms_ty_args(types, held)[0] != ms_facts_type(fn->facts, expr->id)) {
    return MIR_NONE; /* not the success payload */
  }
  if (name_dies && !fn_fresh_owner(fn, temporary)) {
    temporary = fn_expr(fn, dying, LW_MOVE); /* the name hands its value on: its scope no longer releases it */
    if (temporary == MIR_NONE) {
      return MIR_NONE;
    }
  }
  MirTy ty = MIR_VOID;
  return fn_take_payload(fn, temporary, &ty);
}
