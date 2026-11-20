/* Debug type descriptions. Port of debug_types.rs. */
#include <string.h>

#include "ms/mir_debug.h"
#include "ms/mir_layout.h"

typedef struct DtMembers { MirDebugMember *v; uint32_t n, cap; } DtMembers;

typedef struct DtBuild {
    const MirModule *m;
    MirLayouts layouts;
    MirDebugTypes *out;
    uint32_t *ids;              /* by MIR type: list index + 1, 0 for not yet */
    uint32_t leaves[MIR_LEAF_COUNT]; /* by leaf: list index + 1 */
} DtBuild;

static uint32_t dt_ty(DtBuild *b, MirTy ty);

static MsStr dt_str(DtBuild *b, MsStr s) {
    return (MsStr){ms_arena_strndup(&b->out->arena, s.ptr, s.len), s.len};
}

static uint32_t dt_push(DtBuild *b, MsStr name, uint32_t size, MirDebugKind kind) {
    MirDebugTypes *o = b->out;
    if (o->ntypes == o->ctypes) {
        const uint32_t cap = ms_capacity_for(o->ctypes, o->ntypes + 1);
        MirDebugType *grown = MS_NEW_N(&o->arena, MirDebugType, cap);
        if (o->ntypes > 0) {
            memcpy(grown, o->types, sizeof(MirDebugType) * o->ntypes);
        }
        o->types = grown;
        o->ctypes = cap;
    }
    o->types[o->ntypes] = (MirDebugType){.name = name, .size = size, .kind = (uint8_t)kind,
                                         .pointee = MIR_NONE};
    return o->ntypes++;
}

static void dt_add(DtBuild *b, DtMembers *ms, MsStr name, uint32_t offset, uint32_t ty) {
    if (ms->n == ms->cap) {
        ms->cap = ms_capacity_for(ms->cap, ms->n + 1);
        MirDebugMember *grown = MS_NEW_N(&b->out->arena, MirDebugMember, ms->cap);
        if (ms->n > 0) {
            memcpy(grown, ms->v, sizeof(MirDebugMember) * ms->n);
        }
        ms->v = grown;
    }
    ms->v[ms->n++] = (MirDebugMember){name, offset, ty};
}

static MsStr dt_lit(DtBuild *b, const char *s) {
    return dt_str(b, (MsStr){s, (uint32_t)strlen(s)});
}

static void dt_set_members(DtBuild *b, uint32_t id, MirDebugKind kind, const DtMembers *ms) {
    (void)b;
    b->out->types[id].kind = (uint8_t)kind;
    b->out->types[id].members = ms->v;
    b->out->types[id].nmembers = ms->n;
}

/* The base type of one machine leaf. */
static uint32_t dt_leaf(DtBuild *b, MirLeaf leaf) {
    if (b->leaves[leaf] != 0) {
        return b->leaves[leaf] - 1;
    }
    static const struct { const char *name; uint8_t enc; } info[MIR_LEAF_COUNT] = {
        [MIR_LEAF_I64] = {"UInt64", MDE_UNSIGNED}, [MIR_LEAF_F64] = {"Float", MDE_FLOAT},
        [MIR_LEAF_I8] = {"Bool", MDE_BOOL},        [MIR_LEAF_N8] = {"Int8", MDE_SIGNED},
        [MIR_LEAF_N16] = {"Int16", MDE_SIGNED},    [MIR_LEAF_N32] = {"Int32", MDE_SIGNED},
        [MIR_LEAF_U8] = {"UInt8", MDE_UNSIGNED},   [MIR_LEAF_U16] = {"UInt16", MDE_UNSIGNED},
        [MIR_LEAF_U32] = {"UInt32", MDE_UNSIGNED}, [MIR_LEAF_F32] = {"Float32", MDE_FLOAT},
    };
    const uint32_t i = dt_push(b, dt_lit(b, info[leaf].name), mir_leaf_size(leaf), MDK_BASE);
    b->out->types[i].encoding = info[leaf].enc;
    b->leaves[leaf] = i + 1;
    return i;
}

/* ---- names ---- */

