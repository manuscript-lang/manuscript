/* MIR builder: appends instructions to a function under construction and turns mutable
 * variables into block parameters (Braun et al.). Port of crates/ms-mir/src/builder.rs; the
 * block-parameter results, including the removal of trivial parameters, equal the Rust builder's.
 * Owns its scratch tables (an arena freed by `mir_b_into_func`); the function lives in the
 * module's arena. */
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_builder.h"

/* A variable read recurses once per block on a path, so this many nested reads means a cycle of
 * sealed single-predecessor blocks no read can resolve: the build fails instead of overflowing. */
enum { MB_MAX_DEPTH = 100000 };

/* ---- scratch tables ---- */

static void *scratch_grow(MsArena *arena, void *arr, uint32_t *cap, uint32_t n, size_t elem) {
    const uint32_t next = *cap ? *cap * 2 : 8;
    void *grown = ms_alloc(arena, elem * next, _Alignof(max_align_t));
    if (n > 0) {
        memcpy(grown, arr, elem * n);
    }
    *cap = next;
    return grown;
}

static MirBlockLinks *links_of(MirBuilder *b, MirBlock block) {
    if (block >= b->clinks) {
        uint32_t cap = b->clinks ? b->clinks : 16;
        while (cap <= block) {
            cap *= 2;
        }
        MirBlockLinks *grown = MS_NEW_N(&b->scratch, MirBlockLinks, cap);
        memset(grown, 0, sizeof(MirBlockLinks) * cap);
        if (b->clinks > 0) {
            memcpy(grown, b->links, sizeof(MirBlockLinks) * b->clinks);
        }
        b->links = grown;
        b->clinks = cap;
    }
    return &b->links[block];
}

static uint32_t def_hash(MirVar var, MirBlock block) {
    return (var * 0x9E3779B1u) ^ (block * 0x85EBCA6Bu);
}

static MirVarDef *def_find(MirBuilder *b, MirVar var, MirBlock block) {
    if (b->cdefs == 0) {
        return NULL;
    }
    for (uint32_t i = def_hash(var, block) & (b->cdefs - 1);; i = (i + 1) & (b->cdefs - 1)) {
        MirVarDef *slot = &b->defs[i];
        if (!slot->used) {
            return NULL;
        }
        if (slot->var == var && slot->block == block) {
            return slot;
        }
    }
}

static void def_rehash(MirBuilder *b) {
    const uint32_t cap = b->cdefs ? b->cdefs * 2 : 64;
    MirVarDef *old = b->defs;
    const uint32_t old_cap = b->cdefs;
    b->defs = MS_NEW_N(&b->scratch, MirVarDef, cap);
    memset(b->defs, 0, sizeof(MirVarDef) * cap);
    b->cdefs = cap;
    for (uint32_t i = 0; i < old_cap; i++) {
        if (!old[i].used) {
            continue;
        }
        uint32_t k = def_hash(old[i].var, old[i].block) & (cap - 1);
        while (b->defs[k].used) {
            k = (k + 1) & (cap - 1);
        }
        b->defs[k] = old[i];
    }
}

static void def_set(MirBuilder *b, MirVar var, MirBlock block, MirValue value) {
    MirVarDef *slot = def_find(b, var, block);
    if (slot != NULL) {
        slot->value = value;
        return;
    }
    if ((size_t)(b->ndefs + 1) * 2 > b->cdefs) {
        def_rehash(b);
    }
    uint32_t k = def_hash(var, block) & (b->cdefs - 1);
    while (b->defs[k].used) {
        k = (k + 1) & (b->cdefs - 1);
    }
    b->defs[k] = (MirVarDef){var, block, value, true};
    b->ndefs++;
}

/* ---- construction ---- */

void mir_b_init(MirBuilder *b, MirModule *m, MsSym name, const MirParam *params, uint32_t nparams,
                MirTy ret) {
    memset(b, 0, sizeof *b);
    b->m = m;
    b->loc = MIR_LOC_NONE;
    mir_func_init(m, &b->f, name, params, nparams, ret);
    links_of(b, 0)->sealed = true;
}

void mir_b_init_fast_path(MirBuilder *b, MirModule *m, MsSym name, const MirParam *params,
                          uint32_t nparams, MirTy ret) {
    mir_b_init(b, m, name, params, nparams, ret);
    b->f.linkage = ML_INTERNAL;
    b->f.inline_hint = MINL_ALWAYS;
}

void mir_b_params(const MirBuilder *b, MirValue *out, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        out[i] = i < b->f.blocks[0].nparams ? b->f.blocks[0].params[i].value : MIR_NONE; /* every slot is written */
    }
}

