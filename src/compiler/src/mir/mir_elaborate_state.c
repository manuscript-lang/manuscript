/* elaborate, the move-state dataflow: the state of the owners in scope, its transfer function over
 * one instruction, the join of two states, and the fixpoint over the function. Port of the first
 * half of elaborate.rs. */
#include "mir/mir_elaborate.h"

bool el_fail(ElCx *cx, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vsnprintf(cx->err, sizeof cx->err, fmt, args);
    va_end(args);
    return false;
}

/* ---- states ---- */

ElSt el_part(ElCx *cx, uint32_t alt, uint32_t cs, uint32_t mask) {
    for (uint32_t i = 0; i < cx->nparts; i++) {
        const ElPart *p = &cx->parts[i];
        if (p->alt == alt && p->cs == cs && p->mask == mask) {
            return EL_PLAIN_KINDS + i;
        }
    }
    if (cx->nparts == cx->cparts) {
        const uint32_t cap = cx->cparts ? cx->cparts * 2 : 8;
        ElPart *grown = MS_NEW_N(cx->ma, ElPart, cap);
        if (cx->nparts > 0) {
            memcpy(grown, cx->parts, sizeof(ElPart) * cx->nparts);
        }
        cx->parts = grown;
        cx->cparts = cap;
    }
    cx->parts[cx->nparts] = (ElPart){alt, cs, mask};
    return EL_PLAIN_KINDS + cx->nparts++;
}

bool el_is_part(ElSt s) { return s >= EL_PLAIN_KINDS; }

const ElPart *el_part_of(const ElCx *cx, ElSt s) { return &cx->parts[s - EL_PLAIN_KINDS]; }

bool el_is_odd(ElSt s) { return s == EL_MAYBE || s == EL_MAYBE_CLOSED || s == EL_CLOSED_OR_MOVED; }

static uint64_t el_pack(MirValue v, ElSt s) { return (uint64_t)v << 32 | s; }

void el_push(ElCx *cx, ElState *st, MirValue v, ElSt s) {
    posmap_insert(cx->ma, &st->at, v, st->next);
    posmap_insert(cx->ma, &st->seq, st->next, el_pack(v, s));
    st->next++;
    if (el_is_odd(s)) {
        owner_insert(cx->ma, &st->odd, v);
    }
}

bool el_position_of(const ElState *st, MirValue v, uint32_t *pos) {
    uint64_t n;
    if (!posmap_get(&st->at, v, &n)) {
        return false;
    }
    *pos = (uint32_t)n;
    return true;
}

bool el_get(const ElState *st, MirValue v, ElSt *s) {
    uint32_t pos;
    uint64_t entry;
    if (!el_position_of(st, v, &pos) || !posmap_get(&st->seq, pos, &entry)) {
        return false;
    }
    *s = (ElSt)entry;
    return true;
}

void el_set(ElCx *cx, ElState *st, MirValue v, ElSt s) {
    uint32_t pos;
    ElSt old;
    if (!el_position_of(st, v, &pos) || (el_get(st, v, &old) && old == s)) {
        return;
    }
    posmap_insert(cx->ma, &st->seq, pos, el_pack(v, s));
    if (el_is_odd(s)) {
        owner_insert(cx->ma, &st->odd, v);
    } else {
        owner_remove(cx->ma, &st->odd, v);
    }
}

void el_remove(ElCx *cx, ElState *st, MirValue v) {
    uint32_t pos;
    if (!el_position_of(st, v, &pos)) {
        return;
    }
    posmap_remove(cx->ma, &st->at, v);
    posmap_remove(cx->ma, &st->seq, pos);
    owner_remove(cx->ma, &st->odd, v);
}

ElOwner *el_owners(ElCx *cx, const ElState *st, uint32_t *n) {
    const uint64_t *entries = posmap_values(cx->ma, &st->seq);
    ElOwner *out = MS_NEW_N(cx->ma, ElOwner, st->seq.len + 1);
    for (uint32_t i = 0; i < st->seq.len; i++) {
        out[i] = (ElOwner){i, (MirValue)(entries[i] >> 32), (ElSt)entries[i]};
    }
    *n = st->seq.len;
    return out;
}

