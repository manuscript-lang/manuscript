/* If-conversion: small pure diamonds and triangles become `select`.
 *
 *     A: br_if c, B(), C()        A: ...B's insts, C's insts...
 *     B: pure insts; br J(x)  =>     p = select c, x, y
 *     C: pure insts; br J(y)         br J(p)
 *
 * Branchy loops with unpredictable conditions pay a misprediction per iteration; the backend
 * lowers `select` to a conditional move. Arms hold at most MAX_ARM scalar instructions. A checked
 * `+` or `-` in an arm is predicated: the arm computes the wrapped result and an overflow flag, and a
 * guard per arm faults when that arm was taken and its flag is set, at the check's own location. The
 * guard is a rarely taken, predictable branch where the arm was a data-dependent one. Functions whose scalar early returns all fit (`if a < b { return -1 } ...`) are first merged
 * into one join so comparators convert too. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"

enum { IFCONV_MAX_ARM = 4, IFCONV_MAX_CHECKS = 2 }; /* most instructions, and checked operations, hoisted from one arm */

/* An arm of the branch: a real block hoisted into the head, or the join itself. */
typedef struct IfArm {
  uint32_t block; /* MIR_NONE when the arm is the join */
  const MirValue *args;
  uint32_t nargs;
} IfArm;

static bool is_scalar_value(const MirModule *m, const MirFunc *f, MirValue v) {
  return mir_is_scalar(m, mir_value_ty(f, v));
}

/* Scalar operations that may run when the arm is not taken: pure ones, and checked `+` and `-`, whose
 * fault becomes a predicated guard. */
static bool speculatable(const MirModule *m, const MirFunc *f, const MirInst *inst,
            const MirBits *positive) {
  if (inst->res == MIR_NONE || !is_scalar_value(m, f, inst->res)) {
    return false;
  }
  switch ((MirOp)inst->op) {
  case MOP_IConst: case MOP_FConst: case MOP_BConst: case MOP_IAdd: case MOP_ISub:
  case MOP_IMul: case MOP_INeg: case MOP_IAddOverflow: case MOP_IMulOverflow: case MOP_And:
  case MOP_Or: case MOP_Xor: case MOP_Shl: case MOP_Sshr: case MOP_Ushr: case MOP_Rotl:
  case MOP_Rotr: case MOP_UMulHi: case MOP_Clz: case MOP_Ctz: case MOP_Popcnt: case MOP_Not:
  case MOP_ICmp: case MOP_UICmp: case MOP_FCmp: case MOP_FAdd: case MOP_FSub: case MOP_FMul:
  case MOP_FDiv: case MOP_FNeg: case MOP_FSqrt: case MOP_FFloor: case MOP_FCeil:
  case MOP_FTrunc: case MOP_FAbs: case MOP_I2F: case MOP_F32Round: case MOP_Conv:
  case MOP_INarrowOpt: case MOP_B2I: case MOP_Select:
    return true;
  case MOP_IAddChk: case MOP_ISubChk:
    /* Sized integers also fault out of their range, which the 64-bit flag does not show. */
    return mir_value_ty(f, inst->res) == MIR_INT && mir_value_ty(f, inst->args[0]) == MIR_INT &&
         mir_value_ty(f, inst->args[1]) == MIR_INT;
  case MOP_SDiv: case MOP_SRem:
    /* Positive literals exclude both zero and MIN / -1. */
    return inst->nargs > 1 && mir_bits_test(positive, inst->args[1]);
  default:
    return false;
  }
}

static bool is_checked_add_sub(const MirInst *inst) {
  return inst->op == MOP_IAddChk || inst->op == MOP_ISubChk;
}

/* The arm reached by `target` when `join` is the common successor; `*after` is where the arm
 * continues. False when the block cannot be hoisted. */
