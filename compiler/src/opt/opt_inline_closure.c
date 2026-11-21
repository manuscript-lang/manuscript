/* The closure half of the `inline` pass: a `call.ind` of a closure built in the same function
 * becomes a direct call and is inlined; a call that passes such a closure to a callee that calls
 * it gets a private specialised copy of the callee; a runtime sort whose comparator is a known
 * closure gets a copy of the generic comparison thunk that calls the closure's code directly.
 * Port of the corresponding parts of crates/ms-mir/src/opt/inline.rs. */
#include <string.h>

#include "opt/opt_inline.h"
#include "opt/opt_simplify.h"

/* ---- the closures a function builds ---- */

/* Per value of one function: the closure code and captures when it is a plain-data closure built
 * by `closure.new`, or reached through one. */
typedef struct IcKnown {
    uint32_t n;
    uint32_t *code;        /* MIR_NONE when unknown */
    const MirValue **caps; /* the captured values */
    uint32_t *ncaps;
    uint32_t count;
} IcKnown;

static IcKnown ic_known_new(MsArena *arena, uint32_t nvalues) {
    IcKnown k = {.n = nvalues};
    k.code = ms_alloc_zeroed(arena, nvalues, sizeof(uint32_t));
    memset(k.code, 0xff, sizeof(uint32_t) * nvalues);
    k.caps = ms_alloc_zeroed(arena, nvalues, sizeof(MirValue *));
    k.ncaps = ms_alloc_zeroed(arena, nvalues, sizeof(uint32_t));
    return k;
}

static bool ic_known_has(const IcKnown *k, MirValue v) {
    return v < k->n && k->code[v] != MIR_NONE;
}

static void ic_known_set(IcKnown *k, MirValue v, uint32_t code, const MirValue *caps, uint32_t n) {
    k->count += k->code[v] == MIR_NONE ? 1u : 0u;
    k->code[v] = code;
    k->caps[v] = caps;
    k->ncaps[v] = n;
}

/* The closures built in `f` by `closure.new` whose captures are all plain data. */
static IcKnown ic_known_closures(MsArena *arena, const MirModule *m, const MirFunc *f) {
    IcKnown known = ic_known_new(arena, f->nvalues);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *in = &f->blocks[b].insts[i];
            if (in->op != MOP_ClosureNew || in->imm.tag != MI_FUNC || in->res == MIR_NONE ||
                m->funcs[in->imm.a].ncapture_closers != 0) {
                continue;
            }
            bool plain = true;
            for (uint32_t a = 0; a < in->nargs; a++) {
                plain = plain && !mir_needs_drop(m, mir_value_ty(f, in->args[a]));
            }
            if (plain) {
                ic_known_set(&known, in->res, in->imm.a, in->args, in->nargs);
            }
        }
    }
    return known;
}

/* Incoming block-parameter arguments: row `base[b] + j` lists the arguments passed for parameter
 * `j` of block `b`. */
typedef struct IcIncoming {
    uint32_t *base; /* nblocks + 1 */
    uint32_t *off;  /* rows + 1 */
    MirValue *args;
} IcIncoming;

static IcIncoming ic_incoming(MsArena *arena, const MirFunc *f) {
    IcIncoming in = {0};
    in.base = ms_alloc_zeroed(arena, (size_t)f->nblocks + 1, sizeof(uint32_t));
    for (uint32_t b = 0; b < f->nblocks; b++) {
        in.base[b + 1] = in.base[b] + f->blocks[b].nparams;
    }
    const uint32_t rows = in.base[f->nblocks];
    in.off = ms_alloc_zeroed(arena, (size_t)rows + 2, sizeof(uint32_t));
    for (uint32_t pass = 0; pass < 2; pass++) {
        uint32_t *cursor = ms_alloc_zeroed(arena, (size_t)rows + 1, sizeof(uint32_t));
        for (uint32_t b = 0; b < f->nblocks; b++) {
            for (uint32_t k = 0; k < mir_term_ntargets(&f->blocks[b].term); k++) {
                const MirTarget *t = mir_term_target_const(&f->blocks[b].term, k);
                for (uint32_t j = 0; j < t->nargs; j++) {
                    const uint32_t row = in.base[t->block] + j;
                    if (pass == 0) {
                        in.off[row + 1]++;
                    } else {
                        in.args[in.off[row] + cursor[row]++] = t->args[j];
                    }
                }
            }
        }
        if (pass == 0) {
            for (uint32_t r = 0; r < rows; r++) {
                in.off[r + 1] += in.off[r];
            }
            in.args = ms_alloc_zeroed(arena, in.off[rows], sizeof(MirValue));
        }
    }
    return in;
}

/* Whether every incoming argument of parameter `p` is `p` itself or an alias of one root; the
 * root is stored in `*root` (MIR_NONE when no argument names one). */
static bool ic_param_class(const IcIncoming *in, uint32_t row, MirValue p, const MirValue *alias,
                           uint32_t *root) {
    if (in->off[row] == in->off[row + 1]) {
        return false;
    }
    *root = MIR_NONE;
    for (uint32_t a = in->off[row]; a < in->off[row + 1]; a++) {
        const MirValue v = in->args[a];
        if (v == p) {
            continue;
        }
        if (alias[v] == MIR_NONE || (*root != MIR_NONE && *root != alias[v])) {
            return false;
        }
        *root = alias[v];
    }
    return *root != MIR_NONE;
}

