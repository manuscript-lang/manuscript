/* MIR: type table, opcode table, module construction and queries (ir.rs, types.rs, module.rs). */
#include <stdlib.h>
#include <string.h>

#include "ms/mir.h"

const MirOpInfo mir_op_info[MOP_COUNT] = {
#define MIR_OP(id, name, imm, res, fx) [MOP_##id] = {name, imm, res, fx},
#include "ms/mir_ops.def"
#undef MIR_OP
};

const char *const mir_cc_name[6] = {"eq", "ne", "lt", "le", "gt", "ge"};

int mir_op_from_name(const char *s, size_t n) {
    for (int i = 0; i < MOP_COUNT; i++) {
        const char *name = mir_op_info[i].name;
        if (strlen(name) == n && memcmp(name, s, n) == 0) {
            return i;
        }
    }
    return -1;
}

void *mir_grow(MirModule *m, void *arr, uint32_t *cap, uint32_t n, size_t elem) {
    uint32_t ncap = *cap == 0 ? 4 : *cap * 2;
    void *p = ms_alloc(&m->arena, (size_t)ncap * elem, 16);
    if (n > 0) {
        memcpy(p, arr, (size_t)n * elem);
    }
    *cap = ncap;
    return p;
}

/* ---- type table ---- */

static uint64_t ty_hash(const MirTyData *d) {
    uint64_t h = 1469598103934665603ull;
#define MIX(x) h = (h ^ (uint64_t)(x)) * 1099511628211ull
    MIX(d->kind);
    MIX(d->id);
    MIX(d->elem);
    MIX(d->name);
    MIX(d->owned);
    for (uint32_t i = 0; i < d->nargs; i++) {
        MIX(d->args[i]);
    }
#undef MIX
    return h ^ (h >> 29);
}

static bool ty_eq(const MirTyData *a, const MirTyData *b) {
    if (a->kind != b->kind || a->id != b->id || a->elem != b->elem || a->name != b->name ||
        a->owned != b->owned || a->nargs != b->nargs) {
        return false;
    }
    return a->nargs == 0 || memcmp(a->args, b->args, sizeof(MirTy) * a->nargs) == 0;
}

static void ty_rehash(MirModule *m, uint32_t cap) {
    MirTyTable *t = &m->types;
    t->index = ms_alloc(&m->arena, sizeof(uint32_t) * cap, 4);
    memset(t->index, 0, sizeof(uint32_t) * cap);
    t->mask = cap - 1;
    for (uint32_t i = 0; i < t->len; i++) {
        uint32_t slot = (uint32_t)ty_hash(&t->kinds[i]) & t->mask;
        while (t->index[slot] != 0) {
            slot = (slot + 1) & t->mask;
        }
        t->index[slot] = i + 1;
    }
}

bool mir_ty_find(const MirModule *m, const MirTyData *d, MirTy *out) {
    const MirTyTable *t = &m->types;
    uint32_t slot = (uint32_t)ty_hash(d) & t->mask;
    while (t->index[slot] != 0) {
        if (ty_eq(&t->kinds[t->index[slot] - 1], d)) {
            *out = t->index[slot] - 1;
            return true;
        }
        slot = (slot + 1) & t->mask;
    }
    return false;
}

MirTy mir_ty_intern(MirModule *m, const MirTyData *d) {
    MirTyTable *t = &m->types;
    uint32_t slot = (uint32_t)ty_hash(d) & t->mask;
    while (t->index[slot] != 0) {
        if (ty_eq(&t->kinds[t->index[slot] - 1], d)) {
            return t->index[slot] - 1;
        }
        slot = (slot + 1) & t->mask;
    }
    MirTyData copy = *d;
    if (d->nargs > 0) {
        MirTy *args = MS_NEW_N(&m->arena, MirTy, d->nargs);
        memcpy(args, d->args, sizeof(MirTy) * d->nargs);
        copy.args = args;
    }
    MIR_PUSH(m, t->kinds, t->len, t->cap, MirTyData, copy);
    if ((uint64_t)t->len * 2 > (uint64_t)t->mask + 1) {
        ty_rehash(m, (t->mask + 1) * 2);
    } else {
        t->index[slot] = t->len;
    }
    return t->len - 1;
}