static void dt_name_to(const DtBuild *b, MirTy ty, MsBuf *out);

static void dt_name_list(const DtBuild *b, const MirTy *tys, uint32_t n, MsBuf *out) {
    for (uint32_t i = 0; i < n; i++) {
        if (i > 0) {
            ms_buf_puts(out, ", ");
        }
        dt_name_to(b, tys[i], out);
    }
}

static void dt_put_sym(const DtBuild *b, MsSym s, MsBuf *out) {
    const MsStr n = ms_name(&b->m->names, s);
    ms_buf_put(out, n.ptr, n.len);
}

static void dt_name_to(const DtBuild *b, MirTy ty, MsBuf *out) {
    static const char *const plain[] = {
        [MK_VOID] = "Void", [MK_BOOL] = "Bool", [MK_INT] = "Int", [MK_FLOAT] = "Float",
        [MK_INT8] = "Int8", [MK_INT16] = "Int16", [MK_INT32] = "Int32", [MK_FLOAT32] = "Float32",
        [MK_UINT8] = "UInt8", [MK_UINT16] = "UInt16", [MK_UINT32] = "UInt32",
        [MK_UINT64] = "UInt64", [MK_STR] = "String", [MK_BYTES] = "Bytes", [MK_PTR] = "Ptr",
    };
    const MirModule *m = b->m;
    const MirTyData *d = mir_ty_data(m, ty);
    if (d->kind <= MK_PTR) {
        ms_buf_puts(out, plain[d->kind]);
        return;
    }
    switch (d->kind) {
    case MK_TYPE: dt_put_sym(b, m->type_defs[d->id].name, out); break;
    case MK_ALT: dt_put_sym(b, m->alts[d->id].name, out); break;
    case MK_IFACE: dt_put_sym(b, m->ifaces[d->id].name, out); break;
    case MK_LIST:
        ms_buf_puts(out, "List[");
        dt_name_to(b, d->elem, out);
        ms_buf_putc(out, ']');
        break;
    case MK_OPT:
        dt_name_to(b, d->elem, out);
        ms_buf_putc(out, '?');
        break;
    case MK_OBJ:
        dt_put_sym(b, d->name, out);
        if (d->nargs > 0) {
            ms_buf_putc(out, '[');
            dt_name_list(b, d->args, d->nargs, out);
            ms_buf_putc(out, ']');
        }
        break;
    default: /* MK_FN */
        ms_buf_puts(out, "Fn(");
        dt_name_list(b, d->args, d->nargs, out);
        ms_buf_puts(out, ") ");
        dt_name_to(b, d->elem, out);
        break;
    }
}

static MsStr dt_name(DtBuild *b, MirTy ty) {
    MsBuf buf = {0};
    dt_name_to(b, ty, &buf);
    const MsStr s = dt_str(b, (MsStr){buf.data ? buf.data : "", (uint32_t)buf.len});
    ms_buf_free(&buf);
    return s;
}

/* "<base>*" for a pointer to type `to`. */
static uint32_t dt_pointer_to(DtBuild *b, uint32_t to) {
    const MsStr base = b->out->types[to].name;
    const MsStr name = ms_arena_fmt(&b->out->arena, "%.*s*", (int)base.len, base.ptr);
    const uint32_t id = dt_push(b, name, 8, MDK_POINTER);
    b->out->types[id].pointee = to;
    return id;
}

/* ---- members ---- */

static MirMemLayout dt_mem(DtBuild *b, MirLeafSpan leaves, uint32_t **offsets) {
    *offsets = MS_NEW_N(&b->out->arena, uint32_t, leaves.len ? leaves.len : 1);
    return mir_mem_layout(leaves.ptr, leaves.len, *offsets);
}

/* Adds the field `name` of type `fty`, whose leaves sit at `offsets[idx[..]]` of the enclosing
 * layout. It is shown whole only when its leaves keep their relative offsets inside the enclosing
 * flat layout; otherwise each leaf is shown as `name.k`. */