/* One sweep over the copies and block parameters; whether an alias was added. */
static bool ic_alias_sweep(const MirFunc *f, const IcIncoming *in, MirValue *alias) {
    bool grew = false;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            if (inst->op == MOP_Clone && inst->res != MIR_NONE && alias[inst->res] == MIR_NONE &&
                alias[inst->args[0]] != MIR_NONE) {
                alias[inst->res] = alias[inst->args[0]];
                grew = true;
            }
        }
    }
    for (uint32_t b = 1; b < f->nblocks; b++) {
        for (uint32_t j = 0; j < f->blocks[b].nparams; j++) {
            const MirValue p = f->blocks[b].params[j].value;
            uint32_t root = MIR_NONE;
            if (alias[p] == MIR_NONE && ic_param_class(in, in->base[b] + j, p, alias, &root)) {
                alias[p] = root;
                grew = true;
            }
        }
    }
    return grew;
}

/* Maps every value that always holds the same known closure to that closure's `closure.new`
 * result: the result itself, `copy` of such a value, and a block parameter each of whose incoming
 * arguments is such a value (or the parameter itself, on a loop back edge). */
static MirValue *ic_aliases(MsArena *arena, const MirFunc *f, const IcKnown *roots) {
    MirValue *alias = ms_alloc_zeroed(arena, f->nvalues, sizeof(MirValue));
    memset(alias, 0xff, sizeof(MirValue) * f->nvalues);
    for (uint32_t v = 0; v < f->nvalues; v++) {
        alias[v] = ic_known_has(roots, v) ? v : MIR_NONE;
    }
    const IcIncoming in = ic_incoming(arena, f);
    while (ic_alias_sweep(f, &in, alias)) {
    }
    return alias;
}

/* ---- deleting closures nothing calls ---- */

typedef struct IcDelete {
    const MirValue *alias;
    bool *live;       /* by root */
    bool *dead_param; /* by row */
    const uint32_t *base;
} IcDelete;

static void ic_note(const IcDelete *d, MirValue v) {
    if (d->alias[v] != MIR_NONE) {
        d->live[d->alias[v]] = true;
    }
}

static bool ic_dead(const IcDelete *d, MirValue v) {
    return d->alias[v] != MIR_NONE && !d->live[d->alias[v]];
}

static void ic_note_block(const IcDelete *d, const MirFunc *f, const MirBlockData *b) {
    for (uint32_t i = 0; i < b->ninsts; i++) {
        const MirInst *in = &b->insts[i];
        const bool class_only = in->op == MOP_Drop || (in->op == MOP_Clone && in->res != MIR_NONE &&
                                                       d->alias[in->res] != MIR_NONE);
        for (uint32_t a = 0; a < in->nargs && !class_only; a++) {
            ic_note(d, in->args[a]);
        }
    }
    if (b->term.kind == MT_CONDBR || b->term.kind == MT_SWITCH ||
        (b->term.kind == MT_RET && b->term.value != MIR_NONE)) {
        ic_note(d, b->term.value);
    }
    /* An argument into a block parameter outside the class keeps the closure alive. */
    for (uint32_t k = 0; k < mir_term_ntargets(&b->term); k++) {
        const MirTarget *t = mir_term_target_const(&b->term, k);
        for (uint32_t j = 0; j < t->nargs; j++) {
            if (d->alias[f->blocks[t->block].params[j].value] == MIR_NONE) {
                ic_note(d, t->args[j]);
            }
        }
    }
}

static bool ic_sweep_insts(const IcDelete *d, MirBlockData *b) {
    uint32_t kept = 0;
    for (uint32_t i = 0; i < b->ninsts; i++) {
        const MirInst *in = &b->insts[i];
        const bool gone = ((in->op == MOP_ClosureNew || in->op == MOP_Clone) && in->res != MIR_NONE &&
                           ic_dead(d, in->res)) ||
                          (in->op == MOP_Drop && ic_dead(d, in->args[0]));
        if (!gone) {
            b->insts[kept++] = *in;
        }
    }
    const bool changed = kept != b->ninsts;
    b->ninsts = kept;
    return changed;
}

static void ic_sweep_target(MirModule *m, const IcDelete *d, MirTarget *t) {
    uint32_t kept = 0;
    MirValue *args = NULL;
    for (uint32_t j = 0; j < t->nargs; j++) {
        if (d->dead_param[d->base[t->block] + j]) {
            continue;
        }
        if (args == NULL) {
            args = MS_NEW_N(&m->arena, MirValue, (size_t)t->nargs + 1);
        }
        args[kept++] = t->args[j];
    }
    if (kept != t->nargs) {
        t->args = args != NULL ? args : MS_NEW_N(&m->arena, MirValue, 1);
        t->nargs = kept;
    }
}

static void ic_sweep_params(const IcDelete *d, MirBlockData *b, uint32_t bi) {
    uint32_t kept = 0;
    for (uint32_t j = 0; j < b->nparams; j++) {
        if (!d->dead_param[d->base[bi] + j]) {
            b->params[kept++] = b->params[j];
        }
    }
    b->nparams = kept;
}