int el_by_position_cmp(const void *x, const void *y) {
    const ElOwner *a = x, *b = y;
    return (a->pos > b->pos) - (a->pos < b->pos);
}

ElOwner *el_odd(ElCx *cx, const ElState *st, uint32_t *n) {
    uint32_t count;
    const uint32_t *values = owner_to_vec(cx->ma, &st->odd, &count);
    ElOwner *out = MS_NEW_N(cx->ma, ElOwner, count + 1);
    uint32_t kept = 0;
    for (uint32_t i = 0; i < count; i++) {
        ElOwner o = {0, values[i], 0};
        if (el_position_of(st, o.v, &o.pos) && el_get(st, o.v, &o.st)) {
            out[kept++] = o;
        }
    }
    qsort(out, kept, sizeof *out, el_by_position_cmp);
    *n = kept;
    return out;
}

/* Equal states are the common join: the shared trees say so without reading an entry. */
bool el_state_equal(const ElState *a, const ElState *b) {
    if (posmap_same_entries(&a->seq, &b->seq) && posmap_same_entries(&a->at, &b->at)) {
        return true;
    }
    if (a->seq.len != b->seq.len) {
        return false;
    }
    MsArena tmp = {0};
    const uint64_t *x = posmap_values(&tmp, &a->seq);
    const uint64_t *y = posmap_values(&tmp, &b->seq);
    const bool same = memcmp(x, y, sizeof(uint64_t) * a->seq.len) == 0;
    ms_arena_free(&tmp);
    return same;
}

/* ---- tags ---- */

bool el_tagged(const ElCx *cx, MirValue v) { return v < cx->nvalues0 && cx->tag_scope[v] >= 0; }

bool el_is_slot_owner(const ElCx *cx, MirValue v) {
    return cx->f->values[v] == MIR_PTR && el_tagged(cx, v) && cx->tag_kind[v] >= 2;
}

/* ---- transfer ---- */

/* The owner `v` left the scope's hands on this path. A slot owner or a disowned owner stays
 * tracked as moved: its cleanup entry or the exits after it still act on it. Any other owner
 * needs nothing from here on, so its entry goes: keeping one per moved temporary made every
 * block's state grow with the function. */
static void el_finish(ElCx *cx, ElState *st, MirValue v) {
    const bool tracked = (el_tagged(cx, v) && cx->tag_kind[v] >= 2) || uh_has(&cx->disown_moves, v);
    if (tracked) {
        el_set(cx, st, v, EL_MOVED);
    } else {
        el_remove(cx, st, v);
    }
}

bool el_consume_value(ElCx *cx, ElState *st, MirValue v) {
    ElSt s;
    if (!el_get(st, v, &s)) {
        return true;
    }
    if (s == EL_LIVE) {
        el_finish(cx, st, v);
        return true;
    }
    if (s == EL_MOVED) {
        /* Disowned, then consumed by the op that takes it. */
        return uh_has(&cx->disown_moves, v) ||
               el_fail(cx, "%%%u is consumed after it was moved", v);
    }
    if (s == EL_MAYBE || s == EL_CLOSED_OR_MOVED) {
        return el_fail(cx, "%%%u is consumed but moved on some path", v);
    }
    if (el_is_part(s)) {
        return el_fail(cx, "%%%u is consumed after a partial move", v);
    }
    return el_fail(cx, "%%%u is consumed after the program closed it", v);
}

static const char *el_kind_name(ElSt s) {
    static const char *const names[] = {"Live", "Moved", "Maybe", "Closed", "MaybeClosed",
                                        "ClosedOrMoved"};
    return names[s];
}

