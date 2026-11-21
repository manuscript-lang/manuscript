/* Name maps, symbol columns and the module list: the tables every checker pass reads. */
#include <stdlib.h>
#include <string.h>

#include "ms/methods.h"
#include "ms/tables.h"

/* ---- MsNameMap: open addressing, linear probing, values stored as value + 1 ---- */

void ms_map_free(MsNameMap *map) {
    free(map->keys);
    free(map->vals);
    *map = (MsNameMap){0};
}

static uint32_t slot_of(const MsNameMap *map, MsSym key) {
    uint32_t slot = (uint32_t)(key * 2654435761u) & (map->cap - 1);
    while (map->vals[slot] != 0 && map->keys[slot] != key) {
        slot = (slot + 1) & (map->cap - 1);
    }
    return slot;
}

uint32_t ms_map_get(const MsNameMap *map, MsSym key) {
    if (map->cap == 0) {
        return MS_NONE;
    }
    const uint32_t slot = slot_of(map, key);
    return map->vals[slot] == 0 ? MS_NONE : map->vals[slot] - 1;
}

/* Doubles the slot count (16 at first) and re-inserts every entry. */
static void map_grow(MsNameMap *map) {
    const MsNameMap old = *map;
    const uint32_t cap = old.cap != 0 ? old.cap * 2 : 16;
    map->keys = calloc(cap, sizeof *map->keys);
    map->vals = calloc(cap, sizeof *map->vals);
    if (map->keys == NULL || map->vals == NULL) {
        ms_oom();
    }
    map->cap = cap;
    for (uint32_t i = 0; i < old.cap; i++) {
        if (old.vals[i] != 0) {
            const uint32_t slot = slot_of(map, old.keys[i]);
            map->keys[slot] = old.keys[i];
            map->vals[slot] = old.vals[i];
        }
    }
    free(old.keys);
    free(old.vals);
}

bool ms_map_add(MsNameMap *map, MsSym key, uint32_t val) {
    if (map->cap == 0 || (size_t)(map->count + 1) * 2 > map->cap) {
        map_grow(map);
    }
    const uint32_t slot = slot_of(map, key);
    if (map->vals[slot] != 0) {
        return false;
    }
    map->keys[slot] = key;
    map->vals[slot] = val + 1;
    map->count++;
    return true;
}

/* ---- MsCheck ---- */

void ms_check_init(MsCheck *c, MsNames *names) {
    *c = (MsCheck){0};
    c->names = names;
    ms_tys_init(&c->tys);
}

static void syms_free(MsSyms *syms) {
    free(syms->name);
    free(syms->id);
    free(syms->kind);
    free(syms->module);
    free(syms->native);
    free(syms->native_name);
    free(syms->is_exported);
    free(syms->decl);
    free(syms->ty);
    free(syms->nvars);
    *syms = (MsSyms){0};
}

void ms_check_free(MsCheck *c) {
    if (c->methods != NULL) {
        ms_methods_free(c->methods);
        free(c->methods);
    }
    ms_tys_free(&c->tys);
    syms_free(&c->syms);
    for (uint32_t i = 0; i < c->nmods; i++) {
        ms_map_free(&c->mods[i].scope);
        ms_map_free(&c->mods[i].names);
        free(c->mods[i].diags);
        free(c->mods[i].order);
    }
    free(c->mods);
    ms_map_free(&c->std_types);
    ms_map_free(&c->module_by_path);
    ms_map_free(&c->primitives);
    free(c->defs);
    for (uint32_t i = 0; i < c->var_info_cap; i++) {
        free(c->var_info[i].bounds);
    }
    free(c->var_info);
    ms_arena_free(&c->arena);
    *c = (MsCheck){0};
}

MsModId ms_module_add(MsCheck *c, MsSym path, const MsModule *syntax) {
    if (c->nmods == c->mods_cap) {
        c->mods_cap = ms_capacity_for(c->mods_cap, c->nmods + 1);
        c->mods = ms_array_resize(c->mods, c->mods_cap, sizeof *c->mods);
    }
    c->mods[c->nmods] = (MsModuleRow){.path = path, .syntax = syntax};
    (void)ms_map_add(&c->module_by_path, path, c->nmods);
    return c->nmods++;
}

