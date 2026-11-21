/* Resources in the lowering (crates/ms-lower/src/close.rs): a local whose type has its own `close`
 * lives in a stack slot, and the elaborate pass closes it where its scope ends, on every way out.
 * The lowering writes what that pass reads:
 *
 *     slot, put/store          the local, in memory
 *     scope.own %slot, kind    kind = the function that closes the slot, plus two
 *
 * and makes the helper functions it names. The closing thunk takes the address and runs `close`;
 * for a `close` returning a `Result` the pass also wants the thunk that returns that result
 * (`slot_result`) and the functions that turn a failed close into the function's own return value
 * (`close_exit`, plain and with the value the function was already returning).
 *
 * Handled: a `let` local made from a call or construction, of a type with a direct `close`
 * (a `Closeable` implementation, or an own `close() Void!`) that does not change `self`, used only
 * as a borrow. Every other use (a move, a close by hand, a capture), type holding resources, or
 * drop of a resource leaves the function to the Rust lowering. */
#include <stdio.h>
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/mir_pass.h"

enum { LC_OK = 0, LC_ERROR = 1 }; /* the cases of `Result` */

/* The row of the `close` that closes values of `ty` itself, or MS_NONE. */
static uint32_t lc_row(Lb *lb, MsTy ty) {
    const MsMethods *methods = lb->facts->methods;
    const MsTyTable *tys = &lb->c->tys;
    for (uint32_t i = 0; i < methods->count; i++) {
        const MsFunc *decl = methods->decl[i];
        MsTy args[LB_MAX_TARGS];
        if (decl == NULL || !ms_name_is(lb->c->names, decl->name, "close") || !lm_has(lb, i)) {
            continue;
        }
        // The close of this type, or of a generic type this one is an instance of (`WriteStream[String]`).
        const bool direct = methods->receiver[i] == ty && methods->nvars[i] == 0;
        if (!direct && !(methods->nvars[i] != 0 && lm_match(lb, i, ty, args))) {
            continue;
        }
        if (methods->contract[i] != MS_TY_NONE && ms_ty_is(tys, methods->contract[i], MS_BI_CLOSEABLE)) {
            return i;
        }
        const MsTy result = tys->result[methods->ty[i]];
        if (methods->inherent[i] && tys->nparams[methods->ty[i]] == 0 && ms_ty_is(tys, result, MS_BI_RESULT) &&
            tys->nargs[result] == 2 && ms_ty_is(tys, ms_ty_args(tys, result)[0], MS_BI_VOID) &&
            ms_ty_is(tys, ms_ty_args(tys, result)[1], MS_BI_ERROR)) {
            return i;
        }
    }
    return MS_NONE;
}

bool lc_has_closer(Lb *lb, MsTy ty) {
    uint32_t slot;
    MirTy result;
    if (ms_ty_kind(&lb->c->tys, ty) == MS_K_CONTRACT) {
        return li_closer(lb, ty, &slot, &result);
    }
    const uint32_t row = lc_row(lb, ty);
    return row != MS_NONE && (lb->facts->methods->access[row] & MS_METHOD_MUTATING) == 0;
}

void lc_register(Lb *lb, MsTy ty, MirTy mir) {
    for (uint32_t i = 0; i < lb->nclosers; i++) {
        if (lb->closers[i].ty == mir) {
            return;
        }
    }
    if (ms_ty_kind(&lb->c->tys, ty) == MS_K_CONTRACT) {
        MirTy result;
        LbCloser through = {.ty = mir, .row = MS_NONE, .func = MIR_NONE, .owned = true, .thunk = MIR_NONE, .result = MIR_NONE, .contract = ty};
        if (li_closer(lb, ty, &through.slot, &result)) {
            MIR_PUSH(lb->m, lb->closers, lb->nclosers, lb->cclosers, LbCloser, through);
        }
        return;
    }
    const uint32_t row = lc_row(lb, ty);
    if (row == MS_NONE) {
        return;
    }
    const LbCloser closer = {.ty = mir,
                             .row = row,
                             .func = MIR_NONE,
                             .contract = MS_TY_NONE,
                             .owned = (lb->facts->methods->access[row] & MS_METHOD_CONSUMING) != 0,
                             .thunk = MIR_NONE,
                             .result = MIR_NONE};
    MIR_PUSH(lb->m, lb->closers, lb->nclosers, lb->cclosers, LbCloser, closer);
    if (lb->facts->methods->nvars[row] != 0) { // registered first: the copy's own signature names this type again
        const uint32_t at = lb->nclosers - 1;
        const uint32_t func = lm_instance(lb, row, ty);
        lb->closers[at].func = func;
    }
}

