/* Name resolution of a module's top level; see ms/check.h. A port of begin_module,
 * add_standard_prelude, import_symbols, declare_symbols and add_symbol of
 * crates/ms-check/src/checker.rs. */
#include <string.h>

#include "ms/text.h"
#include "ms/check.h"
#include "ms/import_hints.h"
#include "ms/prelude_fix.h"

enum { CONSTRUCTOR_COUNT = 4 };

static const char *const scope_constructors[CONSTRUCTOR_COUNT] = {"some", "none", "ok", "error"};

static const char scope_std_prefix[] = "@std/";
static const char scope_internal_prefix[] = "@std/internal/";
static const char scope_core_path[] = "@std/core.ms";
static const char scope_range_path[] = "@std/collections/collections.ms";
static const char scope_twin_suffix[] = "+source";

/* ---- text helpers ---- */

static bool scope_in(MsStr s, const char *const *list, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (ms_text_is(s, list[i])) {
            return true;
        }
    }
    return false;
}

/* `@std/core.ms+source` is the source half of `@std/core.ms`: the same file to the checker. */
static MsStr scope_file_of(const MsCheck *c, MsModId module) {
    MsStr path = ms_name(c->names, c->mods[module].path);
    const size_t suffix = strlen(scope_twin_suffix);
    if (path.len > suffix && memcmp(path.ptr + path.len - suffix, scope_twin_suffix, suffix) == 0) {
        path.len -= (uint32_t)suffix;
    }
    return path;
}

static bool scope_same_file(const MsCheck *c, MsModId a, MsModId b) {
    if (a == MS_NONE || b == MS_NONE) {
        return a == b;
    }
    const MsStr x = scope_file_of(c, a);
    const MsStr y = scope_file_of(c, b);
    return x.len == y.len && memcmp(x.ptr, y.ptr, x.len) == 0;
}

static MsSym scope_intern_text(MsCheck *c, MsStr s) {
    return ms_intern(c->names, s.ptr, s.len);
}

MsModId ms_module_find(const MsCheck *c, MsSym path) {
    return ms_map_get(&c->module_by_path, path);
}

/* ---- diagnostics ---- */

void ms_report(MsCheck *c, MsModId module, const MsCheckDiag *diag) {
    MsModuleRow *row = &c->mods[module];
    /* Once an unknown type is reported, `<invalid>` in a later message only restates it. */
    if (row->unknown_type && diag->phase != MS_PHASE_RESOLUTION &&
        ms_text_contains(diag->diag.message, "<invalid>")) {
        return;
    }
    /* One message at one position is reported once (the Rust checker's `unique_diagnostics`). */
    for (uint32_t i = 0; i < row->ndiags; i++) {
        const MsDiag *old = &row->diags[i].diag;
        if (old->pos.offset == diag->diag.pos.offset && old->pos.line == diag->diag.pos.line &&
            old->pos.column == diag->diag.pos.column && old->message.len == diag->diag.message.len &&
            memcmp(old->message.ptr, diag->diag.message.ptr, old->message.len) == 0) {
            return;
        }
    }
    if (row->ndiags == row->diags_cap) {
        row->diags_cap = ms_capacity_for(row->diags_cap, row->ndiags + 1);
        row->diags = ms_array_resize(row->diags, row->diags_cap, sizeof *row->diags);
    }
    row->diags[row->ndiags++] = *diag;
}

static void scope_report_at(MsCheck *c, MsModId module, MsPos pos, MsStr message) {
    const MsCheckDiag diag = {.diag = {.pos = pos, .message = message}, .phase = MS_PHASE_RESOLUTION};
    ms_report(c, module, &diag);
}

/* ---- the prelude ---- */

/* Whether `sym` is a declaration every module sees: `print`, or one of the prelude types. */
bool ms_is_prelude_symbol(const MsCheck *c, MsSymId sym) {
    const MsStr name = ms_name(c->names, c->syms.name[sym]);
    const MsModId owner = c->syms.module[sym];
    if (owner != MS_NONE && ms_text_is(name, "print")) {
        /* The path as written: the source half of a mixed file is not `@std/core.ms` itself. */
        if (ms_text_is(ms_name(c->names, c->mods[owner].path), scope_core_path)) {
            return true;
        }
    }
    if (!scope_in(name, ms_prelude_names, ms_prelude_name_count)) {
        return false;
    }
    return ms_map_get(&c->std_types, c->syms.name[sym]) == sym;
}

