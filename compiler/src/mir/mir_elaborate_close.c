/* elaborate, cleanup: closes or drops the owners of a scope where it ends, on the paths that still
 * hold them, and builds the error edge a failing close leaves through. Port of the second half of
 * the `Em` code in elaborate.rs. */
#include "mir/mir_elaborate.h"

static MirImm em_imm_ty(MirTy ty) { return (MirImm){.tag = MI_TY, .a = ty}; }

void em_drop_owned(ElEm *em, uint32_t at, MirValue v) {
    if (mir_needs_drop(em->m, em->f->values[v])) {
        em_push(em, at, MOP_Drop, &v, 1, mir_imm_none(), EM_NO_RESULT);
    }
}

MirValue em_is_error(ElEm *em, uint32_t at, MirValue r) {
    const MirValue tag = em_push(em, at, MOP_AltTag, &r, 1, mir_imm_none(), MIR_INT);
    const MirValue err = em_iconst(em, at, 1); /* the `Error` case of a Result */
    const MirValue pair[2] = {tag, err};
    return em_push(em, at, MOP_ICmp, pair, 2, mir_imm_cc(MCC_EQ), MIR_BOOL);
}

/* Whether the shield calls exist; the error says a closing owner needs them otherwise. */
static bool em_shield(ElEm *em) {
    return em->cx->shield_enter != MIR_NONE ||
           el_fail(em->cx, "a closing owner needs the shield calls");
}

/* What a `slot_close` thunk left in the slot is taken out and dropped. */
static void em_release_slot(ElEm *em, uint32_t at, MirValue v, uint32_t close) {
    const MirFunc *cf = &em->m->funcs[close];
    if (cf->has_slot_close) {
        const MirValue left = em_push(em, at, MOP_Take, &v, 1, em_imm_ty(cf->slot_close), cf->slot_close);
        em_push(em, at, MOP_Drop, &left, 1, mir_imm_none(), EM_NO_RESULT);
    }
}

bool em_close_result(ElEm *em, uint32_t at, MirValue v, uint32_t rc, MirValue *r) {
    uint32_t close;
    if (!em_shield(em)) {
        return false;
    }
    em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_enter), MIR_VOID);
    *r = em_push(em, at, MOP_Call, &v, 1, em_imm_func(rc), em->m->funcs[rc].ret);
    em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_exit), MIR_VOID);
    if (!em_closer(em, v, &close)) {
        return false;
    }
    em_release_slot(em, at, v, close);
    return true;
}

/* Closes the live `v` of an owner that cannot fail, shielded from a stop request; the caller drops
 * what the close leaves behind. */
static bool em_close_infallible(ElEm *em, uint32_t at, MirValue v) {
    uint32_t close;
    if (!em_closer(em, v, &close) || !em_shield(em)) {
        return false;
    }
    em_discard(em, at, v);
    em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_enter), MIR_VOID);
    em_push(em, at, MOP_Call, &v, 1, em_imm_func(close), MIR_VOID);
    em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_exit), MIR_VOID);
    return true;
}

/* Closes the infallible memory slot owner `v` that still holds its value, shielded: its close
 * function (an in-slot cleanup entry, `slot_close`) takes the address, and what the close leaves in
 * the slot is taken out and dropped. */
static bool em_close_slot(ElEm *em, uint32_t at, MirValue v) {
    uint32_t close;
    if (!em_close_infallible(em, at, v) || !em_closer(em, v, &close)) {
        return false;
    }
    em_release_slot(em, at, v, close);
    return true;
}

/* The success of the `Result` type `rty` (its `ok` payload is `unit`). */
static bool em_ok_unit(ElEm *em, uint32_t at, MirTy rty, MirValue *out) {
    const MirTyData *d = mir_ty_data(em->m, rty);
    if (d->kind != MK_ALT) {
        return el_fail(em->cx, "a fallible close returns a Result");
    }
    if (em->m->alts[d->id].cases[0].fields[0].ty != MIR_VOID) {
        return el_fail(em->cx, "a moved slot owner whose close succeeds with a value");
    }
    const MirValue unit = em_push(em, at, MOP_VoidConst, NULL, 0, mir_imm_none(), MIR_VOID);
    *out = em_push(em, at, MOP_AltNew, &unit, 1, em_imm_case(d->id, 0), rty);
    return true;
}

static bool em_no_flag(ElEm *em, bool slot) {
    return el_fail(em->cx, slot ? "a moved slot owner without a drop flag"
                                : "a moved owner without a drop flag");
}