/* The function that closes a `closer`'s type: its own method, or the copy for a generic type's instance. */
static uint32_t lc_func(const Lb *lb, const LbCloser *closer) {
    return closer->func != MIR_NONE ? closer->func : lb->method_func[closer->row];
}

static LbCloser *lc_find(Lb *lb, MirTy mir) {
    for (uint32_t i = 0; i < lb->nclosers; i++) {
        if (lb->closers[i].ty == mir) {
            return &lb->closers[i];
        }
    }
    return NULL;
}

bool lc_is_resource(Lb *lb, MirTy mir) {
    return lc_find(lb, mir) != NULL;
}

/* ---- helper functions ---- */

/* What the close of `closer` returns. */
static MirTy lc_ret(const Lb *lb, const LbCloser *closer) {
    if (closer->contract != MS_TY_NONE) {
        return lb->m->ifaces[mir_ty_data(lb->m, closer->ty)->id].methods[closer->slot].ret;
    }
    return lb->m->funcs[lc_func(lb, closer)].ret;
}

/* Whether the close of `closer` can be called: its function is lowered, or it goes through a vtable. */
static bool lc_callable(const Lb *lb, const LbCloser *closer) {
    return closer->contract != MS_TY_NONE || lc_func(lb, closer) != MIR_NONE;
}

static MirTy lc_result_ty(const Lb *lb, const LbCloser *closer) {
    const MirTy ret = lc_ret(lb, closer);
    if (ret == MIR_VOID || ret == MIR_NONE || mir_ty_data(lb->m, ret)->kind != MK_ALT ||
        lb->m->alts[mir_ty_data(lb->m, ret)->id].std != MSTD_RESULT) {
        return MIR_NONE;
    }
    return ret;
}

static void lc_drop(Lb *lb, MirBuilder *b, MirValue v) {
    if (mir_needs_drop(lb->m, mir_b_ty(b, v))) {
        (void)mir_b_emit(b, MOP_Drop, &v, 1, (MirImm){0}, MIR_NONE);
    }
}

/* Faults when `r`, the `Result` of a close, is an error; otherwise releases it. */
static void lc_fault(Lb *lb, MirBuilder *b, MirValue r) {
    const MirValue tag = mir_b_emit(b, MOP_AltTag, &r, 1, (MirImm){0}, MIR_INT);
    const MirValue failed = mir_b_icmp(b, MCC_EQ, tag, mir_b_iconst(b, LC_ERROR));
    const MirBlock bad = mir_b_new_block(b);
    const MirBlock good = mir_b_new_block(b);
    mir_b_br_if(b, failed, bad, NULL, 0, good, NULL, 0);
    mir_b_seal_block(b, bad);
    mir_b_seal_block(b, good);
    mir_b_switch_to(b, bad);
    lc_drop(lb, b, r);
    const char text[] = "a resource could not be closed: its close returned an error";
    const MirImm imm = {.tag = MI_STR, .a = mir_add_string(lb->m, text, sizeof text - 1)};
    const MirValue message = mir_b_emit(b, MOP_StrLit, NULL, 0, imm, MIR_STR);
    const MirTy param[1] = {MIR_STR};
    const uint32_t fault = mir_extern_get(lb->m, "msrt_fault_string", param, 1, MIR_VOID, true, MR_NONE);
    lb->m->externs[fault].noreturn = true;
    (void)mir_b_call_rt(b, fault, &message, 1);
    mir_b_unreachable(b);
    mir_b_switch_to(b, good);
}

