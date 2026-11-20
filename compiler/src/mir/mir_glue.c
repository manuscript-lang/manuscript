/* glue: the helper functions every backend would otherwise write for itself. Port of
 * crates/ms-mir/src/glue.rs and the descriptor plan of statics.rs.
 *
 * For each type whose drop is a walk of its fields (a record, an alternative, an optional, a list
 * or bytes, a map or set, an interface) the pass makes a drop function, and a clone function for
 * the types that are cloned; for each type a descriptor points at, a slot drop and a slot copy;
 * for each interface payload, a block drop and a block clone; and for each closure object, drop
 * and clone entries. Backends call these functions instead of writing a body of their own, so
 * they cannot disagree on which cases and fields a drop releases. Names carry the module's
 * function count (`ms.glue.mir.<n>.<kind>`), so the same module always gets the same names.
 *
 * Block and extern creation order matches the Rust pass exactly: it decides the numbering the
 * text form prints. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_builder.h"
#include "ms/mir_data.h"
#include "ms/mir_layout.h"
#include "ms/mir_pass.h"

enum {
    GL_CLOSURE_CODE_OFFSET = 16,
    GL_DEEP_DROP_HEADROOM = 192 << 10,
    GL_MAX_CHAIN_FIELD = 32 /* a mask covers 32 fields */
};

/* ---- the table of what was made ---- */

uint32_t mir_glue_find(const MirGlue *g, MirGlueKind kind, MirTy ty, uint32_t a, uint32_t b) {
    for (uint32_t i = 0; i < g->n; i++) {
        const MirGlueEntry *e = &g->v[i];
        if (e->kind == kind && e->ty == ty && e->a == a && e->b == b) {
            return e->func;
        }
    }
    return MIR_NONE;
}

static void gl_record(MirModule *m, MirGlue *g, MirGlueKind kind, MirTy ty, uint32_t a, uint32_t b,
                      uint32_t func) {
    const MirGlueEntry e = {.kind = (uint8_t)kind, .a = a, .b = b, .ty = ty, .func = func};
    MIR_PUSH(m, g->v, g->n, g->cap, MirGlueEntry, e);
}

static uint32_t gl_count(const MirGlue *g, MirGlueKind kind) {
    uint32_t n = 0;
    for (uint32_t i = 0; i < g->n; i++) {
        n += g->v[i].kind == kind;
    }
    return n;
}

/* ---- sets of types (sorted vectors in a scratch arena) ---- */

typedef struct GlVec {
    uint32_t *v;
    uint32_t n, cap;
} GlVec;

static void gl_push(MsArena *a, GlVec *vec, uint32_t x) {
    if (vec->n == vec->cap) {
        uint32_t cap = vec->cap ? vec->cap * 2 : 16;
        uint32_t *grown = MS_NEW_N(a, uint32_t, cap);
        if (vec->n > 0) {
            memcpy(grown, vec->v, sizeof(uint32_t) * vec->n);
        }
        vec->v = grown;
        vec->cap = cap;
    }
    vec->v[vec->n++] = x;
}

static int gl_cmp(const void *x, const void *y) {
    const uint32_t a = *(const uint32_t *)x, b = *(const uint32_t *)y;
    return a < b ? -1 : a > b;
}

static void gl_sort_unique(GlVec *vec) {
    if (vec->n < 2) {
        return;
    }
    qsort(vec->v, vec->n, sizeof(uint32_t), gl_cmp);
    uint32_t out = 1;
    for (uint32_t i = 1; i < vec->n; i++) {
        if (vec->v[i] != vec->v[out - 1]) {
            vec->v[out++] = vec->v[i];
        }
    }
    vec->n = out;
}

/* ---- type queries ---- */

static bool gl_is_map_or_set(const MirModule *m, const MirTyData *d) {
    (void)m;
    return d->kind == MK_OBJ && d->obj_class == MIR_OBJ_COLLECTION;
}

static bool gl_is_opt(const MirModule *m, MirTy ty, MirTy *inner) {
    const MirTyData *d = mir_ty_data(m, ty);
    if (d->kind != MK_OPT) {
        return false;
    }
    *inner = d->elem;
    return true;
}

/* The element of a list; `bytes` too when `seq`. MIR_NONE otherwise. */
static MirTy gl_elem(const MirModule *m, MirTy ty, bool seq) {
    const MirTyData *d = mir_ty_data(m, ty);
    if (d->kind == MK_LIST) {
        return d->elem;
    }
    return seq && d->kind == MK_BYTES ? MIR_UINT8 : MIR_NONE;
}

/* Pushes the types whose values a drop of `ty` drops. */
static void gl_children(MsArena *a, GlVec *out, const MirModule *m, MirTy ty) {
    const MirTyData *d = mir_ty_data(m, ty);
    switch ((MirTyKind)d->kind) {
    case MK_OPT:
    case MK_LIST:
        gl_push(a, out, d->elem);
        return;
    case MK_OBJ:
        if (gl_is_map_or_set(m, d)) {
            for (uint32_t i = 0; i < d->nargs; i++) {
                gl_push(a, out, d->args[i]);
            }
        }
        return;
    case MK_TYPE: {
        const MirTypeDef *def = &m->type_defs[d->id];
        for (uint32_t i = 0; i < def->nfields; i++) {
            gl_push(a, out, def->fields[i].ty);
        }
        return;
    }
    case MK_ALT: {
        const MirAltDef *def = &m->alts[d->id];
        for (uint32_t c = 0; c < def->ncases; c++) {
            if (mir_owns(def->borrowed, c)) {
                continue;
            }
            for (uint32_t k = 0; k < def->cases[c].nfields; k++) {
                gl_push(a, out, def->cases[c].fields[k].ty);
            }
        }
        return;
    }
    default:
        return;
    }
}

/* Whether dropping `ty` reaches `ty` again through its fields, cases, optional payloads and
 * collection elements: the drop of such data bounds its own nesting. */
static bool gl_recurses(const MirModule *m, MirTy ty) {
    MsArena scratch = {0};
    GlVec todo = {0}, seen = {0};
    gl_children(&scratch, &todo, m, ty);
    bool found = false;
    while (todo.n > 0 && !found) {
        const MirTy t = todo.v[--todo.n];
        if (t == ty) {
            found = true;
            break;
        }
        bool known = false;
        for (uint32_t i = 0; i < seen.n && !known; i++) {
            known = seen.v[i] == t;
        }
        if (!known) {
            gl_push(&scratch, &seen, t);
            gl_children(&scratch, &todo, m, t);
        }
    }
    ms_arena_free(&scratch);
    return found;
}

/* `seed` and the types dropped (or cloned) when a value of one of them is, as a sorted set. */
static void gl_close(MsArena *a, GlVec *out, const MirModule *m, const GlVec *seed) {
    GlVec todo = {0}, seen = {0};
    for (uint32_t i = 0; i < seed->n; i++) {
        gl_push(a, &todo, seed->v[i]);
    }
    const MirTy nty = m->types.len;
    bool *mark = MS_NEW_N(a, bool, nty ? nty : 1);
    memset(mark, 0, nty ? nty : 1);
    while (todo.n > 0) {
        const MirTy t = mir_ty_unscoped(todo.v[--todo.n]);
        if (t < nty && !mark[t]) {
            mark[t] = true;
            gl_push(a, &seen, t);
            gl_children(a, &todo, m, t);
        }
    }
    for (uint32_t i = 0; i < seen.n; i++) {
        gl_push(a, out, seen.v[i]);
    }
    gl_sort_unique(out);
}

static uint32_t gl_mem_size(const MirModule *m, MirTy ty) {
    MirLayouts lay;
    mir_layouts_init(&lay, m);
    const uint32_t size = mir_type_mem(&lay, ty).size;
    mir_layouts_free(&lay);
    return size;
}

/* ---- builder helpers ---- */

static MirValue gl_val(MirBuilder *b, MirOp op, const MirValue *args, uint32_t n, MirImm imm,
                       MirTy ty) {
    return mir_b_emit(b, op, args, n, imm, ty);
}

static MirImm gl_imm_ty(MirTy ty) { return (MirImm){.tag = MI_TY, .a = ty}; }
static MirImm gl_imm_func(uint32_t f) { return (MirImm){.tag = MI_FUNC, .a = f}; }

static MirValue gl_ptr_at(MirBuilder *b, MirValue base, int64_t off) {
    if (off == 0) {
        return base;
    }
    const MirValue args[2] = {base, mir_b_iconst(b, off)};
    return gl_val(b, MOP_PtrAdd, args, 2, (MirImm){0}, MIR_PTR);
}

static MirValue gl_clone(MirBuilder *b, MirValue v) {
    return gl_val(b, MOP_Clone, &v, 1, (MirImm){0}, mir_b_ty(b, v));
}

static MirValue gl_take(MirBuilder *b, MirValue at, MirTy ty) {
    return gl_val(b, MOP_Take, &at, 1, gl_imm_ty(ty), ty);
}

static MirValue gl_load(MirBuilder *b, MirValue at, MirTy ty) {
    return gl_val(b, MOP_Load, &at, 1, gl_imm_ty(ty), ty);
}

static void gl_put(MirBuilder *b, MirValue to, MirValue v) {
    const MirValue args[2] = {to, v};
    (void)gl_val(b, MOP_Put, args, 2, (MirImm){0}, MIR_NONE);
}

static MirValue gl_slot(MirBuilder *b, MirTy ty) {
    return gl_val(b, MOP_Slot, NULL, 0, gl_imm_ty(ty), MIR_PTR);
}

static void gl_drop(MirBuilder *b, MirValue v) {
    (void)gl_val(b, MOP_Drop, &v, 1, (MirImm){0}, MIR_NONE);
}

static void gl_free(MirBuilder *b, MirValue v) {
    (void)gl_val(b, MOP_Free, &v, 1, (MirImm){0}, MIR_NONE);
}