/* Splits `at` on `flag` into two fresh blocks and a join. */
static void em_split(ElEm *em, uint32_t at, MirValue flag, MirBlock *yes, MirBlock *no,
                     MirBlock *join) {
    *yes = em_new_block(em);
    *no = em_new_block(em);
    *join = em_new_block(em);
    em_condbr(em, at, flag, *yes, *no);
}

/* ---- owners that cannot fail ---- */

/* Cleans up an owner whose close cannot fail: it closes only on the paths that still hold it. */
static bool em_cleanup_infallible(ElEm *em, uint32_t *at, MirValue v, ElSt s, MirValue flag) {
    const bool ptr = em->f->values[v] == MIR_PTR;
    if (s == EL_LIVE) {
        if (ptr) {
            return em_close_slot(em, *at, v);
        }
        if (!em_close_infallible(em, *at, v)) {
            return false;
        }
        em_push(em, *at, MOP_Drop, &v, 1, mir_imm_none(), EM_NO_RESULT);
        return true;
    }
    if (el_is_part(s)) {
        return el_fail(em->cx, "a partially moved closing owner");
    }
    if (s == EL_CLOSED || s == EL_MAYBE_CLOSED) {
        /* Closing again releases what the hand close left; the result is ignored. */
        return em_close_slot(em, *at, v);
    }
    if (ptr && (s == EL_MOVED || s == EL_MAYBE || s == EL_CLOSED_OR_MOVED)) {
        /* The flag says whether the value is still in the slot. The cancelled entry (or the live
         * one) leaves the stack either way. */
        if (flag == MIR_NONE) {
            return em_no_flag(em, true);
        }
        MirBlock yes, no, join;
        em_split(em, *at, flag, &yes, &no, &join);
        if (!em_close_slot(em, yes, v)) {
            return false;
        }
        em_br(em, yes, join, NULL, 0);
        em_discard(em, no, v);
        em_br(em, no, join, NULL, 0);
        *at = join;
        return true;
    }
    if (s == EL_CLOSED_OR_MOVED) {
        return el_fail(em->cx, "only a memory slot owner is closed by hand");
    }
    if (flag == MIR_NONE) {
        return em_no_flag(em, false);
    }
    const MirValue args[2] = {flag, v};
    if (s == EL_MOVED) {
        em_push(em, *at, MOP_DropIf, args, 2, mir_imm_none(), EM_NO_RESULT);
        return true;
    }
    const MirBlock yes = em_new_block(em);
    const MirBlock join = em_new_block(em);
    em_condbr(em, *at, flag, yes, join);
    if (!em_close_infallible(em, yes, v)) {
        return false;
    }
    em_br(em, yes, join, NULL, 0);
    em_push(em, join, MOP_DropIf, args, 2, mir_imm_none(), EM_NO_RESULT);
    *at = join;
    return true;
}

/* ---- slot owners whose close returns a Result ---- */

/* Closes the slot owner `v` the program may have closed by hand (the closed flag says): a hand
 * close is closed again to release the rest and its result dropped, so the outcome is a plain
 * success. Returns the block to continue in and the close's `Result`. */
static bool em_close_maybe_closed(ElEm *em, uint32_t *at, MirValue v, uint32_t rc, MirValue *out) {
    const MirTy rty = em->m->funcs[rc].ret;
    MirValue key, flag;
    if (!em_flag_of(&em->ckeys, v, &key) || !em_flag_of(&em->flags, key, &flag)) {
        return el_fail(em->cx, "a maybe-closed owner without a flag");
    }
    MirBlock yes, no, join;
    em_split(em, *at, flag, &yes, &no, &join);
    em_discard(em, yes, v);
    em_discard(em, no, v);
    MirValue again, none, real;
    if (!em_close_result(em, yes, v, rc, &again)) {
        return false;
    }
    em_drop_owned(em, yes, again);
    if (!em_ok_unit(em, yes, rty, &none)) {
        return false;
    }
    em_br(em, yes, join, &none, 1);
    if (!em_close_result(em, no, v, rc, &real)) {
        return false;
    }
    em_br(em, no, join, &real, 1);
    *out = em_block_param(em, join, rty, MM_MOVE);
    *at = join;
    return true;
}

/* The `Result` of closing a slot owner that may have moved out on some path: the flag says whether
 * the value is still in the slot; a path that moved it closes nothing and adds the success. */