MirTy mir_ty_list(MirModule *m, MirTy elem) {
    MirTyData d = {.kind = MK_LIST, .elem = elem};
    return mir_ty_intern(m, &d);
}
MirTy mir_ty_opt(MirModule *m, MirTy elem) {
    MirTyData d = {.kind = MK_OPT, .elem = elem};
    return mir_ty_intern(m, &d);
}
MirTy mir_ty_type(MirModule *m, uint32_t id) {
    MirTyData d = {.kind = MK_TYPE, .id = id};
    return mir_ty_intern(m, &d);
}
MirTy mir_ty_alt(MirModule *m, uint32_t id) {
    MirTyData d = {.kind = MK_ALT, .id = id};
    return mir_ty_intern(m, &d);
}
MirTy mir_ty_iface(MirModule *m, uint32_t id) {
    MirTyData d = {.kind = MK_IFACE, .id = id};
    return mir_ty_intern(m, &d);
}
/* The runtime's declaration of the objects that are not one shared word: the only place their names appear. */
static const struct { const char *name; MirObjClass class; } mir_object_decls[] = {
    {"Map", MIR_OBJ_COLLECTION}, {"Set", MIR_OBJ_COLLECTION}, {"BigInt", MIR_OBJ_VALUE},
};

static MirObjClass obj_class_of(const MirModule *m, MsSym name) {
    for (size_t i = 0; i < sizeof mir_object_decls / sizeof mir_object_decls[0]; i++) {
        if (mir_name_is(m, name, mir_object_decls[i].name)) {
            return mir_object_decls[i].class;
        }
    }
    return MIR_OBJ_HANDLE;
}

MirTy mir_ty_obj(MirModule *m, MsSym name, const MirTy *args, uint32_t nargs) {
    MirTyData d = {.kind = MK_OBJ, .obj_class = (uint8_t)obj_class_of(m, name), .name = name, .args = args, .nargs = nargs};
    return mir_ty_intern(m, &d);
}
MirTy mir_ty_fn(MirModule *m, const MirTy *params, uint32_t n, MirTy ret, uint64_t owned) {
    MirTyData d = {.kind = MK_FN, .elem = ret, .args = params, .nargs = n, .owned = owned};
    return mir_ty_intern(m, &d);
}

static bool needs_drop_in(const MirModule *m, MirTy ty, MirTy *seen, uint32_t *nseen) {
    const MirTyData *d = mir_ty_data(m, ty);
    switch (d->kind) {
    case MK_VOID: case MK_BOOL: case MK_INT: case MK_INT8: case MK_INT16: case MK_INT32:
    case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_FLOAT:
    case MK_FLOAT32: case MK_PTR:
        return false;
    case MK_OPT:
        return needs_drop_in(m, d->elem, seen, nseen);
    case MK_TYPE:
    case MK_ALT: {
        for (uint32_t i = 0; i < *nseen; i++) {
            if (seen[i] == ty) {
                return true;
            }
        }
        seen[(*nseen)++] = ty;
        bool out = false;
        if (d->kind == MK_TYPE) {
            const MirTypeDef *def = &m->type_defs[d->id];
            for (uint32_t i = 0; i < def->nfields && !out; i++) {
                out = needs_drop_in(m, def->fields[i].ty, seen, nseen);
            }
        } else {
            const MirAltDef *def = &m->alts[d->id];
            for (uint32_t c = 0; c < def->ncases && !out; c++) {
                if (mir_owns(def->borrowed, c)) {
                    continue;
                }
                for (uint32_t i = 0; i < def->cases[c].nfields && !out; i++) {
                    out = needs_drop_in(m, def->cases[c].fields[i].ty, seen, nseen);
                }
            }
        }
        (*nseen)--;
        return out;
    }
    default:
        return true;
    }
}