/* The Debug text of a state, as the Rust pass formats it in its errors. */
static void el_describe(const ElCx *cx, ElSt s, char *out, size_t n) {
    if (!el_is_part(s)) {
        snprintf(out, n, "%s", el_kind_name(s));
        return;
    }
    const ElPart *p = el_part_of(cx, s);
    snprintf(out, n, "Part(AltId(%u), %u, %u)", p->alt, p->cs, p->mask);
}

static bool el_apply_disown(ElCx *cx, ElState *st, MirValue v) {
    ElSt s;
    if (el_is_slot_owner(cx, v)) {
        /* A memory slot owner whose value moved out stays tracked: its entry is cancelled and
         * the scope end closes nothing for it on this path. */
        if (!el_get(st, v, &s) || s == EL_MOVED) {
            return true;
        }
        if (s == EL_LIVE || s == EL_CLOSED) {
            el_set(cx, st, v, EL_MOVED);
            return true;
        }
        char text[64];
        el_describe(cx, s, text, sizeof text);
        return el_fail(cx, "slot owner %%%u moved out of in an unsupported state %s", v, text);
    }
    /* A flagged owner stays tracked as moved: the op that consumes it after the disown, and the
     * exits after it, see the flag turn false. */
    if (uh_has(&cx->disown_moves, v) && el_get(st, v, &s) && s == EL_LIVE) {
        el_set(cx, st, v, EL_MOVED);
    } else {
        el_remove(cx, st, v);
    }
    return true;
}

static bool el_apply_mark(ElCx *cx, ElState *st, const MirInst *inst) {
    const MirValue v = inst->args[0];
    const bool refill = inst->imm.tag == MI_INT && inst->imm.i == 2;
    const ElSt next = inst->imm.tag == MI_INT && inst->imm.i == 1 ? EL_CLOSED : EL_LIVE;
    ElSt s;
    if (!el_get(st, v, &s)) {
        return true;
    }
    if (s == EL_LIVE || s == EL_CLOSED || s == EL_MAYBE_CLOSED) {
        el_set(cx, st, v, next);
        return true;
    }
    /* A refill stores a new value in a slot whose value moved out. */
    if (refill && (s == EL_MOVED || s == EL_MAYBE || s == EL_CLOSED_OR_MOVED)) {
        el_set(cx, st, v, EL_LIVE);
        return true;
    }
    return el_fail(cx, "slot owner %%%u closed by hand after a move", v);
}

/* `alt.take` of a payload field out of an owner marks it partially moved. */
static bool el_apply_take(ElCx *cx, ElState *st, const MirInst *inst) {
    ElSt cur;
    if (inst->op != MOP_AltTake) {
        return true;
    }
    const MirValue v = inst->args[0];
    if (!el_get(st, v, &cur) || !el_tagged(cx, v)) {
        return true;
    }
    const uint32_t alt = inst->imm.a, cs = inst->imm.b, bit = 1u << inst->imm.c;
    ElSt next;
    if (cur == EL_LIVE) {
        next = el_part(cx, alt, cs, bit);
    } else if (el_is_part(cur) && el_part_of(cx, cur)->alt == alt && el_part_of(cx, cur)->cs == cs) {
        next = el_part(cx, alt, cs, el_part_of(cx, cur)->mask | bit);
    } else if (cur == EL_MOVED && uh_has(&cx->disown_moves, v)) {
        /* Disowned ahead of the take: the value already left the scope. */
        next = EL_MOVED;
    } else {
        return el_fail(cx, "alt.take on %%%u in an unsupported state", v);
    }
    el_set(cx, st, v, next);
    return true;
}

static bool el_consume_args(ElCx *cx, ElState *st, const MirInst *inst) {
    MirMode *modes = MS_NEW_N(cx->ma, MirMode, inst->nargs + 1);
    mir_arg_modes(cx->m, cx->f, inst, modes);
    for (uint32_t i = 0; i < inst->nargs; i++) {
        const MirValue a = inst->args[i];
        if (modes[i] == MM_MOVE && mir_needs_drop(cx->m, cx->f->values[a]) &&
            !el_consume_value(cx, st, a)) {
            return false;
        }
    }
    return true;
}