static bool em_close_flagged(ElEm *em, uint32_t *at, MirValue v, ElSt s, uint32_t rc, MirValue *out) {
    const MirTy rty = em->m->funcs[rc].ret;
    MirValue flag, closed, none;
    if (!em_flag_of(&em->flags, v, &flag)) {
        return em_no_flag(em, true);
    }
    MirBlock yes, no, join;
    em_split(em, *at, flag, &yes, &no, &join);
    if (s == EL_CLOSED_OR_MOVED) {
        /* If the value is in the slot the closed flag says whether the program closed it. */
        uint32_t end = yes;
        if (!em_close_maybe_closed(em, &end, v, rc, &closed)) {
            return false;
        }
        em_br(em, end, join, &closed, 1);
        em_discard(em, no, v);
    } else {
        em_discard(em, yes, v);
        em_discard(em, no, v);
        if (!em_close_result(em, yes, v, rc, &closed)) {
            return false;
        }
        em_br(em, yes, join, &closed, 1);
    }
    if (!em_ok_unit(em, no, rty, &none)) {
        return false;
    }
    em_br(em, no, join, &none, 1);
    *out = em_block_param(em, join, rty, MM_MOVE);
    *at = join;
    return true;
}

/* The first failing close is the outcome (the `Result` it returned, owned); later results are
 * dropped. */
static bool em_keep_first_error(ElEm *em, uint32_t *at, MirValue first, MirValue r, MirTy rty,
                                MirValue *out) {
    const MirValue failed = em_is_error(em, *at, first);
    const MirBlock keep = em_new_block(em);
    const MirBlock replace = em_new_block(em);
    const MirBlock join = em_new_block(em);
    em_condbr(em, *at, failed, keep, replace);
    em_drop_owned(em, keep, r);
    em_br(em, keep, join, &first, 1);
    em_drop_owned(em, replace, first);
    em_br(em, replace, join, &r, 1);
    *out = em_block_param(em, join, rty, MM_MOVE);
    *at = join;
    return true;
}

/* Cleans up a memory-slot owner whose close returns a `Result` (`rc` runs it): shielded, on the
 * path that still holds it. */
static bool em_cleanup_fallible(ElEm *em, uint32_t *at, MirValue v, ElSt s, uint32_t rc,
                                MirValue *outcome) {
    if (el_is_part(s)) {
        return el_fail(em->cx, "a partially moved slot owner");
    }
    MirValue r = MIR_NONE;
    if (s == EL_CLOSED) {
        /* Closed by the program: close again to release the rest, drop that result. */
        em_discard(em, *at, v);
        if (!em_close_result(em, *at, v, rc, &r)) {
            return false;
        }
        em_drop_owned(em, *at, r);
        return true;
    }
    bool ok;
    if (s == EL_MAYBE_CLOSED) {
        ok = em_close_maybe_closed(em, at, v, rc, &r);
    } else if (s == EL_LIVE) {
        em_discard(em, *at, v);
        ok = em_close_result(em, *at, v, rc, &r);
    } else {
        ok = em_close_flagged(em, at, v, s, rc, &r);
    }
    if (!ok) {
        return false;
    }
    if (*outcome == MIR_NONE) {
        *outcome = r;
        return true;
    }
    return em_keep_first_error(em, at, *outcome, r, em->m->funcs[rc].ret, outcome);
}

/* ---- one owner, one scope ---- */

