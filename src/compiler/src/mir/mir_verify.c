/* The MIR verifier (verify.rs): declarations, the shape of each function, SSA dominance, operand
 * types (mir_verify_types.c) and linear ownership. A function that fails an earlier stage is not
 * checked by a later one, as in the Rust verifier, so the two report the same errors.
 *
 * Ownership is checked on values whose type needs a drop. A value is owned when its defining
 * instruction returns an owned value (mir_result_mode), or it is a `move` parameter or block
 * parameter; every other value is borrowed. A consuming position needs an owned operand and removes
 * it from the live set; a borrowing position takes either, but an owned value must still be live.
 * The live set must be the same on every edge into a block and empty at `ret`. */
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_verify.h"

/* ---- errors ---- */

static void mv_push(MirVerifyErrors *errs, MsStr func, MirBlock block, MsStr message) {
    MirVerifyError e = {func, block, message};
    if (errs->count == errs->cap) {
        uint32_t cap = errs->cap == 0 ? 16 : errs->cap * 2;
        MirVerifyError *grown = MS_NEW_N(&errs->arena, MirVerifyError, cap);
        if (errs->count > 0) {
            memcpy(grown, errs->errors, sizeof *grown * errs->count);
        }
        errs->errors = grown;
        errs->cap = cap;
    }
    errs->errors[errs->count++] = e;
}

static MsStr mv_copy(MirVerifyErrors *errs, MsStr s) {
    MsStr c = {ms_arena_strndup(&errs->arena, s.ptr, s.len), s.len};
    return c;
}

void mir_verify_errors_free(MirVerifyErrors *errors) {
    ms_arena_free(&errors->arena);
    memset(errors, 0, sizeof *errors);
}

void mir_verify_error_text(const MirVerifyError *e, MsBuf *out) {
    ms_buf_put(out, e->func.ptr, e->func.len);
    ms_buf_puts(out, ": ");
    if (e->block != MIR_NONE) {
        ms_buf_printf(out, "b%u: ", e->block);
    }
    ms_buf_put(out, e->message.ptr, e->message.len);
}

/* ---- sets of values: sorted, ascending, no duplicates ---- */

typedef struct MvSet {
    uint32_t *ids;
    uint32_t count, cap;
} MvSet;

/* The index of the first member that is not below `id`. */
static uint32_t mvs_lower_bound(const MvSet *s, uint32_t id) {
    uint32_t lo = 0, hi = s->count;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2;
        if (s->ids[mid] < id) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo;
}

static bool mvs_has(const MvSet *s, uint32_t id) {
    uint32_t at = mvs_lower_bound(s, id);
    return at < s->count && s->ids[at] == id;
}

static void mvs_reserve(MsArena *arena, MvSet *s, uint32_t extra) {
    if (s->count + extra <= s->cap) {
        return;
    }
    uint32_t cap = s->cap == 0 ? 8 : s->cap;
    while (cap < s->count + extra) {
        cap *= 2;
    }
    uint32_t *grown = MS_NEW_N(arena, uint32_t, cap);
    if (s->count > 0) {
        memcpy(grown, s->ids, sizeof *grown * s->count);
    }
    s->ids = grown;
    s->cap = cap;
}

static void mvs_add(MsArena *arena, MvSet *s, uint32_t id) {
    uint32_t at = mvs_lower_bound(s, id);
    if (at < s->count && s->ids[at] == id) {
        return;
    }
    mvs_reserve(arena, s, 1);
    memmove(&s->ids[at + 1], &s->ids[at], sizeof *s->ids * (s->count - at));
    s->ids[at] = id;
    s->count++;
}

/* Removes `id`; false when it was not a member. */
static bool mvs_remove(MvSet *s, uint32_t id) {
    uint32_t at = mvs_lower_bound(s, id);
    if (at >= s->count || s->ids[at] != id) {
        return false;
    }
    memmove(&s->ids[at], &s->ids[at + 1], sizeof *s->ids * (s->count - at - 1));
    s->count--;
    return true;
}

static MvSet mvs_clone(MsArena *arena, const MvSet *s) {
    MvSet c = {0};
    mvs_reserve(arena, &c, s->count);
    if (s->count > 0) {
        memcpy(c.ids, s->ids, sizeof *c.ids * s->count);
    }
    c.count = s->count;
    return c;
}

static bool mvs_equal(const MvSet *a, const MvSet *b) {
    return a->count == b->count && (a->count == 0 || memcmp(a->ids, b->ids, sizeof *a->ids * a->count) == 0);
}

/* `%a, %b, ...` for the values in exactly one of the two sets, ascending. */
static const char *mvs_difference_text(MsArena *arena, const MvSet *a, const MvSet *b) {
    MsBuf text = {0};
    uint32_t i = 0, j = 0;
    while (i < a->count || j < b->count) {
        bool take_a = j >= b->count || (i < a->count && a->ids[i] <= b->ids[j]);
        uint32_t id = take_a ? a->ids[i] : b->ids[j];
        bool both = i < a->count && j < b->count && a->ids[i] == b->ids[j];
        i += (take_a || both) ? 1 : 0;
        j += (!take_a || both) ? 1 : 0;
        if (both) {
            continue;
        }
        ms_buf_printf(&text, text.len == 0 ? "%%%u" : ", %%%u", id);
    }
    const char *s = ms_arena_strndup(arena, text.data == NULL ? "" : text.data, text.len);
    ms_buf_free(&text);
    return s;
}

