/* frames: which values may live in their maker's frame. Port of frames.rs, with a flag per value
 * in place of a hash set. */
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_pass.h"

/* Clears the flag of every value the terminator of `b` uses beyond a plain operand: a returned
 * value, a branch condition or scrutinee, and every branch argument. */
static void fr_term_uses(const MirBlockData *b, bool *framed) {
    const MirTerm *t = &b->term;
    if ((t->kind == MT_RET || t->kind == MT_CONDBR || t->kind == MT_SWITCH) && t->value != MIR_NONE) {
        framed[t->value] = false;
    }
    const uint32_t n = mir_term_ntargets(t);
    for (uint32_t k = 0; k < n; k++) {
        const MirTarget *target = mir_term_target_const(t, k);
        for (uint32_t a = 0; a < target->nargs; a++) {
            framed[target->args[a]] = false;
        }
    }
}

static bool *fr_flags(MsArena *arena, const MirFunc *f) {
    bool *framed = MS_NEW_N(arena, bool, f->nvalues ? f->nvalues : 1);
    memset(framed, 0, f->nvalues ? f->nvalues : 1);
    return framed;
}

/* The `iface.borrow` results used only by drops and by calls that do not return a view of them. */
bool *mir_framed_iface_borrows(MsArena *arena, const MirModule *m, const MirFunc *f) {
    bool *framed = fr_flags(arena, f);
    bool any = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t k = 0; k < f->blocks[bi].ninsts; k++) {
            const MirInst *in = &f->blocks[bi].insts[k];
            if (in->op == MOP_IfaceBorrow && in->res != MIR_NONE) {
                framed[in->res] = true;
                any = true;
            }
        }
    }
    if (!any) {
        return NULL;
    }
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        for (uint32_t k = 0; k < b->ninsts; k++) {
            const MirInst *in = &b->insts[k];
            const bool plain = in->op == MOP_Drop ||
                               ((in->op == MOP_Call || in->op == MOP_CallMethod) &&
                                !mir_result_views(m, f, in));
            for (uint32_t a = 0; !plain && a < in->nargs; a++) {
                framed[in->args[a]] = false;
            }
        }
        fr_term_uses(b, framed);
    }
    return framed;
}

/* Whether argument `k` of call `in` is borrowed. */
static bool fr_borrows(const MirModule *m, const MirInst *in, uint32_t k) {
    if (in->op == MOP_Call && in->imm.tag == MI_FUNC) {
        const MirFunc *g = &m->funcs[in->imm.a];
        return k < g->nparams && g->params[k].mode == MM_BORROW;
    }
    if (in->op == MOP_CallRt && in->imm.tag == MI_EXT) {
        const MirExtern *e = &m->externs[in->imm.a];
        return k < e->nparams && e->params[k].mode == MM_BORROW;
    }
    return in->op == MOP_CallInd && k == 0;
}

/* The closure objects (of closures that close nothing) that only drops and borrowing calls use. */
bool *mir_framed_closure_objects(MsArena *arena, const MirModule *m, const MirFunc *f) {
    bool *framed = fr_flags(arena, f);
    bool any = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t k = 0; k < f->blocks[bi].ninsts; k++) {
            const MirInst *in = &f->blocks[bi].insts[k];
            if (in->op == MOP_ClosureNew && in->imm.tag == MI_FUNC && in->res != MIR_NONE &&
                m->funcs[in->imm.a].ncapture_closers == 0) {
                framed[in->res] = true;
                any = true;
            }
        }
    }
    if (!any) {
        return NULL;
    }
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        for (uint32_t k = 0; k < b->ninsts; k++) {
            const MirInst *in = &b->insts[k];
            const bool plain_call = (in->op == MOP_Call || in->op == MOP_CallRt || in->op == MOP_CallInd) &&
                                    !mir_result_views(m, f, in);
            for (uint32_t a = 0; a < in->nargs; a++) {
                if (in->op != MOP_Drop && !(plain_call && fr_borrows(m, in, a))) {
                    framed[in->args[a]] = false;
                }
            }
        }
        fr_term_uses(b, framed);
    }
    return framed;
}