static MirValue gl_alt_tag(MirBuilder *b, MirValue obj) {
    return gl_val(b, MOP_AltTag, &obj, 1, (MirImm){0}, MIR_INT);
}

static MirValue gl_alt_get(MirBuilder *b, uint32_t alt, uint32_t c, uint32_t k, MirValue obj) {
    const MirTy ty = b->m->alts[alt].cases[c].fields[k].ty;
    return gl_val(b, MOP_AltGet, &obj, 1, (MirImm){.tag = MI_ALTFIELD, .a = alt, .b = c, .c = k},
                  ty);
}

static void gl_alt_release(MirBuilder *b, uint32_t alt, uint32_t c, uint32_t mask, MirValue obj) {
    (void)gl_val(b, MOP_AltRelease, &obj, 1, (MirImm){.tag = MI_ALTMASK, .a = alt, .b = c, .c = mask},
                 MIR_NONE);
}

static MirValue gl_alt_new(MirBuilder *b, uint32_t alt, uint32_t c, const MirValue *fields,
                           uint32_t n) {
    const MirTy ty = mir_ty_alt(b->m, alt);
    return gl_val(b, MOP_AltNew, fields, n, (MirImm){.tag = MI_CASE, .a = alt, .b = c}, ty);
}

static MirValue gl_opt_is_some(MirBuilder *b, MirValue o) {
    return gl_val(b, MOP_OptIsSome, &o, 1, (MirImm){0}, MIR_BOOL);
}

static MirValue gl_opt_payload(MirBuilder *b, MirOp op, MirValue o) {
    MirTy inner = MIR_NONE;
    (void)gl_is_opt(b->m, mir_b_ty(b, o), &inner);
    return gl_val(b, op, &o, 1, (MirImm){0}, inner);
}

static MirValue gl_list_len(MirBuilder *b, MirValue l) {
    return gl_val(b, MOP_ListLen, &l, 1, (MirImm){0}, MIR_INT);
}

static void gl_switch_to(MirBuilder *b, MirBlock blk) { mir_b_switch_to(b, blk); }

static uint32_t gl_finish(MirBuilder *b) {
    uint32_t id = MIR_NONE;
    if (!mir_b_finish(b, &id)) {
        return MIR_NONE;
    }
    return id;
}

static MsSym gl_func_name(MirModule *m, uint32_t n, const char *suffix) {
    char buf[96];
    const int len = snprintf(buf, sizeof buf, "ms.glue.mir.%u.%s", n, suffix);
    return mir_name(m, buf, (size_t)len);
}

/* The extern with this symbol and signature, declared (borrowed parameters) if the module has
 * none. */
static uint32_t gl_extern(MirModule *m, const char *name, const MirTy *params, uint32_t nparams,
                          MirTy ret, bool fresh) {
    const MsSym sym = mir_name(m, name, strlen(name));
    for (uint32_t i = 0; i < m->nexterns; i++) {
        const MirExtern *e = &m->externs[i];
        if (e->name != sym || e->ret != ret || e->nparams != nparams) {
            continue;
        }
        bool same = true;
        for (uint32_t k = 0; k < nparams && same; k++) {
            same = e->params[k].ty == params[k];
        }
        if (same) {
            return i;
        }
    }
    MirExtern e = {.name = sym, .params = MS_NEW_N(&m->arena, MirParam, nparams ? nparams : 1),
                   .nparams = nparams, .ret = ret, .fresh = fresh};
    for (uint32_t i = 0; i < nparams; i++) {
        e.params[i] = (MirParam){params[i], MM_BORROW};
    }
    return mir_add_extern(m, &e);
}

static MirValue gl_call_rt(MirBuilder *b, uint32_t ext, const MirValue *args, uint32_t n) {
    return mir_b_call_rt(b, ext, args, n);
}

/* ---- what the program asks for ---- */

/* The types a function of the program drops and the types it clones, with what dropping or
 * cloning those drops or clones in turn. A type missing here only keeps the backend's own
 * function. */
static void gl_wanted(MsArena *a, const MirModule *m, GlVec *drops, GlVec *clones) {
    GlVec d = {0}, c = {0};
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            const MirBlockData *blk = &f->blocks[bi];
            for (uint32_t ii = 0; ii < blk->ninsts; ii++) {
                const MirInst *inst = &blk->insts[ii];
                const MirTy t0 = inst->nargs > 0 ? f->values[inst->args[0]] : MIR_NONE;
                switch ((MirOp)inst->op) {
                case MOP_Drop:
                    if (t0 != MIR_NONE) {
                        gl_push(a, &d, t0);
                    }
                    break;
                case MOP_DropIf:
                    if (inst->nargs > 1) {
                        gl_push(a, &d, f->values[inst->args[1]]);
                    }
                    break;
                case MOP_Clone:
                    if (t0 != MIR_NONE) {
                        gl_push(a, &c, t0);
                    }
                    break;
                case MOP_OptUnwrap: {
                    MirTy inner = MIR_NONE;
                    if (t0 != MIR_NONE && gl_is_opt(m, t0, &inner)) {
                        gl_push(a, &c, inner);
                    }
                    break;
                }
                case MOP_AltOwn:
                    if (inst->res != MIR_NONE) {
                        gl_push(a, &c, f->values[inst->res]);
                    }
                    break;
                case MOP_AltRelease:
                case MOP_AltUnbox:
                case MOP_AltTake:
                case MOP_TypeRelease:
                case MOP_OptUnbox:
                    if (t0 != MIR_NONE) {
                        gl_push(a, &d, t0);
                    }
                    break;
                case MOP_ListSet:
                case MOP_ListSetNn:
                case MOP_ListSetU:
                case MOP_ListDropLast:
                case MOP_ListRelease:
                    if (t0 != MIR_NONE && gl_elem(m, t0, true) != MIR_NONE) {
                        gl_push(a, &d, gl_elem(m, t0, true));
                    }
                    break;
                case MOP_TypeDesc:
                    if (inst->imm.tag == MI_TY) {
                        gl_push(a, &d, inst->imm.a);
                        gl_push(a, &c, inst->imm.a);
                    }
                    break;
                default:
                    break;
                }
            }
        }
    }
    gl_close(a, drops, m, &d);
    gl_close(a, clones, m, &c);
}

/* The types whose descriptors point at slot drop and copy functions, and the data types of the
 * interface vtables (whose payload blocks get drop and clone functions): sorted sets. */
static void gl_addr_types(MsArena *a, const MirModule *m, GlVec *slots, GlVec *blocks) {
    MirLayouts lay;
    mir_layouts_init(&lay, m);
    GlVec keys = {0}, seen = {0};
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
                const MirInst *inst = &f->blocks[bi].insts[ii];
                if (inst->op == MOP_TypeDesc && inst->imm.tag == MI_TY) {
                    gl_push(a, &keys, inst->imm.a);
                }
            }
        }
    }
    while (keys.n > 0) {
        const MirTy key = keys.v[--keys.n];
        bool known = false;
        for (uint32_t i = 0; i < seen.n && !known; i++) {
            known = seen.v[i] == key;
        }
        if (known) {
            continue;
        }
        gl_push(a, &seen, key);
        MirDescPlan plan;
        mir_desc_plan(m, &lay, key, &plan);
        for (uint32_t i = 0; i < 2; i++) {
            if (plan.inner[i] != MIR_NONE) {
                gl_push(a, &keys, plan.inner[i]);
            }
        }
        if (plan.slot_glue != MIR_NONE) {
            gl_push(a, slots, plan.slot_glue);
        }
    }
    for (uint32_t i = 0; i < m->nvtables; i++) {
        gl_push(a, blocks, mir_ty_unscoped(m->vtables[i].data_ty));
    }
    gl_sort_unique(slots);
    gl_sort_unique(blocks);
    mir_layouts_free(&lay);
}

/* ---- slot and block functions ---- */

static const MirParam gl_ptr_param = {MIR_PTR, MM_BORROW};