/* ---- the verifier of one function ---- */

typedef struct Mv {
    MirVerifyErrors *errs;
    MirVerifyCx cx;
    MsArena scratch; /* the analyses and sets of this function */
    bool require_locs;
    uint32_t first; /* errs->count when this function started */
} Mv;

static bool mv_clean(const Mv *v) { return v->errs->count == v->first; }

static MsStr mv_func_name(const Mv *v) {
    return mv_copy(v->errs, ms_name(&v->cx.m->names, v->cx.f->name));
}

static void mv_err(Mv *v, MirBlock block, const char *fmt, ...) MS_PRINTF(3, 4);

static void mv_err(Mv *v, MirBlock block, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    MsStr message = ms_arena_vfmt(&v->errs->arena, fmt, ap);
    va_end(ap);
    mv_push(v->errs, mv_func_name(v), block, message);
}

static const char *mv_type_name(Mv *v, MirTy t) {
    MsBuf b = {0};
    mir_print_ty(v->cx.m, t, &b);
    const char *s = ms_arena_strndup(&v->errs->arena, b.data == NULL ? "" : b.data, b.len);
    ms_buf_free(&b);
    return s;
}

static const char *mv_op_name(const MirInst *in) { return mir_op_info[in->op].name; }

static MirTy mv_ty(const Mv *v, MirValue x) { return v->cx.f->values[x]; }

static bool mv_rc(const Mv *v, MirValue x) { return v->cx.drops[mv_ty(v, x)]; }

/* A function is Raw until `elaborate` runs: it still carries scope markers. */
static bool mv_is_raw(const MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            MirOp op = (MirOp)f->blocks[b].insts[i].op;
            if (op == MOP_ScopeBegin || op == MOP_ScopeOwn || op == MOP_ScopeEnd ||
                op == MOP_ScopeDisown || op == MOP_ScopeMark) {
                return true;
            }
        }
    }
    return false;
}

static MirMode *mv_modes(Mv *v, const MirInst *in) {
    MirMode *modes = MS_NEW_N(&v->scratch, MirMode, in->nargs + 1);
    mir_arg_modes(v->cx.m, v->cx.f, in, modes);
    return modes;
}

/* ---- closures that borrow their maker's frame must not outlive it ---- */

static bool mv_is_clone_into(const MirInst *in, const MirBits *family, MirValue *res) {
    if (in->op != MOP_Clone || in->nargs == 0 || in->res == MIR_NONE ||
        !mir_bits_test(family, in->args[0])) {
        return false;
    }
    *res = in->res;
    return true;
}

static bool mv_seed_family(const Mv *v, MirBits *family) {
    const MirFunc *f = v->cx.f;
    bool any = false;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *in = &f->blocks[b].insts[i];
            if (in->op == MOP_ClosureNew && in->imm.tag == MI_FUNC && in->res != MIR_NONE &&
                in->imm.a < v->cx.m->nfuncs && v->cx.m->funcs[in->imm.a].scoped) {
                mir_bits_set(family, in->res);
                any = true;
            }
        }
    }
    return any;
}

/* One pass over the blocks adding copies and block parameters; true when the family grew. */
static bool mv_grow_family(const Mv *v, MirBits *family) {
    const MirFunc *f = v->cx.f;
    bool grew = false;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            MirValue res = 0;
            if (mv_is_clone_into(&blk->insts[i], family, &res) && !mir_bits_test(family, res)) {
                mir_bits_set(family, res);
                grew = true;
            }
        }
        for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
            const MirTarget *t = mir_term_target_const(&blk->term, k);
            const MirBlockData *dest = &f->blocks[t->block];
            for (uint32_t a = 0; a < t->nargs && a < dest->nparams; a++) {
                MirValue p = dest->params[a].value;
                if (mir_bits_test(family, t->args[a]) && !mir_bits_test(family, p)) {
                    mir_bits_set(family, p);
                    grew = true;
                }
            }
        }
    }
    return grew;
}

static bool mv_keeps_closure(const Mv *v, const MirInst *in, uint32_t pos, MirMode mode,
                             const MirBits *frame_slots) {
    /* A call to a function that keeps its closures, or the closure such a function builds around
     * one, is held by the checker until the promise is dropped. */
    bool entry = (in->op == MOP_Call || in->op == MOP_ClosureNew) && in->imm.tag == MI_FUNC &&
                 v->cx.m->funcs[in->imm.a].keeps_scoped;
    if (entry) {
        return false;
    }
    switch ((MirOp)in->op) {
    case MOP_Drop: case MOP_Forget: case MOP_DropIf: case MOP_Clone: case MOP_CallInd:
        return false;
    case MOP_Store:
        /* A stack slot of this frame cannot outlive it. */
        return pos == 1 && !mir_bits_test(frame_slots, in->args[0]);
    default:
        return mode == MM_MOVE;
    }
}

static void mv_check_closure_uses(Mv *v, const MirBits *family, const MirBits *frame_slots) {
    const MirFunc *f = v->cx.f;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            const MirInst *in = &blk->insts[i];
            const MirMode *modes = mv_modes(v, in);
            for (uint32_t k = 0; k < in->nargs; k++) {
                if (mir_bits_test(family, in->args[k]) &&
                    mv_keeps_closure(v, in, k, modes[k], frame_slots)) {
                    mv_err(v, b, "a closure that borrows its maker's variables is kept by %s",
                           mv_op_name(in));
                }
            }
        }
        if (blk->term.kind == MT_RET && blk->term.value != MIR_NONE &&
            mir_bits_test(family, blk->term.value)) {
            mv_err(v, b, "a closure that borrows its maker's variables is returned");
        }
    }
}