/* The failure code the close of a kind-1 owner returns, once its block is built. */
static bool em_close_code(ElEm *em, uint32_t *at, MirValue v, ElSt s, MirValue flag, MirValue *code) {
    uint32_t close;
    const int64_t kind = em->cx->tag_kind[v];
    *code = MIR_NONE;
    if (el_is_part(s)) {
        if (kind != 0) {
            return el_fail(em->cx, "a partially moved closing owner");
        }
        const ElPart *p = el_part_of(em->cx, s);
        const MirImm imm = {.tag = MI_ALTMASK, .a = p->alt, .b = p->cs, .c = p->mask};
        em_push(em, *at, MOP_AltRelease, &v, 1, imm, EM_NO_RESULT);
        return true;
    }
    if (s == EL_CLOSED || s == EL_MAYBE_CLOSED || s == EL_CLOSED_OR_MOVED) {
        return el_fail(em->cx, "only a memory slot owner is closed by hand");
    }
    if (s == EL_LIVE && kind == 0) {
        em_push(em, *at, MOP_Drop, &v, 1, mir_imm_none(), EM_NO_RESULT);
        return true;
    }
    if (s == EL_LIVE) {
        em_discard(em, *at, v);
        if (!em_closer(em, v, &close)) {
            return false;
        }
        *code = em_push(em, *at, MOP_Call, &v, 1, em_imm_func(close), MIR_INT);
        return true;
    }
    if (flag == MIR_NONE) {
        return em_no_flag(em, false);
    }
    const MirValue args[2] = {flag, v};
    if (s == EL_MOVED || kind == 0) {
        em_push(em, *at, MOP_DropIf, args, 2, mir_imm_none(), EM_NO_RESULT);
        return true;
    }
    /* Maybe-moved closing owner: close it where the flag says it is still held. */
    MirBlock yes, no, join;
    em_split(em, *at, flag, &yes, &no, &join);
    em_discard(em, yes, v);
    if (!em_closer(em, v, &close)) {
        return false;
    }
    const MirValue c = em_push(em, yes, MOP_Call, &v, 1, em_imm_func(close), MIR_INT);
    em_br(em, yes, join, &c, 1);
    em_push(em, no, MOP_DropIf, args, 2, mir_imm_none(), EM_NO_RESULT);
    const MirValue zero = em_iconst(em, no, 0);
    em_br(em, no, join, &zero, 1);
    *code = em_block_param(em, join, MIR_INT, MM_BORROW);
    *at = join;
    return true;
}

/* Cleans up one owner, `st` already says its state. `*outcome` is the first close failure so far. */
bool em_cleanup_one(ElEm *em, uint32_t *at, MirValue v, ElSt s, MirValue *outcome) {
    const int64_t kind = em->cx->tag_kind[v];
    MirValue flag = MIR_NONE, code;
    em_flag_of(&em->flags, v, &flag);
    if (kind >= 2) {
        uint32_t close;
        if (em->f->values[v] == MIR_PTR) {
            if (!em_closer(em, v, &close)) {
                return false;
            }
            if (em->m->funcs[close].has_slot_result) {
                return em_cleanup_fallible(em, at, v, s, em->m->funcs[close].slot_result, outcome);
            }
        }
        return em_cleanup_infallible(em, at, v, s, flag);
    }
    if (!em_close_code(em, at, v, s, flag, &code)) {
        return false;
    }
    if (code == MIR_NONE) {
        return true;
    }
    if (*outcome == MIR_NONE) {
        *outcome = code;
        return true;
    }
    const MirValue zero = em_iconst(em, *at, 0);
    const MirValue pair[2] = {*outcome, zero};
    const MirValue failed = em_push(em, *at, MOP_ICmp, pair, 2, mir_imm_cc(MCC_NE), MIR_BOOL);
    const MirValue pick[3] = {failed, *outcome, code};
    *outcome = em_push(em, *at, MOP_Select, pick, 3, mir_imm_none(), MIR_INT);
    return true;
}

typedef struct EmByPosition { MirValue v; ElSt s; uint32_t pos; } EmByPosition;

static int em_latest_first(const void *x, const void *y) {
    const EmByPosition *a = x, *b = y;
    return (a->pos < b->pos) - (a->pos > b->pos);
}

/* Closes or drops the owners of `scope`, last defined first. */
static bool em_cleanup(ElEm *em, uint32_t *at, ElState *st, int64_t scope, MirValue *outcome) {
    const ElCx *cx = em->cx;
    if ((uint64_t)scope >= cx->nscopes) {
        return true;
    }
    const ElList *list = &cx->owners[scope];
    EmByPosition *owners = MS_NEW_N(cx->ma, EmByPosition, list->n + 1);
    uint32_t n = 0;
    for (uint32_t i = 0; i < list->n; i++) {
        EmByPosition o = {list->v[i], 0, 0};
        if (el_get(st, o.v, &o.s) && el_position_of(st, o.v, &o.pos)) {
            owners[n++] = o;
        }
    }
    qsort(owners, n, sizeof *owners, em_latest_first);
    for (uint32_t i = 0; i < n; i++) {
        el_remove(em->cx, st, owners[i].v);
        if (owners[i].s == EL_MOVED && !uh_has(&em->flagged, owners[i].v)) {
            /* A slot owner's cancelled entry leaves the stack now. */
            if (el_is_slot_owner(cx, owners[i].v)) {
                em_discard(em, *at, owners[i].v);
            }
        } else if (!em_cleanup_one(em, at, owners[i].v, owners[i].s, outcome)) {
            return false;
        }
    }
    return true;
}