static bool make_arm(const MirModule *m, const MirFunc *f, const uint32_t *edges, MirBlock head,
          const MirTarget *target, MirBlock join, const MirBits *positive, IfArm *arm,
          MirBlock *after) {
  const MirBlock b = target->block;
  if (b == join) {
    *arm = (IfArm){MIR_NONE, target->args, target->nargs};
    *after = b;
    return true;
  }
  const MirBlockData *blk = &f->blocks.ptr[b];
  if (b == head || edges[b] != 1 || blk->params.len != 0 || target->nargs != 0 ||
    blk->insts.len > IFCONV_MAX_ARM || blk->term.kind != MT_BR) {
    return false;
  }
  uint32_t checks = 0;
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    if (!speculatable(m, f, &blk->insts.ptr[i], positive)) {
      return false;
    }
    checks += is_checked_add_sub(&blk->insts.ptr[i]) ? 1u : 0u;
  }
  if (checks > IFCONV_MAX_CHECKS) {
    return false;
  }
  *arm = (IfArm){b, blk->term.a.args, blk->term.a.nargs};
  *after = blk->term.a.block;
  return true;
}

static void decrement_edges(const MirFunc *f, uint32_t *edges, MirBlock b) {
  for (uint32_t t = 0; t < mir_term_ntargets(&f->blocks.ptr[b].term); t++) {
    edges[mir_term_target_const(&f->blocks.ptr[b].term, t)->block]--;
  }
}

/* Whether `j` only branches on its single parameter. `a and b` as an `if` condition leaves such a
 * join; jump threading turns the arms into direct branches, cheaper than selecting. */
static bool join_only_branches_on_flag(const MirFunc *f, MirBlock j) {
  const MirBlockData *blk = &f->blocks.ptr[j];
  return blk->params.len == 1 && blk->insts.len == 0 && blk->term.kind == MT_CONDBR &&
     blk->term.value == blk->params.ptr[0].value;
}

/* Moves the arm's instructions to the end of the head. */
static void hoist(MirFunc *f, MirBlock head, const IfArm *arm) {
  if (arm->block == MIR_NONE) {
    return;
  }
  MirBlockData *blk = &f->blocks.ptr[arm->block];
  for (uint32_t i = 0; i < blk->insts.len; i++) {
    mir_block_insert(&f->blocks.ptr[head], (uint32_t)f->blocks.ptr[head].insts.len, &blk->insts.ptr[i]);
  }
  blk->insts.len = 0;
  blk->term.kind = MT_UNREACHABLE;
}


static MirValue push_inst(MirModule *m, MirFunc *f, MirBlockData *blk, MirOp op, const MirValue *args,
              uint32_t nargs, MirImm imm, MirTy ty, MirLoc loc) {
  const MirValue res = mir_new_value(f, ty);
  const MirInst inst = opt_inst_make(m, op, args, nargs, imm, res, loc);
  mir_block_insert(blk, (uint32_t)blk->insts.len, &inst);
  return res;
}

/* Rewrites the checked `+` and `-` of arm `arm` (already hoisted into `head` at positions `from` to `end`) to
 * wrapped operations that also compute an overflow flag; returns the flag that is set when any of them
 * overflowed (MIR_NONE when there is none) and the location of the first. */
static MirValue predicate_checks(MirModule *m, MirFunc *f, MirBlock head, uint32_t from, uint32_t end,
                 MirLoc *where) {
  MirValue any = MIR_NONE, zero = MIR_NONE;
  for (uint32_t i = from; i < end; i++) {
    MirInst *inst = &f->blocks.ptr[head].insts.ptr[i];
    if (!is_checked_add_sub(inst)) {
      continue;
    }
    const bool add = inst->op == MOP_IAddChk;
    const MirValue a = inst->args[0], b = inst->args[1], r = inst->res;
    const MirLoc loc = inst->loc;
    inst->op = add ? MOP_IAdd : MOP_ISub;
    if (zero == MIR_NONE) {
      zero = push_inst(m, f, &f->blocks.ptr[head], MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT}, MIR_INT, loc);
    }
    MirValue flag;
    if (add) {
      const MirValue ab[2] = {a, b};
      flag = push_inst(m, f, &f->blocks.ptr[head], MOP_IAddOverflow, ab, 2, mir_imm_none(), MIR_BOOL, loc);
    } else {
      /* a - b overflows when a and b differ in sign and r differs from a in sign. */
      const MirValue x1[2] = {a, b}, x2[2] = {a, r};
      const MirValue t1 = push_inst(m, f, &f->blocks.ptr[head], MOP_Xor, x1, 2, mir_imm_none(), MIR_INT, loc);
      const MirValue t2 = push_inst(m, f, &f->blocks.ptr[head], MOP_Xor, x2, 2, mir_imm_none(), MIR_INT, loc);
      const MirValue ta[2] = {t1, t2};
      const MirValue t3 = push_inst(m, f, &f->blocks.ptr[head], MOP_And, ta, 2, mir_imm_none(), MIR_INT, loc);
      const MirValue ca[2] = {t3, zero};
      flag = push_inst(m, f, &f->blocks.ptr[head], MOP_ICmp, ca, 2, (MirImm){.tag = MI_CC, .a = MCC_LT},
               MIR_BOOL, loc);
    }
    if (any == MIR_NONE) {
      any = flag;
      *where = loc;
    } else {
      const MirValue oa[2] = {any, flag};
      any = push_inst(m, f, &f->blocks.ptr[head], MOP_Or, oa, 2, mir_imm_none(), MIR_BOOL, loc);
    }
  }
  return any;
}