/* The declaration `name` of the native module `path`, else MS_NONE. */
static MsSymId scope_native_symbol(MsCheck *c, const char *path, MsSym name) {
    const MsModId module = ms_module_find(c, ms_intern_cstr(c->names, path));
    if (module == MS_NONE || c->mods[module].source) {
        return MS_NONE;
    }
    return ms_map_get(&c->mods[module].scope, name);
}

/* The declaration `name` of standard module `path`: a native or stub symbol, else a symbol of its
 * source half, which this declares on demand. MS_NONE when the module has none. */
static MsSymId scope_standard_symbol(MsCheck *c, MsStr path, MsSym name) {
    const MsModId module = ms_module_find(c, scope_intern_text(c, path));
    if (module == MS_NONE) {
        return MS_NONE;
    }
    if (c->mods[module].source) {
        ms_module_declare(c, module);
        return ms_map_get(&c->mods[module].scope, name);
    }
    const MsSymId native = ms_map_get(&c->mods[module].scope, name);
    if (native != MS_NONE) {
        return native;
    }
    const MsStr twin_path = ms_arena_fmt(&c->arena, "%.*s%s", (int)path.len, path.ptr, scope_twin_suffix);
    const MsModId twin = ms_module_find(c, scope_intern_text(c, twin_path));
    if (twin == MS_NONE) {
        return MS_NONE;
    }
    ms_module_declare(c, twin);
    return ms_map_get(&c->mods[twin].scope, name);
}

static bool scope_imports_name(const MsModule *module, MsSym name) {
    for (uint32_t i = 0; i < module->nimports; i++) {
        if (module->imports[i].name == name && ms_text_starts_with(module->imports[i].path, scope_std_prefix)) {
            return true;
        }
    }
    return false;
}

/* `some`, `none`, `ok` and `error` always mean the prelude's cases. */
static void scope_reject_constructor_names(MsCheck *c, MsModId module) {
    const MsModule *syntax = c->mods[module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        const MsSym name = ms_decl_name(d);
        if (name == 0) {
            continue;
        }
        const MsStr text = ms_name(c->names, name);
        if (scope_in(text, scope_constructors, CONSTRUCTOR_COUNT)) {
            scope_report_at(c, module, d->pos,
                      ms_arena_fmt(&c->arena,
                                   "declaration %.*s reuses a prelude constructor name; rename it, because %.*s "
                                   "always refers to the prelude case",
                                   (int)text.len, text.ptr, (int)text.len, text.ptr));
        }
    }
}

static void scope_declare_primitives(MsCheck *c) {
    if (c->primitives.count != 0) {
        return;
    }
    for (size_t i = 0; i < ms_primitive_count(); i++) {
        const char *written = ms_primitive_name(i);
        /* `Int64` and `Float64` are the default widths: the same type as `Int` and `Float`. */
        const char *identity = written;
        if (strcmp(written, "Int64") == 0) {
            identity = "Int";
        } else if (strcmp(written, "Float64") == 0) {
            identity = "Float";
        }
        const MsSym identity_name = ms_intern_cstr(c->names, identity);
        const MsSymSpec spec = {.name = ms_intern_cstr(c->names, written),
                                .id = identity_name,
                                .kind = MS_SYM_TYPE,
                                .native = MS_NATIVE_SOURCE,
                                .is_exported = true};
        const MsSymId sym = ms_sym_new(c, MS_NONE, &spec);
        const MsTyDesc type = {.name = identity_name,
                               .id = identity_name,
                               .kind = MS_K_PRIMITIVE,
                               .builtin = ms_builtin_primitive(ms_name(c->names, identity_name))};
        c->syms.ty[sym] = ms_ty_intern(&c->tys, &type);
        (void)ms_map_add(&c->primitives, spec.name, sym);
    }
}