static void dt_place(DtBuild *b, DtMembers *ms, MsStr name, MirTy fty, const uint32_t *idx,
                     uint32_t nidx, const uint32_t *offsets) {
    if (nidx == 0) {
        return;
    }
    const MirLeafSpan own_leaves = mir_leaves(&b->layouts, fty);
    uint32_t *own_off;
    (void)dt_mem(b, own_leaves, &own_off);
    const uint32_t first = offsets[idx[0]];
    bool whole = nidx == own_leaves.len;
    for (uint32_t k = 0; whole && k < nidx; k++) {
        whole = (int64_t)offsets[idx[k]] - (int64_t)first == (int64_t)own_off[k];
    }
    if (whole) {
        const uint32_t ty = dt_ty(b, fty);
        dt_add(b, ms, dt_str(b, name), first, ty);
        return;
    }
    const MirLeafSpan leaves = mir_leaves(&b->layouts, fty);
    for (uint32_t k = 0; k < nidx && k < leaves.len; k++) {
        const uint32_t ty = dt_leaf(b, leaves.ptr[k]);
        const MsStr n = ms_arena_fmt(&b->out->arena, "%.*s.%u", (int)name.len, name.ptr, k);
        dt_add(b, ms, n, offsets[idx[k]], ty);
    }
}

static void dt_struct_of(DtBuild *b, uint32_t id, MirLeafSpan leaves, const char *const *names,
                         uint32_t nnames) {
    uint32_t *offsets;
    (void)dt_mem(b, leaves, &offsets);
    DtMembers ms = {0};
    for (uint32_t i = 0; i < leaves.len && i < nnames; i++) {
        const uint32_t ty = dt_leaf(b, leaves.ptr[i]);
        dt_add(b, &ms, dt_lit(b, names[i]), offsets[i], ty);
    }
    dt_set_members(b, id, MDK_STRUCT, &ms);
}

/* ---- kinds ---- */

static void dt_list(DtBuild *b, uint32_t id, MirTy elem_ty) {
    const uint32_t elem = dt_ty(b, elem_ty);
    const uint32_t ptr = dt_pointer_to(b, elem);
    const uint32_t len = dt_leaf(b, MIR_LEAF_I64);
    DtMembers ms = {0};
    dt_add(b, &ms, dt_lit(b, "ptr"), 0, ptr);
    dt_add(b, &ms, dt_lit(b, "len"), 8, len);
    dt_add(b, &ms, dt_lit(b, "cap"), 16, len);
    dt_set_members(b, id, MDK_STRUCT, &ms);
}

/* A record: its fields at their memory offsets, or a pointer to them when it is indirect. */
static void dt_record(DtBuild *b, uint32_t id, MirTy ty, uint32_t type_id, MsStr name) {
    const MirTypeDef *def = &b->m->type_defs[type_id];
    const bool indirect = def->indirect;
    const MirLeafSpan leaves =
        indirect ? mir_type_block(&b->layouts, type_id) : mir_leaves(&b->layouts, ty);
    uint32_t *offsets;
    const MirMemLayout mem = dt_mem(b, leaves, &offsets);
    uint32_t at = 0;
    DtMembers ms = {0};
    for (uint32_t i = 0; i < def->nfields; i++) {
        const MirField *f = &def->fields[i];
        const bool boxed = indirect && mir_type_field_boxed(&b->layouts, f->ty);
        const uint32_t w = boxed ? 1 : mir_leaves(&b->layouts, f->ty).len;
        const MsStr fname = ms_name(&b->m->names, f->name);
        if (boxed) {
            const uint32_t header = dt_ty(b, f->ty);
            const uint32_t ptr = dt_pointer_to(b, header);
            dt_add(b, &ms, dt_str(b, fname), offsets[at], ptr);
        } else {
            uint32_t *idx = MS_NEW_N(&b->out->arena, uint32_t, w ? w : 1);
            for (uint32_t k = 0; k < w; k++) {
                idx[k] = at + k;
            }
            dt_place(b, &ms, fname, f->ty, idx, w, offsets);
        }
        at += w;
    }
    if (!indirect) {
        dt_set_members(b, id, MDK_STRUCT, &ms);
        return;
    }
    const MsStr bname = ms_arena_fmt(&b->out->arena, "%.*s block", (int)name.len, name.ptr);
    const uint32_t block = dt_push(b, bname, mem.size, MDK_STRUCT);
    dt_set_members(b, block, MDK_STRUCT, &ms);
    b->out->types[id].kind = MDK_POINTER;
    b->out->types[id].pointee = block;
}