/* The close of the value at `ptr`, in place: a close that takes the value takes it out of its place. */
static MirValue lc_close_at(Lb *lb, MirBuilder *b, const LbCloser *closer, MirValue ptr) {
    const MirImm ty = {.tag = MI_TY, .a = closer->ty};
    const MirValue value = mir_b_emit(b, closer->owned ? MOP_Take : MOP_Load, &ptr, 1, ty, closer->ty);
    if (closer->contract == MS_TY_NONE) {
        return mir_b_call(b, lc_func(lb, closer), &value, 1);
    }
    // An interface value closes through its vtable, then its box is freed without dropping the payload the close took.
    const uint32_t iface = mir_ty_data(lb->m, closer->ty)->id;
    const MirImm method = {.tag = MI_METHOD, .a = iface, .b = closer->slot};
    const MirValue result = mir_b_emit(b, MOP_CallMethod, &value, 1, method, lc_ret(lb, closer));
    li_free_box(b, value);
    return result;
}

/* The function that closes the value in a slot, dropping a result; `with_result` makes the one that
 * returns the result of a close that can fail. */
static uint32_t lc_thunk(Lb *lb, const LbCloser *closer, bool with_result) {
    const MirTy rty = lc_result_ty(lb, closer);
    const MirParam params[1] = {{MIR_PTR, MM_BORROW}};
    MirBuilder b;
    mir_b_init(&b, lb->m, lb_unique_name(lb, (MsStr){"close", 5}), params, 1, with_result ? rty : MIR_VOID);
    MirValue ptr;
    mir_b_params(&b, &ptr, 1);
    const MirValue r = lc_close_at(lb, &b, closer, ptr);
    if (with_result) {
        mir_b_ret(&b, r);
    } else {
        lc_drop(lb, &b, r);
        mir_b_ret(&b, mir_b_unit(&b));
    }
    if (!with_result) {
        b.f.has_slot_close = mir_needs_drop(lb->m, closer->ty) && !closer->owned;
        b.f.slot_close = closer->ty;
    }
    MirFunc f = {0};
    return mir_b_into_func(&b, &f) ? mir_add_func(lb->m, &f) : MIR_NONE;
}

/* The function that returns a failed close `e` as the function's own result; `pending` also takes the
 * value the function was already returning, which stays when it is an error (the first error wins). */
static uint32_t lc_exit(Lb *lb, MirTy rty, bool pending) {
    const MirTy ret = lb->b.f.ret;
    const bool borrowed = lb->b.f.ret_borrowed;
    for (uint32_t i = 0; i < lb->nexits; i++) {
        const LbCloseExit *x = &lb->exits[i];
        if (x->rty == rty && x->ret == ret && x->pending == pending && x->borrowed == borrowed) {
            return x->func;
        }
    }
    const MirParam params[2] = {{rty, MM_MOVE}, {ret, borrowed ? MM_BORROW : MM_MOVE}};
    MirBuilder b;
    mir_b_init(&b, lb->m, lb_unique_name(lb, (MsStr){"close_exit", 10}), params, pending ? 2 : 1, ret);
    b.f.ret_borrowed = borrowed && pending;
    MirValue given[2];
    mir_b_params(&b, given, pending ? 2 : 1);
    const MirValue e = given[0];
    const MirTyData *back = mir_ty_data(lb->m, ret);
    const bool back_result = back->kind == MK_ALT && lb->m->alts[back->id].std == MSTD_RESULT;
    if (pending) {
        const MirValue held = given[1];
        if (back_result) {
            const MirValue tag = mir_b_emit(&b, MOP_AltTag, &held, 1, (MirImm){0}, MIR_INT);
            const MirValue failed = mir_b_icmp(&b, MCC_EQ, tag, mir_b_iconst(&b, LC_ERROR));
            const MirBlock keep = mir_b_new_block(&b);
            const MirBlock replace = mir_b_new_block(&b);
            mir_b_br_if(&b, failed, keep, NULL, 0, replace, NULL, 0);
            mir_b_seal_block(&b, keep);
            mir_b_seal_block(&b, replace);
            mir_b_switch_to(&b, keep);
            lc_drop(lb, &b, e);
            mir_b_ret(&b, held);
            mir_b_switch_to(&b, replace);
        }
        if (!borrowed) {
            lc_drop(lb, &b, held);
        }
    }
    const MirAltDef *closed = &lb->m->alts[mir_ty_data(lb->m, rty)->id];
    const bool same_cause = back_result && !(borrowed && pending) &&
                            lb->m->alts[back->id].cases[LC_ERROR].fields[0].ty == closed->cases[LC_ERROR].fields[0].ty;
    if (same_cause) {
        const uint32_t alt = mir_ty_data(lb->m, rty)->id;
        const MirImm field = {.tag = MI_ALTFIELD, .a = alt, .b = LC_ERROR, .c = 0};
        const MirValue cause = mir_b_emit(&b, MOP_AltTake, &e, 1, field, closed->cases[LC_ERROR].fields[0].ty);
        const MirImm mask = {.tag = MI_ALTMASK, .a = alt, .b = LC_ERROR, .c = 1};
        (void)mir_b_emit(&b, MOP_AltRelease, &e, 1, mask, MIR_NONE);
        const MirImm error_case = {.tag = MI_CASE, .a = back->id, .b = LC_ERROR};
        mir_b_ret(&b, mir_b_emit(&b, MOP_AltNew, &cause, 1, error_case, ret));
    } else {
        lc_fault(lb, &b, e);
        lc_drop(lb, &b, e);
        mir_b_unreachable(&b);
    }
    MirFunc f = {0};
    if (!mir_b_into_func(&b, &f)) {
        return MIR_NONE;
    }
    const uint32_t id = mir_add_func(lb->m, &f);
    const LbCloseExit made = {.rty = rty, .ret = ret, .pending = pending, .borrowed = borrowed, .func = id};
    MIR_PUSH(lb->m, lb->exits, lb->nexits, lb->cexits, LbCloseExit, made);
    return id;
}