static void mv_scoped_closures(Mv *v) {
    const MirFunc *f = v->cx.f;
    MirBits family = mir_bits_new(&v->scratch, f->nvalues);
    if (!mv_seed_family(v, &family)) {
        return;
    }
    while (mv_grow_family(v, &family)) {
    }
    MirBits slots = mir_bits_new(&v->scratch, f->nvalues);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *in = &f->blocks[b].insts[i];
            if (in->op == MOP_Slot && in->res != MIR_NONE) {
                mir_bits_set(&slots, in->res);
            }
        }
    }
    mv_check_closure_uses(v, &family, &slots);
}

/* ---- shape: entry block, definitions, dominance ---- */

/* Where a value is defined: `index` is -1 for a block parameter. */
typedef struct MvDef {
    bool defined;
    uint32_t block;
    int64_t index;
} MvDef;

/* The entry block's parameters mirror the signature; false when they do not. */
static bool mv_check_entry(Mv *v) {
    const MirFunc *f = v->cx.f;
    const MirBlockData *entry = &f->blocks[0];
    if (entry->nparams != f->nparams) {
        mv_err(v, 0, "entry block parameters do not match the function signature");
        return false;
    }
    for (uint32_t i = 0; i < f->nparams; i++) {
        const MirBlockParam *bp = &entry->params[i];
        const MirParam *p = &f->params[i];
        if (bp->value >= f->nvalues || mv_ty(v, bp->value) != p->ty ||
            (v->cx.drops[p->ty] && bp->mode != p->mode)) {
            mv_err(v, 0, "entry block parameter differs from the signature");
            return false;
        }
    }
    return true;
}

static void mv_check_function_kind(Mv *v) {
    const MirFunc *f = v->cx.f;
    if (f->kind == MFK_NORMAL) {
        return;
    }
    if (f->nparams == 0 || f->params[0].ty != MIR_PTR) {
        mv_err(v, MIR_NONE, "closure and method functions take the erased environment/receiver as parameter 0 (ptr)");
    }
    if (f->nparams > 0 && f->params[0].mode == MM_MOVE) {
        mv_err(v, MIR_NONE, "closure and method functions borrow their environment/receiver");
    }
}

static void mv_define(Mv *v, MvDef *defs, MirValue x, uint32_t block, int64_t index,
                      const char *what) {
    if (x >= v->cx.f->nvalues) {
        mv_err(v, MIR_NONE, "%s Value(%u) out of range", what, x);
    } else if (defs[x].defined) {
        mv_err(v, MIR_NONE, "%%%u defined twice", x);
    } else {
        defs[x] = (MvDef){true, block, index};
    }
}

static MvDef *mv_collect_defs(Mv *v) {
    const MirFunc *f = v->cx.f;
    MvDef *defs = MS_NEW_N(&v->scratch, MvDef, f->nvalues + 1);
    memset(defs, 0, sizeof *defs * (f->nvalues + 1));
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = 0; i < blk->nparams; i++) {
            mv_define(v, defs, blk->params[i].value, b, -1, "block parameter");
        }
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            if (blk->insts[i].res != MIR_NONE) {
                mv_define(v, defs, blk->insts[i].res, b, (int64_t)i, "result");
            }
        }
    }
    return defs;
}

/* The dominator tree as entry and exit numbers of a depth-first walk, so "a dominates b" is two
 * comparisons rather than a climb up the tree: that climb made a use of a value defined at the top of
 * a long function cost its depth, and verification quadratic. Unreachable blocks have no numbers. */
typedef struct MvFlow {
    const MvDef *defs;
    const uint32_t *tin;
    const uint32_t *tout;
} MvFlow;

static MvFlow mv_flow(Mv *v, const MvDef *defs, const MirBlock *idom) {
    const uint32_t n = v->cx.f->nblocks;
    uint32_t *tin = MS_NEW_N(&v->scratch, uint32_t, n);
    uint32_t *tout = MS_NEW_N(&v->scratch, uint32_t, n);
    uint32_t *child = MS_NEW_N(&v->scratch, uint32_t, n); /* first child, then the next sibling chain */
    uint32_t *sibling = MS_NEW_N(&v->scratch, uint32_t, n);
    uint32_t *stack = MS_NEW_N(&v->scratch, uint32_t, n);
    for (uint32_t b = 0; b < n; b++) {
        tin[b] = tout[b] = child[b] = sibling[b] = MIR_NONE;
    }
    for (uint32_t b = n; b-- > 1;) {
        if (idom[b] != MIR_NONE && idom[b] != b) {
            sibling[b] = child[idom[b]];
            child[idom[b]] = b;
        }
    }
    uint32_t clock = 0, top = 0;
    if (n > 0) {
        tin[0] = clock++;
        stack[top++] = 0;
    }
    while (top > 0) {
        const uint32_t b = stack[top - 1];
        const uint32_t next = child[b];
        if (next == MIR_NONE) {
            tout[b] = clock++;
            top--;
        } else {
            child[b] = sibling[next];
            tin[next] = clock++;
            stack[top++] = next;
        }
    }
    return (MvFlow){defs, tin, tout};
}