bool el_apply(ElCx *cx, ElState *st, const MirInst *inst) {
    if (inst->op == MOP_ScopeDisown) {
        return el_apply_disown(cx, st, inst->args[0]);
    }
    if (inst->op == MOP_ScopeMark) {
        return el_apply_mark(cx, st, inst);
    }
    ElSt s;
    if (inst->op == MOP_ScopeOwn) {
        /* A disowned view that moves into another local is owned again by that local's scope; a
         * slot owner handed on to an enclosing scope holds its value again. */
        const MirValue v = inst->args[0];
        if (!el_get(st, v, &s)) {
            el_push(cx, st, v, EL_LIVE);
        } else if (s == EL_MOVED && el_is_slot_owner(cx, v)) {
            el_set(cx, st, v, EL_LIVE);
        }
        return true;
    }
    if (inst->op == MOP_ScopeEnd) {
        const int64_t scope = inst->imm.a;
        if ((uint64_t)scope < cx->nscopes) {
            for (uint32_t i = 0; i < cx->owners[scope].n; i++) {
                el_remove(cx, st, cx->owners[scope].v[i]);
            }
        }
        return true;
    }
    /* Lowering releases what an `alt.take` left behind itself: that finishes the owner. */
    if (inst->op == MOP_AltRelease && el_get(st, inst->args[0], &s) && el_is_part(s)) {
        el_finish(cx, st, inst->args[0]);
        return true;
    }
    MirMode result;
    if (!el_consume_args(cx, st, inst) || !el_apply_take(cx, st, inst)) {
        return false;
    }
    if (mir_result_mode(cx->m, cx->f, inst, &result) && result == MM_MOVE && inst->res != MIR_NONE) {
        el_push(cx, st, inst->res, EL_LIVE);
    }
    return true;
}

/* ---- edges and joins ---- */

bool el_own_params(const ElCx *cx, uint32_t b, MirValue **out, uint32_t *n) {
    const MirBlockData *blk = &cx->f->blocks[b];
    MirValue *list = MS_NEW_N(cx->ma, MirValue, blk->nparams + 1);
    uint32_t count = 0;
    for (uint32_t i = 0; i < blk->nparams; i++) {
        const MirBlockParam *p = &blk->params[i];
        if (p->mode == MM_MOVE && mir_needs_drop(cx->m, cx->f->values[p->value])) {
            list[count++] = p->value;
        }
    }
    *out = list;
    *n = count;
    return true;
}

/* The state flowing along the edge `t`: the arguments of owning parameters are consumed. */
bool el_edge_state(ElCx *cx, const ElState *st, const MirTarget *t, ElState *out) {
    const MirBlockData *dest = &cx->f->blocks[t->block];
    *out = *st;
    const uint32_t n = t->nargs < dest->nparams ? t->nargs : dest->nparams;
    for (uint32_t i = 0; i < n; i++) {
        if (dest->params[i].mode == MM_MOVE &&
            mir_needs_drop(cx->m, cx->f->values[t->args[i]]) &&
            !el_consume_value(cx, out, t->args[i])) {
            return false;
        }
    }
    return true;
}

static bool el_held_or_closed(ElSt s) {
    return s == EL_LIVE || s == EL_CLOSED || s == EL_MAYBE_CLOSED;
}

static bool el_hand_closed(ElSt s) {
    return s == EL_CLOSED || s == EL_MAYBE_CLOSED || s == EL_CLOSED_OR_MOVED;
}

/* The state of an owner both paths hold, or false when they cannot be joined. */
static bool el_join_one(ElCx *cx, MirValue v, ElSt a, ElSt b, ElSt *out) {
    if (a == b) {
        *out = a;
    } else if (el_held_or_closed(a) && el_held_or_closed(b)) {
        *out = EL_MAYBE_CLOSED;
    } else if (el_is_part(a) || el_is_part(b)) {
        return el_fail(cx, "%%%u is partially moved on only some paths", v);
    } else if (el_hand_closed(a) || el_hand_closed(b)) {
        *out = EL_CLOSED_OR_MOVED;
    } else {
        *out = EL_MAYBE;
    }
    return true;
}