/* ---- the scope end ---- */

/* The failure test of the outcome of a scope: nonzero code, or an error `Result`. */
static MirValue em_failed(ElEm *em, uint32_t at, MirValue first, bool by_result) {
    if (by_result) {
        return em_is_error(em, at, first);
    }
    const MirValue zero = em_iconst(em, at, 0);
    const MirValue pair[2] = {first, zero};
    return em_push(em, at, MOP_ICmp, pair, 2, mir_imm_cc(MCC_NE), MIR_BOOL);
}

/* What else is live when a failing close leaves the function: the owners the cleanup did not reach,
 * latest first. */
static bool em_drop_rest(ElEm *em, uint32_t at, ElState *rest, bool by_result) {
    uint32_t n;
    const ElOwner *owners = el_owners(em->cx, rest, &n);
    for (uint32_t i = n; i-- > 0;) {
        const MirValue v = owners[i].v;
        MirValue flag;
        /* A fallible outcome consumes the value the function was about to return. */
        if (by_result && em->pending == v) {
            continue;
        }
        if (owners[i].st == EL_LIVE) {
            em_push(em, at, MOP_Drop, &v, 1, mir_imm_none(), EM_NO_RESULT);
        } else if (uh_has(&em->flagged, v)) {
            if (!em_flag_of(&em->flags, v, &flag)) {
                return el_fail(em->cx, "no drop flag for %%%u", v);
            }
            const MirValue args[2] = {flag, v};
            em_push(em, at, MOP_DropIf, args, 2, mir_imm_none(), EM_NO_RESULT);
        }
    }
    return true;
}

/* The error edge: the enclosing scopes' cleanup, then what else is live, then return. */
static bool em_error_edge(ElEm *em, uint32_t at, ElState *st, int64_t scope, MirValue first,
                          bool by_result) {
    ElCx *cx = em->cx;
    ElState rest = *st;
    MirValue outcome = first;
    int64_t s = (uint64_t)scope < cx->nscopes && cx->has_parent[scope] ? cx->parent[scope] : -1;
    while (s >= 0) {
        if (!em_cleanup(em, &at, &rest, s, &outcome)) {
            return false;
        }
        s = (uint64_t)s < cx->nscopes && cx->has_parent[s] ? cx->parent[s] : -1;
    }
    if (!em_drop_rest(em, at, &rest, by_result)) {
        return false;
    }
    MirValue ret = outcome;
    if (by_result) {
        /* The function leaves here: undo its recursion guard like any return. */
        if (em->counts_depth) {
            em_push(em, at, MOP_DepthLeave, NULL, 0, mir_imm_none(), EM_NO_RESULT);
        }
        if (!em->f->has_close_exit) {
            return el_fail(cx, "a fallible close needs the function's close exit");
        }
        const MirFunc *f = em->f;
        const MirValue with_pending[2] = {outcome, em->pending};
        ret = em->pending != MIR_NONE
                  ? em_push(em, at, MOP_Call, with_pending, 2, em_imm_func(f->close_exit[1]), f->ret)
                  : em_push(em, at, MOP_Call, &outcome, 1, em_imm_func(f->close_exit[0]), f->ret);
    }
    MirTerm *t = &em->f->blocks[at].term;
    memset(t, 0, sizeof *t);
    t->kind = MT_RET;
    t->value = ret;
    return true;
}

/* The cleanup of `scope` at a `scope.end`. `*cur` becomes the block to continue in. */
bool em_exit(ElEm *em, uint32_t *cur, ElState *st, int64_t scope) {
    MirValue first = MIR_NONE;
    if (!em_cleanup(em, cur, st, scope, &first)) {
        return false;
    }
    if (first == MIR_NONE) {
        return true;
    }
    const bool by_result = em->f->values[first] != MIR_INT;
    if (em->in_cancel) {
        /* The exit serves a cancel: a close error has nowhere to go and is dropped. */
        if (by_result) {
            em_drop_owned(em, *cur, first);
        }
        return true;
    }
    const MirValue failed = em_failed(em, *cur, first, by_result);
    const MirBlock err = em_new_block(em);
    const MirBlock after = em_new_block(em);
    if (by_result) {
        em_drop_owned(em, after, first);
    }
    em_condbr(em, *cur, failed, err, after);
    if (!em_error_edge(em, err, st, scope, first, by_result)) {
        return false;
    }
    *cur = after;
    return true;
}