static bool mv_dominates(const MvFlow *flow, MirBlock a, MirBlock b) {
    if (a == b) {
        return true;
    }
    if (flow->tin[a] == MIR_NONE || flow->tin[b] == MIR_NONE) {
        return false;
    }
    return flow->tin[a] < flow->tin[b] && flow->tout[b] < flow->tout[a];
}

/* Whether the use of `x` at instruction `index` of `block` follows its definition. */
static bool mv_use_ok(Mv *v, const MvFlow *flow, MirValue x, MirBlock block, int64_t index,
                      const char *what) {
    if (x >= v->cx.f->nvalues || !flow->defs[x].defined) {
        mv_err(v, block, "%s: use of undefined value %%%u", what, x);
        return false;
    }
    const MvDef *d = &flow->defs[x];
    bool ok = d->block == block ? d->index < index : mv_dominates(flow, d->block, block);
    if (!ok) {
        mv_err(v, block, "%s: %%%u does not dominate its use", what, x);
    }
    return ok;
}

/* ---- per-instruction and per-terminator checks ---- */

static void mv_check_inst(Mv *v, const MvFlow *flow, MirBlock bi, uint32_t ii) {
    const MirInst *in = &v->cx.f->blocks[bi].insts[ii];
    const char *name = mv_op_name(in);
    if (v->require_locs && mir_loc_none(in->loc)) {
        mv_err(v, bi, "%s: missing source location", name);
    }
    /* The lowering re-invokes the function from the check on a new stack segment with the entry
     * block's parameters, so nothing may run before it. */
    if (in->op == MOP_DepthEnter && (bi != 0 || ii != 0)) {
        mv_err(v, bi, "%s: must be the first instruction of the entry block", name);
    }
    bool ok = true;
    for (uint32_t k = 0; k < in->nargs; k++) {
        ok &= mv_use_ok(v, flow, in->args[k], bi, (int64_t)ii, name);
    }
    if ((mir_op_info[in->op].has_result != 0) != (in->res != MIR_NONE)) {
        mv_err(v, bi, "%s: result presence does not match the opcode", name);
        return;
    }
    if (!ok) {
        return;
    }
    const char *why = mir_verify_inst_types(&v->cx, in);
    if (why != NULL) {
        mv_err(v, bi, "%s: %s", name, why);
    }
}

typedef struct MvUses {
    Mv *v;
    const MvFlow *flow;
    MirBlock block;
    int64_t index;
    bool ok;
} MvUses;

static void mv_term_use(void *ctx, MirValue *x) { // NOLINT(readability-non-const-parameter): the MirUseFn signature lets other users rewrite the operand
    MvUses *u = ctx;
    u->ok &= mv_use_ok(u->v, u->flow, *x, u->block, u->index, "terminator");
}

static void mv_check_target(Mv *v, MirBlock bi, const MirTarget *t) {
    const MirFunc *f = v->cx.f;
    if (t->block >= f->nblocks) {
        mv_err(v, bi, "branch to a nonexistent block");
        return;
    }
    const MirBlockData *dest = &f->blocks[t->block];
    if (t->nargs != dest->nparams) {
        mv_err(v, bi, "branch to b%u passes %u arguments for %u parameters", t->block, t->nargs,
               dest->nparams);
        return;
    }
    for (uint32_t k = 0; k < t->nargs; k++) {
        MirTy have = mv_ty(v, t->args[k]), want = mv_ty(v, dest->params[k].value);
        if (have != want) {
            const char *have_name = mv_type_name(v, have);
            mv_err(v, bi, "branch to b%u: argument %%%u has type %s but the parameter has %s",
                   t->block, t->args[k], have_name, mv_type_name(v, want));
        }
    }
}

static void mv_check_term_kind(Mv *v, MirBlock bi) {
    const MirFunc *f = v->cx.f;
    const MirTerm *t = &f->blocks[bi].term;
    switch ((MirTermKind)t->kind) {
    case MT_CONDBR:
        if (mv_ty(v, t->value) != MIR_BOOL) {
            mv_err(v, bi, "condition must be bool");
        }
        break;
    case MT_SWITCH:
        if (mv_ty(v, t->value) != MIR_INT) {
            mv_err(v, bi, "switch value must be int");
        }
        break;
    case MT_RET: {
        MirTy ty = t->value == MIR_NONE ? (MirTy)MIR_VOID : mv_ty(v, t->value);
        if (ty != f->ret) {
            const char *have = mv_type_name(v, ty);
            mv_err(v, bi, "returns %s but the function returns %s", have, mv_type_name(v, f->ret));
        }
        break;
    }
    case MT_FAULT:
        if (t->fault == MF_MESSAGE && t->fault_str >= v->cx.m->strings.count) {
            mv_err(v, bi, "fault message literal out of range");
        }
        break;
    case MT_BR: case MT_UNREACHABLE:
        break;
    }
}

static void mv_check_term(Mv *v, const MvFlow *flow, MirBlock bi) {
    MirBlockData *blk = &v->cx.f->blocks[bi];
    MirTerm term = blk->term; /* a copy: the use walk takes a mutable terminator */
    MvUses uses = {v, flow, bi, (int64_t)blk->ninsts, true};
    mir_term_each_use(&term, mv_term_use, &uses);
    if (!uses.ok) {
        return;
    }
    for (uint32_t k = 0; k < mir_term_ntargets(&term); k++) {
        mv_check_target(v, bi, mir_term_target_const(&term, k));
    }
    mv_check_term_kind(v, bi);
}

