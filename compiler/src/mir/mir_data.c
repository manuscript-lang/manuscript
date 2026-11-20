/* The static data of a module: descriptors, vtables and globals, as plain symbols with relocations
 * (compiler/include/ms/mir_data.h). Port of the descriptor plan of crates/ms-mir/src/statics.rs
 * and the data definitions of crates/ms-mir-llvm/src/state.rs. */
#include <stdio.h>
#include <string.h>

#include "ms/mir_data.h"

static const char *md_runtime_desc(MirTyKind kind) {
    switch (kind) {
    case MK_INT: return "msrt_desc_int";
    case MK_FLOAT: return "msrt_desc_float";
    case MK_FLOAT32: return "msrt_desc_float32";
    case MK_BOOL: return "msrt_desc_bool";
    case MK_STR: return "msrt_desc_string";
    case MK_BYTES: return "msrt_desc_bytes";
    default: return NULL;
    }
}

static void md_plan_shape(const MirModule *m, MirLayouts *lay, MirTy ty, const MirTyData *d,
                          MirDescPlan *p) {
    if (d->kind == MK_LIST) {
        p->kind = MIR_DESC_LIST;
        p->inner[0] = d->elem;
    } else if (d->kind == MK_OBJ && d->obj_class == MIR_OBJ_COLLECTION && d->nargs > 1) { /* keys and values */
        p->kind = MIR_DESC_MAP;
        p->inner[0] = d->nargs > 0 ? d->args[0] : MIR_NONE;
        p->inner[1] = d->nargs > 1 ? d->args[1] : MIR_NONE;
    } else if (d->kind == MK_OBJ && d->obj_class == MIR_OBJ_COLLECTION) { /* keys only */
        p->kind = MIR_DESC_SET;
        p->inner[0] = d->nargs > 0 ? d->args[0] : MIR_NONE;
    } else if (d->kind == MK_OBJ || d->kind == MK_FN ||
               (d->kind == MK_OPT && mir_opt_is_nullable(lay, d->elem))) {
        /* An object, a closure or a nullable optional is one shared word. */
        p->kind = MIR_DESC_SHARED;
    } else if (!mir_needs_drop(m, ty)) {
        p->kind = MIR_DESC_POD;
    } else {
        p->kind = MIR_DESC_CUSTOM;
        p->slot_glue = ty;
    }
}

void mir_desc_plan(const MirModule *m, MirLayouts *lay, MirTy key, MirDescPlan *out) {
    const uint32_t scope = mir_ty_scope(key);
    const MirTy ty = mir_ty_unscoped(key);
    const MirTyData *d = mir_ty_data(m, ty);
    *out = (MirDescPlan){.inner = {MIR_NONE, MIR_NONE}, .slot_glue = MIR_NONE};
    out->runtime = md_runtime_desc(d->kind);
    if (out->runtime != NULL) {
        return;
    }
    const MirMemLayout mem = mir_type_mem(lay, ty);
    out->size = mem.size;
    out->align = mem.align;
    out->kind = MIR_DESC_POD;
    if (scope == MIR_FORGOTTEN_SCOPE) {
        return; /* plain bits whatever it holds */
    }
    md_plan_shape(m, lay, ty, d, out);
    /* The scope's own glue, else the unscoped one. */
    for (int pass = 0; pass < 2 && !out->has_eq_hash; pass++) {
        const MirTy want = pass == 0 ? key : ty;
        for (uint32_t i = 0; i < m->ndesc_glue; i++) {
            if (m->desc_glue[i].ty == want) {
                out->has_eq_hash = true;
                out->eq = m->desc_glue[i].eq;
                out->hash = m->desc_glue[i].hash;
                break;
            }
        }
    }
    for (uint32_t i = 0; i < 2; i++) {
        if (out->inner[i] != MIR_NONE) {
            out->inner[i] = mir_ty_unscoped(out->inner[i]) | scope << MIR_SCOPE_SHIFT;
        }
    }
}

/* ---- building ---- */

typedef struct MdCx {
    MirModule *m;
    const MirGlue *glue;
    MirLayouts *lay;
    MirData *d;
} MdCx;

static uint32_t md_new_sym(MdCx *c, const MirDataSym *s) {
    MirData *d = c->d;
    MIR_PUSH(c->m, d->syms, d->nsyms, d->csyms, MirDataSym, *s);
    return d->nsyms - 1;
}

static const char *md_name(MdCx *c, const char *kind, uint32_t n) {
    return ms_arena_fmt(&c->m->arena, "ms.%s.%u", kind, n).ptr;
}