/* The prelude's names for the module: `..`, `print`, and the prelude types unless imported. */
static void scope_add_prelude(MsCheck *c, MsModId module) {
    MsNameMap *names = &c->mods[module].names;
    const MsModule *syntax = c->mods[module].syntax;
    const bool standard = ms_text_starts_with(ms_name(c->names, c->mods[module].path), scope_std_prefix);
    if (!standard) {
        scope_reject_constructor_names(c, module);
    }
    const MsSymId range = scope_native_symbol(c, scope_range_path, ms_intern_cstr(c->names, "range"));
    if (range != MS_NONE) {
        (void)ms_map_add(names, ms_intern_cstr(c->names, ".."), range);
    }
    const MsSym print = ms_intern_cstr(c->names, "print");
    if (!standard && !scope_imports_name(syntax, print)) {
        const MsSymId symbol = scope_standard_symbol(c, (MsStr){scope_core_path, sizeof scope_core_path - 1}, print);
        if (symbol != MS_NONE) {
            (void)ms_map_add(names, print, symbol);
        }
    }
    for (size_t i = 0; i < ms_prelude_name_count; i++) {
        const MsSym name = ms_intern_cstr(c->names, ms_prelude_names[i]);
        const MsSymId symbol = ms_map_get(&c->std_types, name);
        if (symbol == MS_NONE || c->syms.module[symbol] == module || scope_imports_name(syntax, name)) {
            continue;
        }
        (void)ms_map_add(names, name, symbol);
    }
}

static void scope_begin_module(MsCheck *c, MsModId module) {
    scope_declare_primitives(c);
    for (size_t i = 0; i < ms_primitive_count(); i++) {
        const MsSym name = ms_intern_cstr(c->names, ms_primitive_name(i));
        (void)ms_map_add(&c->mods[module].names, name, ms_map_get(&c->primitives, name));
    }
    scope_add_prelude(c, module);
}

/* ---- names ---- */

/* Binds `name` to `sym` in the module's scope, or says why it cannot be: the name is already a
 * prelude name, an import, a declaration or a primitive. */
static void scope_add_symbol(MsCheck *c, MsModId module, MsSym name, MsSymId sym, MsPos pos) {
    const MsSymId existing = ms_map_get(&c->mods[module].names, name);
    if (existing == MS_NONE) {
        (void)ms_map_add(&c->mods[module].names, name, sym);
        return;
    }
    const MsStr text = ms_name(c->names, name);
    const bool existing_is_prelude = ms_is_prelude_symbol(c, existing);
    if (existing_is_prelude && !ms_is_prelude_symbol(c, sym) && !scope_same_file(c, c->syms.module[existing], module)) {
        scope_report_at(c, module, pos,
                  ms_arena_fmt(&c->arena,
                               "declaration %.*s reuses a prelude name; rename it, because %.*s always refers to the "
                               "standard declaration",
                               (int)text.len, text.ptr, (int)text.len, text.ptr));
        return;
    }
    if (c->syms.module[sym] != module && !existing_is_prelude) {
        scope_report_at(c, module, pos,
                  ms_arena_fmt(&c->arena,
                               "import %.*s collides with another %.*s in this module; an import cannot be renamed, so "
                               "import only one %.*s here and wrap the other in a small module that exports it under "
                               "a new name",
                               (int)text.len, text.ptr, (int)text.len, text.ptr, (int)text.len, text.ptr));
        return;
    }
    scope_report_at(c, module, pos,
              ms_arena_fmt(&c->arena,
                           "duplicate or intrinsic name %.*s; this name is already declared, imported, or built in, so "
                           "rename one of them",
                           (int)text.len, text.ptr));
}

/* ---- imports ---- */

static bool scope_is_internal_path(MsStr path) {
    return ms_text_starts_with(path, scope_internal_prefix);
}