static bool ic_delete_dead(MirModule *m, MirFunc *f, IcDelete *d) {
    bool changed = false;
    for (uint32_t b = 1; b < f->nblocks; b++) {
        for (uint32_t j = 0; j < f->blocks[b].nparams; j++) {
            const bool dead = ic_dead(d, f->blocks[b].params[j].value);
            d->dead_param[d->base[b] + j] = dead;
            changed |= dead;
        }
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        changed |= ic_sweep_insts(d, &f->blocks[b]);
        for (uint32_t k = 0; k < mir_term_ntargets(&f->blocks[b].term); k++) {
            ic_sweep_target(m, d, mir_term_target(&f->blocks[b].term, k));
        }
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        ic_sweep_params(d, &f->blocks[b], b);
    }
    return changed;
}

/* Deletes each known closure whose aliases are only copied, dropped and carried through block
 * parameters, together with those copies, drops and parameters (and the arguments feeding them). A
 * plain-data environment owns nothing, so ownership stays linear. Returns whether anything was
 * deleted. */
static bool ic_delete_unused(MirModule *m, uint32_t fi) {
    MsArena arena = {0};
    MirFunc *f = &m->funcs[fi];
    const IcKnown roots = ic_known_closures(&arena, m, f);
    if (roots.count == 0) {
        ms_arena_free(&arena);
        return false;
    }
    const IcIncoming in = ic_incoming(&arena, f);
    IcDelete d = {.alias = ic_aliases(&arena, f, &roots), .base = in.base};
    d.live = ms_alloc_zeroed(&arena, f->nvalues, sizeof(bool));
    d.dead_param = ms_alloc_zeroed(&arena, in.base[f->nblocks], sizeof(bool));
    for (uint32_t b = 0; b < f->nblocks; b++) {
        ic_note_block(&d, f, &f->blocks[b]);
    }
    const bool changed = ic_delete_dead(m, f, &d);
    ms_arena_free(&arena);
    return changed;
}

/* ---- closure code as a plain function ---- */

typedef struct IcEnvUse {
    MirValue env;
    bool used;
} IcEnvUse;

static void ic_env_term(void *ctx, MirValue v) {
    IcEnvUse *u = ctx;
    u->used = u->used || v == u->env;
}

/* Whether the closure's environment is used in any way besides `closure.cap`. */
static bool ic_env_escapes(const MirFunc *f, MirValue env) {
    IcEnvUse u = {.env = env};
    for (uint32_t b = 0; b < f->nblocks && !u.used; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *in = &f->blocks[b].insts[i];
            const bool cap = in->op == MOP_ClosureCap && in->imm.tag == MI_IDX && in->res != MIR_NONE;
            for (uint32_t a = 0; a < in->nargs && !cap; a++) {
                u.used = u.used || in->args[a] == env;
            }
        }
        mir_term_each_value(&f->blocks[b].term, ic_env_term, &u);
    }
    return u.used;
}

static bool ic_closure_usable(const MirFunc *f) {
    return f->kind == MFK_CLOSURE && f->nblocks > 0 && !ic_env_escapes(f, f->blocks[0].params[0].value);
}

static MirValue ic_sub(const MirValue *sub, MirValue v) {
    return sub[v] == MIR_NONE ? v : sub[v];
}

static void ic_subst_term(void *ctx, MirValue *v) {
    *v = ic_sub(ctx, *v);
}

/* A copy of closure code `f` as a plain function taking the captures before the arguments, or
 * false when the environment is used in any way besides `closure.cap`. */
static bool ic_closure_body(MirModule *m, const MirFunc *f, MirFunc *out) {
    if (!ic_closure_usable(f)) {
        return false;
    }
    mir_func_deep_clone(m, f, out);
    MsArena arena = {0};
    MirValue *sub = ms_alloc_zeroed(&arena, f->nvalues, sizeof(MirValue));
    memset(sub, 0xff, sizeof(MirValue) * f->nvalues);
    MirValue *cap = MS_NEW_N(&arena, MirValue, (size_t)f->ncaptures + 1);
    for (uint32_t k = 0; k < f->ncaptures; k++) {
        cap[k] = mir_new_value(m, out, f->captures[k]);
    }
    for (uint32_t b = 0; b < out->nblocks; b++) {
        MirBlockData *blk = &out->blocks[b];
        uint32_t kept = 0;
        for (uint32_t i = 0; i < blk->ninsts; i++) {
            const MirInst *in = &blk->insts[i];
            if (in->op == MOP_ClosureCap && in->imm.tag == MI_IDX && in->res != MIR_NONE) {
                sub[in->res] = cap[in->imm.a];
            } else {
                blk->insts[kept++] = *in;
            }
        }
        blk->ninsts = kept;
    }
    for (uint32_t b = 0; b < out->nblocks; b++) {
        for (uint32_t i = 0; i < out->blocks[b].ninsts; i++) {
            MirInst *in = &out->blocks[b].insts[i];
            for (uint32_t a = 0; a < in->nargs; a++) {
                in->args[a] = ic_sub(sub, in->args[a]);
            }
        }
        mir_term_each_use(&out->blocks[b].term, ic_subst_term, sub);
    }
    MirBlockData *entry = &out->blocks[0];
    MirBlockParam *params = MS_NEW_N(&m->arena, MirBlockParam, (size_t)entry->nparams + f->ncaptures);
    for (uint32_t k = 0; k < f->ncaptures; k++) {
        params[k] = (MirBlockParam){cap[k], MM_BORROW};
    }
    for (uint32_t j = 1; j < entry->nparams; j++) {
        params[f->ncaptures + j - 1] = entry->params[j];
    }
    entry->nparams = entry->cparams = entry->nparams - 1 + f->ncaptures;
    entry->params = params;
    ms_arena_free(&arena);
    return true;
}