MirBlock mir_b_new_block(MirBuilder *b) {
    const MirBlock block = mir_new_block(b->m, &b->f);
    links_of(b, block)->sealed = false;
    return block;
}

MirValue mir_b_add_block_param(MirBuilder *b, MirBlock block, MirTy ty, MirMode mode) {
    const MirValue v = mir_new_value(b->m, &b->f, ty);
    MirBlockData *blk = &b->f.blocks[block];
    const MirBlockParam param = {v, (uint8_t)mode};
    MIR_PUSH(b->m, blk->params, blk->nparams, blk->cparams, MirBlockParam, param);
    return v;
}

static MirValue *copy_values(MirBuilder *b, const MirValue *values, uint32_t n) {
    if (n == 0) {
        return NULL;
    }
    MirValue *copy = MS_NEW_N(&b->m->arena, MirValue, n);
    memcpy(copy, values, sizeof(MirValue) * n);
    return copy;
}

MirValue mir_b_emit(MirBuilder *b, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
                    MirTy res_ty) {
    MirInst inst = {0};
    inst.op = (uint8_t)op;
    inst.imm = imm;
    inst.res = res_ty == MIR_NONE ? MIR_NONE : mir_new_value(b->m, &b->f, res_ty);
    inst.loc = b->loc;
    inst.args = copy_values(b, args, nargs);
    inst.nargs = nargs;
    MirBlockData *blk = &b->f.blocks[b->cur];
    MIR_PUSH(b->m, blk->insts, blk->ninsts, blk->cinsts, MirInst, inst);
    return inst.res;
}

MirValue mir_b_iconst(MirBuilder *b, int64_t v) {
    return mir_b_emit(b, MOP_IConst, NULL, 0, (MirImm){.tag = MI_INT, .i = v}, MIR_INT);
}

MirValue mir_b_bconst(MirBuilder *b, bool v) {
    return mir_b_emit(b, MOP_BConst, NULL, 0, (MirImm){.tag = MI_BOOL, .a = v ? 1u : 0u}, MIR_BOOL);
}

MirValue mir_b_unit(MirBuilder *b) {
    return mir_b_emit(b, MOP_VoidConst, NULL, 0, (MirImm){0}, MIR_VOID);
}

MirValue mir_b_binop(MirBuilder *b, MirOp op, MirValue a, MirValue c) {
    const MirValue args[2] = {a, c};
    return mir_b_emit(b, op, args, 2, (MirImm){0}, mir_b_ty(b, a));
}

MirValue mir_b_icmp(MirBuilder *b, MirCc cc, MirValue a, MirValue c) {
    const MirValue args[2] = {a, c};
    const MirImm imm = {.tag = MI_CC, .a = (uint32_t)cc};
    if (mir_b_ty(b, a) == MIR_UINT64 && cc != MCC_EQ && cc != MCC_NE) {
        return mir_b_emit(b, MOP_UICmp, args, 2, imm, MIR_BOOL);
    }
    return mir_b_emit(b, MOP_ICmp, args, 2, imm, MIR_BOOL);
}

MirValue mir_b_select(MirBuilder *b, MirValue cond, MirValue a, MirValue c) {
    const MirValue args[3] = {cond, a, c};
    return mir_b_emit(b, MOP_Select, args, 3, (MirImm){0}, mir_b_ty(b, a));
}

MirValue mir_b_list_new(MirBuilder *b, MirTy elem, MirValue cap) {
    return mir_b_emit(b, MOP_ListNew, &cap, 1, (MirImm){0}, mir_ty_list(b->m, elem));
}

MirValue mir_b_call_rt(MirBuilder *b, uint32_t ext, const MirValue *args, uint32_t nargs) {
    return mir_b_emit(b, MOP_CallRt, args, nargs, (MirImm){.tag = MI_EXT, .a = ext},
                      b->m->externs[ext].ret);
}

static bool same_fields(const MirField *x, const MirField *y, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        if (x[i].name != y[i].name || x[i].ty != y[i].ty) {
            return false;
        }
    }
    return true;
}

/* Whether `have` is a borrowing variant of the ordinary alternative `want`. */
static bool is_variant_of(const MirModule *m, MirTy have, MirTy want) {
    const MirTyData *h = mir_ty_data(m, have), *w = mir_ty_data(m, want);
    if (h->kind != MK_ALT || w->kind != MK_ALT) {
        return false;
    }
    const MirAltDef *dh = &m->alts[h->id], *dw = &m->alts[w->id];
    if (dh->borrowed == 0 || dw->borrowed != 0 || dh->name != dw->name || dh->ncases != dw->ncases) {
        return false;
    }
    for (uint32_t c = 0; c < dh->ncases; c++) {
        if (dh->cases[c].name != dw->cases[c].name || dh->cases[c].nfields != dw->cases[c].nfields ||
            !same_fields(dh->cases[c].fields, dw->cases[c].fields, dh->cases[c].nfields)) {
            return false;
        }
    }
    return true;
}