/* `fn(slot)`: drops the value stored at `slot`. */
static uint32_t gl_make_slot_drop(MirModule *m, MirTy ty) {
    MirBuilder b;
    mir_b_init(&b, m, gl_func_name(m, m->nfuncs, "slot_drop"), &gl_ptr_param, 1, MIR_VOID);
    MirValue p;
    mir_b_params(&b, &p, 1);
    gl_drop(&b, gl_take(&b, p, ty));
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

/* `fn(src, dst)`: clones the value at `src` into uninitialised `dst`. */
static uint32_t gl_make_slot_copy(MirModule *m, MirTy ty) {
    const MirParam ptrs[2] = {gl_ptr_param, gl_ptr_param};
    MirBuilder b;
    mir_b_init(&b, m, gl_func_name(m, m->nfuncs, "slot_copy"), ptrs, 2, MIR_VOID);
    MirValue p[2];
    mir_b_params(&b, p, 2);
    const MirValue c = gl_clone(&b, gl_load(&b, p[0], ty));
    gl_put(&b, p[1], c);
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

/* `fn(block)`: drops the `ty` value the heap block holds and frees the block. */
static uint32_t gl_make_block_drop(MirModule *m, MirTy ty) {
    const bool needs = mir_needs_drop(m, ty);
    MirBuilder b;
    mir_b_init(&b, m, gl_func_name(m, m->nfuncs, "block_drop"), &gl_ptr_param, 1, MIR_VOID);
    MirValue p;
    mir_b_params(&b, &p, 1);
    if (needs) {
        gl_drop(&b, gl_take(&b, p, ty));
    }
    gl_free(&b, p);
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

/* `fn(block) -> block`: a new heap block holding a clone of the `ty` value in `block`. */
static uint32_t gl_make_block_clone(MirModule *m, MirTy ty) {
    const int64_t size = gl_mem_size(m, ty);
    const MirTy int_param = MIR_INT;
    const uint32_t alloc = gl_extern(m, "msrt_alloc", &int_param, 1, MIR_PTR, true);
    MirBuilder b;
    mir_b_init(&b, m, gl_func_name(m, m->nfuncs, "block_clone"), &gl_ptr_param, 1, MIR_PTR);
    MirValue p;
    mir_b_params(&b, &p, 1);
    const MirValue c = gl_clone(&b, gl_load(&b, p, ty));
    const MirValue n = mir_b_iconst(&b, size > 1 ? size : 1);
    const MirValue blk = gl_call_rt(&b, alloc, &n, 1);
    gl_put(&b, blk, c);
    mir_b_ret(&b, blk);
    return gl_finish(&b);
}

/* ---- drop and clone of one type ---- */

/* What one kind's drop or clone function is built from. */
typedef struct GlCx {
    MirModule *m;
    MirGlue *g;
    MsSym name;
    MirParam param;
    MirTy ty;
    const MirTyData *d;
} GlCx;

typedef struct GlTail {
    bool some;
    uint32_t field;
    bool optional;
    int64_t offset; /* clone: where the next block's pointer lives in this block */
} GlTail;

/* `fn(obj)` that drops the captures of `c` and frees the object; one in a stack frame frees
 * nothing. See make_closure_drop in the Rust pass for the cleanup it registers around a
 * capture's closer. */
static bool gl_closer_of(const MirFunc *cf, uint32_t capture, uint32_t *close) {
    for (uint32_t i = 0; i < cf->ncapture_closers; i++) {
        if (cf->capture_closers[i].capture == capture) {
            *close = cf->capture_closers[i].func;
            return true;
        }
    }
    return false;
}

/* Whether capture `k` of closure function `cf` leaves a value in its slot for a drop: false when
 * a closer that takes the value ran. */
static bool gl_capture_dropped(const MirModule *m, const MirFunc *cf, uint32_t k, MirTy ty) {
    uint32_t close = 0;
    if (!mir_needs_drop(m, ty)) {
        return false;
    }
    return !gl_closer_of(cf, k, &close) || m->funcs[close].has_slot_close;
}

typedef struct GlCaptures {
    MirLayouts lay;
    MirClosureLayout layout;
} GlCaptures;

static void gl_captures(GlCaptures *cc, const MirModule *m, uint32_t c) {
    mir_layouts_init(&cc->lay, m);
    cc->layout = mir_closure_layout(&cc->lay, &m->funcs[c]);
}

/* `fn(obj)` registered while the close of capture `k` runs: when a guarded task unwinds out of
 * it, drops capture `k` (without closing it again) and the later captures, and frees the object. */
static uint32_t gl_make_closure_drop_from(MirModule *m, MirGlue *g, uint32_t c, uint32_t k) {
    GlCaptures cc;
    gl_captures(&cc, m, c);
    const MirFunc *cf = &m->funcs[c];
    const uint32_t ncaps = cc.layout.ncaptures;
    MirTy *tys = MS_NEW_N(&m->arena, MirTy, ncaps ? ncaps : 1);
    int64_t *offs = MS_NEW_N(&m->arena, int64_t, ncaps ? ncaps : 1);
    bool *needs = MS_NEW_N(&m->arena, bool, ncaps ? ncaps : 1);
    for (uint32_t j = 0; j < ncaps; j++) {
        tys[j] = cc.layout.captures[j].ty;
        offs[j] = cc.layout.captures[j].offset;
        needs[j] = gl_capture_dropped(m, cf, j, tys[j]);
    }
    mir_layouts_free(&cc.lay);
    const uint32_t on_ext = gl_extern(m, "msrt_unwind_drops", NULL, 0, MIR_BOOL, false);
    MirBuilder b;
    mir_b_init(&b, m, gl_func_name(m, m->nfuncs, "closure_drop_from"), &gl_ptr_param, 1, MIR_VOID);
    mir_b_func(&b)->unwind_only = true;
    MirValue obj;
    mir_b_params(&b, &obj, 1);
    const MirBlock body = mir_b_new_block(&b), done = mir_b_new_block(&b);
    const MirValue on = gl_call_rt(&b, on_ext, NULL, 0);
    mir_b_br_if(&b, on, body, NULL, 0, done, NULL, 0);
    gl_switch_to(&b, body);
    for (uint32_t j = 0; j < ncaps; j++) {
        if (j >= k && needs[j]) {
            const MirValue at = gl_ptr_at(&b, obj, offs[j]);
            gl_drop(&b, gl_take(&b, at, tys[j]));
        }
    }
    gl_free(&b, obj);
    mir_b_br(&b, done, NULL, 0);
    gl_switch_to(&b, done);
    mir_b_ret(&b, MIR_NONE);
    const uint32_t id = gl_finish(&b);
    gl_record(m, g, MG_CLOSURE_DROP_FROM, MIR_VOID, c, k, id);
    return id;
}

/* `fn(obj)` that drops the captures of a closure object and frees it (a framed object lives in
 * a stack slot and is not freed). A capture with a closer is closed in place first, with a
 * cleanup registered that releases the rest of the object if the close faults. */
static uint32_t gl_make_closure_drop(MirModule *m, MirGlue *g, uint32_t c, bool framed) {
    GlCaptures cc;
    gl_captures(&cc, m, c);
    const MirFunc *cf = &m->funcs[c];
    const uint32_t ncaps = cc.layout.ncaptures;
    MirTy *tys = MS_NEW_N(&m->arena, MirTy, ncaps ? ncaps : 1);
    int64_t *offs = MS_NEW_N(&m->arena, int64_t, ncaps ? ncaps : 1);
    bool *needs = MS_NEW_N(&m->arena, bool, ncaps ? ncaps : 1);
    uint32_t *tails = MS_NEW_N(&m->arena, uint32_t, ncaps ? ncaps : 1);
    uint32_t *closes = MS_NEW_N(&m->arena, uint32_t, ncaps ? ncaps : 1);
    for (uint32_t k = 0; k < ncaps; k++) {
        tys[k] = cc.layout.captures[k].ty;
        offs[k] = cc.layout.captures[k].offset;
        needs[k] = gl_capture_dropped(m, cf, k, tys[k]);
    }
    mir_layouts_free(&cc.lay);
    for (uint32_t k = 0; k < ncaps; k++) {
        tails[k] = MIR_NONE;
        if (gl_closer_of(cf, k, &closes[k])) {
            tails[k] = gl_make_closure_drop_from(m, g, c, k);
        }
    }
    const MirTy int_param = MIR_INT;
    const uint32_t discard = gl_extern(m, "msrt_cleanup_discard", &int_param, 1, MIR_VOID, false);
    const uint32_t shield_in = gl_extern(m, "msrt_shield_enter", NULL, 0, MIR_VOID, false);
    const uint32_t shield_out = gl_extern(m, "msrt_shield_exit", NULL, 0, MIR_VOID, false);
    MirBuilder b;
    mir_b_init(&b, m, gl_func_name(m, m->nfuncs, "closure_drop"), &gl_ptr_param, 1, MIR_VOID);
    MirValue obj;
    mir_b_params(&b, &obj, 1);
    for (uint32_t k = 0; k < ncaps; k++) {
        const MirValue at = gl_ptr_at(&b, obj, offs[k]);
        if (tails[k] != MIR_NONE) {
            const MirValue h = gl_val(&b, MOP_CleanupPush, &obj, 1, gl_imm_func(tails[k]), MIR_INT);
            /* Like every implicit close, the close of a capture is not interrupted by a cancel. */
            (void)gl_call_rt(&b, shield_in, NULL, 0);
            (void)gl_val(&b, MOP_Call, &at, 1, gl_imm_func(closes[k]), MIR_NONE);
            (void)gl_call_rt(&b, shield_out, NULL, 0);
            (void)gl_call_rt(&b, discard, &h, 1);
        }
        if (needs[k]) {
            gl_drop(&b, gl_take(&b, at, tys[k]));
        }
    }
    if (!framed) {
        gl_free(&b, obj);
    }
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

/* `fn(obj) -> obj`: a new closure object with the same clone and code entries, the heap drop
 * entry, and a clone of every capture. */
static uint32_t gl_make_closure_clone(MirModule *m, MirGlue *g, uint32_t c) {
    GlCaptures cc;
    gl_captures(&cc, m, c);
    const uint32_t ncaps = cc.layout.ncaptures;
    const int64_t size = cc.layout.size;
    MirTy *tys = MS_NEW_N(&m->arena, MirTy, ncaps ? ncaps : 1);
    int64_t *offs = MS_NEW_N(&m->arena, int64_t, ncaps ? ncaps : 1);
    for (uint32_t k = 0; k < ncaps; k++) {
        tys[k] = cc.layout.captures[k].ty;
        offs[k] = cc.layout.captures[k].offset;
    }
    mir_layouts_free(&cc.lay);
    const uint32_t drop = mir_glue_find(g, MG_CLOSURE_DROP, MIR_VOID, c, 0);
    const MirTy int_param = MIR_INT;
    const uint32_t alloc = gl_extern(m, "msrt_alloc", &int_param, 1, MIR_PTR, true);
    MirBuilder b;
    mir_b_init(&b, m, gl_func_name(m, m->nfuncs, "closure_clone"), &gl_ptr_param, 1, MIR_PTR);
    MirValue src;
    mir_b_params(&b, &src, 1);
    MirValue *copies = MS_NEW_N(&m->arena, MirValue, ncaps ? ncaps : 1);
    for (uint32_t k = 0; k < ncaps; k++) {
        const MirValue at = gl_ptr_at(&b, src, offs[k]);
        copies[k] = gl_clone(&b, gl_load(&b, at, tys[k]));
    }
    const MirValue n = mir_b_iconst(&b, size);
    const MirValue obj = gl_call_rt(&b, alloc, &n, 1);
    /* The clone and code entries carry over; the drop entry is the heap one even when `src`
     * lives in a frame. */
    const int64_t words[2] = {0, GL_CLOSURE_CODE_OFFSET};
    for (uint32_t i = 0; i < 2; i++) {
        const MirValue from = gl_ptr_at(&b, src, words[i]);
        const MirValue word = gl_load(&b, from, MIR_PTR);
        gl_put(&b, gl_ptr_at(&b, obj, words[i]), word);
    }
    const MirValue da = gl_val(&b, MOP_FuncAddr, NULL, 0, gl_imm_func(drop), MIR_PTR);
    gl_put(&b, gl_ptr_at(&b, obj, 8), da);
    for (uint32_t k = 0; k < ncaps; k++) {
        gl_put(&b, gl_ptr_at(&b, obj, offs[k]), copies[k]);
    }
    mir_b_ret(&b, obj);
    return gl_finish(&b);
}

/* The drop function of recursive data: its nesting is bounded. When the stack is nearly used up
 * the value is parked on the runtime's worklist, to be dropped from the top of the stack later
 * through its slot drop function; otherwise `body` runs, counted as one more level. */
static uint32_t gl_wrap_deep_drop(MirModule *m, MirGlue *g, MirTy ty, uint32_t body) {
    MIR_PUSH(m, g->bodies, g->nbodies, g->cbodies, uint32_t, body);
    uint32_t slot_drop = mir_glue_find(g, MG_SLOT_DROP, ty, 0, 0);
    if (slot_drop == MIR_NONE) {
        slot_drop = gl_make_slot_drop(m, ty);
        gl_record(m, g, MG_SLOT_DROP, ty, 0, 0, slot_drop);
    }
    const int64_t size = gl_mem_size(m, ty);
    const MirTy int_param = MIR_INT, two_ptrs[2] = {MIR_PTR, MIR_PTR};
    const uint32_t enter = gl_extern(m, "msrt_drop_enter", NULL, 0, MIR_INT, false);
    const uint32_t defer = gl_extern(m, "msrt_drop_defer", two_ptrs, 2, MIR_VOID, false);
    const uint32_t leave = gl_extern(m, "msrt_drop_leave", NULL, 0, MIR_VOID, false);
    const uint32_t alloc = gl_extern(m, "msrt_alloc", &int_param, 1, MIR_PTR, true);
    const MirParam param = {ty, MM_MOVE};
    MirBuilder b;
    mir_b_init(&b, m, gl_func_name(m, m->nfuncs, "drop_deep"), &param, 1, MIR_VOID);
    MirValue v;
    mir_b_params(&b, &v, 1);
    const MirBlock enter_blk = mir_b_new_block(&b), park = mir_b_new_block(&b),
                   run = mir_b_new_block(&b), leave_blk = mir_b_new_block(&b),
                   done = mir_b_new_block(&b);
    const MirValue deep =
        gl_val(&b, MOP_StackNear, NULL, 0, mir_imm_int(GL_DEEP_DROP_HEADROOM), MIR_BOOL);
    mir_b_br_if(&b, deep, enter_blk, NULL, 0, run, NULL, 0);
    gl_switch_to(&b, enter_blk);
    const MirValue defer_it = gl_call_rt(&b, enter, NULL, 0);
    const MirValue zero = mir_b_iconst(&b, 0);
    const MirValue parked = mir_b_icmp(&b, MCC_NE, defer_it, zero);
    mir_b_br_if(&b, parked, park, NULL, 0, run, NULL, 0);
    gl_switch_to(&b, park);
    const MirValue n = mir_b_iconst(&b, size > 1 ? size : 1);
    const MirValue blk = gl_call_rt(&b, alloc, &n, 1);
    gl_put(&b, blk, v);
    const MirValue f = gl_val(&b, MOP_FuncAddr, NULL, 0, gl_imm_func(slot_drop), MIR_PTR);
    const MirValue defer_args[2] = {f, blk};
    (void)gl_call_rt(&b, defer, defer_args, 2);
    mir_b_ret(&b, MIR_NONE);
    gl_switch_to(&b, run);
    (void)gl_val(&b, MOP_Call, &v, 1, gl_imm_func(body), MIR_NONE);
    mir_b_br_if(&b, deep, leave_blk, NULL, 0, done, NULL, 0);
    gl_switch_to(&b, leave_blk);
    (void)gl_call_rt(&b, leave, NULL, 0);
    mir_b_br(&b, done, NULL, 0);
    gl_switch_to(&b, done);
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

/* The clone function of recursive data: when the stack is nearly used up the copy runs on a new
 * stack segment through the slot copy function; otherwise `body` runs. */
static uint32_t gl_wrap_deep_clone(MirModule *m, MirGlue *g, MirTy ty, uint32_t body) {
    MIR_PUSH(m, g->bodies, g->nbodies, g->cbodies, uint32_t, body);
    uint32_t slot_copy = mir_glue_find(g, MG_SLOT_COPY, ty, 0, 0);
    if (slot_copy == MIR_NONE) {
        slot_copy = gl_make_slot_copy(m, ty);
        gl_record(m, g, MG_SLOT_COPY, ty, 0, 0, slot_copy);
    }
    const MirTy three_ptrs[3] = {MIR_PTR, MIR_PTR, MIR_PTR};
    const uint32_t grown = gl_extern(m, "msrt_slot_copy_grown", three_ptrs, 3, MIR_VOID, false);
    const MirParam param = {ty, MM_BORROW};
    MirBuilder b;
    mir_b_init(&b, m, gl_func_name(m, m->nfuncs, "clone_deep"), &param, 1, ty);
    MirValue v;
    mir_b_params(&b, &v, 1);
    const MirBlock grow = mir_b_new_block(&b), run = mir_b_new_block(&b);
    const MirValue low = gl_val(&b, MOP_StackNear, NULL, 0, mir_imm_int(0), MIR_BOOL);
    mir_b_br_if(&b, low, grow, NULL, 0, run, NULL, 0);
    gl_switch_to(&b, grow);
    const MirValue src = gl_slot(&b, ty);
    const MirValue store_args[2] = {src, v};
    (void)gl_val(&b, MOP_Store, store_args, 2, (MirImm){0}, MIR_NONE);
    const MirValue dst = gl_slot(&b, ty);
    const MirValue f = gl_val(&b, MOP_FuncAddr, NULL, 0, gl_imm_func(slot_copy), MIR_PTR);
    const MirValue grown_args[3] = {f, src, dst};
    (void)gl_call_rt(&b, grown, grown_args, 3);
    mir_b_ret(&b, gl_take(&b, dst, ty));
    gl_switch_to(&b, run);
    const MirValue out = gl_val(&b, MOP_Call, &v, 1, gl_imm_func(body), ty);
    mir_b_ret(&b, out);
    return gl_finish(&b);
}

/* The field of case `c` that holds the same boxed alternative again (the tail of a chain such as
 * `Cons(head, tail)`), as the last such field and whether it is optional. A chain is freed by a
 * loop, so its length cannot overflow the stack. */
static GlTail gl_drop_tail(const MirModule *m, bool boxed, MirTy ty, const MirCaseDef *def) {
    GlTail t = {0};
    if (!boxed) {
        return t;
    }
    for (uint32_t k = def->nfields; k-- > 0;) {
        MirTy inner = MIR_NONE;
        const bool opt = gl_is_opt(m, def->fields[k].ty, &inner);
        if (def->fields[k].ty == ty && k < GL_MAX_CHAIN_FIELD) {
            return (GlTail){.some = true, .field = k, .optional = false};
        }
        if (opt && inner == ty && k < GL_MAX_CHAIN_FIELD) {
            return (GlTail){.some = true, .field = k, .optional = true};
        }
    }
    return t;
}

/* The arm of a case that ends a chain link: the next block of the chain is read before this one
 * is released (the release leaves the tail field alone), then the loop goes on with it. */
static void gl_drop_chain_arm(MirBuilder *b, uint32_t alt, uint32_t c, const GlTail *tail,
                              MirValue p, MirBlock loop_head, MirBlock done) {
    const MirValue next_block = gl_alt_get(b, alt, c, tail->field, p);
    gl_alt_release(b, alt, c, 1u << tail->field, p);
    if (!tail->optional) {
        mir_b_br(b, loop_head, &next_block, 1);
        return;
    }
    const MirBlock more = mir_b_new_block(b), last = mir_b_new_block(b);
    const MirValue present = gl_opt_is_some(b, next_block);
    mir_b_br_if(b, present, more, NULL, 0, last, NULL, 0);
    gl_switch_to(b, more);
    const MirValue next = gl_opt_payload(b, MOP_OptGet, next_block);
    mir_b_br(b, loop_head, &next, 1);
    gl_switch_to(b, last);
    mir_b_br(b, done, NULL, 0);
}

/* Per case: whether a drop releases fields (some owned field needs a drop), and the chain tail. */
static bool gl_drop_alt_plan(const MirModule *m, MirTy ty, uint32_t alt, bool boxed, bool *owns,
                             GlTail *tails) {
    const MirAltDef *def = &m->alts[alt];
    bool looped = false;
    for (uint32_t c = 0; c < def->ncases; c++) {
        owns[c] = !mir_owns(def->borrowed, c);
        if (owns[c]) {
            bool any = false;
            for (uint32_t k = 0; k < def->cases[c].nfields && !any; k++) {
                any = mir_needs_drop(m, def->cases[c].fields[k].ty);
            }
            owns[c] = any;
        }
        tails[c] = gl_drop_tail(m, boxed, ty, &def->cases[c]);
        looped = looped || tails[c].some;
    }
    return looped;
}

static uint32_t gl_make_drop_alt(MirModule *m, const MirParam *param, MirTy ty, uint32_t alt,
                                 MsSym name) {
    const bool boxed = mir_alt_is_boxed(m, alt);
    const MirAltDef *def = &m->alts[alt];
    const uint32_t ncases = def->ncases;
    bool *owns = MS_NEW_N(&m->arena, bool, ncases ? ncases : 1);
    GlTail *tails = MS_NEW_N(&m->arena, GlTail, ncases ? ncases : 1);
    const bool looped = gl_drop_alt_plan(m, ty, alt, boxed, owns, tails);
    MirBuilder b;
    mir_b_init(&b, m, name, param, 1, MIR_VOID);
    MirValue first;
    mir_b_params(&b, &first, 1);
    const MirBlock done = mir_b_new_block(&b);
    MirBlock loop_head = MIR_NONE;
    MirValue p = first;
    if (looped) {
        const MirBlock head = mir_b_new_block(&b);
        p = mir_b_add_block_param(&b, head, ty, MM_MOVE);
        mir_b_br(&b, head, &first, 1);
        gl_switch_to(&b, head);
        loop_head = head;
    }
    /* A case that owns nothing needs no code, unless it holds a block to free: payloadless cases
     * of a boxed alternative share a static block that is never freed. */
    uint32_t *arms = MS_NEW_N(&m->arena, uint32_t, ncases ? ncases : 1);
    uint32_t narms = 0;
    for (uint32_t c = 0; c < ncases; c++) {
        if (def->cases[c].nfields == 0 || (!boxed && !owns[c])) {
            continue;
        }
        arms[narms++] = c;
    }
    if (narms == 0) {
        mir_b_ret(&b, MIR_NONE);
        return gl_finish(&b);
    }
    const MirValue tag = gl_alt_tag(&b, p);
    MirBlock *blocks = MS_NEW_N(&m->arena, MirBlock, narms);
    MirCase *cases = MS_NEW_N(&m->arena, MirCase, narms);
    for (uint32_t i = 0; i < narms; i++) {
        blocks[i] = mir_b_new_block(&b);
        cases[i] = (MirCase){(int64_t)arms[i], {blocks[i], NULL, 0}};
    }
    mir_b_switch(&b, tag, cases, narms, done);
    for (uint32_t i = 0; i < narms; i++) {
        const uint32_t c = arms[i];
        gl_switch_to(&b, blocks[i]);
        if (tails[c].some) {
            gl_drop_chain_arm(&b, alt, c, &tails[c], p, loop_head, done);
            continue;
        }
        /* Every field marked moved: the release only frees the block. */
        const uint32_t n = def->cases[c].nfields;
        uint32_t mask = 0;
        if (!owns[c]) {
            mask = n >= 32 ? UINT32_MAX : (1u << n) - 1;
        }
        gl_alt_release(&b, alt, c, mask, p);
        mir_b_br(&b, done, NULL, 0);
    }
    gl_switch_to(&b, done);
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

static uint32_t gl_drop_type(const GlCx *cx) {
    MirModule *m = cx->m;
    const MsSym name = cx->name;
    const MirParam param = cx->param;
    const MirTyData *d = cx->d;
    MirBuilder b;
    mir_b_init(&b, m, name, &param, 1, MIR_VOID);
    MirValue p;
    mir_b_params(&b, &p, 1);
    (void)gl_val(&b, MOP_TypeRelease, &p, 1, (MirImm){.tag = MI_TYPEMASK, .a = d->id, .b = 0},
                 MIR_NONE);
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

static uint32_t gl_drop_opt(const GlCx *cx) {
    MirModule *m = cx->m;
    const MsSym name = cx->name;
    const MirParam param = cx->param;
    const MirTyData *d = cx->d;
    MirBuilder b;
    const bool boxed = mir_opt_is_boxed(m, d->elem);
    mir_b_init(&b, m, name, &param, 1, MIR_VOID);
    MirValue p;
    mir_b_params(&b, &p, 1);
    const MirBlock some = mir_b_new_block(&b), done = mir_b_new_block(&b);
    const MirValue present = gl_opt_is_some(&b, p);
    mir_b_br_if(&b, present, some, NULL, 0, done, NULL, 0);
    gl_switch_to(&b, some);
    /* A boxed payload is moved out of its box, which is freed. */
    gl_drop(&b, gl_opt_payload(&b, boxed ? MOP_OptUnbox : MOP_OptGet, p));
    mir_b_br(&b, done, NULL, 0);
    gl_switch_to(&b, done);
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

/* Drops the elements of an owned list from index `from` on and frees its block. A view (capacity 0) borrows its
 * elements and owns no block: nothing to drop or free. `from` is the second parameter of the release function and
 * the constant 0 of the drop function; a negative one counts from the start. */
static uint32_t gl_list_end(const GlCx *cx, bool with_from) {
    MirModule *m = cx->m;
    const MirTy ty = cx->ty;
    MirParam params[2] = {cx->param, {MIR_INT, MM_BORROW}};
    MirBuilder b;
    MirTy elem = gl_elem(m, ty, false);
    if (elem != MIR_NONE && !mir_needs_drop(m, elem)) {
        elem = MIR_NONE;
    }
    mir_b_init(&b, m, cx->name, params, with_from ? 2 : 1, MIR_VOID);
    MirValue p[2];
    mir_b_params(&b, p, with_from ? 2 : 1);
    const MirBlock owned = mir_b_new_block(&b), done = mir_b_new_block(&b);
    const MirValue cap = gl_val(&b, MOP_ListCap, p, 1, (MirImm){0}, MIR_INT);
    const MirValue zero = mir_b_iconst(&b, 0);
    const MirValue is_owned = mir_b_icmp(&b, MCC_NE, cap, zero);
    mir_b_br_if(&b, is_owned, owned, NULL, 0, done, NULL, 0);
    gl_switch_to(&b, owned);
    if (elem != MIR_NONE) {
        const MirValue len = gl_list_len(&b, p[0]);
        const MirBlock head = mir_b_new_block(&b), body = mir_b_new_block(&b),
                       free_blk = mir_b_new_block(&b);
        const MirValue i = mir_b_add_block_param(&b, head, MIR_INT, MM_BORROW);
        const MirValue start = with_from ? mir_b_select(&b, mir_b_icmp(&b, MCC_LT, p[1], zero), zero, p[1])
                                         : mir_b_iconst(&b, 0);
        mir_b_br(&b, head, &start, 1);
        gl_switch_to(&b, head);
        const MirValue more = mir_b_icmp(&b, MCC_LT, i, len);
        mir_b_br_if(&b, more, body, NULL, 0, free_blk, NULL, 0);
        gl_switch_to(&b, body);
        const MirValue get_args[2] = {p[0], i};
        gl_drop(&b, gl_val(&b, MOP_ListGetU, get_args, 2, (MirImm){0}, elem));
        const MirValue one = mir_b_iconst(&b, 1);
        const MirValue next = mir_b_binop(&b, MOP_IAdd, i, one);
        mir_b_br(&b, head, &next, 1);
        gl_switch_to(&b, free_blk);
    }
    gl_free(&b, p[0]);
    mir_b_br(&b, done, NULL, 0);
    gl_switch_to(&b, done);
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

static uint32_t gl_drop_list(const GlCx *cx) { return gl_list_end(cx, false); }

/* The function `(list, from)` that `lower_ops` calls for `list.release`. Its drops of the elements are
 * `drop` ops, which `lower_ops` rewrites to calls of the element's drop glue. */
uint32_t mir_glue_list_release(MirModule *m, MirTy ty) {
    const MirParam param = {ty, MM_MOVE};
    const GlCx cx = {m, NULL, gl_func_name(m, m->nfuncs, "release"), param, ty, mir_ty_data(m, ty)};
    return gl_list_end(&cx, true);
}

static uint32_t gl_drop_obj(const GlCx *cx) {
    MirModule *m = cx->m;
    const MsSym name = cx->name;
    const MirParam param = cx->param;
    const MirTy ty = cx->ty;
    MirBuilder b;
    /* The runtime drops a map or set it finds in memory, through its descriptor. */
    const MirTy two_ptrs[2] = {MIR_PTR, MIR_PTR};
    const uint32_t drop = gl_extern(m, "msrt_slot_drop", two_ptrs, 2, MIR_VOID, false);
    mir_b_init(&b, m, name, &param, 1, MIR_VOID);
    MirValue p;
    mir_b_params(&b, &p, 1);
    const MirValue slot = gl_slot(&b, ty);
    gl_put(&b, slot, p);
    /* A map that was never filled has no slots (word 0 is null): nothing to release, so no
     * runtime call. */
    const MirValue first = gl_load(&b, slot, MIR_INT);
    const MirValue zero = mir_b_iconst(&b, 0);
    const MirValue filled = mir_b_icmp(&b, MCC_NE, first, zero);
    const MirBlock run = mir_b_new_block(&b), done = mir_b_new_block(&b);
    mir_b_br_if(&b, filled, run, NULL, 0, done, NULL, 0);
    mir_b_seal_block(&b, run);
    mir_b_seal_block(&b, done);
    gl_switch_to(&b, run);
    const MirValue desc = gl_val(&b, MOP_TypeDesc, NULL, 0, gl_imm_ty(ty), MIR_PTR);
    const MirValue args[2] = {desc, slot};
    (void)gl_call_rt(&b, drop, args, 2);
    mir_b_br(&b, done, NULL, 0);
    gl_switch_to(&b, done);
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

static uint32_t gl_drop_iface(const GlCx *cx) {
    MirModule *m = cx->m;
    const MsSym name = cx->name;
    const MirParam param = cx->param;
    MirBuilder b;
    /* The vtable word's tag says what the value owns: 0 the box and its payload, 1 only the
     * box (`iface.borrow`), 2 nothing (`iface.view`). */
    mir_b_init(&b, m, name, &param, 1, MIR_VOID);
    MirValue p;
    mir_b_params(&b, &p, 1);
    const MirBlock owned = mir_b_new_block(&b), rest = mir_b_new_block(&b),
                   boxed = mir_b_new_block(&b), done = mir_b_new_block(&b);
    const MirValue tag = gl_val(&b, MOP_IfaceTag, &p, 1, (MirImm){0}, MIR_INT);
    const MirValue zero = mir_b_iconst(&b, 0);
    const MirValue is_owned = mir_b_icmp(&b, MCC_EQ, tag, zero);
    mir_b_br_if(&b, is_owned, owned, NULL, 0, rest, NULL, 0);
    gl_switch_to(&b, owned);
    (void)gl_val(&b, MOP_IfaceDestroy, &p, 1, (MirImm){0}, MIR_NONE);
    mir_b_br(&b, done, NULL, 0);
    gl_switch_to(&b, rest);
    const MirValue one = mir_b_iconst(&b, 1);
    const MirValue is_box = mir_b_icmp(&b, MCC_EQ, tag, one);
    mir_b_br_if(&b, is_box, boxed, NULL, 0, done, NULL, 0);
    gl_switch_to(&b, boxed);
    const MirValue data = gl_val(&b, MOP_IfaceData, &p, 1, (MirImm){0}, MIR_PTR);
    gl_free(&b, data);
    mir_b_br(&b, done, NULL, 0);
    gl_switch_to(&b, done);
    mir_b_ret(&b, MIR_NONE);
    return gl_finish(&b);
}

static uint32_t gl_make_drop(MirModule *m, MirGlue *g, MirTy ty) {
    const bool recurses = gl_recurses(m, ty);
    const char *suffix = recurses ? "drop_body" : "drop";
    const MirParam param = {ty, MM_MOVE};
    const MirTyData *d = mir_ty_data(m, ty);
    const MsSym name = gl_func_name(m, m->nfuncs, suffix);
    const GlCx cx = {m, g, name, param, ty, d};
    switch ((MirTyKind)d->kind) {
    case MK_TYPE: return gl_drop_type(&cx);
    case MK_ALT: return gl_make_drop_alt(m, &param, ty, d->id, name);
    case MK_OPT: return gl_drop_opt(&cx);
    case MK_LIST:
    case MK_BYTES: return gl_drop_list(&cx);
    case MK_OBJ: return gl_drop_obj(&cx);
    case MK_IFACE: return gl_drop_iface(&cx);
    default: return MIR_NONE; /* drop glue is made for the kinds `gl_eligible` accepts */
    }
}

/* For a boxed alternative with a chain (a case holding the alternative again as its last such
 * field): per case the tail field, whether it is optional, and the byte offset in the block of
 * the leaf that holds the next block's pointer. False for any other alternative. */
static bool gl_boxed_chain(const MirModule *m, MirTy ty, uint32_t alt, GlTail *tails) {
    MirLayouts lay;
    mir_layouts_init(&lay, m);
    bool any = false;
    if (mir_layouts_alt_boxed(&lay, alt)) {
        const MirShape *shape = mir_shape(&lay, ty);
        if (shape->alt == MIR_ALT_BOXED) {
            uint32_t *offsets = MS_NEW_N(&lay.arena, uint32_t, shape->block.len + 1);
            (void)mir_mem_layout(shape->block.ptr, shape->block.len, offsets);
            const MirAltFields *fields = mir_alt_fields(&lay, alt);
            const MirAltDef *def = &m->alts[alt];
            for (uint32_t c = 0; c < def->ncases; c++) {
                tails[c] = (GlTail){0};
                for (uint32_t k = def->cases[c].nfields; k-- > 0;) {
                    MirTy inner = MIR_NONE;
                    const MirTy fty = def->cases[c].fields[k].ty;
                    const bool opt = gl_is_opt(m, fty, &inner);
                    if (k >= GL_MAX_CHAIN_FIELD || (fty != ty && !(opt && inner == ty))) {
                        continue;
                    }
                    const MirAltField *f = &fields->fields[fields->case_start[c] + k];
                    if (f->nleaves == 0) {
                        continue;
                    }
                    tails[c] = (GlTail){.some = true, .field = k, .optional = fty != ty,
                                        .offset = offsets[f->leaves[f->nleaves - 1]]};
                    any = true;
                    break;
                }
            }
        }
    }
    mir_layouts_free(&lay);
    return any;
}

/* The clone of a boxed alternative with a chain: a loop that copies the blocks front to back.
 * Each round clones the other fields, makes the new block, stores it where the previous block's
 * tail leaf (or the result slot) points, and goes on with the source's tail, so a long chain does
 * not use the stack. */
static uint32_t gl_clone_chain(MirModule *m, MsSym name, const MirParam *param, MirTy ty,
                               uint32_t alt, const GlTail *tails) {
    const MirAltDef *def = &m->alts[alt];
    MirBuilder b;
    mir_b_init(&b, m, name, param, 1, ty);
    MirValue first;
    mir_b_params(&b, &first, 1);
    const MirBlock head = mir_b_new_block(&b), exit = mir_b_new_block(&b);
    const MirValue src = mir_b_add_block_param(&b, head, ty, MM_BORROW);
    const MirValue dst = mir_b_add_block_param(&b, head, MIR_PTR, MM_BORROW);
    const MirValue result = gl_slot(&b, ty);
    const MirValue entry_args[2] = {first, result};
    mir_b_br(&b, head, entry_args, 2);
    gl_switch_to(&b, head);
    const MirValue tag = gl_alt_tag(&b, src);
    MirBlock *blocks = MS_NEW_N(&m->arena, MirBlock, def->ncases ? def->ncases : 1);
    MirCase *sw = MS_NEW_N(&m->arena, MirCase, def->ncases ? def->ncases : 1);
    for (uint32_t c = 0; c < def->ncases; c++) {
        blocks[c] = mir_b_new_block(&b);
    }
    const MirBlock fallback = mir_b_new_block(&b);
    for (uint32_t c = 0; c < def->ncases; c++) {
        sw[c] = (MirCase){(int64_t)c, {blocks[c], NULL, 0}};
    }
    mir_b_switch(&b, tag, sw, def->ncases, fallback);
    for (uint32_t c = 0; c < def->ncases; c++) {
        gl_switch_to(&b, blocks[c]);
        const uint32_t n = def->cases[c].nfields;
        MirValue *fields = MS_NEW_N(&m->arena, MirValue, n ? n : 1);
        MirValue tail_value = MIR_NONE;
        for (uint32_t k = 0; k < n; k++) {
            const MirValue v = gl_alt_get(&b, alt, c, k, src);
            if (tails[c].some && tails[c].field == k) {
                /* The source's tail is copied as it is; the next round replaces it. */
                tail_value = v;
                fields[k] = v;
            } else {
                fields[k] = gl_clone(&b, v);
            }
        }
        const MirValue fresh = gl_alt_new(&b, alt, c, fields, n);
        gl_put(&b, dst, fresh);
        if (!tails[c].some || tail_value == MIR_NONE) {
            mir_b_br(&b, exit, NULL, 0);
            continue;
        }
        const MirValue block_ptr = gl_load(&b, dst, MIR_PTR);
        const MirValue next_dst = gl_ptr_at(&b, block_ptr, tails[c].offset);
        if (tails[c].optional) {
            const MirBlock more = mir_b_new_block(&b), last = mir_b_new_block(&b);
            const MirValue present = gl_opt_is_some(&b, tail_value);
            mir_b_br_if(&b, present, more, NULL, 0, last, NULL, 0);
            gl_switch_to(&b, more);
            const MirValue next_args[2] = {gl_opt_payload(&b, MOP_OptGet, tail_value), next_dst};
            mir_b_br(&b, head, next_args, 2);
            gl_switch_to(&b, last);
            mir_b_br(&b, exit, NULL, 0);
        } else {
            const MirValue next_args[2] = {tail_value, next_dst};
            mir_b_br(&b, head, next_args, 2);
        }
    }
    gl_switch_to(&b, fallback);
    mir_b_unreachable(&b);
    gl_switch_to(&b, exit);
    mir_b_ret(&b, gl_take(&b, result, ty));
    return gl_finish(&b);
}

static uint32_t gl_clone_type(const GlCx *cx) {
    MirModule *m = cx->m;
    const MsSym name = cx->name;
    const MirParam param = cx->param;
    const MirTy ty = cx->ty;
    const MirTyData *d = cx->d;
    MirBuilder b;
    const uint32_t n = m->type_defs[d->id].nfields;
    mir_b_init(&b, m, name, &param, 1, ty);
    MirValue p;
    mir_b_params(&b, &p, 1);
    MirValue *fields = MS_NEW_N(&m->arena, MirValue, n ? n : 1);
    for (uint32_t k = 0; k < n; k++) {
        const MirValue v = gl_val(&b, MOP_TypeGet, &p, 1,
                                  (MirImm){.tag = MI_FIELD, .a = d->id, .b = k},
                                  m->type_defs[d->id].fields[k].ty);
        fields[k] = gl_clone(&b, v);
    }
    const MirValue out = gl_val(&b, MOP_TypeNew, fields, n, (MirImm){.tag = MI_TYPE, .a = d->id},
                                mir_ty_type(m, d->id));
    mir_b_ret(&b, out);
    return gl_finish(&b);
}

static uint32_t gl_clone_alt(const GlCx *cx) {
    MirModule *m = cx->m;
    const MsSym name = cx->name;
    const MirParam param = cx->param;
    const MirTy ty = cx->ty;
    const MirTyData *d = cx->d;
    MirBuilder b;
    const MirAltDef *def = &m->alts[d->id];
    GlTail *chain = MS_NEW_N(&m->arena, GlTail, def->ncases ? def->ncases : 1);
    memset(chain, 0, sizeof(GlTail) * (def->ncases ? def->ncases : 1));
    if (gl_boxed_chain(m, ty, d->id, chain)) {
        return gl_clone_chain(m, name, &param, ty, d->id, chain);
    }
    mir_b_init(&b, m, name, &param, 1, ty);
    MirValue p;
    mir_b_params(&b, &p, 1);
    const MirValue tag = gl_alt_tag(&b, p);
    MirBlock *blocks = MS_NEW_N(&m->arena, MirBlock, def->ncases ? def->ncases : 1);
    MirCase *sw = MS_NEW_N(&m->arena, MirCase, def->ncases ? def->ncases : 1);
    for (uint32_t c = 0; c < def->ncases; c++) {
        blocks[c] = mir_b_new_block(&b);
    }
    const MirBlock fallback = mir_b_new_block(&b);
    for (uint32_t c = 0; c < def->ncases; c++) {
        sw[c] = (MirCase){(int64_t)c, {blocks[c], NULL, 0}};
    }
    mir_b_switch(&b, tag, sw, def->ncases, fallback);
    for (uint32_t c = 0; c < def->ncases; c++) {
        gl_switch_to(&b, blocks[c]);
        const uint32_t n = def->cases[c].nfields;
        MirValue *fields = MS_NEW_N(&m->arena, MirValue, n ? n : 1);
        for (uint32_t k = 0; k < n; k++) {
            fields[k] = gl_clone(&b, gl_alt_get(&b, d->id, c, k, p));
        }
        mir_b_ret(&b, gl_alt_new(&b, d->id, c, fields, n));
    }
    gl_switch_to(&b, fallback);
    mir_b_unreachable(&b);
    return gl_finish(&b);
}

static uint32_t gl_clone_opt(const GlCx *cx) {
    MirModule *m = cx->m;
    const MsSym name = cx->name;
    const MirParam param = cx->param;
    const MirTy ty = cx->ty;
    MirBuilder b;
    mir_b_init(&b, m, name, &param, 1, ty);
    MirValue p;
    mir_b_params(&b, &p, 1);
    const MirBlock some = mir_b_new_block(&b), none = mir_b_new_block(&b);
    const MirValue present = gl_opt_is_some(&b, p);
    mir_b_br_if(&b, present, some, NULL, 0, none, NULL, 0);
    gl_switch_to(&b, some);
    const MirValue copy = gl_clone(&b, gl_opt_payload(&b, MOP_OptGet, p));
    mir_b_ret(&b, gl_val(&b, MOP_OptSome, &copy, 1, (MirImm){0},
                         mir_ty_opt(m, mir_b_ty(&b, copy))));
    gl_switch_to(&b, none);
    mir_b_ret(&b, gl_val(&b, MOP_OptNone, NULL, 0, (MirImm){0}, ty));
    return gl_finish(&b);
}

static uint32_t gl_clone_list(const GlCx *cx) {
    MirModule *m = cx->m;
    const MsSym name = cx->name;
    const MirParam param = cx->param;
    const MirTy ty = cx->ty;
    const MirTyData *d = cx->d;
    MirBuilder b;
    const MirTy elem = d->elem;
    mir_b_init(&b, m, name, &param, 1, ty);
    MirValue p;
    mir_b_params(&b, &p, 1);
    const MirValue len = gl_list_len(&b, p);
    const MirValue fresh = mir_b_list_new(&b, elem, len);
    const MirBlock head = mir_b_new_block(&b), body = mir_b_new_block(&b),
                   exit = mir_b_new_block(&b);
    const MirValue i = mir_b_add_block_param(&b, head, MIR_INT, MM_BORROW);
    const MirValue acc = mir_b_add_block_param(&b, head, ty, MM_MOVE);
    const MirValue start = mir_b_iconst(&b, 0);
    const MirValue entry_args[2] = {start, fresh};
    mir_b_br(&b, head, entry_args, 2);
    gl_switch_to(&b, head);
    const MirValue more = mir_b_icmp(&b, MCC_LT, i, len);
    mir_b_br_if(&b, more, body, NULL, 0, exit, NULL, 0);
    gl_switch_to(&b, body);
    const MirValue get_args[2] = {p, i};
    const MirValue x = gl_val(&b, MOP_ListGetU, get_args, 2, (MirImm){0}, elem);
    const MirValue push_args[2] = {acc, gl_clone(&b, x)};
    const MirValue grown = gl_val(&b, MOP_ListPushU, push_args, 2, (MirImm){0}, ty);
    const MirValue one = mir_b_iconst(&b, 1);
    const MirValue next_args[2] = {mir_b_binop(&b, MOP_IAdd, i, one), grown};
    mir_b_br(&b, head, next_args, 2);
    gl_switch_to(&b, exit);
    mir_b_ret(&b, acc);
    return gl_finish(&b);
}

static uint32_t gl_clone_obj(const GlCx *cx) {
    MirModule *m = cx->m;
    const MsSym name = cx->name;
    const MirParam param = cx->param;
    const MirTy ty = cx->ty;
    MirBuilder b;
    const MirTy three_ptrs[3] = {MIR_PTR, MIR_PTR, MIR_PTR};
    const uint32_t copy = gl_extern(m, "msrt_slot_copy", three_ptrs, 3, MIR_VOID, false);
    mir_b_init(&b, m, name, &param, 1, ty);
    MirValue p;
    mir_b_params(&b, &p, 1);
    const MirValue src = gl_slot(&b, ty);
    const MirValue store_args[2] = {src, p};
    (void)gl_val(&b, MOP_Store, store_args, 2, (MirImm){0}, MIR_NONE);
    const MirValue dst = gl_slot(&b, ty);
    const MirValue desc = gl_val(&b, MOP_TypeDesc, NULL, 0, gl_imm_ty(ty), MIR_PTR);
    const MirValue args[3] = {desc, src, dst};
    (void)gl_call_rt(&b, copy, args, 3);
    mir_b_ret(&b, gl_take(&b, dst, ty));
    return gl_finish(&b);
}

static uint32_t gl_make_clone(MirModule *m, MirGlue *g, MirTy ty) {
    const bool recurses = gl_recurses(m, ty);
    const char *suffix = recurses ? "clone_body" : "clone";
    const MsSym name = gl_func_name(m, gl_count(g, MG_CLONE), suffix);
    const MirParam param = {ty, MM_BORROW};
    const MirTyData *d = mir_ty_data(m, ty);
    const GlCx cx = {m, g, name, param, ty, d};
    switch ((MirTyKind)d->kind) {
    case MK_TYPE: return gl_clone_type(&cx);
    case MK_ALT: return gl_clone_alt(&cx);
    case MK_OPT: return gl_clone_opt(&cx);
    case MK_LIST: return gl_clone_list(&cx);
    case MK_OBJ: return gl_clone_obj(&cx);
    default: return MIR_NONE;
    }
}

/* ---- the pass ---- */

/* Whether a drop or clone function is made for `ty`: the kinds whose drop is a walk of fields. */
static bool gl_eligible(MirModule *m, MirLayouts *lay, MirTy t) {
    const MirTyData *d = mir_ty_data(m, t);
    bool kind = false;
    switch ((MirTyKind)d->kind) {
    case MK_TYPE: case MK_ALT: case MK_LIST: case MK_BYTES: case MK_IFACE:
        kind = true;
        break;
    case MK_OPT:
        /* A present flag and the payload's leaves, or a box; the other layouts are one pointer. */
        kind = (mir_layouts_opt_boxed(lay, d->elem) || !mir_opt_is_nullable(lay, d->elem)) &&
               !mir_is_str_like(lay, t);
        break;
    case MK_OBJ:
        kind = gl_is_map_or_set(m, d);
        break;
    default:
        break;
    }
    return kind && mir_needs_drop(m, t);
}

/* Whether closure object `r` (a value of `f`) lives in `f`'s stack frame: a closure that owns no
 * resource, only dropped, called, or lent to calls that neither keep nor return it. */
void mir_framed_closures(const MirModule *m, const MirFunc *f, bool *framed) {
    bool any = false;
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
            const MirInst *inst = &f->blocks[bi].insts[ii];
            if (inst->op == MOP_ClosureNew && inst->imm.tag == MI_FUNC && inst->res != MIR_NONE &&
                m->funcs[inst->imm.a].ncapture_closers == 0) {
                framed[inst->res] = true;
                any = true;
            }
        }
    }
    if (!any) {
        return;
    }
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *blk = &f->blocks[bi];
        for (uint32_t ii = 0; ii < blk->ninsts; ii++) {
            const MirInst *inst = &blk->insts[ii];
            const bool call = inst->op == MOP_Call || inst->op == MOP_CallRt || inst->op == MOP_CallInd;
            const bool plain_call = call && !mir_result_views(m, f, inst);
            for (uint32_t k = 0; k < inst->nargs; k++) {
                bool borrows = false;
                if (inst->op == MOP_Call && inst->imm.tag == MI_FUNC) {
                    const MirFunc *g = &m->funcs[inst->imm.a];
                    borrows = k < g->nparams && g->params[k].mode == MM_BORROW;
                } else if (inst->op == MOP_CallRt && inst->imm.tag == MI_EXT) {
                    const MirExtern *e = &m->externs[inst->imm.a];
                    borrows = k < e->nparams && e->params[k].mode == MM_BORROW;
                } else if (inst->op == MOP_CallInd) {
                    borrows = k == 0;
                }
                if (!(inst->op == MOP_Drop || (plain_call && borrows))) {
                    framed[inst->args[k]] = false;
                }
            }
        }
        const MirTerm *t = &blk->term;
        if (t->kind == MT_RET && t->value != MIR_NONE) {
            framed[t->value] = false;
        }
        if (t->kind == MT_CONDBR || t->kind == MT_SWITCH) {
            framed[t->value] = false;
        }
        const MirTarget *targets[2] = {NULL, NULL};
        if (t->kind == MT_BR) {
            targets[0] = &t->a;
        } else if (t->kind == MT_CONDBR) {
            targets[0] = &t->a;
            targets[1] = &t->b;
        }
        for (uint32_t i = 0; i < 2; i++) {
            for (uint32_t k = 0; targets[i] && k < targets[i]->nargs; k++) {
                framed[targets[i]->args[k]] = false;
            }
        }
        if (t->kind == MT_SWITCH) {
            for (uint32_t i = 0; i < t->ncases; i++) {
                for (uint32_t k = 0; k < t->cases[i].target.nargs; k++) {
                    framed[t->cases[i].target.args[k]] = false;
                }
            }
        }
    }
}

typedef struct GlClosure {
    uint32_t func;
    bool framed;
} GlClosure;

static int gl_cmp_closure(const void *x, const void *y) {
    const GlClosure *a = x, *b = y;
    if (a->func != b->func) {
        return a->func < b->func ? -1 : 1;
    }
    return (int)a->framed - (int)b->framed;
}

/* The closure functions whose objects the program makes, with whether the object lives in a
 * stack frame (and so is not freed), sorted and unique; and those whose objects get a clone
 * entry. */
static void gl_closure_demand(MsArena *a, const MirModule *m, GlClosure **drops, uint32_t *ndrops,
                              GlVec *clones) {
    GlClosure *list = NULL;
    uint32_t n = 0, cap = 0;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        bool *framed = MS_NEW_N(a, bool, f->nvalues ? f->nvalues : 1);
        memset(framed, 0, f->nvalues ? f->nvalues : 1);
        mir_framed_closures(m, f, framed);
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
                const MirInst *inst = &f->blocks[bi].insts[ii];
                if (inst->op != MOP_ClosureNew || inst->imm.tag != MI_FUNC || inst->res == MIR_NONE) {
                    continue;
                }
                if (n == cap) {
                    cap = cap ? cap * 2 : 16;
                    GlClosure *grown = MS_NEW_N(a, GlClosure, cap);
                    if (n > 0) {
                        memcpy(grown, list, sizeof(GlClosure) * n);
                    }
                    list = grown;
                }
                list[n++] = (GlClosure){inst->imm.a, framed[inst->res]};
                gl_push(a, clones, inst->imm.a);
            }
        }
    }
    if (n > 1) {
        qsort(list, n, sizeof(GlClosure), gl_cmp_closure);
        uint32_t out = 1;
        for (uint32_t i = 1; i < n; i++) {
            if (gl_cmp_closure(&list[i], &list[out - 1]) != 0) {
                list[out++] = list[i];
            }
        }
        n = out;
    }
    gl_sort_unique(clones);
    *drops = list;
    *ndrops = n;
}

typedef struct GlWork {
    MsArena a; /* owns every vector below */
    GlVec drop_tys, clone_tys, slot_tys, block_tys, cclone_todo;
    GlClosure *cdrops;
    uint32_t ncdrops;
} GlWork;

static void gl_plan(MirModule *m, const MirGlue *g, GlWork *w) {
    GlVec drops = {0}, clones = {0}, slots = {0}, blocks = {0}, addressed = {0};
    gl_wanted(&w->a, m, &drops, &clones);
    /* The slot and block functions call the drop and clone of their types. */
    gl_addr_types(&w->a, m, &slots, &blocks);
    for (uint32_t i = 0; i < slots.n; i++) {
        gl_push(&w->a, &addressed, slots.v[i]);
    }
    for (uint32_t i = 0; i < blocks.n; i++) {
        gl_push(&w->a, &addressed, blocks.v[i]);
    }
    GlVec closed = {0};
    gl_close(&w->a, &closed, m, &addressed);
    for (uint32_t i = 0; i < closed.n; i++) {
        gl_push(&w->a, &drops, closed.v[i]);
        gl_push(&w->a, &clones, closed.v[i]);
    }
    gl_sort_unique(&drops);
    gl_sort_unique(&clones);

    MirLayouts lay;
    mir_layouts_init(&lay, m);
    for (uint32_t i = 0; i < drops.n; i++) {
        const MirTy t = drops.v[i];
        if (gl_eligible(m, &lay, t) && mir_glue_find(g, MG_DROP, t, 0, 0) == MIR_NONE) {
            gl_push(&w->a, &w->drop_tys, t);
        }
    }
    for (uint32_t i = 0; i < clones.n; i++) {
        const MirTy t = clones.v[i];
        if (!gl_eligible(m, &lay, t) || mir_glue_find(g, MG_CLONE, t, 0, 0) != MIR_NONE) {
            continue;
        }
        /* A list of plain elements is copied by the backends in one block copy. */
        const MirTyData *d = mir_ty_data(m, t);
        if ((d->kind == MK_LIST && !mir_needs_drop(m, d->elem)) || d->kind == MK_BYTES ||
            d->kind == MK_IFACE) {
            continue;
        }
        gl_push(&w->a, &w->clone_tys, t);
    }
    mir_layouts_free(&lay);
    for (uint32_t i = 0; i < slots.n; i++) {
        if (mir_glue_find(g, MG_SLOT_COPY, slots.v[i], 0, 0) == MIR_NONE) {
            gl_push(&w->a, &w->slot_tys, slots.v[i]);
        }
    }
    for (uint32_t i = 0; i < blocks.n; i++) {
        if (mir_glue_find(g, MG_BLOCK_DROP, blocks.v[i], 0, 0) == MIR_NONE) {
            gl_push(&w->a, &w->block_tys, blocks.v[i]);
        }
    }
    GlVec cclones = {0};
    gl_closure_demand(&w->a, m, &w->cdrops, &w->ncdrops, &cclones);
    uint32_t keep = 0;
    for (uint32_t i = 0; i < w->ncdrops; i++) {
        const MirGlueKind kind = w->cdrops[i].framed ? MG_CLOSURE_DROP_FRAMED : MG_CLOSURE_DROP;
        if (mir_glue_find(g, kind, MIR_VOID, w->cdrops[i].func, 0) == MIR_NONE) {
            w->cdrops[keep++] = w->cdrops[i];
        }
    }
    w->ncdrops = keep;
    for (uint32_t i = 0; i < cclones.n; i++) {
        if (mir_glue_find(g, MG_CLOSURE_CLONE, MIR_VOID, cclones.v[i], 0) == MIR_NONE) {
            gl_push(&w->a, &w->cclone_todo, cclones.v[i]);
        }
    }
}

static void gl_build(MirModule *m, MirGlue *g, GlWork *w) {
    for (uint32_t i = 0; i < w->drop_tys.n; i++) {
        const MirTy ty = w->drop_tys.v[i];
        uint32_t id = gl_make_drop(m, g, ty);
        if (gl_recurses(m, ty)) {
            id = gl_wrap_deep_drop(m, g, ty, id);
        }
        gl_record(m, g, MG_DROP, ty, 0, 0, id);
    }
    for (uint32_t i = 0; i < w->clone_tys.n; i++) {
        const MirTy ty = w->clone_tys.v[i];
        uint32_t id = gl_make_clone(m, g, ty);
        if (gl_recurses(m, ty)) {
            id = gl_wrap_deep_clone(m, g, ty, id);
        }
        gl_record(m, g, MG_CLONE, ty, 0, 0, id);
    }
    for (uint32_t i = 0; i < w->slot_tys.n; i++) {
        const MirTy ty = w->slot_tys.v[i];
        if (mir_glue_find(g, MG_SLOT_DROP, ty, 0, 0) == MIR_NONE) {
            gl_record(m, g, MG_SLOT_DROP, ty, 0, 0, gl_make_slot_drop(m, ty));
        }
        gl_record(m, g, MG_SLOT_COPY, ty, 0, 0, gl_make_slot_copy(m, ty));
    }
    for (uint32_t i = 0; i < w->block_tys.n; i++) {
        const MirTy ty = w->block_tys.v[i];
        gl_record(m, g, MG_BLOCK_DROP, ty, 0, 0, gl_make_block_drop(m, ty));
        gl_record(m, g, MG_BLOCK_CLONE, ty, 0, 0, gl_make_block_clone(m, ty));
    }
    GlVec dropped = {0};
    for (uint32_t i = 0; i < w->ncdrops; i++) {
        const uint32_t id = gl_make_closure_drop(m, g, w->cdrops[i].func, w->cdrops[i].framed);
        gl_record(m, g, w->cdrops[i].framed ? MG_CLOSURE_DROP_FRAMED : MG_CLOSURE_DROP, MIR_VOID,
                  w->cdrops[i].func, 0, id);
        if (!w->cdrops[i].framed) {
            gl_push(&w->a, &dropped, w->cdrops[i].func);
        }
    }
    for (uint32_t i = 0; i < w->cclone_todo.n; i++) {
        const uint32_t c = w->cclone_todo.v[i];
        bool have = false;
        for (uint32_t k = 0; k < dropped.n && !have; k++) {
            have = dropped.v[k] == c;
        }
        if (!have && mir_glue_find(g, MG_CLOSURE_DROP, MIR_VOID, c, 0) == MIR_NONE) {
            gl_record(m, g, MG_CLOSURE_DROP, MIR_VOID, c, 0, gl_make_closure_drop(m, g, c, false));
        }
        gl_record(m, g, MG_CLOSURE_CLONE, MIR_VOID, c, 0, gl_make_closure_clone(m, g, c));
    }
}

bool mir_glue(MirModule *m, MirGlue *g) {
    GlWork w = {0};
    gl_plan(m, g, &w);
    const bool made = w.drop_tys.n + w.clone_tys.n + w.slot_tys.n + w.block_tys.n + w.ncdrops +
                          w.cclone_todo.n > 0;
    gl_build(m, g, &w);
    ms_arena_free(&w.a);
    return made;
}

void mir_glue_run_and_expand(MirModule *m, MirGlue *g) {
    while (mir_glue(m, g)) {
        (void)mir_expand_owned(m);
    }
    (void)mir_expand_owned(m);
}