bool mir_name_is(const MirModule *m, MsSym sym, const char *text) {
    const MsStr name = ms_name(&m->names, sym);
    return name.len == strlen(text) && memcmp(name.ptr, text, name.len) == 0;
}

bool mir_needs_drop(const MirModule *m, MirTy ty) {
    /* The recursion depth is bounded by the number of declarations. */
    uint32_t cap = m->ntype_defs + m->nalts + 1, n = 0;
    MirTy *seen = malloc(sizeof(MirTy) * cap);
    bool r = needs_drop_in(m, ty, seen, &n);
    free(seen);
    return r;
}

/* ---- module ---- */

void mir_module_init(MirModule *m) {
    memset(m, 0, sizeof *m);
    ms_names_init(&m->names);
    ms_names_init(&m->strings);
    m->entry = MIR_NONE;
    m->close = MIR_NONE;
    m->name = ms_intern_cstr(&m->names, "module");
    ty_rehash(m, 64);
    static const MirTyKind builtin[MIR_BUILTIN_TYPES] = {
        MK_VOID, MK_BOOL, MK_INT, MK_FLOAT, MK_STR, MK_BYTES, MK_PTR, MK_INT8, MK_INT16, MK_INT32,
        MK_FLOAT32, MK_UINT8, MK_UINT16, MK_UINT32, MK_UINT64};
    for (int i = 0; i < MIR_BUILTIN_TYPES; i++) {
        MirTyData d = {.kind = (uint8_t)builtin[i]};
        mir_ty_intern(m, &d);
    }
}

void mir_module_free(MirModule *m) {
    ms_names_free(&m->names);
    ms_names_free(&m->strings);
    ms_arena_free(&m->arena);
    memset(m, 0, sizeof *m);
}

MsSym mir_name(MirModule *m, const char *s, size_t n) { return ms_intern(&m->names, s, n); }

uint32_t mir_add_string(MirModule *m, const char *s, size_t n) {
    return ms_intern(&m->strings, s, n);
}

static uint32_t symmap_get(const MirSymMap *map, MsSym s) {
    return s < map->cap ? map->v[s] : MIR_NONE;
}

static void symmap_add(MirModule *m, MirSymMap *map, MsSym s, uint32_t id) {
    if (s >= map->cap) {
        uint32_t cap = map->cap == 0 ? 64 : map->cap;
        while (cap <= s) {
            cap *= 2;
        }
        uint32_t *v = MS_NEW_N(&m->arena, uint32_t, cap);
        if (map->cap > 0) {
            memcpy(v, map->v, sizeof(uint32_t) * map->cap);
        }
        for (uint32_t i = map->cap; i < cap; i++) {
            v[i] = MIR_NONE;
        }
        map->v = v;
        map->cap = cap;
    }
    if (map->v[s] == MIR_NONE) {
        map->v[s] = id;
    }
}

uint32_t mir_func_by_name(const MirModule *m, MsSym n) { return symmap_get(&m->by_func, n); }
uint32_t mir_type_by_name(const MirModule *m, MsSym n) { return symmap_get(&m->by_type, n); }
uint32_t mir_alt_by_name(const MirModule *m, MsSym n) { return symmap_get(&m->by_alt, n); }
uint32_t mir_iface_by_name(const MirModule *m, MsSym n) { return symmap_get(&m->by_iface, n); }
uint32_t mir_vtable_by_name(const MirModule *m, MsSym n) { return symmap_get(&m->by_vtable, n); }
uint32_t mir_global_by_name(const MirModule *m, MsSym n) { return symmap_get(&m->by_global, n); }
uint32_t mir_extern_by_name(const MirModule *m, MsSym n) { return symmap_get(&m->by_extern, n); }

uint32_t mir_add_func(MirModule *m, const MirFunc *f) {
    MIR_PUSH(m, m->funcs, m->nfuncs, m->cfuncs, MirFunc, *f);
    symmap_add(m, &m->by_func, f->name, m->nfuncs - 1);
    return m->nfuncs - 1;
}

