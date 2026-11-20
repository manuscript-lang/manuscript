/* The bundled standard library: parse, split, register.
 * Follows the Rust loader (crates/ms-check/src/stdlib.rs, bundled.rs, build.rs) step for step on
 * what it records, so the tables compare equal; the structure around it is flat arrays. */
#include <stdlib.h>
#include <string.h>

#include "ms/parse.h"
#include "ms/stdlib.h"

static const char *const extension_modules[] = {
    "core.ms", "collections/collections.ms", "bytes.ms", "collections/ordering.ms", "string.ms",
    "math/decimal.ms",
};
static const char *const package_names[] = {"collections", "concurrency", "data", "io", "math", "net", "os"};

static bool sl_str_is(MsStr s, const char *lit) {
    size_t n = strlen(lit);
    return s.len == n && memcmp(s.ptr, lit, n) == 0;
}

MsStr ms_module_stem(MsStr file) {
    MsStr p = file;
    if (p.len >= 5 && memcmp(p.ptr, "@std/", 5) == 0) {
        p.ptr += 5;
        p.len -= 5;
    }
    if (p.len >= 3 && memcmp(p.ptr + p.len - 3, ".ms", 3) == 0) {
        p.len -= 3;
    }
    if (sl_str_is(p, "test/test")) {
        MsStr r = {"test", 4};
        return r;
    }
    if (sl_str_is(p, "test/bench")) {
        MsStr r = {"bench", 5};
        return r;
    }
    const char *slash = memchr(p.ptr, '/', p.len);
    if (slash != NULL) {
        size_t head = (size_t)(slash - p.ptr);
        for (size_t i = 0; i < sizeof package_names / sizeof *package_names; i++) {
            if (strlen(package_names[i]) == head && memcmp(package_names[i], p.ptr, head) == 0) {
                MsStr r = {slash + 1, (uint32_t)(p.len - head - 1)};
                return r;
            }
        }
    }
    return p;
}

/* ---- declaration helpers ---- */

static const MsTypeParams *decl_type_params(const MsDecl *d) {
    switch (d->kind) {
    case MS_D_FN: return &d->u.fn.type_params;
    case MS_D_TYPE: return &d->u.type.type_params;
    case MS_D_ENUM: return &d->u.enumeration.type_params;
    case MS_D_ALIAS: return &d->u.alias.type_params;
    case MS_D_INTERFACE: return &d->u.iface.type_params;
    default: return NULL;
    }
}

#define ANY_BODY(methods)                                                                          \
    do {                                                                                           \
        for (uint32_t i_ = 0; i_ < (methods).len; i_++) {                                          \
            if ((methods).ptr[i_]->func.body.len != 0) {                                           \
                return true;                                                                       \
            }                                                                                      \
        }                                                                                          \
        return false;                                                                              \
    } while (0)

/* A declaration that carries an implementation: a body, an `extern fn`, a constant or alias, a test. */
static bool decl_has_body(const MsDecl *d) {
    switch (d->kind) {
    case MS_D_FN: return d->u.fn.body.len != 0 || d->u.fn.external;
    case MS_D_CONST:
    case MS_D_ALIAS: return true;
    case MS_D_TEST: return d->u.test.body.len != 0;
    case MS_D_IMPL: ANY_BODY(d->u.impl.methods);
    default: return false;
    }
}

/* `has_implementation` of the Rust loader: aliases do not count, interface defaults do. */
static bool has_implementation(const MsDecl *d) {
    switch (d->kind) {
    case MS_D_FN: return d->u.fn.body.len != 0 || d->u.fn.external;
    case MS_D_CONST: return true;
    case MS_D_TEST: return d->u.test.body.len != 0;
    case MS_D_IMPL: ANY_BODY(d->u.impl.methods);
    case MS_D_INTERFACE: ANY_BODY(d->u.iface.methods);
    default: return false;
    }
}

static bool is_bodyless_inherent(const MsDecl *d) {
    if (d->kind != MS_D_IMPL || d->u.impl.contract != NULL) {
        return false;
    }
    for (uint32_t i = 0; i < d->u.impl.methods.len; i++) {
        if (d->u.impl.methods.ptr[i]->func.body.len == 0) {
            return true;
        }
    }
    return false;
}