/* ---- constant closure fields ---- */

/* The closure code held by each type field that every construction in the module sets to the same
 * capture-free closure and that nothing else ever writes: an open-addressed table of
 * (type, field) -> code, MIR_NONE marking a field with two closures or a write the analysis cannot
 * see. */
typedef struct IcFields {
    uint32_t mask;
    bool *used;
    uint32_t *type, *field, *code;
} IcFields;

static uint32_t ic_field_slot(const IcFields *t, uint32_t type, uint32_t field) {
    uint32_t h = (type * 0x9e3779b1u) ^ (field * 0x85ebca6bu);
    h ^= h >> 15;
    uint32_t s = h & t->mask;
    while (t->used[s] && (t->type[s] != type || t->field[s] != field)) {
        s = (s + 1) & t->mask;
    }
    return s;
}

static IcFields ic_fields_new(MsArena *arena, uint32_t bound) {
    uint32_t cap = 16;
    while (cap < bound * 2) {
        cap *= 2;
    }
    IcFields t = {.mask = cap - 1};
    t.used = ms_alloc_zeroed(arena, cap, sizeof(bool));
    t.type = ms_alloc_zeroed(arena, cap, sizeof(uint32_t));
    t.field = ms_alloc_zeroed(arena, cap, sizeof(uint32_t));
    t.code = ms_alloc_zeroed(arena, cap, sizeof(uint32_t));
    return t;
}

/* `code` is the new fact about the field; `overwrite` replaces what is known (a write). */
static void ic_fields_note(IcFields *t, uint32_t type, uint32_t field, uint32_t code, bool overwrite) {
    const uint32_t s = ic_field_slot(t, type, field);
    if (!t->used[s]) {
        t->used[s] = true;
        t->type[s] = type;
        t->field[s] = field;
        t->code[s] = code;
    } else if (overwrite || t->code[s] != code) {
        t->code[s] = MIR_NONE;
    }
}

static uint32_t ic_fields_bound(const MirModule *m) {
    uint32_t n = 0;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        for (uint32_t b = 0; b < m->funcs[fi].nblocks; b++) {
            for (uint32_t i = 0; i < m->funcs[fi].blocks[b].ninsts; i++) {
                n += m->funcs[fi].blocks[b].insts[i].nargs + 1;
            }
        }
    }
    return n;
}

/* The closure code `v` always is: through copies to a `closure.new` with no captures. */
static uint32_t ic_capture_free_code(const MirInst *const *defs, MirValue v) {
    while (defs[v] != NULL && defs[v]->op == MOP_Clone) {
        v = defs[v]->args[0];
    }
    const MirInst *d = defs[v];
    if (d != NULL && d->op == MOP_ClosureNew && d->imm.tag == MI_FUNC && d->nargs == 0) {
        return d->imm.a;
    }
    return MIR_NONE;
}

static void ic_fields_scan(IcFields *t, MsArena *arena, const MirModule *m, const MirFunc *f) {
    const MirInst **defs = ms_alloc_zeroed(arena, f->nvalues, sizeof(MirInst *));
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *in = &f->blocks[b].insts[i];
            if (in->res != MIR_NONE) {
                defs[in->res] = in;
            }
        }
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *in = &f->blocks[b].insts[i];
            if ((in->op == MOP_TypeSet || in->op == MOP_TypeFill || in->op == MOP_PtrField) &&
                in->imm.tag == MI_FIELD) {
                ic_fields_note(t, in->imm.a, in->imm.b, MIR_NONE, true);
            }
            if (in->op != MOP_TypeNew || in->imm.tag != MI_TYPE) {
                continue;
            }
            for (uint32_t k = 0; k < in->nargs; k++) {
                if (mir_ty_data(m, mir_value_ty(f, in->args[k]))->kind == MK_FN) {
                    ic_fields_note(t, in->imm.a, k, ic_capture_free_code(defs, in->args[k]), false);
                }
            }
        }
    }
}

/* ---- inlining the known calls ---- */

typedef struct IcInline {
    MirModule *m;
    uint32_t fi, budget, grown;
    uint32_t *work, nwork, cwork;
    const IcFields *fields;
} IcInline;

static void ic_work_push(IcInline *w, uint32_t bi) {
    if (w->nwork == w->cwork) {
        const uint32_t cap = w->cwork == 0 ? 16 : w->cwork * 2;
        uint32_t *grown = MS_NEW_N(&w->m->arena, uint32_t, cap);
        if (w->nwork > 0) {
            memcpy(grown, w->work, sizeof(uint32_t) * w->nwork);
        }
        w->work = grown;
        w->cwork = cap;
    }
    w->work[w->nwork++] = bi;
}

/* The closures of `f` as `known` sees them: every alias of a root, and every read of a constant
 * closure field. */
