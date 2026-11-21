/* If-conversion: small pure diamonds and triangles become `select`.
 *
 *     A: br_if c, B(), C()        A: ...B's insts, C's insts...
 *     B: pure insts; br J(x)  =>     p = select c, x, y
 *     C: pure insts; br J(y)         br J(p)
 *
 * Branchy loops with unpredictable conditions pay a misprediction per iteration; the backend
 * lowers `select` to a conditional move. Arms hold at most MAX_ARM total scalar instructions and
 * no checked arithmetic: predicating an overflow check costs about as much as the branch it saves.
 * Functions whose scalar early returns all fit (`if a < b { return -1 } ...`) are first merged
 * into one join so comparators convert too. Port of the former Rust crates/ms-mir/src/opt/ifconv.rs. */
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_opt.h"
#include "ms_rt/safe.h"

enum { IFCONV_MAX_ARM = 4 }; /* most instructions hoisted from one arm */

/* An arm of the branch: a real block hoisted into the head, or the join itself. */
typedef struct IfArm {
    uint32_t block; /* MIR_NONE when the arm is the join */
    const MirValue *args;
    uint32_t nargs;
} IfArm;

static bool is_scalar_value(const MirModule *m, const MirFunc *f, MirValue v) {
    return mir_is_scalar(m, mir_value_ty(f, v));
}

/* Total scalar operations, plus the two checks expanded to predicated guards. */
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
    case MOP_SDiv: case MOP_SRem:
        /* Positive literals exclude both zero and MIN / -1. */
        return inst->nargs > 1 && mir_bits_test(positive, inst->args[1]);
    default:
        return false;
    }
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
    const MirBlockData *blk = &f->blocks[b];
    if (b == head || edges[b] != 1 || blk->nparams != 0 || target->nargs != 0 ||
        blk->ninsts > IFCONV_MAX_ARM || blk->term.kind != MT_BR) {
        return false;
    }
    for (uint32_t i = 0; i < blk->ninsts; i++) {
        if (!speculatable(m, f, &blk->insts[i], positive)) {
            return false;
        }
    }
    *arm = (IfArm){b, blk->term.a.args, blk->term.a.nargs};
    *after = blk->term.a.block;
    return true;
}

static void decrement_edges(const MirFunc *f, uint32_t *edges, MirBlock b) {
    for (uint32_t t = 0; t < mir_term_ntargets(&f->blocks[b].term); t++) {
        edges[mir_term_target_const(&f->blocks[b].term, t)->block]--;
    }
}

/* Whether `j` only branches on its single parameter. `a and b` as an `if` condition leaves such a
 * join; jump threading turns the arms into direct branches, cheaper than selecting. */
static bool join_only_branches_on_flag(const MirFunc *f, MirBlock j) {
    const MirBlockData *blk = &f->blocks[j];
    return blk->nparams == 1 && blk->ninsts == 0 && blk->term.kind == MT_CONDBR &&
           blk->term.value == blk->params[0].value;
}

/* Moves the arm's instructions to the end of the head. */
static void hoist(MirModule *m, MirFunc *f, MirBlock head, const IfArm *arm) {
    if (arm->block == MIR_NONE) {
        return;
    }
    MirBlockData *blk = &f->blocks[arm->block];
    for (uint32_t i = 0; i < blk->ninsts; i++) {
        mir_block_insert(m, &f->blocks[head], f->blocks[head].ninsts, &blk->insts[i]);
    }
    blk->ninsts = 0;
    blk->term.kind = MT_UNREACHABLE;
}

/* Joins the two arms in `head`: hoists them, selects the differing arguments and branches to `j`. */
static void convert_diamond(MirModule *m, MirFunc *f, MirBlock head, MirBlock j, const IfArm *ta,
                            const IfArm *ea, uint32_t *edges) {
    const MirValue cond = f->blocks[head].term.value;
    const MirLoc loc = f->blocks[head].term_loc;
    /* Keep counts current as this diamond is removed. */
    decrement_edges(f, edges, head);
    if (ta->block != MIR_NONE) {
        decrement_edges(f, edges, ta->block);
    }
    if (ea->block != MIR_NONE) {
        decrement_edges(f, edges, ea->block);
    }
    edges[j]++;
    hoist(m, f, head, ta);
    hoist(m, f, head, ea);
    MirValue *args = MS_NEW_N(&m->arena, MirValue, (size_t)ta->nargs + 1);
    for (uint32_t k = 0; k < ta->nargs; k++) {
        const MirValue x = ta->args[k], y = ea->args[k];
        if (x == y) {
            args[k] = x;
            continue;
        }
        MirInst select = {0};
        select.op = MOP_Select;
        select.res = mir_new_value(m, f, mir_value_ty(f, x));
        select.loc = loc;
        select.nargs = 3;
        select.args = MS_NEW_N(&m->arena, MirValue, 3);
        select.args[0] = cond;
        select.args[1] = x;
        select.args[2] = y;
        mir_block_insert(m, &f->blocks[head], f->blocks[head].ninsts, &select);
        args[k] = select.res;
    }
    MirTerm *term = &f->blocks[head].term;
    term->kind = MT_BR;
    term->value = MIR_NONE;
    term->a = (MirTarget){j, args, ta->nargs};
    term->b = (MirTarget){0, NULL, 0};
}