/* Makes room for one more symbol in every column. */
static void syms_reserve(MsSyms *syms) {
    if (syms->count < syms->cap) {
        return;
    }
    const uint32_t cap = ms_capacity_for(syms->cap, syms->count + 1);
    syms->name = ms_array_resize(syms->name, cap, sizeof *syms->name);
    syms->id = ms_array_resize(syms->id, cap, sizeof *syms->id);
    syms->kind = ms_array_resize(syms->kind, cap, sizeof *syms->kind);
    syms->module = ms_array_resize(syms->module, cap, sizeof *syms->module);
    syms->native = ms_array_resize(syms->native, cap, sizeof *syms->native);
    syms->native_name = ms_array_resize(syms->native_name, cap, sizeof *syms->native_name);
    syms->is_exported = ms_array_resize(syms->is_exported, cap, sizeof *syms->is_exported);
    syms->decl = ms_array_resize(syms->decl, cap, sizeof(const MsDecl *)); // NOLINT(bugprone-sizeof-expression): a column of declaration pointers
    syms->ty = ms_array_resize(syms->ty, cap, sizeof *syms->ty);
    syms->nvars = ms_array_resize(syms->nvars, cap, sizeof *syms->nvars);
    syms->cap = cap;
}

MsSymId ms_sym_new(MsCheck *c, MsModId module, const MsSymSpec *spec) {
    MsSyms *syms = &c->syms;
    syms_reserve(syms);
    const MsSymId id = syms->count++;
    syms->name[id] = spec->name;
    syms->id[id] = spec->id;
    syms->kind[id] = spec->kind;
    syms->module[id] = module;
    syms->native[id] = spec->native;
    syms->native_name[id] = spec->native_name;
    syms->is_exported[id] = spec->is_exported;
    syms->decl[id] = spec->decl;
    syms->ty[id] = MS_TY_NONE;
    syms->nvars[id] = spec->nvars;
    return id;
}

MsSymId ms_sym_add(MsCheck *c, MsModId module, const MsSymSpec *spec) {
    MsModuleRow *row = &c->mods[module];
    if (ms_map_get(&row->scope, spec->name) != MS_NONE) {
        return MS_NONE;
    }
    const MsSymId id = ms_sym_new(c, module, spec);
    /* The scope lists every symbol the module declares; `is_exported` says which importers see. */
    (void)ms_map_add(&row->scope, spec->name, id);
    row->order = ms_array_resize(row->order, row->norder + 1, sizeof *row->order);
    row->order[row->norder++] = id;
    return id;
}

MsSym ms_decl_name(const MsDecl *d) {
    switch ((MsDeclKind)d->kind) {
    case MS_D_FN: return d->u.fn.name;
    case MS_D_CONST: return d->u.konst.name;
    case MS_D_TYPE: return d->u.type.name;
    case MS_D_ENUM: return d->u.enumeration.name;
    case MS_D_ALIAS: return d->u.alias.name;
    case MS_D_INTERFACE: return d->u.iface.name;
    case MS_D_IMPL:
    case MS_D_TEST: return 0;
    }
    return 0;
}

uint32_t ms_decl_nvars(const MsDecl *d) {
    switch ((MsDeclKind)d->kind) {
    case MS_D_FN: return d->u.fn.type_params.len;
    case MS_D_TYPE: return d->u.type.type_params.len;
    case MS_D_ENUM: return d->u.enumeration.type_params.len;
    case MS_D_ALIAS: return d->u.alias.type_params.len;
    case MS_D_INTERFACE: return d->u.iface.type_params.len;
    case MS_D_CONST:
    case MS_D_IMPL:
    case MS_D_TEST: return 0;
    }
    return 0;
}

MsDef *ms_def(MsCheck *c, MsSymId sym) {
    if (sym >= c->defs_cap) {
        const uint32_t old = c->defs_cap;
        c->defs_cap = ms_capacity_for(c->defs_cap, sym + 1);
        c->defs = ms_array_resize(c->defs, c->defs_cap, sizeof *c->defs);
        memset(c->defs + old, 0, (size_t)(c->defs_cap - old) * sizeof *c->defs);
    }
    return &c->defs[sym];
}

MsVarInfo *ms_var_info(MsCheck *c, MsTy ty) {
    if (ty >= c->var_info_cap) {
        const uint32_t old = c->var_info_cap;
        c->var_info_cap = ms_capacity_for(c->var_info_cap, ty + 1);
        c->var_info = ms_array_resize(c->var_info, c->var_info_cap, sizeof *c->var_info);
        memset(c->var_info + old, 0, (size_t)(c->var_info_cap - old) * sizeof *c->var_info);
    }
    return &c->var_info[ty];
}
