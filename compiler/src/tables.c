/* Name maps, symbol columns and the module list. */
#include <stdlib.h>
#include <string.h>

#include "ms/tables.h"

/* ---- MsNameMap ---- */

void ms_map_free(MsNameMap *m) {
    free(m->keys);
    free(m->vals);
    memset(m, 0, sizeof *m);
}

static uint32_t slot_of(const MsNameMap *m, MsSym key) {
    uint32_t i = (uint32_t)(key * 2654435761u) & (m->cap - 1);
    while (m->vals[i] != 0 && m->keys[i] != key) {
        i = (i + 1) & (m->cap - 1);
    }
    return i;
}

uint32_t ms_map_get(const MsNameMap *m, MsSym key) {
    if (m->cap == 0) {
        return MS_NONE;
    }
    uint32_t i = slot_of(m, key);
    return m->vals[i] == 0 ? MS_NONE : m->vals[i] - 1;
}

bool ms_map_add(MsNameMap *m, MsSym key, uint32_t val) {
    if (m->cap == 0 || (size_t)(m->count + 1) * 2 > m->cap) {
        MsNameMap old = *m;
        uint32_t cap = old.cap ? old.cap * 2 : 16;
        m->keys = calloc(cap, sizeof *m->keys);
        m->vals = calloc(cap, sizeof *m->vals);
        if (m->keys == NULL || m->vals == NULL) {
            abort();
        }
        m->cap = cap;
        for (uint32_t i = 0; i < old.cap; i++) {
            if (old.vals[i] != 0) {
                uint32_t s = slot_of(m, old.keys[i]);
                m->keys[s] = old.keys[i];
                m->vals[s] = old.vals[i];
            }
        }
        free(old.keys);
        free(old.vals);
    }
    uint32_t i = slot_of(m, key);
    if (m->vals[i] != 0) {
        return false;
    }
    m->keys[i] = key;
    m->vals[i] = val + 1;
    m->count++;
    return true;
}

/* ---- MsCheck ---- */

void ms_check_init(MsCheck *c, MsNames *names) {
    memset(c, 0, sizeof *c);
    c->names = names;
    ms_tys_init(&c->tys);
}

void ms_check_free(MsCheck *c) {
    ms_tys_free(&c->tys);
    MsSyms *s = &c->syms;
    free(s->name); free(s->id); free(s->kind); free(s->module); free(s->native);
    free(s->native_name); free(s->is_exported); free(s->decl); free(s->ty); free(s->nvars);
    for (uint32_t i = 0; i < c->nmods; i++) {
        ms_map_free(&c->mods[i].scope);
        free(c->mods[i].order);
    }
    free(c->mods);
    ms_map_free(&c->std_types);
    ms_arena_free(&c->arena);
    memset(c, 0, sizeof *c);
}

MsModId ms_module_add(MsCheck *c, MsSym path, const MsModule *syntax) {
    if (c->nmods == c->mods_cap) {
        c->mods_cap = c->mods_cap ? c->mods_cap * 2 : 32;
        c->mods = realloc(c->mods, c->mods_cap * sizeof *c->mods);
        if (c->mods == NULL) {
            abort();
        }
    }
    MsModuleRow *m = &c->mods[c->nmods];
    memset(m, 0, sizeof *m);
    m->path = path;
    m->syntax = syntax;
    return c->nmods++;
}

#define COLUMN(field) s->field = realloc(s->field, c2 * sizeof *s->field); if (s->field == NULL) abort()

MsSymId ms_sym_add(MsCheck *c, MsModId module, MsSym name, MsSym id, MsSymKind kind,
                   MsNativeKind native, MsSym native_name, bool is_exported, const MsDecl *decl,
                   uint32_t nvars) {
    MsModuleRow *m = &c->mods[module];
    MsSyms *s = &c->syms;
    if (ms_map_get(&m->scope, name) != MS_NONE) {
        return MS_NONE;
    }
    if (s->count == s->cap) {
        uint32_t c2 = s->cap ? s->cap * 2 : 256;
        COLUMN(name); COLUMN(id); COLUMN(kind); COLUMN(module); COLUMN(native); COLUMN(native_name);
        COLUMN(is_exported); COLUMN(decl); COLUMN(ty); COLUMN(nvars);
        s->cap = c2;
    }
    MsSymId r = s->count++;
    s->name[r] = name;
    s->id[r] = id;
    s->kind[r] = kind;
    s->module[r] = module;
    s->native[r] = native;
    s->native_name[r] = native_name;
    s->is_exported[r] = is_exported;
    s->decl[r] = decl;
    s->ty[r] = MS_TY_NONE;
    s->nvars[r] = nvars;
    /* The module's own scope lists every symbol, exported or not; `is_exported` says which are visible to importers. */
    ms_map_add(&m->scope, name, r);
    m->order = realloc(m->order, (m->norder + 1) * sizeof *m->order);
    if (m->order == NULL) {
        abort();
    }
    m->order[m->norder++] = r;
    return r;
}