/* Tries join `j` for the branch at the end of `a`; converts it when both arms fit. */
static bool try_join(MirModule *m, MirFunc *f, MirBlock a, MirBlock j, uint32_t *edges,
                     const MirBits *positive) {
    const MirTarget then = f->blocks[a].term.a, els = f->blocks[a].term.b;
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
    const uint32_t nparams = f->blocks[j].nparams;
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
    const MirTerm *term = &f->blocks[t->block].term;
    return term->kind == MT_BR ? term->a.block : MIR_NONE;
}

/* One sweep: converts every head that fits; false when none did. */
static bool convert_all(MirModule *m, MirFunc *f, const MirBits *positive) {
    MsArena arena = {0};
    uint32_t *edges = MS_NEW_N(&arena, uint32_t, (size_t)f->nblocks + 1);
    memset(edges, 0, sizeof(uint32_t) * ((size_t)f->nblocks + 1));
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t t = 0; t < mir_term_ntargets(&f->blocks[b].term); t++) {
            edges[mir_term_target_const(&f->blocks[b].term, t)->block]++;
        }
    }
    bool changed = false;
    for (MirBlock a = 0; a < f->nblocks; a++) {
        if (f->blocks[a].term.kind != MT_CONDBR) {
            continue;
        }
        const MirTarget then = f->blocks[a].term.a, els = f->blocks[a].term.b;
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
    for (uint32_t b = 0; b < f->nblocks; b++) {
        n += f->blocks[b].term.kind == MT_CONDBR ? 1u : 0u;
    }
    return n;
}

/* Early returns of scalars become one join with a block parameter so the diamonds above can turn
 * into selects. Kept only when every return is absorbed: a partly converted function would just
 * gain a jump. Fills `merged` and returns true when the merge is kept. */
static bool merge_returns(MirModule *m, const MirFunc *f, const MirBits *positive, MirFunc *merged) {
    uint32_t nrets = 0;
    MirBlock first = MIR_NONE;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirTerm *term = &f->blocks[b].term;
        if (term->kind == MT_RET && term->value != MIR_NONE && is_scalar_value(m, f, term->value)) {
            first = first == MIR_NONE ? b : first;
            nrets++;
        }
    }
    if (nrets < 2) {
        return false;
    }
    mir_func_clone(m, f, merged);
    const MirTy ty = mir_value_ty(merged, merged->blocks[first].term.value);
    const MirBlock exit = mir_new_block(m, merged);
    const MirValue p = mir_new_value(m, merged, ty);
    const MirBlockParam param = {p, MM_BORROW};
    MirBlockData *exit_block = &merged->blocks[exit];
    MIR_PUSH(m, exit_block->params, exit_block->nparams, exit_block->cparams, MirBlockParam, param);
    exit_block->term.kind = MT_RET;
    exit_block->term.value = p;
    exit_block->term_loc = merged->blocks[first].term_loc;
    for (uint32_t b = 0; b < exit; b++) {
        MirTerm *term = &merged->blocks[b].term;
        if (term->kind == MT_RET && term->value != MIR_NONE && is_scalar_value(m, f, term->value)) {
            MirValue *args = MS_NEW_N(&m->arena, MirValue, 1);
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
    return any && count_condbrs(merged) + nrets - 1 <= before;
}

/* Runs the pass over one function; returns whether it changed. */
bool mir_opt_ifconv_func(MirModule *m, MirFunc *f) {
    MsArena arena = {0};
    MirBits positive = mir_bits_new(&arena, f->nvalues);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            if (inst->op == MOP_IConst && inst->imm.tag == MI_INT && inst->imm.i > 0) {
                mir_bits_set(&positive, inst->res);
            }
        }
    }
    bool any = false;
    MirFunc merged;
    if (merge_returns(m, f, &positive, &merged)) {
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

bool mir_opt_ifconv(MirModule *m) {
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        changed = mir_opt_ifconv_func(m, &m->funcs[fi]) || changed;
    }
    return changed;
}