static void dt_optional(DtBuild *b, uint32_t id, MirTy ty, MirTy inner) {
    if (mir_opt_is_nullable(&b->layouts, inner)) {
        b->out->types[id].kind = MDK_POINTER;
        if (mir_layouts_opt_boxed(&b->layouts, inner)) {
            b->out->types[id].pointee = dt_ty(b, inner);
        }
        return;
    }
    const MirLeafSpan leaves = mir_leaves(&b->layouts, ty);
    if (mir_is_str_like(&b->layouts, ty)) {
        static const char *const names[] = {"ptr", "tagged"};
        dt_struct_of(b, id, leaves, names, 2);
        return;
    }
    uint32_t *offsets;
    (void)dt_mem(b, leaves, &offsets);
    DtMembers ms = {0};
    dt_add(b, &ms, dt_lit(b, "present"), 0, dt_leaf(b, MIR_LEAF_I8));
    const uint32_t n = leaves.len > 0 ? leaves.len - 1 : 0;
    uint32_t *idx = MS_NEW_N(&b->out->arena, uint32_t, n ? n : 1);
    for (uint32_t k = 0; k < n; k++) {
        idx[k] = k + 1;
    }
    dt_place(b, &ms, dt_lit(b, "value"), inner, idx, n, offsets);
    dt_set_members(b, id, MDK_STRUCT, &ms);
}

/* An enum: its tag, and the payload of every case laid over the same bytes. */
static void dt_alt(DtBuild *b, uint32_t id, MirTy ty, uint32_t alt, MsStr name) {
    const MirShape *shape = mir_shape(&b->layouts, ty);
    const bool boxed = shape->alt == MIR_ALT_BOXED;
    const MirLeafSpan leaves = boxed ? shape->block : shape->leaves;
    uint32_t *offsets;
    const MirMemLayout mem = dt_mem(b, leaves, &offsets);
    const MirAltFields *fields = mir_alt_fields(&b->layouts, alt);
    const MirAltDef *def = &b->m->alts[alt];
    DtMembers cases = {0};
    for (uint32_t c = 0; c < def->ncases; c++) {
        const MirCaseDef *cd = &def->cases[c];
        DtMembers ms = {0};
        const MirAltField *fs = &fields->fields[fields->case_start[c]];
        for (uint32_t k = 0; k < cd->nfields; k++) {
            dt_place(b, &ms, ms_name(&b->m->names, cd->fields[k].name), fs[k].ty, fs[k].leaves,
                     fs[k].nleaves, offsets);
        }
        const MsStr cname = ms_name(&b->m->names, cd->name);
        const MsStr full = ms_arena_fmt(&b->out->arena, "%.*s.%.*s", (int)name.len, name.ptr,
                                        (int)cname.len, cname.ptr);
        const uint32_t case_ty = dt_push(b, full, mem.size, MDK_STRUCT);
        dt_set_members(b, case_ty, MDK_STRUCT, &ms);
        dt_add(b, &cases, dt_str(b, cname), 0, case_ty);
    }
    const MsStr pname = ms_arena_fmt(&b->out->arena, "%.*s payload", (int)name.len, name.ptr);
    const uint32_t payload = dt_push(b, pname, mem.size, MDK_UNION);
    dt_set_members(b, payload, MDK_UNION, &cases);
    const uint32_t tag = dt_leaf(b, MIR_LEAF_I64);
    DtMembers top = {0};
    dt_add(b, &top, dt_lit(b, "tag"), 0, tag);
    dt_add(b, &top, dt_lit(b, "payload"), 0, payload);
    if (!boxed) {
        dt_set_members(b, id, MDK_STRUCT, &top);
        return;
    }
    const MsStr bname = ms_arena_fmt(&b->out->arena, "%.*s block", (int)name.len, name.ptr);
    const uint32_t block = dt_push(b, bname, mem.size, MDK_STRUCT);
    dt_set_members(b, block, MDK_STRUCT, &top);
    b->out->types[id].kind = MDK_POINTER;
    b->out->types[id].pointee = block;
}