static IcKnown ic_known_with_fields(MsArena *arena, const MirModule *m, const MirFunc *f,
                                    const IcFields *fields) {
    const IcKnown roots = ic_known_closures(arena, m, f);
    IcKnown known = ic_known_new(arena, f->nvalues);
    const MirValue *alias = ic_aliases(arena, f, &roots);
    for (uint32_t v = 0; v < f->nvalues; v++) {
        if (alias[v] != MIR_NONE) {
            ic_known_set(&known, v, roots.code[alias[v]], roots.caps[alias[v]], roots.ncaps[alias[v]]);
        }
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *in = &f->blocks[b].insts[i];
            if (in->op != MOP_TypeGet || in->imm.tag != MI_FIELD || in->res == MIR_NONE) {
                continue;
            }
            const uint32_t s = ic_field_slot(fields, in->imm.a, in->imm.b);
            if (fields->used[s] && fields->code[s] != MIR_NONE) {
                ic_known_set(&known, in->res, fields->code[s], NULL, 0);
            }
        }
    }
    return known;
}

/* Makes the `call.ind` at (`bi`, `ii`) a direct call of `g` over `caps` and inlines it; false when
 * the callee is not eligible. */
static bool ic_inline_call(IcInline *w, const IcKnown *known, uint32_t bi, uint32_t ii) {
    MirModule *m = w->m;
    MirFunc *f = &m->funcs[w->fi];
    MirInst *call = &f->blocks[bi].insts[ii];
    const MirValue callee_value = call->args[0];
    if (!ic_known_has(known, callee_value)) {
        return false;
    }
    const uint32_t gi = known->code[callee_value];
    const MirFunc *callee = &m->funcs[gi];
    const uint32_t size = mir_inst_count(callee);
    if (gi == w->fi || callee->inline_hint == MINL_NEVER || size > MIR_INLINE_BASE_THRESHOLD ||
        mir_inline_cancel_mismatch(f, callee) || w->grown + size > w->budget) {
        return false;
    }
    MirFunc body;
    if (!ic_closure_body(m, callee, &body)) {
        return false;
    }
    w->grown += size;
    const uint32_t ncaps = known->ncaps[callee_value];
    MirValue *args = MS_NEW_N(&m->arena, MirValue, (size_t)ncaps + call->nargs);
    if (ncaps > 0) {
        memcpy(args, known->caps[callee_value], sizeof(MirValue) * ncaps);
    }
    memcpy(args + ncaps, call->args + 1, sizeof(MirValue) * (call->nargs - 1));
    call->op = MOP_Call;
    call->imm = (MirImm){.tag = MI_FUNC, .a = gi};
    call->args = args;
    call->nargs = ncaps + call->nargs - 1;
    const bool ret_own = mir_needs_drop(m, body.ret);
    ic_work_push(w, mir_inline_at(m, f, bi, ii, &body, ret_own));
    return true;
}

static bool ic_inline_block(IcInline *w, const IcKnown *known, uint32_t bi) {
    const MirFunc *f = &w->m->funcs[w->fi];
    for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
        if (f->blocks[bi].insts[ii].op == MOP_CallInd && ic_inline_call(w, known, bi, ii)) {
            return true;
        }
    }
    return false;
}

static bool ic_inline_closures_in(MirModule *m, uint32_t fi, const IcFields *fields) {
    MsArena arena = {0};
    IcInline w = {.m = m, .fi = fi, .fields = fields};
    w.budget = mir_inst_count(&m->funcs[fi]) * MIR_INLINE_GROWTH_FACTOR + MIR_INLINE_GROWTH_SLACK;
    for (uint32_t b = 0; b < m->funcs[fi].nblocks; b++) {
        ic_work_push(&w, b);
    }
    const IcKnown known = ic_known_with_fields(&arena, m, &m->funcs[fi], fields);
    bool changed = false;
    if (known.count > 0) {
        while (w.nwork > 0) {
            changed |= ic_inline_block(&w, &known, w.work[--w.nwork]);
        }
        changed |= ic_delete_unused(m, fi);
    }
    ms_arena_free(&arena);
    return changed;
}

bool mir_inline_closures(MirModule *m) {
    MsArena arena = {0};
    IcFields fields = ic_fields_new(&arena, ic_fields_bound(m));
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        ic_fields_scan(&fields, &arena, m, &m->funcs[fi]);
    }
    bool changed = false;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        changed |= ic_inline_closures_in(m, fi, &fields);
    }
    ms_arena_free(&arena);
    return changed;
}

/* ---- closure arguments ---- */

/* Specialised copies already made: (callee, closure code, parameter) -> copy. */
typedef struct IcMade {
    uint32_t *callee, *code, *param, *copy;
    uint32_t n, cap;
} IcMade;

static uint32_t ic_made_find(const IcMade *t, uint32_t a, uint32_t b, uint32_t c) {
    for (uint32_t i = 0; i < t->n; i++) {
        if (t->callee[i] == a && t->code[i] == b && t->param[i] == c) {
            return t->copy[i];
        }
    }
    return MIR_NONE;
}

static void ic_made_add(MsArena *arena, IcMade *t, uint32_t a, uint32_t b, uint32_t c, uint32_t copy) {
    if (t->n == t->cap) {
        const uint32_t cap = t->cap == 0 ? 16 : t->cap * 2;
        uint32_t **cols[4] = {&t->callee, &t->code, &t->param, &t->copy};
        for (uint32_t k = 0; k < 4; k++) {
            uint32_t *grown = MS_NEW_N(arena, uint32_t, cap);
            if (t->n > 0) {
                memcpy(grown, *cols[k], sizeof(uint32_t) * t->n);
            }
            *cols[k] = grown;
        }
        t->cap = cap;
    }
    t->callee[t->n] = a;
    t->code[t->n] = b;
    t->param[t->n] = c;
    t->copy[t->n++] = copy;
}