/* Faults when the arm `cond` selects has its overflow flag set: one guard when both arms' checks sit at one
 * source position, else one guard per arm so the fault names the check that failed. */
static void guard_arms(MirModule *m, MirFunc *f, MirBlock head, MirValue cond, MirValue then_flag, MirLoc then_loc,
             MirValue else_flag, MirLoc else_loc) {
  MirBlockData *blk = &f->blocks.ptr[head];
  if (then_flag == MIR_NONE && else_flag == MIR_NONE) {
    return;
  }
  const bool same = then_flag != MIR_NONE && else_flag != MIR_NONE && then_loc.file == else_loc.file &&
            then_loc.line == else_loc.line && then_loc.col == else_loc.col && then_loc.scope == else_loc.scope;
  const MirLoc loc = then_flag != MIR_NONE ? then_loc : else_loc;
  const MirValue no = push_inst(m, f, blk, MOP_BConst, NULL, 0, (MirImm){.tag = MI_BOOL, .a = 0}, MIR_BOOL, loc);
  MirValue hit[2] = {MIR_NONE, MIR_NONE};
  const MirValue sel[3] = {cond, then_flag != MIR_NONE ? then_flag : no, else_flag != MIR_NONE ? else_flag : no};
  if (same || then_flag == MIR_NONE || else_flag == MIR_NONE) {
    hit[0] = push_inst(m, f, blk, MOP_Select, sel, 3, mir_imm_none(), MIR_BOOL, loc);
  } else {
    const MirValue st[3] = {cond, then_flag, no}, se[3] = {cond, no, else_flag};
    hit[0] = push_inst(m, f, blk, MOP_Select, st, 3, mir_imm_none(), MIR_BOOL, then_loc);
    hit[1] = push_inst(m, f, blk, MOP_Select, se, 3, mir_imm_none(), MIR_BOOL, else_loc);
  }
  for (uint32_t k = 0; k < 2 && hit[k] != MIR_NONE; k++) {
    const MirInst guard = opt_inst_make(m, MOP_IntOverflowIf, &hit[k], 1, mir_imm_none(), MIR_NONE,
                      k == 0 && hit[1] != MIR_NONE ? then_loc : (hit[1] != MIR_NONE ? else_loc : loc));
    mir_block_insert(blk, (uint32_t)blk->insts.len, &guard);
  }
}