MirValue mir_b_call(MirBuilder *b, uint32_t func, const MirValue *args, uint32_t nargs) {
    const MirFunc *callee = &b->m->funcs[func];
    const MirTy ret = callee->ret;
    MirValue *plain = MS_NEW_N(&b->scratch, MirValue, (size_t)nargs + 1);
    for (uint32_t i = 0; i < nargs; i++) {
        plain[i] = args[i];
        if (i < callee->nparams && callee->params[i].mode == MM_BORROW &&
            is_variant_of(b->m, mir_b_ty(b, args[i]), callee->params[i].ty)) {
            plain[i] = mir_b_emit(b, MOP_AltPlain, &args[i], 1, (MirImm){0}, callee->params[i].ty);
        }
    }
    return mir_b_emit(b, MOP_Call, plain, nargs, (MirImm){.tag = MI_FUNC, .a = func}, ret);
}

/* ---- terminators ---- */

static void add_edge(MirBuilder *b, MirBlock from, MirBlock to) {
    MirBlockLinks *l = links_of(b, to);
    if (l->npreds == l->cpreds) {
        l->preds = scratch_grow(&b->scratch, l->preds, &l->cpreds, l->npreds, sizeof(MirBlock));
    }
    l->preds[l->npreds++] = from;
}

/* Records the edges of the terminator just stored in the current block. */
static void end_block(MirBuilder *b) {
    MirBlockData *blk = &b->f.blocks[b->cur];
    blk->term_loc = b->loc;
    for (uint32_t t = 0; t < mir_term_ntargets(&blk->term); t++) {
        add_edge(b, b->cur, mir_term_target(&blk->term, t)->block);
    }
}

static MirTerm *start_term(MirBuilder *b, MirTermKind kind) {
    MirTerm *term = &b->f.blocks[b->cur].term;
    memset(term, 0, sizeof *term);
    term->kind = (uint8_t)kind;
    term->value = MIR_NONE;
    return term;
}

void mir_b_br(MirBuilder *b, MirBlock to, const MirValue *args, uint32_t nargs) {
    MirTerm *term = start_term(b, MT_BR);
    term->a = (MirTarget){to, copy_values(b, args, nargs), nargs};
    end_block(b);
}

void mir_b_br_if(MirBuilder *b, MirValue cond, MirBlock then, const MirValue *then_args,
                 uint32_t nthen, MirBlock els, const MirValue *els_args, uint32_t nels) {
    MirTerm *term = start_term(b, MT_CONDBR);
    term->value = cond;
    term->a = (MirTarget){then, copy_values(b, then_args, nthen), nthen};
    term->b = (MirTarget){els, copy_values(b, els_args, nels), nels};
    end_block(b);
}

void mir_b_switch(MirBuilder *b, MirValue value, const MirCase *cases, uint32_t ncases,
                  MirBlock fallback) {
    MirTerm *term = start_term(b, MT_SWITCH);
    term->value = value;
    term->cases = MS_NEW_N(&b->m->arena, MirCase, (size_t)ncases + 1);
    for (uint32_t i = 0; i < ncases; i++) {
        term->cases[i] = (MirCase){cases[i].value, {cases[i].target.block, NULL, 0}};
    }
    term->ncases = ncases;
    term->b = (MirTarget){fallback, NULL, 0};
    end_block(b);
}

void mir_b_ret(MirBuilder *b, MirValue value) {
    start_term(b, MT_RET)->value = value;
    end_block(b);
}

void mir_b_fault(MirBuilder *b, MirFault kind) {
    start_term(b, MT_FAULT)->fault = (uint8_t)kind;
    end_block(b);
}

void mir_b_unreachable(MirBuilder *b) {
    start_term(b, MT_UNREACHABLE);
    end_block(b);
}

/* ---- variables ---- */

static MirVar declare(MirBuilder *b, MirTy ty, MirMode mode, bool single) {
    const MirVarInfo info = {ty, (uint8_t)mode, single, MIR_NONE};
    if (b->nvars == b->cvars) {
        b->vars = scratch_grow(&b->scratch, b->vars, &b->cvars, b->nvars, sizeof(MirVarInfo));
    }
    b->vars[b->nvars] = info;
    return b->nvars++;
}