/* ---- locals ---- */

/* Whether the function being lowered holds nothing the elaborate pass does not own: a failed close
 * returns at once, so no cleanup the lowering still runs by hand may be pending. */
bool lc_exits_clean(const Lb *lb) {
    if (lb->closure || lb->nvars != 0 || lb->ntemps != 0) {
        return false;
    }
    for (uint32_t i = 0; i < lb_slots(&lb->cur); i++) {
        if (lb_slot_mutable(&lb->cur, i)) {
            return false; // a `var` parameter is put back by the return only
        }
    }
    return true;
}

/* Puts the owned resource `value` of local `binding` in a slot the elaborate pass closes at its scope's
 * end; false when the function cannot be left to that pass. */
static bool lc_slot_own(Lb *lb, uint32_t binding, MirValue value) {
    uint32_t fields[LB_MAX_MOVED];
    const uint32_t moved = ls_moved_fields(lb, binding, fields);
    if (moved != 0) {
        return ls_own(lb, binding, value, fields, moved);
    }
    const MirTy ty = mir_b_ty(&lb->b, value);
    LbCloser *closer = lc_find(lb, ty);
    if (closer == NULL || !lc_callable(lb, closer) || !lc_exits_clean(lb)) {
        return false;
    }
    const MirTy rty = lc_result_ty(lb, closer);
    if (lc_ret(lb, closer) != MIR_VOID && rty == MIR_NONE) {
        return false;
    }
    if (closer->thunk == MIR_NONE) {
        closer->thunk = lc_thunk(lb, closer, false);
        if (rty != MIR_NONE && closer->thunk != MIR_NONE) {
            closer->result = lc_thunk(lb, closer, true);
            lb->m->funcs[closer->thunk].has_slot_result = true;
            lb->m->funcs[closer->thunk].slot_result = closer->result;
        }
    }
    if (closer->thunk == MIR_NONE || (rty != MIR_NONE && closer->result == MIR_NONE)) {
        return false;
    }
    if (rty != MIR_NONE) {
        lb->b.f.has_close_exit = true;
        lb->b.f.close_exit[0] = lc_exit(lb, rty, false);
        lb->b.f.close_exit[1] = lc_exit(lb, rty, true);
    }
    const MirImm slot_ty = {.tag = MI_TY, .a = ty};
    const MirValue slot = mir_b_emit(&lb->b, MOP_Slot, NULL, 0, slot_ty, MIR_PTR);
    const MirValue put[2] = {slot, value};
    (void)mir_b_emit(&lb->b, mir_needs_drop(lb->m, ty) ? MOP_Put : MOP_Store, put, 2, (MirImm){0}, MIR_NONE);
    lscope_own(&lb->scopes, slot, closer->thunk + 2);
    (void)lc_push_slot(lb, (LbSlotLocal){.view = lb->view, .binding = binding, .slot = slot, .ty = ty});
    return true;
}