/* Replaces every use of `from` in `f` by `to`. */
typedef struct IcRename { MirValue from, to; } IcRename;

static void ic_rename_term(void *ctx, MirValue *v) {
    const IcRename *r = ctx;
    *v = *v == r->from ? r->to : *v;
}

static void ic_rename_uses(MirFunc *f, MirValue from, MirValue to) {
    IcRename r = {from, to};
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            MirInst *in = &f->blocks[b].insts[i];
            for (uint32_t a = 0; a < in->nargs; a++) {
                in->args[a] = in->args[a] == from ? to : in->args[a];
            }
        }
        mir_term_each_use(&f->blocks[b].term, ic_rename_term, &r);
    }
}

/* Replaces parameter `i` of `f` by one parameter per capture of closure code `g`. */
static MirValue *ic_split_param(MirModule *m, MirFunc *f, const MirFunc *g, uint32_t i) {
    const uint32_t nc = g->ncaptures;
    MirParam *params = MS_NEW_N(&m->arena, MirParam, (size_t)f->nparams + nc);
    MirBlockData *entry = &f->blocks[0];
    MirBlockParam *bparams = MS_NEW_N(&m->arena, MirBlockParam, (size_t)entry->nparams + nc);
    MirValue *caps = MS_NEW_N(&m->arena, MirValue, (size_t)nc + 1);
    for (uint32_t k = 0; k < nc; k++) {
        caps[k] = mir_new_value(m, f, g->captures[k]);
    }
    uint32_t n = 0;
    for (uint32_t j = 0; j < f->nparams; j++) {
        if (j == i) {
            for (uint32_t k = 0; k < nc; k++) {
                params[n] = (MirParam){g->captures[k], MM_BORROW};
                bparams[n++] = (MirBlockParam){caps[k], MM_BORROW};
            }
            continue;
        }
        params[n] = f->params[j];
        bparams[n++] = entry->params[j];
    }
    /* Parameters after the split one move by the captures that replace it. */
    uint32_t kept = 0;
    for (uint32_t k = 0; k < f->nnoalias; k++) {
        if (f->noalias[k] != i) {
            f->noalias[kept++] = f->noalias[k] > i ? f->noalias[k] - 1 + nc : f->noalias[k];
        }
    }
    f->nnoalias = kept;
    f->params = params;
    f->nparams = n;
    entry->params = bparams;
    entry->nparams = entry->cparams = n;
    return caps;
}

/* `callee` with parameter `i` (a borrowed closure) replaced by the captures of closure code `g`
 * and a `closure.new` of `g` over them at the top of the entry block, dropped before every `ret`.
 * The copy keeps the callee's name: a fault trace names the function the program wrote. */
static void ic_specialized_callee(MirModule *m, uint32_t callee, uint32_t g, uint32_t i, MirFunc *f) {
    mir_func_deep_clone(m, &m->funcs[callee], f);
    const MirFunc *code = &m->funcs[g];
    const MirValue old = f->blocks[0].params[i].value;
    const MirTy ty = mir_value_ty(f, old);
    const MirLoc loc = f->loc;
    MirValue *caps = ic_split_param(m, f, code, i);
    const MirValue k = mir_new_value(m, f, ty);
    ic_rename_uses(f, old, k);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        if (f->blocks[b].term.kind == MT_RET) {
            const MirInst drop = mir_inst_make(m, MOP_Drop, &k, 1, (MirImm){0}, MIR_NONE, f->blocks[b].term_loc);
            mir_block_insert(m, &f->blocks[b], f->blocks[b].ninsts, &drop);
        }
    }
    const MirInst make = mir_inst_make(m, MOP_ClosureNew, caps, code->ncaptures,
                                       (MirImm){.tag = MI_FUNC, .a = g}, k, loc);
    mir_block_insert(m, &f->blocks[0], mir_entry_insert_at(f), &make);
}

/* The argument of the call that a specialisation applies to: a known closure passed in a borrowed
 * parameter whose code is small and takes its environment only through `closure.cap`. */
static bool ic_pick_arg(const MirModule *m, const IcKnown *known, const MirInst *call,
                        const MirFunc *callee, uint32_t *index) {
    for (uint32_t i = 0; i < call->nargs; i++) {
        if (!ic_known_has(known, call->args[i])) {
            continue;
        }
        const MirFunc *code = &m->funcs[known->code[call->args[i]]];
        if (callee->params[i].mode == MM_BORROW && code->inline_hint != MINL_NEVER &&
            mir_inst_count(code) <= MIR_INLINE_BASE_THRESHOLD && ic_closure_usable(code)) {
            *index = i;
            return true;
        }
    }
    return false;
}

static bool ic_has_call_ind(const MirFunc *f) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            if (f->blocks[b].insts[i].op == MOP_CallInd) {
                return true;
            }
        }
    }
    return false;
}

typedef struct IcSpecialize {
    MirModule *m;
    MsArena *arena;
    IcMade made;
    uint32_t spent;
    const bool *cyc;
    uint32_t ncyc;
} IcSpecialize;

/* Whether the call to `ci` from `fi` is worth a private copy: a plain, acyclic, small callee that
 * calls a closure indirectly. */