bool el_merge(ElCx *cx, const ElState *old, const ElState *next, ElState *out) {
    if (el_state_equal(old, next)) {
        *out = *old;
        return true;
    }
    *out = (ElState){0};
    uint32_t n;
    const ElOwner *mine = el_owners(cx, old, &n);
    for (uint32_t i = 0; i < n; i++) {
        ElSt b = EL_LIVE, joined = EL_LIVE;
        if (!el_get(next, mine[i].v, &b)) {
            /* Gone on the other path: consumed or disowned there, so moved. */
            if (mine[i].st == EL_LIVE || mine[i].st == EL_MAYBE) {
                el_push(cx, out, mine[i].v, EL_MAYBE);
            }
        } else if (el_join_one(cx, mine[i].v, mine[i].st, b, &joined)) {
            el_push(cx, out, mine[i].v, joined);
        } else {
            return false;
        }
    }
    const ElOwner *theirs = el_owners(cx, next, &n);
    for (uint32_t i = 0; i < n; i++) {
        ElSt a;
        if (!el_get(old, theirs[i].v, &a) && (theirs[i].st == EL_LIVE || theirs[i].st == EL_MAYBE)) {
            el_push(cx, out, theirs[i].v, EL_MAYBE);
        }
    }
    return true;
}

/* ---- the fixpoint ---- */

/* The state at the end of block `b` from its entry state. */
static bool el_walk_block(ElCx *cx, uint32_t b, ElState *st) {
    MirValue *params;
    uint32_t nparams;
    el_own_params(cx, b, &params, &nparams);
    for (uint32_t i = 0; i < nparams; i++) {
        el_push(cx, st, params[i], EL_LIVE);
    }
    const MirBlockData *blk = &cx->f->blocks[b];
    for (uint32_t i = 0; i < blk->ninsts; i++) {
        if (!el_apply(cx, st, &blk->insts[i])) {
            return false;
        }
    }
    return blk->term.kind != MT_RET || blk->term.value == MIR_NONE ||
           el_consume_value(cx, st, blk->term.value);
}

bool el_analyze(ElCx *cx, const MirBlock *order, uint32_t norder, ElState *entry, bool *has) {
    const uint32_t nblocks = cx->f->nblocks;
    bool *dirty = MS_NEW_N(cx->ma, bool, nblocks + 1);
    memset(dirty, 0, nblocks + 1);
    memset(has, 0, nblocks + 1);
    entry[0] = (ElState){0};
    has[0] = true;
    dirty[0] = true;
    /* A block's outgoing states depend only on its entry state, so a pass revisits just the
     * blocks whose entry changed since they were last walked. */
    for (uint64_t round = 0; round <= 4ull * nblocks + 4; round++) {
        bool changed = false;
        for (uint32_t k = 0; k < norder; k++) {
            const MirBlock b = order[k];
            if (!dirty[b]) {
                continue;
            }
            dirty[b] = false;
            if (!has[b]) {
                continue;
            }
            ElState st = entry[b];
            if (!el_walk_block(cx, b, &st)) {
                return false;
            }
            const MirTerm *term = &cx->f->blocks[b].term;
            for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
                const MirTarget *target = mir_term_target_const(term, t);
                ElState next, merged;
                if (!el_edge_state(cx, &st, target, &next)) {
                    return false;
                }
                const bool seen = has[target->block];
                merged = next;
                if (seen && !el_merge(cx, &entry[target->block], &next, &merged)) {
                    return false;
                }
                if (!seen || !el_state_equal(&entry[target->block], &merged)) {
                    entry[target->block] = merged;
                    has[target->block] = true;
                    dirty[target->block] = true;
                    changed = true;
                }
            }
        }
        if (!changed) {
            return true;
        }
    }
    return el_fail(cx, "the move state did not reach a fixpoint");
}