/* The symbol an import of `item` names, when the standard library has one. */
static MsSymId scope_import_target(MsCheck *c, const MsImport *item) {
    const MsModId module = ms_module_find(c, scope_intern_text(c, item->path));
    if (module == MS_NONE) {
        return MS_NONE;
    }
    const MsSymId found = scope_standard_symbol(c, item->path, item->name);
    if (found == MS_NONE || !scope_same_file(c, c->syms.module[found], module)) {
        return MS_NONE;
    }
    return found;
}

/* An import of a name every module already sees, with the exact-source edit that removes it (when the module's
 * source is known: `ms_program_check_module` records it). */
static void scope_report_redundant_import(MsCheck *c, MsModId module, const MsImport *item) {
    const MsStr name = ms_name(c->names, item->name);
    MsPos end = item->name_pos;
    end.offset += name.len;
    end.column += name.len;
    MsCheckDiag diag = {.diag = {.pos = item->name_pos, .has_end = true, .end = end,
                                 .message = ms_prelude_import_message(&c->arena, name)},
                        .phase = MS_PHASE_RESOLUTION};
    const MsModule *syntax = c->mods[module].syntax;
    MsFix fix;
    if (c->mods[module].text.len > 0 &&
        ms_prelude_import_fix(&c->arena, c->mods[module].text, syntax->imports, syntax->nimports, item, &fix)) {
        diag.diag.has_fix = true;
        diag.diag.fix_pos = fix.pos;
        diag.diag.fix_end = fix.end;
        diag.diag.replacement = fix.replacement;
    }
    ms_report(c, module, &diag);
}

static void scope_report_failed_import(MsCheck *c, MsModId module, const MsImport *item, bool in_standard) {
    const uint32_t width = ms_name(c->names, item->name).len;
    MsPos end = item->name_pos;
    end.offset += width;
    end.column += width;
    const MsStr message = ms_export_message(&c->arena, c, item, in_standard, NULL);
    const MsCheckDiag diag = {.diag = {.pos = item->name_pos, .has_end = true, .end = end, .message = message},
                              .phase = MS_PHASE_RESOLUTION};
    ms_report(c, module, &diag);
}

void ms_module_set_imports(MsCheck *c, MsModId module, const MsModId *targets) {
    c->mods[module].import_targets = targets;
}

/* What an import of a project module can see there: the names it exports, and whether the name
 * asked for is declared without `export`. */
static MsExportList scope_local_exports(MsCheck *c, MsModId target, MsSym wanted) {
    const MsModuleRow *row = &c->mods[target];
    MsStr *names = MS_NEW_N(&c->arena, MsStr, row->norder + 1);
    MsExportList list = {.names = names};
    for (uint32_t i = 0; i < row->norder; i++) {
        const MsSymId sym = row->order[i];
        if (c->syms.module[sym] != target || c->syms.decl[sym] == NULL) {
            continue;
        }
        if (c->syms.is_exported[sym]) {
            names[list.count++] = ms_name(c->names, c->syms.name[sym]);
        } else if (c->syms.name[sym] == wanted) {
            list.name_is_private = true;
        }
    }
    return list;
}

/* An import of a project module: the exported declaration of that name, or the diagnostic. */
static void scope_import_local(MsCheck *c, MsModId module, const MsImport *item, MsModId target) {
    ms_module_declare(c, target);
    const MsSymId found = ms_map_get(&c->mods[target].scope, item->name);
    if (found != MS_NONE && c->syms.module[found] == target && c->syms.decl[found] != NULL &&
        c->syms.is_exported[found]) {
        ms_module_resolve_types(c, target); // the importer's signatures name the target's types
        scope_add_symbol(c, module, item->name, found, item->name_pos);
        return;
    }
    const MsExportList local = scope_local_exports(c, target, item->name);
    const uint32_t width = ms_name(c->names, item->name).len;
    MsPos end = item->name_pos;
    end.offset += width;
    end.column += width;
    const MsStr message = ms_export_message(&c->arena, c, item, false, &local);
    const MsCheckDiag diag = {.diag = {.pos = item->name_pos, .has_end = true, .end = end, .message = message},
                              .phase = MS_PHASE_RESOLUTION};
    ms_report(c, module, &diag);
}