static bool ic_specializable(const IcSpecialize *s, uint32_t fi, uint32_t ci) {
    const MirFunc *callee = &s->m->funcs[ci];
    const bool cyclic = ci < s->ncyc && s->cyc[ci];
    return ci != fi && !cyclic && callee->kind == MFK_NORMAL && callee->inline_hint != MINL_NEVER &&
           mir_inst_count(callee) <= MIR_INLINE_SPECIALIZE_MAX_SIZE && ic_has_call_ind(callee);
}

/* The copy of `c` specialised for closure code `g` in parameter `i`, made on first use; MIR_NONE
 * when the budget is spent. */
static uint32_t ic_specialized(IcSpecialize *s, uint32_t c, uint32_t g, uint32_t i) {
    const uint32_t have = ic_made_find(&s->made, c, g, i);
    if (have != MIR_NONE) {
        return have;
    }
    MirFunc copy;
    ic_specialized_callee(s->m, c, g, i, &copy);
    const uint32_t size = mir_inst_count(&copy);
    if (s->spent + size > MIR_INLINE_SPECIALIZE_BUDGET) {
        return MIR_NONE;
    }
    s->spent += size;
    const uint32_t id = mir_add_func(s->m, &copy);
    ic_made_add(s->arena, &s->made, c, g, i, id);
    return id;
}

/* Calls `spec` instead, passing the captures in place of argument `i`. */
static void ic_redirect(MirModule *m, MirInst *call, uint32_t spec, uint32_t i, const MirValue *caps,
                        uint32_t ncaps) {
    MirValue *args = MS_NEW_N(&m->arena, MirValue, (size_t)call->nargs + ncaps);
    memcpy(args, call->args, sizeof(MirValue) * i);
    if (ncaps > 0) {
        memcpy(args + i, caps, sizeof(MirValue) * ncaps);
    }
    memcpy(args + i + ncaps, call->args + i + 1, sizeof(MirValue) * (call->nargs - i - 1));
    call->imm.a = spec;
    call->nargs = call->nargs - 1 + ncaps;
    call->args = args;
}

static bool ic_specialize_in(IcSpecialize *s, uint32_t fi) {
    MirModule *m = s->m;
    MsArena arena = {0};
    const IcKnown known = ic_known_closures(&arena, m, &m->funcs[fi]);
    bool changed = false;
    for (uint32_t bi = 0; known.count > 0 && bi < m->funcs[fi].nblocks; bi++) {
        for (uint32_t ii = 0; ii < m->funcs[fi].blocks[bi].ninsts; ii++) {
            const MirInst *inst = &m->funcs[fi].blocks[bi].insts[ii];
            uint32_t i = 0;
            if (inst->op != MOP_Call || inst->imm.tag != MI_FUNC ||
                !ic_specializable(s, fi, inst->imm.a) ||
                !ic_pick_arg(m, &known, inst, &m->funcs[inst->imm.a], &i)) {
                continue;
            }
            const MirValue arg = inst->args[i];
            const uint32_t spec = ic_specialized(s, inst->imm.a, known.code[arg], i);
            if (spec == MIR_NONE) {
                continue;
            }
            ic_redirect(m, &m->funcs[fi].blocks[bi].insts[ii], spec, i, known.caps[arg], known.ncaps[arg]);
            changed = true;
        }
    }
    if (changed) {
        (void)ic_delete_unused(m, fi);
    }
    ms_arena_free(&arena);
    return changed;
}

enum { IC_SPECIALIZE_ROUNDS = 4 };

/* Gives each call that passes a closure built in the caller (plain-data captures, borrowed
 * parameter) a private copy of the callee in which that parameter is replaced by a `closure.new`
 * of the same code over captures taken as parameters. The closure inliner then resolves the
 * callee's indirect calls and deletes the closure. */
bool mir_inline_specialize_closure_args(MirModule *m) {
    MsArena arena = {0};
    IcSpecialize s = {.m = m, .arena = &arena};
    bool changed = false;
    for (uint32_t round = 0; round < IC_SPECIALIZE_ROUNDS; round++) {
        const MirInlineGraph g = mir_inline_direct_graph(&arena, m);
        s.cyc = mir_inline_cyclic(&arena, &g);
        s.ncyc = g.n;
        bool any = false;
        const uint32_t nfuncs = m->nfuncs;
        for (uint32_t fi = 0; fi < nfuncs; fi++) {
            any |= ic_specialize_in(&s, fi);
        }
        changed |= any;
        if (!any) {
            break;
        }
    }
    ms_arena_free(&arena);
    return changed;
}

/* ---- runtime sort comparators ---- */

/* `thunk` with its closure parameter replaced by the raw environment pointer and the indirect call
 * replaced by a direct call (inlined when small) of closure code `g`; false when `g` is not
 * eligible. */