static bool is_mixed(const MsModule *m) {
    bool bodyless = false, body = false;
    for (uint32_t i = 0; i < m->ndecls; i++) {
        bodyless |= is_bodyless_inherent(m->decls[i]);
        body |= decl_has_body(m->decls[i]);
    }
    return bodyless && body;
}

static bool is_pure_source(const MsModule *m) {
    if (is_mixed(m)) {
        return false;
    }
    bool body = false;
    for (uint32_t i = 0; i < m->ndecls; i++) {
        const MsDecl *d = m->decls[i];
        body |= decl_has_body(d);
        if (d->kind == MS_D_TYPE && d->u.type.external) {
            return false;
        }
    }
    return body;
}

/* ---- loading ---- */

typedef struct Loaded {
    MsStr path; /* `@std/<name>` */
    const char *name;
    MsModule mod;
    bool eager;
} Loaded;

typedef struct Loader {
    MsCheck *c;
    MsArena *syn;
    MsStr err;
    const MsStdFile *files;
    Loaded *loaded;
    uint32_t n;
} Loader;

static bool sl_fail(Loader *l, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static bool sl_fail(Loader *l, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    l->err = ms_arena_vfmt(l->syn, fmt, ap);
    va_end(ap);
    return false;
}

static MsStr sl_at(Loader *l, MsStr file, MsPos p) {
    return ms_arena_fmt(l->syn, "%.*s:%u:%u", (int)file.len, file.ptr, p.line, p.column);
}

static int by_name(const void *a, const void *b) {
    return strcmp(((const MsStdFile *)a)->name, ((const MsStdFile *)b)->name);
}

static bool is_extension(const char *name) {
    for (size_t i = 0; i < sizeof extension_modules / sizeof *extension_modules; i++) {
        if (strcmp(extension_modules[i], name) == 0) {
            return true;
        }
    }
    return false;
}

/* Modules loaded with the standard declarations: everything that is not pure source, the
 * extension modules, and what they import (build.rs `eager_modules`). */
static void mark_eager(Loader *l) {
    uint32_t *stack = malloc(sizeof *stack * (l->n * 8 + 8));
    uint32_t top = 0;
    for (uint32_t i = 0; i < l->n; i++) {
        if (is_extension(l->loaded[i].name) || !is_pure_source(&l->loaded[i].mod)) {
            stack[top++] = i;
        }
    }
    while (top != 0) {
        uint32_t i = stack[--top];
        if (l->loaded[i].eager) {
            continue;
        }
        l->loaded[i].eager = true;
        const MsModule *m = &l->loaded[i].mod;
        for (uint32_t k = 0; k < m->nimports; k++) {
            MsStr p = m->imports[k].path;
            if (p.len > 5 && memcmp(p.ptr, "@std/", 5) == 0) {
                p.ptr += 5;
                p.len -= 5;
            }
            for (uint32_t j = 0; j < l->n; j++) {
                if (sl_str_is(p, l->loaded[j].name) && top < l->n * 8 + 8) {
                    stack[top++] = j;
                }
            }
        }
    }
    free(stack);
}

static MsSym intern_str(Loader *l, MsStr s) { return ms_intern(l->c->names, s.ptr, s.len); }

static MsSym intern_fmt(Loader *l, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static MsSym intern_fmt(Loader *l, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    MsStr s = ms_arena_vfmt(l->syn, fmt, ap);
    va_end(ap);
    return intern_str(l, s);
}

/* The bare type of a nominal symbol: variables are filled in by `declare_identities`. */
/* The kind of type a nominal declaration makes. */
static bool is_nominal(const MsDecl *d) {
    return d->kind == MS_D_TYPE || d->kind == MS_D_ENUM || d->kind == MS_D_INTERFACE;
}

static MsKind nominal_kind(const MsDecl *d) {
    switch ((MsDeclKind)d->kind) {
    case MS_D_ENUM: return MS_K_ALTERNATIVE;
    case MS_D_INTERFACE: return MS_K_CONTRACT;
    case MS_D_FN:
    case MS_D_CONST:
    case MS_D_TYPE:
    case MS_D_ALIAS:
    case MS_D_IMPL:
    case MS_D_TEST: return MS_K_TYPE;
    }
    return MS_K_TYPE;
}

static MsTy nominal_type(Loader *l, MsSymId s, MsKind kind, MsBuiltin builtin) {
    MsCheck *c = l->c;
    MsTyDesc d = {0};
    d.name = c->syms.name[s];
    d.id = c->syms.id[s];
    d.kind = kind;
    d.builtin = builtin;
    d.def = s + 1;
    return ms_ty_intern(&c->tys, &d);
}

static bool register_extern_type(Loader *l, MsModId m, const MsDecl *d) {
    MsCheck *c = l->c;
    MsStr file = ms_name(c->names, c->mods[m].path);
    if (d->u.type.type_params.len != 0) {
        return sl_fail(l, "extern types cannot be generic yet: %.*s", (int)sl_at(l, file, d->pos).len,
                    sl_at(l, file, d->pos).ptr);
    }
    MsSym name = d->u.type.name;
    MsSym id = intern_fmt(l, "@std/%.*s", (int)ms_name(c->names, name).len, ms_name(c->names, name).ptr);
    if (ms_map_get(&c->std_types, name) != MS_NONE) {
        return sl_fail(l, "duplicate standard type %.*s", (int)ms_name(c->names, name).len,
                    ms_name(c->names, name).ptr);
    }
    const MsSymSpec spec = {.name = name,
                            .id = id,
                            .kind = MS_SYM_TYPE,
                            .native = MS_NATIVE_BUILTIN,
                            .native_name = name,
                            .is_exported = d->is_exported,
                            .decl = d};
    MsSymId s = ms_sym_add(c, m, &spec);
    if (s == MS_NONE) {
        return sl_fail(l, "duplicate standard declaration %.*s", (int)sl_at(l, file, d->pos).len, sl_at(l, file, d->pos).ptr);
    }
    MsBuiltin b = ms_builtin_from_id(ms_name(c->names, id));
    if (b == MS_B_NONE) {
        b = ms_builtin_source(file, ms_name(c->names, name));
    }
    c->syms.ty[s] = nominal_type(l, s, MS_K_NATIVE, b);
    ms_map_add(&c->std_types, name, s);
    return true;
}

/* Source modules record their exported types so native modules can name them (stubs). */
static void register_source_stubs(Loader *l, MsModId m, const MsModule *mod) {
    MsCheck *c = l->c;
    MsStr file = ms_name(c->names, c->mods[m].path);
    MsStr stem = ms_module_stem(file);
    for (uint32_t i = 0; i < mod->ndecls; i++) {
        const MsDecl *d = mod->decls[i];
        bool nominal = d->kind == MS_D_TYPE || d->kind == MS_D_ENUM || d->kind == MS_D_INTERFACE;
        if (!nominal || !d->is_exported || (d->kind == MS_D_TYPE && d->u.type.external)) {
            continue;
        }
        MsSym name = ms_decl_name(d);
        MsStr nm = ms_name(c->names, name);
        MsSym id = intern_fmt(l, "standard_%.*s_symbol_%.*s", (int)stem.len, stem.ptr, (int)nm.len, nm.ptr);
        const MsSymSpec spec = {.name = name,
                                .id = id,
                                .kind = MS_SYM_TYPE,
                                .native = MS_NATIVE_SOURCE,
                                .is_exported = true,
                                .decl = d,
                                .nvars = ms_decl_nvars(d)};
        MsSymId s = ms_sym_add(c, m, &spec);
        if (s == MS_NONE) {
            continue;
        }
        const MsKind kind = nominal_kind(d);
        MsBuiltin b = ms_builtin_source(file, nm);
        MsTyDesc td = {0};
        td.name = name;
        td.id = intern_fmt(l, "module/%.*s#%.*s", (int)file.len, file.ptr, (int)nm.len, nm.ptr);
        td.kind = kind;
        td.builtin = b;
        td.def = s + 1;
        c->syms.ty[s] = ms_ty_intern(&c->tys, &td);
    }
}

/* A module with bodies is checked like user code; the loader registers only its `extern type`s and
 * the exported types native modules may name. */
static bool register_source_module(Loader *l, MsModId m, const MsModule *mod) {
    l->c->mods[m].source = true;
    for (uint32_t i = 0; i < mod->ndecls; i++) {
        const MsDecl *d = mod->decls[i];
        if (d->kind == MS_D_TYPE && d->u.type.external && !register_extern_type(l, m, d)) {
            return false;
        }
    }
    register_source_stubs(l, m, mod);
    return true;
}

static bool fail_at(Loader *l, const char *what, MsStr file, MsPos pos) {
    const MsStr where = sl_at(l, file, pos);
    return sl_fail(l, "%s: %.*s", what, (int)where.len, where.ptr);
}

/* The Rust loader's rejection of a native declaration that carries a body. */
static bool check_native_decl(Loader *l, MsStr file, const MsDecl *d) {
    if (d->kind == MS_D_TEST) {
        return fail_at(l, "standard declarations cannot contain implementation bodies", file, d->pos);
    }
    if (has_implementation(d)) {
        return fail_at(l, "native declarations must not have bodies", file, d->pos);
    }
    return true;
}

/* An `impl` of a native module may declare operations but no bodies. */
static bool check_native_impl(Loader *l, MsStr file, const MsDecl *d) {
    const MsMethod *const *methods = (const MsMethod *const *)d->u.impl.methods.ptr;
    for (uint32_t i = 0; i < d->u.impl.methods.len; i++) {
        if (methods[i]->func.body.len != 0) {
            return fail_at(l, "native implementations must not have bodies", file, methods[i]->pos);
        }
    }
    return true;
}

/* The kind of the nominal type a native declaration makes; false for a function, constant or alias. */
static bool native_nominal_kind(const MsDecl *d, MsKind *kind) {
    if (!is_nominal(d)) {
        return false;
    }
    const bool external = d->kind == MS_D_TYPE && d->u.type.external;
    *kind = external ? MS_K_NATIVE : nominal_kind(d);
    return true;
}

/* A native function is `module/name`; a native type is `@std/Name`. */
static MsSym native_binding(Loader *l, const MsDecl *d, MsStr stem, MsSym *id) {
    const MsCheck *c = l->c;
    const MsStr name = ms_name(c->names, ms_decl_name(d));
    if (d->kind != MS_D_FN) {
        *id = intern_fmt(l, "@std/%.*s", (int)name.len, name.ptr);
        return ms_decl_name(d);
    }
    const MsSym binding = intern_fmt(l, "%.*s/%.*s", (int)stem.len, stem.ptr, (int)name.len, name.ptr);
    const MsStr text = ms_name(c->names, binding);
    *id = intern_fmt(l, "@std/%.*s", (int)text.len, text.ptr);
    return binding;
}

static bool register_native_decl(Loader *l, MsModId m, MsStr stem, const MsDecl *d) {
    MsCheck *c = l->c;
    const MsStr file = ms_name(c->names, c->mods[m].path);
    const MsSym name = ms_decl_name(d);
    const MsStr name_text = ms_name(c->names, name);
    MsSym id = 0;
    const MsSym native_name = native_binding(l, d, stem, &id);
    const MsSymSpec spec = {.name = name,
                            .id = id,
                            .kind = d->kind == MS_D_FN ? MS_SYM_FN : MS_SYM_TYPE,
                            .native = MS_NATIVE_BUILTIN,
                            .native_name = native_name,
                            .is_exported = d->is_exported,
                            .decl = d,
                            .nvars = ms_decl_nvars(d)};
    const MsSymId sym = ms_sym_add(c, m, &spec);
    if (sym == MS_NONE) {
        return fail_at(l, "duplicate standard declaration", file, d->pos);
    }
    MsKind kind = MS_K_TYPE;
    if (!native_nominal_kind(d, &kind)) {
        return true;
    }
    if (ms_map_get(&c->std_types, name) != MS_NONE) {
        return sl_fail(l, "duplicate standard type %.*s", (int)name_text.len, name_text.ptr);
    }
    c->syms.ty[sym] = nominal_type(l, sym, kind, ms_builtin_from_id(ms_name(c->names, id)));
    (void)ms_map_add(&c->std_types, name, sym);
    return true;
}

static bool module_has_implementation(const MsModule *mod) {
    for (uint32_t i = 0; i < mod->ndecls; i++) {
        if (has_implementation(mod->decls[i])) {
            return true;
        }
    }
    return false;
}

static bool register_module(Loader *l, MsModId m, const MsModule *mod) {
    if (module_has_implementation(mod)) {
        return register_source_module(l, m, mod);
    }
    const MsCheck *c = l->c;
    const MsStr file = ms_name(c->names, c->mods[m].path);
    const MsStr stem = ms_module_stem(file);
    for (uint32_t i = 0; i < mod->ndecls; i++) {
        const MsDecl *d = mod->decls[i];
        const bool ok = d->kind == MS_D_IMPL ? check_native_impl(l, file, d)
                                              : check_native_decl(l, file, d) && register_native_decl(l, m, stem, d);
        if (!ok) {
            return false;
        }
    }
    return true;
}

/* Gives each native type its declared variables: the variable types are `<symbol id>/<name>`, and
 * the symbol's type becomes the declaration applied to them. */
static void declare_identities(Loader *l, MsModId m) {
    MsCheck *c = l->c;
    for (uint32_t i = 0; i < c->mods[m].norder; i++) {
        MsSymId s = c->mods[m].order[i];
        const MsDecl *d = c->syms.decl[s];
        const MsTypeParams *tp = d ? decl_type_params(d) : NULL;
        if (tp == NULL || tp->len == 0 || c->syms.native[s] != MS_NATIVE_BUILTIN) {
            continue;
        }
        MsTy vars[64];
        uint32_t n = tp->len < 64 ? tp->len : 64;
        MsStr sid = ms_name(c->names, c->syms.id[s]);
        for (uint32_t k = 0; k < n; k++) {
            MsStr pn = ms_name(c->names, tp->ptr[k]->name);
            MsTyDesc vd = {0};
            vd.name = tp->ptr[k]->name;
            vd.id = intern_fmt(l, "%.*s/%.*s", (int)sid.len, sid.ptr, (int)pn.len, pn.ptr);
            vd.kind = MS_K_VARIABLE;
            vars[k] = ms_ty_fresh(&c->tys, &vd);
        }
        if (c->syms.kind[s] == MS_SYM_TYPE && c->syms.ty[s] != MS_TY_NONE) {
            MsTyTable *t = &c->tys;
            MsTyDesc td = {t->name[c->syms.ty[s]], t->id[c->syms.ty[s]], (MsKind)t->kind[c->syms.ty[s]],
                           (MsBuiltin)t->builtin[c->syms.ty[s]], t->def[c->syms.ty[s]], vars, n, NULL, 0, MS_TY_NONE};
            c->syms.ty[s] = ms_ty_intern(t, &td);
        }
    }
}

static MsModule *half(Loader *l, const MsModule *of, const MsDecl **decls, uint32_t n) {
    MsModule *m = MS_NEW(l->syn, MsModule);
    *m = *of;
    m->decls = MS_NEW_N(l->syn, MsDecl *, n ? n : 1); // NOLINT(bugprone-sizeof-expression): an array of declaration pointers
    memcpy(m->decls, decls, n * sizeof *decls);   // NOLINT(bugprone-sizeof-expression): same array
    m->ndecls = n;
    return m;
}

static bool implements_all_with_body(const MsModule *m, MsSym name) {
    bool any = false;
    for (uint32_t i = 0; i < m->ndecls; i++) {
        const MsDecl *x = m->decls[i];
        if (x->kind == MS_D_IMPL && x->u.impl.contract != NULL && x->u.impl.contract->name == name) {
            any = true;
            if (!decl_has_body(x)) {
                return false;
            }
        }
    }
    return any;
}

bool ms_std_load(MsCheck *c, MsArena *syn, const MsStdFile *in, uint32_t nfiles, MsStr *err) {
    Loader l = {0};
    l.c = c;
    l.syn = syn;
    l.n = nfiles;
    MsStdFile *files = MS_NEW_N(syn, MsStdFile, nfiles ? nfiles : 1);
    memcpy(files, in, nfiles * sizeof *files);
    qsort(files, nfiles, sizeof *files, by_name);
    l.files = files;
    l.loaded = MS_NEW_N(syn, Loaded, nfiles ? nfiles : 1);
    memset(l.loaded, 0, sizeof *l.loaded * (nfiles ? nfiles : 1));
    for (uint32_t i = 0; i < nfiles; i++) {
        Loaded *ld = &l.loaded[i];
        ld->name = files[i].name;
        ld->path = ms_arena_fmt(syn, "@std/%s", files[i].name);
        MsDiag diag;
        if (!ms_parse(syn, c->names, files[i].text, files[i].len, &ld->mod, &diag)) {
            sl_fail(&l, "parse %.*s: %u:%u: %.*s", (int)ld->path.len, ld->path.ptr, diag.pos.line,
                 diag.pos.column, (int)diag.message.len, diag.message.ptr);
            *err = l.err;
            return false;
        }
    }
    mark_eager(&l);
    bool ok = true;
    for (uint32_t i = 0; i < nfiles && ok; i++) {
        Loaded *ld = &l.loaded[i];
        MsSym path = intern_str(&l, ld->path);
        if (!ld->eager) {
            /* A pure source module: recorded now, checked when a program first imports it. */
            MsModId m = ms_module_add(c, path, &ld->mod);
            c->mods[m].source = true;
            c->mods[m].text = (MsStr){files[i].text, (uint32_t)files[i].len};
            register_source_stubs(&l, m, &ld->mod);
            continue;
        }
        if (is_mixed(&ld->mod)) {
            const uint32_t room = ld->mod.ndecls + 1;
            const MsDecl **nat = MS_NEW_N(syn, const MsDecl *, room); // NOLINT(bugprone-sizeof-expression): an array of declaration pointers
            const MsDecl **src = MS_NEW_N(syn, const MsDecl *, room); // NOLINT(bugprone-sizeof-expression): same
            uint32_t nn = 0, ns = 0;
            for (uint32_t k = 0; k < ld->mod.ndecls; k++) {
                const MsDecl *d = ld->mod.decls[k];
                bool to_source = d->kind == MS_D_INTERFACE ? implements_all_with_body(&ld->mod, d->u.iface.name)
                                                          : decl_has_body(d);
                (to_source ? src : nat)[to_source ? ns++ : nn++] = d;
            }
            MsModule *nh = half(&l, &ld->mod, nat, nn);
            MsModule *sh = half(&l, &ld->mod, src, ns);
            MsModId nm = ms_module_add(c, path, nh);
            c->mods[nm].text = (MsStr){files[i].text, (uint32_t)files[i].len};
            ok = register_module(&l, nm, nh);
            if (ok) {
                MsStr sp = ms_arena_fmt(syn, "%.*s+source", (int)ld->path.len, ld->path.ptr);
                MsModId sm = ms_module_add(c, intern_str(&l, sp), sh);
                ok = register_module(&l, sm, sh);
                c->mods[sm].source = true;
                c->mods[sm].text = (MsStr){files[i].text, (uint32_t)files[i].len};
            }
            continue;
        }
        MsModId m = ms_module_add(c, path, &ld->mod);
        c->mods[m].text = (MsStr){files[i].text, (uint32_t)files[i].len};
        ok = register_module(&l, m, &ld->mod);
    }
    if (ok) {
        for (uint32_t m = 0; m < c->nmods; m++) {
            if (!c->mods[m].source) {
                declare_identities(&l, m);
            }
        }
    }
    *err = l.err;
    return ok;
}