static void mv_check_block(Mv *v, const MvFlow *flow, MirBlock bi) {
    for (uint32_t ii = 0; ii < v->cx.f->blocks[bi].ninsts; ii++) {
        mv_check_inst(v, flow, bi, ii);
    }
    mv_check_term(v, flow, bi);
}

/* ---- ownership ---- */

typedef struct MvOwn {
    Mv *v;
    bool *owned_def;        /* the value is defined owned */
    MirValue *owner_of;     /* the owned value a borrow points into, or MIR_NONE */
    bool *views;            /* the value points into its operands */
    MirValue *pointer_owner; /* the owner a pointer from a runtime lookup points into */
    bool *watched;          /* some borrow points into the owner: its drops matter */
    uint64_t **dropped_in;  /* per block: bit set of owners an explicit drop released on some path there, or NULL */
    uint64_t *dropped;      /* the block being walked: the same set, reused across blocks */
    uint32_t words;         /* 64-bit words in one bit set over the function's values */
    MvSet *entry_state;     /* per block: the live set on its first incoming edge */
    bool *has_entry;
    bool *back_target;      /* some edge into the block comes from a later block: its entry state is read again */
    MirValue *scratch_values; /* room for the largest operand list */
} MvOwn;

static bool *mv_flags(Mv *v, uint32_t n) {
    bool *p = MS_NEW_N(&v->scratch, bool, n + 1);
    memset(p, 0, sizeof *p * (n + 1));
    return p;
}

static MirValue *mv_values_none(Mv *v, uint32_t n) {
    MirValue *p = MS_NEW_N(&v->scratch, MirValue, n + 1);
    for (uint32_t i = 0; i <= n; i++) {
        p[i] = MIR_NONE;
    }
    return p;
}

static uint32_t mv_max_operands(const MirFunc *f) {
    uint32_t most = 0;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            most = blk->insts[i].nargs > most ? blk->insts[i].nargs : most;
        }
        for (uint32_t k = 0; k < mir_term_ntargets(&blk->term); k++) {
            uint32_t n = mir_term_target_const(&blk->term, k)->nargs;
            most = n > most ? n : most;
        }
    }
    return most;
}

/* Ownership mode of every value from its definition, and which block parameters take a borrowing
 * variant's views. */
static void mv_own_init(Mv *v, MvOwn *o) {
    const MirModule *m = v->cx.m;
    const MirFunc *f = v->cx.f;
    o->v = v;
    o->owned_def = mv_flags(v, f->nvalues);
    o->views = mv_flags(v, f->nvalues);
    o->watched = mv_flags(v, f->nvalues);
    o->owner_of = mv_values_none(v, f->nvalues);
    o->pointer_owner = mv_values_none(v, f->nvalues);
    o->words = f->nvalues / 64 + 1;
    o->dropped_in = MS_NEW_N(&v->scratch, uint64_t *, f->nblocks + 1);
    o->dropped = MS_NEW_N(&v->scratch, uint64_t, o->words);
    o->entry_state = MS_NEW_N(&v->scratch, MvSet, f->nblocks + 1);
    memset(o->dropped_in, 0, sizeof *o->dropped_in * (f->nblocks + 1));
    memset(o->dropped, 0, sizeof *o->dropped * o->words);
    memset(o->entry_state, 0, sizeof *o->entry_state * (f->nblocks + 1));
    o->has_entry = mv_flags(v, f->nblocks);
    o->back_target = mv_flags(v, f->nblocks);
    o->scratch_values = mv_values_none(v, mv_max_operands(f));
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *blk = &f->blocks[b];
        for (uint32_t i = 0; i < blk->nparams; i++) {
            MirValue p = blk->params[i].value;
            o->owned_def[p] = mv_rc(v, p) && blk->params[i].mode == MM_MOVE;
            const MirTyData *d = mir_ty_data(m, mv_ty(v, p));
            o->views[p] = d->kind == MK_ALT && m->alts[d->id].borrowed != 0;
        }
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            MirMode mode = MM_BORROW;
            const MirInst *in = &blk->insts[i];
            if (mir_result_mode(m, f, in, &mode) && mode == MM_MOVE) {
                o->owned_def[in->res] = true;
            }
        }
    }
}

/* The owned value `x` is, or the one it points into. */
static MirValue mv_owner_or_self(const MvOwn *o, MirValue x) {
    return o->owned_def[x] ? x : o->owner_of[x];
}

/* The dropped owners are a bit set over value ids, not a sorted array: a long function drops
 * thousands of watched owners and every block carries them, so the array form made verification
 * quadratic in memory with a large constant. */
static bool mvd_has(const uint64_t *bits, uint32_t id) {
    return (bits[id / 64] >> (id % 64) & 1) != 0;
}

/* Adds the set `from` to the one a successor block starts with. */
static void mvd_merge_into(MvOwn *o, MirBlock target, const uint64_t *from) {
    uint32_t last = o->words;
    while (last > 0 && from[last - 1] == 0) {
        last--;
    }
    if (last == 0) {
        return;
    }
    uint64_t **into = &o->dropped_in[target];
    if (*into == NULL) {
        *into = MS_NEW_N(&o->v->scratch, uint64_t, o->words);
        memset(*into, 0, sizeof **into * o->words);
    }
    for (uint32_t i = 0; i < last; i++) {
        (*into)[i] |= from[i];
    }
}