/* Joins the two arms in `head`: hoists them, selects the differing arguments and branches to `j`. */
static void convert_diamond(MirModule *m, MirFunc *f, MirBlock head, MirBlock j, const IfArm *ta,
              const IfArm *ea, uint32_t *edges) {
  const MirValue cond = f->blocks.ptr[head].term.value;
  const MirLoc loc = f->blocks.ptr[head].term_loc;
  /* Keep counts current as this diamond is removed. */
  decrement_edges(f, edges, head);
  if (ta->block != MIR_NONE) {
    decrement_edges(f, edges, ta->block);
  }
  if (ea->block != MIR_NONE) {
    decrement_edges(f, edges, ea->block);
  }
  edges[j]++;
  const uint32_t at_then = (uint32_t)f->blocks.ptr[head].insts.len;
  hoist(f, head, ta);
  const uint32_t at_else = (uint32_t)f->blocks.ptr[head].insts.len;
  hoist(f, head, ea);
  const uint32_t at_end = (uint32_t)f->blocks.ptr[head].insts.len;
  MirLoc then_loc = loc, else_loc = loc;
  const MirValue then_flag = predicate_checks(m, f, head, at_then, at_else, &then_loc);
  const MirValue else_flag = predicate_checks(m, f, head, at_else, at_end, &else_loc);
  guard_arms(m, f, head, cond, then_flag, then_loc, else_flag, else_loc);
  MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, (size_t)ta->nargs + 1);
  for (uint32_t k = 0; k < ta->nargs; k++) {
    const MirValue x = ta->args[k], y = ea->args[k];
    if (x == y) {
      args[k] = x;
      continue;
    }
    MirInst select = {0};
    select.op = MOP_Select;
    select.res = mir_new_value(f, mir_value_ty(f, x));
    select.loc = loc;
    select.nargs = 3;
    select.args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, 3);
    select.args[0] = cond;
    select.args[1] = x;
    select.args[2] = y;
    mir_block_insert(&f->blocks.ptr[head], (uint32_t)f->blocks.ptr[head].insts.len, &select);
    args[k] = select.res;
  }
  MirTerm *term = &f->blocks.ptr[head].term;
  term->kind = MT_BR;
  term->value = MIR_NONE;
  term->a = (MirTarget){j, args, ta->nargs};
  term->b = (MirTarget){0, NULL, 0};
}

static uint32_t arm_len(const MirFunc *f, const IfArm *arm) {
  return arm->block == MIR_NONE ? 0u : (uint32_t)f->blocks.ptr[arm->block].insts.len;
}

static uint32_t arm_checks(const MirFunc *f, const IfArm *arm) {
  uint32_t n = 0;
  for (uint32_t i = 0; i < arm_len(f, arm); i++) {
    n += is_checked_add_sub(&f->blocks.ptr[arm->block].insts.ptr[i]) ? 1u : 0u;
  }
  return n;
}

/* Tries join `j` for the branch at the end of `a`; converts it when both arms fit. */
static bool try_join(MirModule *m, MirFunc *f, MirBlock a, MirBlock j, uint32_t *edges,
          const MirBits *positive) {
  const MirTarget then = f->blocks.ptr[a].term.a, els = f->blocks.ptr[a].term.b;
  IfArm ta = {0}, ea = {0};
  MirBlock jt = 0, je = 0;
  if (j == a || j == 0 || !make_arm(m, f, edges, a, &then, j, positive, &ta, &jt) ||
    !make_arm(m, f, edges, a, &els, j, positive, &ea, &je)) {
    return false;
  }
  if (jt != j || je != j || (ta.block == MIR_NONE && ea.block == MIR_NONE) ||
    join_only_branches_on_flag(f, j)) {
    return false;
  }
  /* A branch around one arm usually guards a rare case that predicts well, so predicated checks (a flag, a
   * select and a guard, executed every time) cost more than they save. A choice between two computed arms
   * is the data-dependent one. */
  if ((arm_checks(f, &ta) > 0 || arm_checks(f, &ea) > 0) && (arm_len(f, &ta) == 0 || arm_len(f, &ea) == 0)) {
    return false;
  }
  const uint32_t nparams = (uint32_t)f->blocks.ptr[j].params.len;
  if (ta.nargs != nparams || ea.nargs != nparams) {
    return false;
  }
  for (uint32_t k = 0; k < nparams; k++) {
    if (!is_scalar_value(m, f, ta.args[k]) || !is_scalar_value(m, f, ea.args[k])) {
      return false;
    }
  }
  convert_diamond(m, f, a, j, &ta, &ea, edges);
  return true;
}

/* The block `t` jumps to when it ends in a plain branch, else MIR_NONE. */
static MirBlock branch_target(const MirFunc *f, const MirTarget *t) {
  const MirTerm *term = &f->blocks.ptr[t->block].term;
  return term->kind == MT_BR ? term->a.block : MIR_NONE;
}