static void md_put_word(uint8_t *at, uint64_t v) {
    for (uint32_t i = 0; i < 8; i++) {
        at[i] = (uint8_t)(v >> (8 * i));
    }
}

static MirReloc md_func_reloc(uint32_t offset, uint32_t func) {
    return (MirReloc){offset, {.kind = MT_FUNC, .index = func}};
}

static MirRef md_desc(MdCx *c, MirTy key) {
    MirData *d = c->d;
    for (uint32_t i = 0; i < d->nkeys; i++) {
        if (d->keys[i].key == key) {
            return d->keys[i].to;
        }
    }
    MirDescPlan plan;
    mir_desc_plan(c->m, c->lay, key, &plan);
    MirRef to = {.kind = MT_RUNTIME, .runtime = plan.runtime};
    MirDataSym s = {.size = MIR_DESC_BYTES, .align = 8};
    if (plan.runtime == NULL) {
        s.name = md_name(c, "desc", d->nsyms);
        uint8_t *bytes = MS_NEW_N(&c->m->arena, uint8_t, MIR_DESC_BYTES);
        memset(bytes, 0, MIR_DESC_BYTES);
        md_put_word(bytes, (uint64_t)plan.size | (uint64_t)plan.align << 32);
        md_put_word(bytes + 8, plan.kind);
        s.bytes = bytes;
        s.relocs = MS_NEW_N(&c->m->arena, MirReloc, 6);
        to = (MirRef){.kind = MT_DATA, .index = md_new_sym(c, &s)};
    }
    const MirDescKey entry = {key, to};
    MIR_PUSH(c->m, d->keys, d->nkeys, d->ckeys, MirDescKey, entry);
    if (plan.runtime != NULL) {
        return to;
    }
    /* The symbol exists and the key is recorded; now name what it points at. */
    for (uint32_t i = 0; i < 2; i++) {
        if (plan.inner[i] != MIR_NONE) {
            const MirRef t = md_desc(c, plan.inner[i]);
            MirDataSym *sym = &d->syms[to.index];
            sym->relocs[sym->nrelocs++] = (MirReloc){i == 0 ? MIR_DESC_INNER0 : MIR_DESC_INNER1, t};
        }
    }
    if (plan.slot_glue != MIR_NONE) {
        MirDataSym *sym = &d->syms[to.index];
        sym->relocs[sym->nrelocs++] =
            md_func_reloc(MIR_DESC_DROP, mir_glue_find(c->glue, MG_SLOT_DROP, plan.slot_glue, 0, 0));
        sym->relocs[sym->nrelocs++] =
            md_func_reloc(MIR_DESC_COPY, mir_glue_find(c->glue, MG_SLOT_COPY, plan.slot_glue, 0, 0));
    }
    if (plan.has_eq_hash) {
        MirDataSym *sym = &d->syms[to.index];
        sym->relocs[sym->nrelocs++] = md_func_reloc(MIR_DESC_EQ, plan.eq);
        sym->relocs[sym->nrelocs++] = md_func_reloc(MIR_DESC_HASH, plan.hash);
    }
    return to;
}

static void md_collect_descs(MdCx *c) {
    const MirModule *m = c->m;
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            for (uint32_t ii = 0; ii < f->blocks[bi].ninsts; ii++) {
                const MirInst *inst = &f->blocks[bi].insts[ii];
                if (inst->op == MOP_TypeDesc && inst->imm.tag == MI_TY) {
                    (void)md_desc(c, inst->imm.a);
                }
            }
        }
    }
}

/* Slot 0 is the payload block's drop, the methods follow, then the payload clone. */
static void md_vtables(MdCx *c) {
    const MirModule *m = c->m;
    c->d->vtables = MS_NEW_N(&c->m->arena, uint32_t, m->nvtables);
    for (uint32_t i = 0; i < m->nvtables; i++) {
        const MirVtable *vt = &m->vtables[i];
        const MirTy data = mir_ty_unscoped(vt->data_ty);
        const uint32_t nslots = vt->nmethods + 2;
        MirDataSym s = {.name = md_name(c, "vtable", i), .size = nslots * 8, .align = 8};
        s.relocs = MS_NEW_N(&c->m->arena, MirReloc, nslots);
        s.relocs[s.nrelocs++] = md_func_reloc(0, mir_glue_find(c->glue, MG_BLOCK_DROP, data, 0, 0));
        for (uint32_t k = 0; k < vt->nmethods; k++) {
            s.relocs[s.nrelocs++] = md_func_reloc((k + 1) * 8, vt->methods[k]);
        }
        s.relocs[s.nrelocs++] =
            md_func_reloc((vt->nmethods + 1) * 8, mir_glue_find(c->glue, MG_BLOCK_CLONE, data, 0, 0));
        c->d->vtables[i] = md_new_sym(c, &s);
    }
}