static void mv_report_dead_borrow(Mv *v, MirBlock bi, const MirInst *in, const uint64_t *dropped,
                                  const MvOwn *o) {
    for (uint32_t k = 0; k < in->nargs; k++) {
        MirValue owner = o->owner_of[in->args[k]];
        if (owner != MIR_NONE && mvd_has(dropped, owner)) {
            mv_err(v, bi, "%s: %%%u points into %%%u, which was consumed before this use",
                   mv_op_name(in), in->args[k], owner);
        }
    }
}

/* Records what the result of `in` points into. */
static void mv_track_result(MvOwn *o, const MirInst *in) {
    const Mv *v = o->v;
    MirValue r = in->res;
    if (r == MIR_NONE) {
        return;
    }
    o->views[r] = mir_result_views(v->cx.m, v->cx.f, in);
    if (in->nargs == 0) {
        return;
    }
    MirValue first = in->args[0];
    bool borrows_first = mv_rc(v, first) && !o->views[first];
    if (mv_rc(v, r) && !o->owned_def[r] && borrows_first) {
        o->owner_of[r] = mv_owner_or_self(o, first);
        if (o->owner_of[r] != MIR_NONE) {
            o->watched[o->owner_of[r]] = true;
        }
    }
    /* A runtime lookup (a map entry) returns a pointer into its first operand's storage, and a
     * `load` of that pointer reads a borrow of the same owner. */
    if (in->op == MOP_CallRt && !mv_rc(v, r) && borrows_first) {
        o->pointer_owner[r] = mv_owner_or_self(o, first);
    } else if (in->op == MOP_Load && mv_rc(v, r) && !o->owned_def[r] &&
               o->pointer_owner[first] != MIR_NONE) {
        o->owner_of[r] = o->pointer_owner[first];
        o->watched[o->owner_of[r]] = true;
    }
}

static bool mv_seen(const MirValue *list, uint32_t n, MirValue x) {
    for (uint32_t i = 0; i < n; i++) {
        if (list[i] == x) {
            return true;
        }
    }
    return false;
}

/* The operands of `in` against the live set: uses of consumed values, borrows passed to a moving
 * position and values consumed twice. */
static void mv_check_operands(MvOwn *o, MirBlock bi, const MirInst *in, MvSet *live) {
    Mv *v = o->v;
    const MirMode *modes = mv_modes(v, in);
    MirValue *consumed = o->scratch_values;
    uint32_t nconsumed = 0;
    for (uint32_t k = 0; k < in->nargs; k++) {
        MirValue a = in->args[k];
        if (!mv_rc(v, a)) {
            continue;
        }
        if (o->owned_def[a] && !mvs_has(live, a)) {
            mv_err(v, bi, "%s: %%%u used after it was consumed", mv_op_name(in), a);
        } else if (modes[k] != MM_MOVE) {
            continue;
        } else if (!o->owned_def[a]) {
            mv_err(v, bi, "%s: moving position needs an owned value, %%%u is borrowed (retain it first)",
                   mv_op_name(in), a);
        } else if (mv_seen(consumed, nconsumed, a)) {
            mv_err(v, bi, "%s: %%%u consumed twice", mv_op_name(in), a);
        } else {
            consumed[nconsumed++] = a;
        }
    }
    for (uint32_t k = 0; k < in->nargs; k++) {
        if (modes[k] == MM_BORROW && mv_seen(consumed, nconsumed, in->args[k])) {
            mv_err(v, bi, "%s: %%%u is consumed and borrowed by the same instruction",
                   mv_op_name(in), in->args[k]);
        }
    }
    for (uint32_t k = 0; k < nconsumed; k++) {
        (void)mvs_remove(live, consumed[k]);
    }
}

static void mv_own_inst(MvOwn *o, MirBlock bi, const MirInst *in, MvSet *live, uint64_t *dropped) {
    Mv *v = o->v;
    mv_report_dead_borrow(v, bi, in, dropped, o);
    if ((in->op == MOP_Drop || in->op == MOP_DropIf) && in->nargs > 0 && o->watched[in->args[0]]) {
        dropped[in->args[0] / 64] |= (uint64_t)1 << (in->args[0] % 64);
    }
    mv_track_result(o, in);
    mv_check_operands(o, bi, in, live);
    if (in->res != MIR_NONE && o->owned_def[in->res]) {
        mvs_add(&v->scratch, live, in->res);
    }
}

static void mv_own_ret(MvOwn *o, MirBlock bi, const MirTerm *t, MvSet *live) {
    Mv *v = o->v;
    MirValue x = t->value;
    if (x != MIR_NONE && mv_rc(v, x)) {
        if (v->cx.f->ret_borrowed) {
            if (o->owned_def[x]) {
                mv_err(v, bi, "ret: %%%u is owned, but this function returns a borrow; it would leak", x);
            }
        } else if (!o->owned_def[x]) {
            mv_err(v, bi, "ret: %%%u is borrowed; return an owned value (retain it first)", x);
        } else if (!mvs_remove(live, x)) {
            mv_err(v, bi, "ret: %%%u used after it was consumed", x);
        }
    }
    if (live->count > 0) {
        mv_err(v, bi, "ret: owned value %%%u is never released", live->ids[0]);
    }
}