static bool ic_specialized_thunk(MirModule *m, uint32_t thunk, uint32_t g, MirFunc *t) {
    const MirFunc *code = &m->funcs[g];
    if (code->kind != MFK_CLOSURE || code->inline_hint == MINL_NEVER) {
        return false;
    }
    mir_func_deep_clone(m, &m->funcs[thunk], t);
    if (mir_inline_cancel_mismatch(t, code)) {
        return false;
    }
    const MsStr name = ms_name(&m->names, code->name);
    const MsStr full = ms_arena_fmt(&m->arena, "sort.cmp.%.*s", (int)name.len, name.ptr);
    t->name = mir_name(m, full.ptr, full.len);
    t->sort = MSORT_SPECIALIZED;
    MirParam *params = MS_NEW_N(&m->arena, MirParam, (size_t)t->nparams + 1);
    memcpy(params, t->params, sizeof(MirParam) * t->nparams);
    params[0].ty = MIR_PTR;
    t->params = params;
    const MirValue env = t->blocks[0].params[0].value;
    t->values[env] = MIR_PTR;
    for (uint32_t bi = 0; bi < t->nblocks; bi++) {
        for (uint32_t ii = 0; ii < t->blocks[bi].ninsts; ii++) {
            MirInst *call = &t->blocks[bi].insts[ii];
            if (call->op != MOP_CallInd || call->args[0] != env) {
                continue;
            }
            call->op = MOP_Call;
            call->imm = (MirImm){.tag = MI_FUNC, .a = g};
            /* A `closure.cap` reads the environment through the function's own capture layout,
             * which the thunk does not have: code that captures is called, not inlined. */
            if (mir_inst_count(code) <= MIR_INLINE_BASE_THRESHOLD && code->ncaptures == 0) {
                (void)mir_inline_at(m, t, bi, ii, code, mir_needs_drop(m, code->ret));
            }
            return true;
        }
    }
    return false;
}

typedef struct IcSortEdit { MirValue addr; uint32_t thunk, code; } IcSortEdit;

/* The `func.addr` of a generic sort thunk and the `closure.new` code, by value, of one function. */
static bool ic_sort_scan(MsArena *arena, const MirModule *m, const MirFunc *f, uint32_t **thunks,
                         uint32_t **codes) {
    *thunks = ms_alloc_zeroed(arena, f->nvalues, sizeof(uint32_t));
    *codes = ms_alloc_zeroed(arena, f->nvalues, sizeof(uint32_t));
    memset(*thunks, 0xff, sizeof(uint32_t) * f->nvalues);
    memset(*codes, 0xff, sizeof(uint32_t) * f->nvalues);
    bool any_thunk = false, any_code = false;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *in = &f->blocks[b].insts[i];
            if (in->res == MIR_NONE || in->imm.tag != MI_FUNC) {
                continue;
            }
            if (in->op == MOP_ClosureNew) {
                (*codes)[in->res] = in->imm.a;
                any_code = true;
            } else if (in->op == MOP_FuncAddr && m->funcs[in->imm.a].sort == MSORT_GENERIC) {
                (*thunks)[in->res] = in->imm.a;
                any_thunk = true;
            }
        }
    }
    return any_thunk && any_code;
}

static uint32_t ic_sort_edits(MsArena *arena, const MirFunc *f, const uint32_t *thunks,
                              const uint32_t *codes, IcSortEdit **out) {
    uint32_t n = 0, bound = 0;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            bound += f->blocks[b].insts[i].nargs;
        }
    }
    *out = MS_NEW_N(arena, IcSortEdit, (size_t)bound + 1);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *in = &f->blocks[b].insts[i];
            for (uint32_t w = 0; in->op == MOP_CallRt && w + 1 < in->nargs; w++) {
                if (thunks[in->args[w]] != MIR_NONE && codes[in->args[w + 1]] != MIR_NONE) {
                    (*out)[n++] = (IcSortEdit){in->args[w], thunks[in->args[w]], codes[in->args[w + 1]]};
                }
            }
        }
    }
    return n;
}

/* Points every `func.addr` defining `addr` at `spec`; whether any did. */
static bool ic_sort_retarget(MirFunc *f, MirValue addr, uint32_t spec) {
    bool changed = false;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            MirInst *in = &f->blocks[b].insts[i];
            if (in->res == addr) {
                in->imm.a = spec;
                changed = true;
            }
        }
    }
    return changed;
}

/* Gives each runtime sort whose comparator is a known closure a private copy of the generic
 * `sort.cmp` thunk that calls the closure's code directly (and inlines it). The runtime then makes
 * one indirect call per comparison instead of three. */
bool mir_inline_specialize_sort_thunks(MirModule *m) {
    MsArena arena = {0};
    IcMade made = {0};
    bool changed = false;
    const uint32_t nfuncs = m->nfuncs;
    for (uint32_t fi = 0; fi < nfuncs; fi++) {
        uint32_t *thunks = NULL, *codes = NULL;
        if (!ic_sort_scan(&arena, m, &m->funcs[fi], &thunks, &codes)) {
            continue;
        }
        IcSortEdit *edits = NULL;
        const uint32_t n = ic_sort_edits(&arena, &m->funcs[fi], thunks, codes, &edits);
        for (uint32_t e = 0; e < n; e++) {
            uint32_t spec = ic_made_find(&made, edits[e].thunk, edits[e].code, 0);
            MirFunc thunk;
            if (spec == MIR_NONE && !ic_specialized_thunk(m, edits[e].thunk, edits[e].code, &thunk)) {
                continue;
            }
            if (spec == MIR_NONE) {
                spec = mir_add_func(m, &thunk);
                ic_made_add(&arena, &made, edits[e].thunk, edits[e].code, 0, spec);
            }
            changed |= ic_sort_retarget(&m->funcs[fi], edits[e].addr, spec);
        }
    }
    ms_arena_free(&arena);
    return changed;
}