/* One sweep: converts every head that fits; false when none did. */
static bool convert_all(MirModule *m, MirFunc *f, const MirBits *positive) {
  MsArena arena = ms_arena_new();
  uint32_t *edges = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)f->blocks.len + 1);
  __builtin_memset(edges, 0, sizeof(uint32_t) * ((size_t)f->blocks.len + 1));
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t t = 0; t < mir_term_ntargets(&f->blocks.ptr[b].term); t++) {
      edges[mir_term_target_const(&f->blocks.ptr[b].term, t)->block]++;
    }
  }
  bool changed = false;
  for (MirBlock a = 0; a < f->blocks.len; a++) {
    if (f->blocks.ptr[a].term.kind != MT_CONDBR) {
      continue;
    }
    const MirTarget then = f->blocks.ptr[a].term.a, els = f->blocks.ptr[a].term.b;
    /* The join is the common successor: either arm's target, or both arms' target. */
    const MirBlock candidates[4] = {then.block, els.block, branch_target(f, &then),
                    branch_target(f, &els)};
    for (uint32_t c = 0; c < 4; c++) {
      if (candidates[c] != MIR_NONE && try_join(m, f, a, candidates[c], edges, positive)) {
        changed = true;
        break;
      }
    }
  }
  ms_arena_free(&arena);
  return changed;
}

static uint32_t count_condbrs(const MirFunc *f) {
  uint32_t n = 0;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    n += f->blocks.ptr[b].term.kind == MT_CONDBR ? 1u : 0u;
  }
  return n;
}

/* Early returns of scalars become one join with a block parameter so the diamonds above can turn
 * into selects. Kept only when every return is absorbed: a partly converted function would just
 * gain a jump. Fills `merged` and returns true when the merge is kept. */
static bool merge_returns(MirModule *m, const MirFunc *f, const MirBits *positive, MirFunc *merged) {
  uint32_t nrets = 0;
  MirBlock first = MIR_NONE;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirTerm *term = &f->blocks.ptr[b].term;
    if (term->kind == MT_RET && term->value != MIR_NONE && is_scalar_value(m, f, term->value)) {
      first = first == MIR_NONE ? b : first;
      nrets++;
    }
  }
  if (nrets < 2) {
    return false;
  }
  opt_func_deep_clone(m, f, merged);
  const MirTy ty = mir_value_ty(merged, merged->blocks.ptr[first].term.value);
  const MirBlock exit = mir_new_block(merged);
  const MirValue p = mir_new_value(merged, ty);
  const MirBlockParam param = {p, MM_BORROW};
  MirBlockData *exit_block = &merged->blocks.ptr[exit];
  mir_block_param_list_push(&exit_block->params, param);
  exit_block->term.kind = MT_RET;
  exit_block->term.value = p;
  exit_block->term_loc = merged->blocks.ptr[first].term_loc;
  for (uint32_t b = 0; b < exit; b++) {
    MirTerm *term = &merged->blocks.ptr[b].term;
    if (term->kind == MT_RET && term->value != MIR_NONE && is_scalar_value(m, f, term->value)) {
      MirValue *args = MS_ARENA_NEW_ARRAY(&m->arena, MirValue, 1);
      args[0] = term->value;
      term->kind = MT_BR;
      term->value = MIR_NONE;
      term->a = (MirTarget){exit, args, 1};
    }
  }
  const uint32_t before = count_condbrs(merged);
  bool any = false;
  while (convert_all(m, merged, positive)) {
    any = true;
  }
  const bool keep = any && count_condbrs(merged) + nrets - 1 <= before;
  if (!keep) {
    mir_func_release(merged);
  }
  return keep;
}

/* Runs the pass over one function; returns whether it changed. */
bool opt_ifconv_func(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  MirBits positive = mir_bits_new(&arena, (uint32_t)f->values.len);
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      if (inst->op == MOP_IConst && inst->imm.tag == MI_INT && inst->imm.i > 0) {
        mir_bits_set(&positive, inst->res);
      }
    }
  }
  bool any = false;
  MirFunc merged;
  if (merge_returns(m, f, &positive, &merged)) {
    mir_func_release(f);
    *f = merged;
    any = true;
  }
  while (convert_all(m, f, &positive)) {
    any = true;
  }
  if (any) {
    mir_func_compact_blocks(f);
  }
  ms_arena_free(&arena);
  return any;
}