void mir_funcs_reindex(MirModule *m) {
    for (uint32_t i = 0; i < m->by_func.cap; i++) {
        m->by_func.v[i] = MIR_NONE;
    }
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        symmap_add(m, &m->by_func, m->funcs[i].name, i);
    }
}

uint32_t mir_add_type(MirModule *m, MsSym name) {
    MirTypeDef d = {.name = name};
    MIR_PUSH(m, m->type_defs, m->ntype_defs, m->ctype_defs, MirTypeDef, d);
    symmap_add(m, &m->by_type, name, m->ntype_defs - 1);
    return m->ntype_defs - 1;
}

uint32_t mir_add_alt(MirModule *m, MsSym name) {
    MirAltDef d = {.name = name};
    MIR_PUSH(m, m->alts, m->nalts, m->calts, MirAltDef, d);
    symmap_add(m, &m->by_alt, name, m->nalts - 1);
    return m->nalts - 1;
}

uint32_t mir_add_iface(MirModule *m, MsSym name) {
    MirIfaceDef d = {.name = name};
    MIR_PUSH(m, m->ifaces, m->nifaces, m->cifaces, MirIfaceDef, d);
    symmap_add(m, &m->by_iface, name, m->nifaces - 1);
    return m->nifaces - 1;
}

uint32_t mir_add_vtable(MirModule *m, const MirVtable *v) {
    MIR_PUSH(m, m->vtables, m->nvtables, m->cvtables, MirVtable, *v);
    symmap_add(m, &m->by_vtable, v->name, m->nvtables - 1);
    return m->nvtables - 1;
}

uint32_t mir_add_global(MirModule *m, MsSym name, MirTy ty) {
    MirGlobal g = {name, ty};
    MIR_PUSH(m, m->globals, m->nglobals, m->cglobals, MirGlobal, g);
    symmap_add(m, &m->by_global, name, m->nglobals - 1);
    return m->nglobals - 1;
}

uint32_t mir_add_extern(MirModule *m, const MirExtern *e) {
    MIR_PUSH(m, m->externs, m->nexterns, m->cexterns, MirExtern, *e);
    symmap_add(m, &m->by_extern, e->name, m->nexterns - 1);
    return m->nexterns - 1;
}

/* ---- functions ---- */

MirValue mir_new_value(MirModule *m, MirFunc *f, MirTy ty) {
    MIR_PUSH(m, f->values, f->nvalues, f->cvalues, MirTy, ty);
    return f->nvalues - 1;
}

MirBlockData mir_block_empty(void) {
    MirBlockData b = {0};
    b.term.kind = MT_UNREACHABLE;
    b.term.value = MIR_NONE;
    b.term_loc = MIR_LOC_NONE;
    return b;
}

MirBlock mir_new_block(MirModule *m, MirFunc *f) {
    MirBlockData b = mir_block_empty();
    MIR_PUSH(m, f->blocks, f->nblocks, f->cblocks, MirBlockData, b);
    return f->nblocks - 1;
}

void mir_func_init(MirModule *m, MirFunc *f, MsSym name, const MirParam *params, uint32_t n,
                   MirTy ret) {
    memset(f, 0, sizeof *f);
    f->name = name;
    f->params = MS_NEW_N(&m->arena, MirParam, n ? n : 1);
    if (n > 0) {
        memcpy(f->params, params, sizeof(MirParam) * n);
    }
    f->nparams = n;
    f->ret = ret;
    f->loc = MIR_LOC_NONE;
    mir_new_block(m, f);
    for (uint32_t i = 0; i < n; i++) {
        MirBlockParam bp = {mir_new_value(m, f, params[i].ty), params[i].mode};
        MIR_PUSH(m, f->blocks[0].params, f->blocks[0].nparams, f->blocks[0].cparams, MirBlockParam,
                 bp);
    }
}

void mir_add_desc_glue(MirModule *m, MirTy ty, uint32_t eq, uint32_t hash) {
    const MirDescGlue g = {ty, eq, hash};
    MIR_PUSH(m, m->desc_glue, m->ndesc_glue, m->cdesc_glue, MirDescGlue, g);
}