LbSlotLocal *lc_push_slot(Lb *lb, LbSlotLocal local) {
    MIR_PUSH(lb->m, lb->slots, lb->nslots, lb->cslots, LbSlotLocal, local);
    return &lb->slots[lb->nslots - 1];
}

uint32_t lc_field_thunk(Lb *lb, MirTy field) {
    LbCloser *closer = lc_find(lb, field);
    if (closer == NULL || !lc_callable(lb, closer)) {
        return MIR_NONE;
    }
    if (closer->thunk == MIR_NONE) {
        closer->thunk = lc_thunk(lb, closer, false);
    }
    return closer->thunk;
}

static bool lc_owned_local(const Lb *lb, uint32_t binding) {
    const uint8_t flags = lb->facts->bindings.flags[binding];
    return (flags & MS_BIND_RESOURCE) != 0 && (flags & MS_BIND_BORROWS) == 0;
}

bool lc_bind(Lb *lb, const MsStmt *s, uint32_t binding, LbVal value) {
    const bool plain = s->u.bind.pattern->kind == MS_P_NAME && value.owned && lc_owned_local(lb, binding);
    return plain && lc_slot_own(lb, binding, value.v);
}

bool lc_own_param(Lb *lb, uint32_t binding) {
    return lc_owned_local(lb, binding) && lc_slot_own(lb, binding, lb->value_of[binding]);
}

/* A read of the slot local `binding`. A `moved` read hands the value to a new owner, so the slot is no
 * longer the scope's to close on this path; a failed close then has nothing to stand in for, so the
 * close must succeed with a plain unit. */
bool lc_use(Lb *lb, uint32_t binding, MirValue *out, bool moved) {
    for (uint32_t i = 0; i < lb->nslots; i++) {
        const LbSlotLocal *local = &lb->slots[i];
        if (local->view != lb->view || local->binding != binding) {
            continue;
        }
        if (moved) {
            const LbCloser *closer = lc_find(lb, local->ty);
            const MirTy rty = closer == NULL ? MIR_NONE : lc_result_ty(lb, closer);
            if (rty != MIR_NONE && lb->m->alts[mir_ty_data(lb->m, rty)->id].cases[LC_OK].fields[0].ty != MIR_VOID) {
                return false;
            }
        }
        if (moved && mir_needs_drop(lb->m, local->ty)) { // the value leaves its slot, which is not the scope's to close any more
            *out = mir_b_emit(&lb->b, MOP_Take, &local->slot, 1, (MirImm){.tag = MI_TY, .a = local->ty}, local->ty);
        } else {
            *out = lb_load(lb, local->slot, local->ty);
        }
        if (moved) {
            lscope_disown(&lb->scopes, local->slot);
        }
        return true;
    }
    return false;
}

bool lc_slot_of(const Lb *lb, uint32_t binding, MirValue *slot) {
    for (uint32_t i = 0; i < lb->nslots; i++) {
        if (lb->slots[i].view == lb->view && lb->slots[i].binding == binding) {
            *slot = lb->slots[i].slot;
            return true;
        }
    }
    return false;
}

bool lc_is_slot_local(const Lb *lb, uint32_t binding) {
    for (uint32_t i = 0; i < lb->nslots; i++) {
        if (lb->slots[i].view == lb->view && lb->slots[i].binding == binding) {
            return true;
        }
    }
    return false;
}

bool lc_is_closer_row(Lb *lb, uint32_t row) {
    for (uint32_t i = 0; i < lb->nclosers; i++) {
        if (lb->closers[i].row == row) {
            return true;
        }
    }
    return false;
}

/* A resource that is dropped instead of closed is left to the Rust lowering: fails the function
 * being lowered when it holds such a drop or an owner of one. */
void lc_check(Lb *lb) {
    if (lb->nclosers == 0) {
        return;
    }
    const MirFunc *f = &lb->b.f;
    for (uint32_t k = 0; k < f->nblocks; k++) {
        for (uint32_t i = 0; i < f->blocks[k].ninsts; i++) {
            const MirInst *inst = &f->blocks[k].insts[i];
            const bool owns = inst->op == MOP_ScopeOwn && inst->imm.b == 0;
            if ((inst->op == MOP_Drop || owns) && lc_find(lb, mir_b_ty(&lb->b, inst->args[0])) != NULL) {
                (void)LB_UNSUPPORTED(lb);
                return;
            }
        }
    }
}