static void dt_base(MirDebugType *t, MirDebugEncoding enc) {
    t->kind = MDK_BASE;
    t->encoding = (uint8_t)enc;
}

static void dt_fill(DtBuild *b, uint32_t id, MirTy ty, MsStr name) {
    const MirTyData *d = mir_ty_data(b->m, ty);
    MirDebugType *t = &b->out->types[id];
    const MirLeafSpan leaves = mir_leaves(&b->layouts, ty);
    static const char *const str_names[] = {"ptr", "tagged"}, *const bytes_names[] = {"ptr", "len", "cap"},
                             *const iface_names[] = {"data", "vtable"};
    switch (d->kind) {
    case MK_VOID: dt_set_members(b, id, MDK_STRUCT, &(DtMembers){0}); break;
    case MK_BOOL: dt_base(t, MDE_BOOL); break;
    case MK_INT: case MK_INT8: case MK_INT16: case MK_INT32:
        dt_base(t, MDE_SIGNED);
        break;
    case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64:
        dt_base(t, MDE_UNSIGNED);
        break;
    case MK_FLOAT: case MK_FLOAT32: dt_base(t, MDE_FLOAT); break;
    case MK_PTR: case MK_FN: t->kind = MDK_POINTER; break;
    case MK_STR: dt_struct_of(b, id, leaves, str_names, 2); break;
    case MK_BYTES: dt_struct_of(b, id, leaves, bytes_names, 3); break;
    case MK_LIST: dt_list(b, id, d->elem); break;
    case MK_OBJ:
        if (!mir_type_field_boxed(&b->layouts, ty)) {
            t->kind = MDK_POINTER;
            break;
        }
        {
            const char **names = MS_NEW_N(&b->out->arena, const char *, leaves.len ? leaves.len : 1);
            for (uint32_t i = 0; i < leaves.len; i++) {
                names[i] = ms_arena_fmt(&b->out->arena, "w%u", i).ptr;
            }
            dt_struct_of(b, id, leaves, names, leaves.len);
        }
        break;
    case MK_IFACE: dt_struct_of(b, id, leaves, iface_names, 2); break;
    case MK_TYPE: dt_record(b, id, ty, d->id, name); break;
    case MK_OPT: dt_optional(b, id, ty, d->elem); break;
    default: dt_alt(b, id, ty, d->id, name); break; /* MK_ALT */
    }
}

/* The description of `ty`, made on first ask. A type is registered before its parts so a cycle
 * ends at the entry already there. */
static uint32_t dt_ty(DtBuild *b, MirTy ty) {
    if (b->ids[ty] != 0) {
        return b->ids[ty] - 1;
    }
    const MsStr name = dt_name(b, ty);
    const uint32_t size = mir_type_mem(&b->layouts, ty).size;
    const uint32_t id = dt_push(b, name, size, MDK_POINTER);
    b->ids[ty] = id + 1;
    dt_fill(b, id, ty, name);
    return id;
}

void mir_debug_types(const MirModule *m, MirDebugTypes *out) {
    DtBuild b = {.m = m, .out = out};
    mir_layouts_init(&b.layouts, m);
    b.ids = MS_NEW_N(&out->arena, uint32_t, m->types.len ? m->types.len : 1);
    memset(b.ids, 0, sizeof(uint32_t) * (m->types.len ? m->types.len : 1));
    out->of_ty = MS_NEW_N(&out->arena, uint32_t, m->types.len ? m->types.len : 1);
    out->nty = m->types.len;
    for (uint32_t t = 0; t < m->types.len; t++) {
        out->of_ty[t] = dt_ty(&b, t);
    }
    mir_layouts_free(&b.layouts);
}

void mir_debug_types_free(MirDebugTypes *t) {
    ms_arena_free(&t->arena);
}