MirVar mir_b_declare_var(MirBuilder *b, MirTy ty, MirMode mode) {
    return declare(b, ty, mode, false);
}

MirVar mir_b_declare_single(MirBuilder *b, MirTy ty, MirMode mode) {
    return declare(b, ty, mode, true);
}

void mir_b_def_var(MirBuilder *b, MirVar var, MirValue value) {
    MirVarInfo *info = &b->vars[var];
    if (info->single) {
        info->only_def = value;
        return;
    }
    def_set(b, var, b->cur, value);
}

static MirValue resolve(MirBuilder *b, MirValue v) {
    MirValue end = v;
    while (end < b->cforward && b->forward[end] != MIR_NONE) {
        end = b->forward[end];
    }
    if (end != v) {
        b->forward[v] = end;
    }
    return end;
}

static void set_forward(MirBuilder *b, MirValue from, MirValue to) {
    if (from >= b->cforward) {
        uint32_t cap = b->cforward ? b->cforward : 64;
        while (cap <= from) {
            cap *= 2;
        }
        MirValue *grown = MS_NEW_N(&b->scratch, MirValue, cap);
        for (uint32_t i = 0; i < cap; i++) {
            grown[i] = i < b->cforward ? b->forward[i] : MIR_NONE;
        }
        b->forward = grown;
        b->cforward = cap;
    }
    b->forward[from] = to;
}

static MirValue read_var(MirBuilder *b, MirVar var, MirBlock block);

static uint32_t param_index(const MirBuilder *b, MirBlock block, MirValue param) {
    const MirBlockData *blk = &b->f.blocks[block];
    for (uint32_t i = 0; i < blk->nparams; i++) {
        if (blk->params[i].value == param) {
            return i;
        }
    }
    return blk->nparams; /* unreachable: every caller just added the parameter */
}

/* Fills in the operand every distinct predecessor passes for `param`, reading the variable there. */
static void add_phi_operands(MirBuilder *b, MirVar var, MirBlock block, MirValue param) {
    const uint32_t idx = param_index(b, block, param);
    const uint32_t npreds = links_of(b, block)->npreds;
    for (uint32_t k = 0; k < npreds; k++) {
        const MirBlock pred = links_of(b, block)->preds[k];
        bool seen = false;
        for (uint32_t j = 0; j < k && !seen; j++) {
            seen = links_of(b, block)->preds[j] == pred;
        }
        if (seen) {
            continue;
        }
        const MirValue val = read_var(b, var, pred);
        MirTerm *term = &b->f.blocks[pred].term;
        for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
            MirTarget *target = mir_term_target(term, t);
            if (target->block != block) {
                continue;
            }
            while (target->nargs <= idx) {
                MirValue *grown = MS_NEW_N(&b->m->arena, MirValue, (size_t)target->nargs + 1);
                if (target->nargs > 0) {
                    memcpy(grown, target->args, sizeof(MirValue) * target->nargs);
                }
                grown[target->nargs] = val;
                target->args = grown;
                target->nargs++;
            }
        }
    }
}

/* Whether every edge into `block` passes the same value for parameter `idx`; the value is
 * written to `same`. Edges passing the parameter itself change nothing. */
static bool uniform_operand(MirBuilder *b, MirBlock block, uint32_t idx, MirValue param,
                            MirValue *same) {
    uint32_t edges = 0;
    *same = MIR_NONE;
    const uint32_t npreds = links_of(b, block)->npreds;
    for (uint32_t k = 0; k < npreds; k++) {
        const MirBlock pred = links_of(b, block)->preds[k];
        MirTerm *term = &b->f.blocks[pred].term;
        for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
            const MirTarget *target = mir_term_target(term, t);
            if (target->block != block) {
                continue;
            }
            edges++;
            if (idx >= target->nargs) {
                return false;
            }
            const MirValue a = resolve(b, target->args[idx]);
            if (a == param) {
                continue;
            }
            if (*same != MIR_NONE && *same != a) {
                return false;
            }
            *same = a;
        }
    }
    return edges > 0 && *same != MIR_NONE;
}

/* Removes `param` of the sealed block when every predecessor passes the same value, so that
 * value stays live across the join instead of being handed through an edge. */