/* The live set a successor starts with, after the edge's arguments are passed. */
static MvSet mv_edge_live(MvOwn *o, MirBlock bi, const MirTarget *t, const MvSet *live, bool last) {
    Mv *v = o->v;
    const MirBlockData *dest = &v->cx.f->blocks[t->block];
    /* The last edge out of a block takes the block's set as it is when it passes no values: the block
     * is finished with it, and copying it for every block made a long function quadratic. */
    MvSet after = last && t->nargs == 0 ? *live : mvs_clone(&v->scratch, live);
    MirValue *seen = o->scratch_values;
    uint32_t nseen = 0;
    for (uint32_t k = 0; k < t->nargs; k++) {
        MirValue a = t->args[k];
        if (!mv_rc(v, a)) {
            continue;
        }
        if (o->owned_def[a] && !mvs_has(live, a)) {
            mv_err(v, bi, "branch: %%%u used after it was consumed", a);
        } else if (dest->params[k].mode != MM_MOVE) {
            continue;
        } else if (!o->owned_def[a]) {
            mv_err(v, bi, "branch to b%u: parameter %%%u takes ownership but %%%u is borrowed",
                   t->block, dest->params[k].value, a);
        } else if (mv_seen(seen, nseen, a)) {
            mv_err(v, bi, "branch to b%u: %%%u passed to two owning parameters", t->block, a);
        } else {
            seen[nseen++] = a;
            (void)mvs_remove(&after, a);
        }
    }
    return after;
}

/* Merges the live set `after` arriving over an edge into the successor's entry state. */
static void mv_merge_entry(MvOwn *o, MirBlock bi, MirBlock dest, MvSet after) {
    Mv *v = o->v;
    if (!o->has_entry[dest]) {
        o->has_entry[dest] = true;
        o->entry_state[dest] = after;
        return;
    }
    if (!mvs_equal(&o->entry_state[dest], &after)) {
        const char *diff = mvs_difference_text(&v->errs->arena, &o->entry_state[dest], &after);
        mv_err(v, bi, "branch to b%u: owned values differ between incoming edges (%s)", dest, diff);
    }
}

static void mv_own_edges(MvOwn *o, MirBlock bi, const MirTerm *term, const MvSet *live,
                         const uint64_t *dropped) {
    Mv *v = o->v;
    uint32_t n = mir_term_ntargets(term);
    /* A borrow handed to a successor reads its owner's storage there, so the owner must not have
     * been dropped on the way. */
    for (uint32_t k = 0; k < n; k++) {
        const MirTarget *t = mir_term_target_const(term, k);
        for (uint32_t a = 0; a < t->nargs; a++) {
            MirValue owner = o->owner_of[t->args[a]];
            if (owner != MIR_NONE && mvd_has(dropped, owner)) {
                mv_err(v, bi, "branch: %%%u points into %%%u, which was consumed before this use",
                       t->args[a], owner);
            }
        }
    }
    for (uint32_t k = 0; k < n; k++) {
        const MirTarget *t = mir_term_target_const(term, k);
        mvd_merge_into(o, t->block, dropped);
        mv_merge_entry(o, bi, t->block, mv_edge_live(o, bi, t, live, k + 1 == n));
    }
}

/* The blocks reachable from the entry in order; `live` starts as the entry state of the block. */
static bool mv_own_block_start(MvOwn *o, MirBlock bi, MvSet *live) {
    const MirBlockData *blk = &o->v->cx.f->blocks[bi];
    if (o->has_entry[bi]) {
        /* Every forward edge into the block has been merged by now, so only a later (back) edge
         * reads its entry state again; otherwise the block works on it in place. */
        *live = o->back_target[bi] ? mvs_clone(&o->v->scratch, &o->entry_state[bi]) : o->entry_state[bi];
    } else if (bi != 0) {
        return false;
    }
    for (uint32_t i = 0; i < blk->nparams; i++) {
        if (o->owned_def[blk->params[i].value]) {
            mvs_add(&o->v->scratch, live, blk->params[i].value);
        }
    }
    return true;
}

static void mv_own_block(MvOwn *o, MirBlock bi) {
    const MirBlockData *blk = &o->v->cx.f->blocks[bi];
    MvSet live = {0};
    if (!mv_own_block_start(o, bi, &live)) {
        return;
    }
    uint64_t *dropped = o->dropped;
    if (o->dropped_in[bi] != NULL) {
        memcpy(dropped, o->dropped_in[bi], sizeof *dropped * o->words);
    } else {
        memset(dropped, 0, sizeof *dropped * o->words);
    }
    for (uint32_t i = 0; i < blk->ninsts; i++) {
        mv_own_inst(o, bi, &blk->insts[i], &live, dropped);
    }
    if (blk->term.kind == MT_RET) {
        mv_own_ret(o, bi, &blk->term, &live);
    }
    mv_own_edges(o, bi, &blk->term, &live, dropped);
}

static void mv_check_ownership(Mv *v, const MirBlock *rpo, uint32_t count) {
    MvOwn o;
    mv_own_init(v, &o);
    uint32_t *rank = MS_NEW_N(&v->scratch, uint32_t, v->cx.f->nblocks + 1);
    for (uint32_t i = 0; i < count; i++) {
        rank[rpo[i]] = i;
    }
    for (uint32_t i = 0; i < count; i++) {
        const MirTerm *term = &v->cx.f->blocks[rpo[i]].term;
        for (uint32_t k = 0; k < mir_term_ntargets(term); k++) {
            const MirBlock to = mir_term_target_const(term, k)->block;
            if (rank[to] <= i) {
                o.back_target[to] = true;
            }
        }
    }
    for (uint32_t i = 0; i < count; i++) {
        mv_own_block(&o, rpo[i]);
    }
}