static void md_globals(MdCx *c) {
    const MirModule *m = c->m;
    c->d->globals = MS_NEW_N(&c->m->arena, uint32_t, m->nglobals);
    for (uint32_t i = 0; i < m->nglobals; i++) {
        const uint32_t size = mir_type_mem(c->lay, m->globals[i].ty).size;
        MirDataSym s = {.name = md_name(c, "global", i), .size = size < 8 ? 8 : size, .align = 8,
                        .writable = true};
        c->d->globals[i] = md_new_sym(c, &s);
    }
}

/* The words of a string literal; the layout is MsStr (runtime/include/ms_rt/string.h). */
void mir_str_lit_words(const char *text, uint32_t len, bool *is_static, uint64_t *lo, uint64_t *hi) {
    *is_static = len > MIR_STR_INLINE_MAX;
    if (*is_static) {
        bool ascii = true;
        for (uint32_t i = 0; i < len; i++) {
            ascii = ascii && (uint8_t)text[i] < 0x80;
        }
        *lo = 0;
        *hi = len | MIR_STR_STATIC | (ascii ? MIR_STR_ASCII : 0);
        return;
    }
    uint8_t words[16] = {0};
    *lo = 0;
    memcpy(words, text, len);
    uint64_t second = 0;
    for (uint32_t i = 0; i < 8; i++) {
        *lo |= (uint64_t)words[i] << (8 * i);
        second |= (uint64_t)words[8 + i] << (8 * i);
    }
    *hi = second | MIR_STR_INLINE | ((uint64_t)len << MIR_STR_INLINE_SHIFT);
}

/* The bytes of every long literal a function uses, each followed by a NUL. */
static void md_strings(MdCx *c) {
    MirModule *m = c->m;
    c->d->strings = MS_NEW_N(&m->arena, uint32_t, m->strings.count);
    for (uint32_t i = 0; i < m->strings.count; i++) {
        c->d->strings[i] = MIR_NONE;
    }
    for (uint32_t f = 0; f < m->nfuncs; f++) {
        for (uint32_t b = 0; b < m->funcs[f].nblocks; b++) {
            const MirBlockData *blk = &m->funcs[f].blocks[b];
            for (uint32_t k = 0; k < blk->ninsts; k++) {
                const MirInst *inst = &blk->insts[k];
                const uint32_t id = inst->imm.a;
                if (inst->op != MOP_StrLit || m->strings.len[id] <= MIR_STR_INLINE_MAX ||
                    c->d->strings[id] != MIR_NONE) {
                    continue;
                }
                const uint32_t size = m->strings.len[id] + 1;
                uint8_t *bytes = MS_NEW_N(&m->arena, uint8_t, size);
                memcpy(bytes, m->strings.text[id], size - 1);
                MirDataSym s = {.name = md_name(c, "lit", id), .size = size, .align = 1, .bytes = bytes};
                c->d->strings[id] = md_new_sym(c, &s);
            }
        }
    }
}

/* The bytes of one constant list: each value in the width of the element's leaf, little-endian; a
 * Float32 element holds the bits of a double that are narrowed. */
static uint8_t *md_list_bytes(MirModule *m, MirLeaf leaf, const MirConsts *list, uint32_t *size) {
    const uint32_t width = mir_leaf_size(leaf);
    *size = width * list->n;
    uint8_t *bytes = MS_NEW_N(&m->arena, uint8_t, *size ? *size : 1);
    for (uint32_t i = 0; i < list->n; i++) {
        uint64_t bits = (uint64_t)list->v[i];
        if (leaf == MIR_LEAF_F32) {
            double wide = 0;
            memcpy(&wide, &bits, sizeof wide);
            const float narrow = (float)wide;
            uint32_t word = 0;
            memcpy(&word, &narrow, sizeof word);
            bits = word;
        }
        for (uint32_t b = 0; b < width; b++) {
            bytes[(size_t)i * width + b] = (uint8_t)(bits >> (8 * b));
        }
    }
    return bytes;
}