static void scope_import_symbols(MsCheck *c, MsModId module) {
    const MsModule *syntax = c->mods[module].syntax;
    const MsStr own_path = ms_name(c->names, c->mods[module].path);
    const bool in_standard = ms_text_starts_with(own_path, scope_std_prefix);
    for (uint32_t i = 0; i < syntax->nimports; i++) {
        const MsImport *item = &syntax->imports[i];
        if (!ms_text_starts_with(item->path, scope_std_prefix)) {
            // A project module resolves through the graph's targets; without them the import stays unresolved.
            const MsModId target = c->mods[module].import_targets == NULL ? MS_NONE : c->mods[module].import_targets[i];
            if (target != MS_NONE) {
                scope_import_local(c, module, item, target);
            }
            continue;
        }
        const MsSymId found = scope_import_target(c, item);
        const bool hidden = scope_is_internal_path(item->path) && !in_standard;
        const bool host = scope_is_internal_path(own_path);
        if (found == MS_NONE || hidden || !(c->syms.is_exported[found] || host)) {
            scope_report_failed_import(c, module, item, in_standard);
            continue;
        }
        if (ms_is_prelude_symbol(c, found)) {
            scope_report_redundant_import(c, module, item);
        }
        scope_add_symbol(c, module, item->name, found, item->name_pos);
    }
}

/* ---- declarations ---- */

/* A symbol the loader registered for this very declaration (an `extern type` or an exported
 * type of a bundled source module), or MS_NONE. */
static MsSymId scope_registered_symbol(const MsCheck *c, MsModId module, const MsDecl *d, MsSym name) {
    MsSymId found = c->mods[module].source ? ms_map_get(&c->mods[module].scope, name) : MS_NONE;
    if (found == MS_NONE) {
        found = ms_map_get(&c->std_types, name); // a native module's type is registered by the loader
    }
    return found != MS_NONE && c->syms.decl[found] == d ? found : MS_NONE;
}

static MsSymId scope_declare_one(MsCheck *c, MsModId module, const MsDecl *d, MsSym name) {
    const MsStr path = ms_name(c->names, c->mods[module].path);
    const MsStr text = ms_name(c->names, name);
    const bool external_fn = d->kind == MS_D_FN && d->u.fn.external;
    const MsStr identity = ms_arena_fmt(&c->arena, "%.*s#%.*s", (int)path.len, path.ptr, (int)text.len, text.ptr);
    const MsSymSpec spec = {.name = name,
                            .id = scope_intern_text(c, identity),
                            .kind = ms_decl_symbol_kind(d),
                            .native = external_fn ? MS_NATIVE_EXTERN : MS_NATIVE_SOURCE,
                            .native_name = external_fn ? name : 0,
                            .is_exported = d->is_exported,
                            .decl = d,
                            .nvars = ms_decl_nvars(d)};
    const MsSymId added = ms_sym_add(c, module, &spec);
    /* A repeated name still gets a row, which `add_symbol` then refuses to bind. */
    return added != MS_NONE ? added : ms_sym_new(c, module, &spec);
}

static void scope_declare_symbols(MsCheck *c, MsModId module) {
    const MsModule *syntax = c->mods[module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        const MsSym name = ms_decl_name(d);
        if (d->kind == MS_D_IMPL || d->kind == MS_D_TEST || name == 0) {
            continue;
        }
        MsSymId sym = MS_NONE;
        const bool opaque = d->kind == MS_D_TYPE && d->u.type.external;
        if (opaque || ms_decl_is_nominal(d)) {
            sym = scope_registered_symbol(c, module, d, name);
        }
        if (sym == MS_NONE) {
            sym = scope_declare_one(c, module, d, name);
        }
        scope_add_symbol(c, module, name, sym, d->pos);
    }
}

void ms_module_declare(MsCheck *c, MsModId module) {
    if (c->mods[module].declared) {
        return;
    }
    c->mods[module].declared = true;
    scope_begin_module(c, module);
    scope_import_symbols(c, module);
    scope_declare_symbols(c, module);
}