/* ---- one function ---- */

static void mv_check_blocks(Mv *v, const MvDef *defs) {
    const MirFunc *f = v->cx.f;
    MirBlock *rpo = NULL;
    uint32_t count = mir_rpo(&v->scratch, f, &rpo);
    MirPreds preds = mir_preds(&v->scratch, f);
    if (mir_preds_count(&preds, 0) > 0) {
        mv_err(v, 0, "the entry block must not have predecessors");
    }
    MvFlow flow = mv_flow(v, defs, mir_dominators(&v->scratch, f, rpo, count, &preds));
    for (uint32_t i = 0; i < count; i++) {
        mv_check_block(v, &flow, rpo[i]);
    }
    /* A Raw function leaves its drops to `elaborate`, so its ownership is checked after it. */
    if (mv_clean(v) && !mv_is_raw(f)) {
        mv_check_ownership(v, rpo, count);
    }
}

static void mv_run(Mv *v) {
    const MirFunc *f = v->cx.f;
    if (f->nblocks == 0) {
        mv_err(v, MIR_NONE, "function has no blocks");
        return;
    }
    if (!mv_check_entry(v)) {
        return;
    }
    mv_check_function_kind(v);
    const MvDef *defs = mv_collect_defs(v);
    if (!mv_clean(v)) {
        return;
    }
    mv_check_blocks(v, defs);
}

static void mv_function(MirVerifyErrors *errs, const MirModule *m, const MirFunc *f,
                        const bool *drops, bool require_locs) {
    Mv v = {.errs = errs,
            .cx = {m, f, drops, &errs->arena},
            .scratch = {0},
            .require_locs = require_locs,
            .first = errs->count};
    mv_run(&v);
    if (mv_clean(&v)) {
        mv_scoped_closures(&v);
    }
    ms_arena_free(&v.scratch);
}

/* ---- module ---- */

static void mv_module_err(MirVerifyErrors *errs, const char *fmt, ...) MS_PRINTF(2, 3);

static void mv_module_err(MirVerifyErrors *errs, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    MsStr message = ms_arena_vfmt(&errs->arena, fmt, ap);
    va_end(ap);
    MsStr func = {"<module>", 8};
    mv_push(errs, func, MIR_NONE, message);
}

static const char *mv_sym(MirVerifyErrors *errs, const MirModule *m, MsSym s) {
    MsStr n = ms_name(&m->names, s);
    return ms_arena_strndup(&errs->arena, n.ptr, n.len);
}

/* Whether `f` implements interface method `sig`: a method function taking the receiver first. */
static bool mv_implements(const MirFunc *f, const MirMethodSig *sig) {
    if (f->kind != MFK_METHOD || f->nparams != sig->nparams + 1 || f->ret != sig->ret) {
        return false;
    }
    for (uint32_t k = 0; k < sig->nparams; k++) {
        const MirParam *p = &f->params[k + 1];
        if (p->ty != sig->params[k] || (p->mode == MM_MOVE) != mir_owns(sig->owned, k)) {
            return false;
        }
    }
    return true;
}

static void mv_check_vtable(MirVerifyErrors *errs, const MirModule *m, uint32_t index) {
    const MirVtable *vt = &m->vtables[index];
    const MirIfaceDef *iface = &m->ifaces[vt->iface];
    if (vt->nmethods != iface->nmethods) {
        mv_module_err(errs, "vtable %s has %u methods, interface %s has %u", mv_sym(errs, m, vt->name),
                      vt->nmethods, mv_sym(errs, m, iface->name), iface->nmethods);
        return;
    }
    for (uint32_t k = 0; k < vt->nmethods; k++) {
        const MirFunc *f = &m->funcs[vt->methods[k]];
        if (!mv_implements(f, &iface->methods[k])) {
            mv_module_err(errs, "vtable %s (#%u): function %s does not implement method %s",
                          mv_sym(errs, m, vt->name), index, mv_sym(errs, m, f->name),
                          mv_sym(errs, m, iface->methods[k].name));
        }
    }
}

static void mv_check_declarations(MirVerifyErrors *errs, const MirModule *m) {
    for (uint32_t i = 0; i < m->nvtables; i++) {
        mv_check_vtable(errs, m, i);
    }
    if (m->entry != MIR_NONE) {
        const MirFunc *f = &m->funcs[m->entry];
        if (f->nparams != 0 || f->ret != MIR_INT) {
            mv_module_err(errs, "entry %s must be fn() -> int", mv_sym(errs, m, f->name));
        }
    }
}

bool mir_verify_module(const MirModule *m, bool require_locs, MirVerifyErrors *out) {
    mv_check_declarations(out, m);
    bool *drops = malloc(sizeof *drops * (m->types.len + 1));
    if (drops == NULL) {
        abort();
    }
    for (uint32_t t = 0; t < m->types.len; t++) {
        drops[t] = mir_needs_drop(m, t);
    }
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        mv_function(out, m, &m->funcs[i], drops, require_locs);
    }
    free(drops);
    return out->count == 0;
}