/* One symbol for each constant byte string and constant list a function uses. */
static void md_consts(MdCx *c) {
    MirModule *m = c->m;
    c->d->blobs = MS_NEW_N(&m->arena, uint32_t, m->nblobs ? m->nblobs : 1);
    c->d->list_consts = MS_NEW_N(&m->arena, uint32_t, m->nlist_consts ? m->nlist_consts : 1);
    for (uint32_t i = 0; i < m->nblobs; i++) {
        c->d->blobs[i] = MIR_NONE;
    }
    for (uint32_t i = 0; i < m->nlist_consts; i++) {
        c->d->list_consts[i] = MIR_NONE;
    }
    for (uint32_t f = 0; f < m->nfuncs; f++) {
        for (uint32_t b = 0; b < m->funcs[f].nblocks; b++) {
            const MirBlockData *blk = &m->funcs[f].blocks[b];
            for (uint32_t k = 0; k < blk->ninsts; k++) {
                const MirInst *inst = &blk->insts[k];
                const uint32_t id = (uint32_t)inst->imm.i;
                if (inst->op == MOP_BytesLit && id < m->nblobs && c->d->blobs[id] == MIR_NONE &&
                    m->blobs[id].len > 0) {
                    MirDataSym s = {.name = md_name(c, "blob", id), .size = m->blobs[id].len, .align = 1,
                                    .bytes = (const uint8_t *)m->blobs[id].ptr};
                    c->d->blobs[id] = md_new_sym(c, &s);
                } else if ((inst->op == MOP_ListConst || inst->op == MOP_ListConstView) &&
                           id < m->nlist_consts && c->d->list_consts[id] == MIR_NONE &&
                           m->list_consts[id].n > 0) {
                    const MirLeafSpan leaves = mir_leaves(c->lay, mir_ty_data(m, m->funcs[f].values[inst->res])->elem);
                    uint32_t size = 0;
                    const uint8_t *bytes = md_list_bytes(m, leaves.ptr[0], &m->list_consts[id], &size);
                    MirDataSym s = {.name = md_name(c, "list", id), .size = size, .align = 16, .bytes = bytes};
                    c->d->list_consts[id] = md_new_sym(c, &s);
                }
            }
        }
    }
}

uint32_t mir_data_unit(const MirData *d, uint32_t alt, uint32_t case_index) {
    for (uint32_t i = 0; i < d->nunits; i++) {
        if (d->units[i].alt == alt && d->units[i].case_index == case_index) {
            return d->units[i].sym;
        }
    }
    return MIR_NONE;
}

/* A payloadless case of a boxed alternative is one static block, so building it allocates nothing. */
static void md_unit(MdCx *c, const MirFunc *f, const MirInst *inst) {
    const uint32_t alt = inst->imm.a, case_index = inst->imm.b;
    const MirAltDef *def = &c->m->alts[alt];
    uint32_t size = 0;
    if (def->cases[case_index].nfields != 0 || mir_data_unit(c->d, alt, case_index) != MIR_NONE ||
        !mir_boxed_block_size(c->lay, f->values[inst->res], &size)) {
        return;
    }
    size = size < 8 ? 8 : size;
    uint8_t *bytes = MS_NEW_N(&c->m->arena, uint8_t, size);
    md_put_word(bytes, case_index);
    MirDataSym s = {.name = ms_arena_fmt(&c->m->arena, "ms.unit.%u.%u", alt, case_index).ptr,
                    .size = size, .align = 8, .bytes = bytes};
    const MirUnit unit = {alt, case_index, md_new_sym(c, &s)};
    MIR_PUSH(c->m, c->d->units, c->d->nunits, c->d->cunits, MirUnit, unit);
}

static void md_units(MdCx *c) {
    for (uint32_t f = 0; f < c->m->nfuncs; f++) {
        const MirFunc *fn = &c->m->funcs[f];
        for (uint32_t b = 0; b < fn->nblocks; b++) {
            for (uint32_t k = 0; k < fn->blocks[b].ninsts; k++) {
                const MirInst *inst = &fn->blocks[b].insts[k];
                if (inst->op == MOP_AltNew || inst->op == MOP_AltView) {
                    md_unit(c, fn, inst);
                }
            }
        }
    }
}

void mir_data_build(MirModule *m, const MirGlue *glue, MirData *out) {
    MirLayouts lay;
    mir_layouts_init(&lay, m);
    *out = (MirData){0};
    MdCx c = {.m = m, .glue = glue, .lay = &lay, .d = out};
    md_globals(&c);
    md_vtables(&c);
    md_strings(&c);
    md_consts(&c);
    md_units(&c);
    md_collect_descs(&c);
    mir_layouts_free(&lay);
}

MirRef mir_data_desc(const MirData *d, MirTy key) {
    for (uint32_t i = 0; i < d->nkeys; i++) {
        if (d->keys[i].key == key) {
            return d->keys[i].to;
        }
    }
    return (MirRef){.kind = MT_RUNTIME, .runtime = NULL};
}