static MirValue without_trivial_param(MirBuilder *b, MirVar var, MirBlock block, MirValue param) {
    const uint32_t idx = param_index(b, block, param);
    MirValue same = MIR_NONE;
    if (!uniform_operand(b, block, idx, param, &same)) {
        return param;
    }
    const uint32_t npreds = links_of(b, block)->npreds;
    for (uint32_t k = 0; k < npreds; k++) {
        MirTerm *term = &b->f.blocks[links_of(b, block)->preds[k]].term;
        for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
            MirTarget *target = mir_term_target(term, t);
            if (target->block != block || target->nargs <= idx) {
                continue;
            }
            for (uint32_t a = idx + 1; a < target->nargs; a++) {
                target->args[a - 1] = target->args[a];
            }
            target->nargs--;
        }
    }
    MirBlockData *blk = &b->f.blocks[block];
    for (uint32_t i = idx + 1; i < blk->nparams; i++) {
        blk->params[i - 1] = blk->params[i];
    }
    blk->nparams--;
    def_set(b, var, block, same);
    set_forward(b, param, same);
    return same;
}

static MirValue read_var(MirBuilder *b, MirVar var, MirBlock block) {
    const MirVarInfo info = b->vars[var];
    if (info.single) {
        return resolve(b, info.only_def);
    }
    const MirVarDef *known = def_find(b, var, block);
    if (known != NULL) {
        return resolve(b, known->value);
    }
    if (++b->depth > MB_MAX_DEPTH) {
        b->failed = true;
        b->depth--;
        return info.only_def;
    }
    MirValue val = MIR_NONE;
    MirBlockLinks *links = links_of(b, block);
    if (!links->sealed) {
        val = mir_b_add_block_param(b, block, info.ty, (MirMode)info.mode);
        links = links_of(b, block);
        if (links->nwaiting == links->cwaiting) {
            const uint32_t n = links->nwaiting;
            uint32_t cap = links->cwaiting;
            links->waiting_var = scratch_grow(&b->scratch, links->waiting_var, &cap, n, sizeof(MirVar));
            cap = links->cwaiting;
            links->waiting_param =
                scratch_grow(&b->scratch, links->waiting_param, &cap, n, sizeof(MirValue));
            links->cwaiting = cap;
        }
        links->waiting_var[links->nwaiting] = var;
        links->waiting_param[links->nwaiting++] = val;
    } else if (links->npreds == 1) {
        val = read_var(b, var, links->preds[0]);
    } else if (links->npreds == 0) {
        b->failed = true; /* read before any path defines it */
        val = mir_b_iconst(b, 0);
    } else {
        val = mir_b_add_block_param(b, block, info.ty, (MirMode)info.mode);
        def_set(b, var, block, val);
        add_phi_operands(b, var, block, val);
        val = without_trivial_param(b, var, block, val);
    }
    def_set(b, var, block, val);
    b->depth--;
    return val;
}

MirValue mir_b_use_var(MirBuilder *b, MirVar var) { return read_var(b, var, b->cur); }

void mir_b_seal_block(MirBuilder *b, MirBlock block) {
    if (links_of(b, block)->sealed) {
        return;
    }
    links_of(b, block)->sealed = true;
    const uint32_t n = links_of(b, block)->nwaiting;
    for (uint32_t i = 0; i < n; i++) {
        const MirBlockLinks *links = links_of(b, block);
        add_phi_operands(b, links->waiting_var[i], block, links->waiting_param[i]);
    }
}

/* ---- finishing ---- */

bool mir_b_into_func(MirBuilder *b, MirFunc *out) {
    if (b->cforward > 0) {
        for (uint32_t blk = 0; blk < b->f.nblocks; blk++) {
            MirTerm *term = &b->f.blocks[blk].term;
            for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
                MirTarget *target = mir_term_target(term, t);
                for (uint32_t a = 0; a < target->nargs; a++) {
                    target->args[a] = resolve(b, target->args[a]);
                }
            }
        }
    }
    for (uint32_t i = 0; i < b->f.nnames; i++) {
        b->f.names[i].value = resolve(b, b->f.names[i].value);
    }
    const bool ok = !b->failed;
    *out = b->f;
    ms_arena_free(&b->scratch);
    return ok;
}

bool mir_b_finish(MirBuilder *b, uint32_t *id) {
    MirFunc f = {0};
    if (!mir_b_into_func(b, &f)) {
        return false;
    }
    *id = mir_add_func(b->m, &f);
    return true;
}

uint32_t mir_b_open_scope(MirBuilder *b, MsSym name, uint32_t file, uint32_t call_line) {
    const uint32_t outer = b->loc.scope;
    const MirScope scope = {.name = name, .file = file, .parent = outer, .call_line = call_line};
    MIR_PUSH(b->m, b->f.scopes, b->f.nscopes, b->f.cscopes, MirScope, scope);
    b->loc.scope = b->f.nscopes;
    return outer;
}

void mir_b_close_scope(MirBuilder *b, uint32_t outer) {
    b->loc.scope = outer;
}
