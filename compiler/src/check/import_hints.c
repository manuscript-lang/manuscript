/* Import diagnostics over the standard library tables; see ms/import_hints.h. A port of
 * import_hint, type_import_hint and export_message of crates/ms-check/src/hints.rs. */
#include <string.h>

#include "ms/check.h"
#include "ms/text.h"
#include "ms/hints.h"
#include "ms/import_hints.h"
#include "ms/stdlib.h"

#define STD_PREFIX "@std/"
#define HINT_LIST_LIMIT 12

/* Source-backed prelude names (STANDARD_PRELUDE_NAMES) and functions (STANDARD_PRELUDE_FUNCTIONS). */
static const char *const prelude_names[] = {"Equal", "Stringable", "Comparable", "Hashable", "Clonable",
                                            "Optional", "Result", "Error", "List", "Map", "Set",
                                            "ListEntry", "MapEntry"};
static const char *const prelude_function_module = "@std/core.ms";
static const char *const prelude_function = "print";

static MsStr cstr(const char *s) {
    return (MsStr){s, (uint32_t)strlen(s)};
}

static MsStr after_last_slash(MsStr s) {
    for (uint32_t i = s.len; i > 0; i--) {
        if (s.ptr[i - 1] == '/') {
            return (MsStr){s.ptr + i, s.len - i};
        }
    }
    return s;
}

/* ---- modules and their exports ---- */

typedef struct Export {
    MsStr name;
    MsSymKind kind;
} Export;

static MsStr module_path(const MsCheck *c, MsModId m) {
    return ms_name(c->names, c->mods[m].path);
}

/* The row of the module with this path, or MS_NONE. */
static MsModId find_module(const MsCheck *c, MsStr path, bool source) {
    for (MsModId m = 0; m < c->nmods; m++) {
        if (c->mods[m].source == source && ms_str_equal(module_path(c, m), path)) {
            return m;
        }
    }
    return MS_NONE;
}

static bool is_native_module(const MsCheck *c, MsStr path) {
    return find_module(c, path, false) != MS_NONE;
}

static bool is_source_module(const MsCheck *c, MsStr path) {
    return find_module(c, path, true) != MS_NONE;
}

/* Every standard module path, sorted and without internal modules and `+source` halves. */
static size_t standard_module_names(MsArena *arena, const MsCheck *c, MsStr **out) {
    MsStr *paths = MS_NEW_N(arena, MsStr, (size_t)c->nmods + 1);
    size_t n = 0;
    for (MsModId m = 0; m < c->nmods; m++) {
        MsStr path = module_path(c, m);
        bool listed = ms_text_starts_with(path, STD_PREFIX) && !ms_text_starts_with(path, "@std/internal/") && !ms_text_ends_with(path, "+source");
        if (listed) {
            paths[n++] = path;
        }
    }
    return ms_unique_sorted(arena, paths, n, out);
}

static MsSym declared_name(const MsDecl *d) {
    switch ((MsDeclKind)d->kind) {
    case MS_D_FN:
        return d->u.fn.name;
    case MS_D_CONST:
        return d->u.konst.name;
    case MS_D_TYPE:
        return d->u.type.name;
    case MS_D_ENUM:
        return d->u.enumeration.name;
    case MS_D_ALIAS:
        return d->u.alias.name;
    case MS_D_INTERFACE:
        return d->u.iface.name;
    case MS_D_IMPL:
    case MS_D_TEST:
        return 0;
    }
    return 0;
}

static void add_export(MsBuf *list, MsStr name, MsSymKind kind) {
    for (size_t i = 0; i < MS_VEC_LEN(*list, Export); i++) {
        if (ms_str_equal(MS_VEC_AT(*list, Export, i).name, name)) {
            return;
        }
    }
    MS_VEC_PUSH(*list, Export, ((Export){name, kind}));
}

/* The exported declarations of a source module: the module checks to a symbol per declaration. */
static void add_source_exports(const MsCheck *c, MsBuf *list, MsModId m) {
    const MsModule *syntax = c->mods[m].syntax;
    for (uint32_t i = 0; syntax != NULL && i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        MsSym name = declared_name(d);
        if (d->is_exported && name != 0) {
            add_export(list, ms_name(c->names, name), ms_decl_symbol_kind(d));
        }
    }
}

/* The native symbols a module exports, in declaration order. */
static void add_native_exports(const MsCheck *c, MsBuf *list, MsModId m) {
    for (uint32_t i = 0; i < c->mods[m].norder; i++) {
        MsSymId s = c->mods[m].order[i];
        if (c->syms.is_exported[s]) {
            add_export(list, ms_name(c->names, c->syms.name[s]), c->syms.kind[s]);
        }
    }
}

/* A standard module's exports; the bodies of a mixed file export under the file's own name too. */
static size_t standard_exports(MsArena *arena, const MsCheck *c, MsStr path, Export **out) {
    MsBuf list = {0};
    MsModId source = find_module(c, path, true);
    MsModId native = find_module(c, path, false);
    if (source != MS_NONE) {
        add_source_exports(c, &list, source);
    } else if (native != MS_NONE) {
        add_native_exports(c, &list, native);
        MsStr twin_path = ms_arena_fmt(arena, "%.*s+source", (int)path.len, path.ptr);
        MsModId twin = find_module(c, twin_path, true);
        if (twin != MS_NONE) {
            add_source_exports(c, &list, twin);
        }
    }
    size_t n = MS_VEC_LEN(list, Export);
    Export *items = MS_NEW_N(arena, Export, n + 1);
    if (n != 0) {
        memcpy(items, ms_buf_items(&list), n * sizeof *items);
    }
    ms_buf_free(&list);
    *out = items;
    return n;
}

static bool exports_contain(const Export *items, size_t count, MsStr name, bool types_only) {
    for (size_t i = 0; i < count; i++) {
        if (ms_str_equal(items[i].name, name) && (!types_only || items[i].kind == MS_SYM_TYPE)) {
            return true;
        }
    }
    return false;
}

bool ms_standard_import_ok(MsArena *arena, const MsCheck *c, MsStr path, MsStr name) {
    if (!is_native_module(c, path) && !is_source_module(c, path)) {
        return false;
    }
    Export *items = NULL;
    size_t n = standard_exports(arena, c, path, &items);
    return exports_contain(items, n, name, false);
}

/* ---- import hints ---- */

static bool is_prelude_name(MsStr name) {
    for (size_t i = 0; i < MS_COUNT_OF(prelude_names); i++) {
        if (ms_str_equal(name, cstr(prelude_names[i]))) {
            return true;
        }
    }
    return false;
}

/* Whether the standard symbol of this name is a prelude declaration. */
static bool is_prelude_symbol(const MsCheck *c, MsSymId s) {
    MsStr name = ms_name(c->names, c->syms.name[s]);
    MsStr module = module_path(c, c->syms.module[s]);
    if (ms_str_equal(name, cstr(prelude_function)) && ms_str_equal(module, cstr(prelude_function_module))) {
        return true;
    }
    return is_prelude_name(name);
}

/* The standard symbol of this name: the standard type index of the loader. */
static MsSymId standard_symbol(const MsCheck *c, MsStr name) {
    MsSym sym = ms_intern(c->names, name.ptr, name.len);
    return ms_map_get(&c->std_types, sym);
}

static MsStr import_hint_for(MsArena *arena, const MsCheck *c, MsStr name, bool checking_sources, bool types_only) {
    MsSymId symbol = standard_symbol(c, name);
    if (symbol != MS_NONE && is_prelude_symbol(c, symbol) && (!types_only || c->syms.kind[symbol] == MS_SYM_TYPE)) {
        return ms_arena_fmt(arena,
                            "; use the prelude %.*s declaration directly; rename any shadowing binding or "
                            "declaration",
                            (int)name.len, name.ptr);
    }
    if (checking_sources) {
        return (MsStr){"", 0};
    }
    MsStr *modules = NULL;
    size_t n = standard_module_names(arena, c, &modules);
    for (size_t i = 0; i < n; i++) {
        Export *items = NULL;
        size_t count = standard_exports(arena, c, modules[i], &items);
        if (exports_contain(items, count, name, types_only)) {
            return ms_arena_fmt(arena, "; add: import %.*s from \"%.*s\"", (int)name.len, name.ptr,
                                (int)modules[i].len, modules[i].ptr);
        }
    }
    return (MsStr){"", 0};
}

MsStr ms_import_hint(MsArena *arena, const MsCheck *c, MsStr name, bool checking_sources) {
    return import_hint_for(arena, c, name, checking_sources, false);
}

MsStr ms_type_import_hint(MsArena *arena, const MsCheck *c, MsStr name, bool checking_sources) {
    return import_hint_for(arena, c, name, checking_sources, true);
}

/* ---- export messages ---- */

/* The text between the first pair of single quotes, or empty. */
static MsStr first_quoted(MsStr s) {
    uint32_t open = 0;
    while (open < s.len && s.ptr[open] != '\'') {
        open++;
    }
    uint32_t close = open + 1;
    while (open < s.len && close < s.len && s.ptr[close] != '\'') {
        close++;
    }
    if (open >= s.len || close >= s.len) {
        return (MsStr){"", 0};
    }
    return (MsStr){s.ptr + open + 1, close - open - 1};
}

/* The statement of an `; add: ` hint, or empty when it is another kind of hint. */
static MsStr add_statement(MsStr hint) {
    MsStr prefix = cstr("; add: ");
    if (!ms_str_starts_with(hint, prefix)) {
        return (MsStr){"", 0};
    }
    return (MsStr){hint.ptr + prefix.len, hint.len - prefix.len};
}

/* The module whose stem is `stem`, or empty. */
static MsStr module_with_stem(const MsStr *modules, size_t count, MsStr stem) {
    for (size_t i = 0; i < count; i++) {
        if (ms_str_equal(ms_module_stem(modules[i]), stem)) {
            return modules[i];
        }
    }
    return (MsStr){"", 0};
}

/* The first module with the same file name as `path` under another folder. */
static MsStr module_with_base(const MsStr *modules, size_t count, MsStr path) {
    for (size_t i = 0; i < count; i++) {
        if (ms_str_equal(after_last_slash(modules[i]), after_last_slash(path))) {
            return modules[i];
        }
    }
    return (MsStr){"", 0};
}

static MsStr module_named(const MsStr *modules, size_t count, MsStr path) {
    for (size_t i = 0; i < count; i++) {
        if (ms_str_equal(modules[i], path)) {
            return modules[i];
        }
    }
    return (MsStr){"", 0};
}

/* The spelling suggestion for an unknown standard module, as a `; did you mean` hint. */
static MsStr module_spelling_hint(MsArena *arena, MsStr path, const MsStr *modules, size_t count) {
    MsStr *stems = MS_NEW_N(arena, MsStr, count + 1);
    for (size_t i = 0; i < count; i++) {
        stems[i] = ms_module_stem(modules[i]);
    }
    MsStr hint = ms_did_you_mean(arena, ms_module_stem(path), stems, count);
    if (hint.len == 0) {
        MsStr same = module_with_base(modules, count, path);
        if (same.len != 0) {
            hint = ms_arena_fmt(arena, "; did you mean '%.*s'?", (int)same.len, same.ptr);
        }
    }
    MsStr suggested = first_quoted(hint);
    MsStr full = suggested.len == 0 ? suggested : module_with_stem(modules, count, suggested);
    if (full.len != 0) {
        hint = ms_arena_fmt(arena, "; did you mean '%.*s'?", (int)full.len, full.ptr);
    }
    return hint;
}

/* Why a standard module that does not exist cannot be imported from. */
static MsStr unknown_module_message(MsArena *arena, const MsCheck *c, MsStr path, MsStr name, bool checking_sources) {
    const char *renamed = ms_renamed_module(path);
    if (renamed != NULL) {
        return ms_arena_fmt(arena, "unknown standard module %.*s; it was renamed: import '%s'", (int)path.len, path.ptr,
                            renamed);
    }
    MsStr *modules = NULL;
    size_t count = standard_module_names(arena, c, &modules);
    MsStr with_ext = ms_arena_fmt(arena, "%.*s.ms", (int)path.len, path.ptr);
    if (module_named(modules, count, with_ext).len != 0) {
        return ms_arena_fmt(arena, "unknown standard module %.*s; did you mean '%.*s'? Import paths end in .ms",
                            (int)path.len, path.ptr, (int)with_ext.len, with_ext.ptr);
    }
    MsStr hint = module_spelling_hint(arena, path, modules, count);
    /* The name is exported by another module, and the suggestion (if any) is not one that exports it. */
    MsStr statement = add_statement(ms_import_hint(arena, c, name, checking_sources));
    MsStr suggestion = first_quoted(hint);
    Export *items = NULL;
    size_t nitems = suggestion.len == 0 ? 0 : standard_exports(arena, c, suggestion, &items);
    if (statement.len != 0 && !exports_contain(items, nitems, name, false)) {
        return ms_arena_fmt(arena,
                            "unknown standard module %.*s; %.*s is exported by another standard module, so write: "
                            "%.*s",
                            (int)path.len, path.ptr, (int)name.len, name.ptr, (int)statement.len, statement.ptr);
    }
    return ms_arena_fmt(arena, "unknown standard module %.*s%.*s", (int)path.len, path.ptr, (int)hint.len, hint.ptr);
}

/* The file name of a module path without `.ms` (any number of them, as Rust's trim_end_matches). */
static MsStr file_stem(MsStr path) {
    MsStr file = after_last_slash(path);
    while (ms_text_ends_with(file, ".ms")) {
        file.len -= 3;
    }
    return file;
}

static MsStr join_names(MsArena *arena, const MsStr *names, size_t count) {
    return ms_hint_list(arena, names, count, HINT_LIST_LIMIT);
}

/* The message once the exports of the target module are known. */
static MsStr missing_export_message(MsArena *arena, const MsCheck *c, const MsImport *item, bool checking_sources,
                                    const MsStr *exports, size_t count) {
    MsStr name = ms_name(c->names, item->name);
    MsStr path = item->path;
    MsStr message = ms_arena_fmt(arena, "module does not export %.*s", (int)name.len, name.ptr);
    if (ms_str_equal(file_stem(path), name) && count != 0) {
        MsStr listed = join_names(arena, exports, count);
        return ms_arena_fmt(arena,
                            "%.*s; %.*s is that module, and namespace imports are unsupported, so import what it "
                            "exports by name: %.*s",
                            (int)message.len, message.ptr, (int)path.len, path.ptr, (int)listed.len, listed.ptr);
    }
    MsStr hint = ms_did_you_mean(arena, name, exports, count);
    if (hint.len != 0) {
        return ms_arena_fmt(arena, "%.*s%.*s", (int)message.len, message.ptr, (int)hint.len, hint.ptr);
    }
    MsStr statement = add_statement(ms_import_hint(arena, c, name, checking_sources));
    if (statement.len != 0) {
        return ms_arena_fmt(arena, "%.*s; another standard module exports it, so replace this import with: %.*s",
                            (int)message.len, message.ptr, (int)statement.len, statement.ptr);
    }
    if (count == 0) {
        return ms_arena_fmt(arena,
                            "%.*s; %.*s exports nothing; namespace imports are unsupported, so import individual "
                            "exported declarations",
                            (int)message.len, message.ptr, (int)path.len, path.ptr);
    }
    MsStr listed = join_names(arena, exports, count);
    return ms_arena_fmt(arena,
                        "%.*s; %.*s exports: %.*s; namespace imports are unsupported, so import individual exports "
                        "with 'import Name, OtherName from \"%.*s\"'",
                        (int)message.len, message.ptr, (int)path.len, path.ptr, (int)listed.len, listed.ptr,
                        (int)path.len, path.ptr);
}

MsStr ms_export_message(MsArena *arena, const MsCheck *c, const MsImport *item, bool checking_sources,
                        const MsExportList *local) {
    MsStr name = ms_name(c->names, item->name);
    MsStr path = item->path;
    if (!ms_text_starts_with(path, STD_PREFIX)) {
        if (local != NULL && local->name_is_private) {
            return ms_arena_fmt(arena,
                                "module does not export %.*s; it is declared in %.*s but not exported, so write "
                                "'export' before its declaration",
                                (int)name.len, name.ptr, (int)path.len, path.ptr);
        }
        return missing_export_message(arena, c, item, checking_sources, local != NULL ? local->names : NULL,
                                      local != NULL ? local->count : 0);
    }
    if (!is_native_module(c, path) && !is_source_module(c, path)) {
        return unknown_module_message(arena, c, path, name, checking_sources);
    }
    Export *items = NULL;
    size_t count = standard_exports(arena, c, path, &items);
    MsStr *names = MS_NEW_N(arena, MsStr, count + 1);
    for (size_t i = 0; i < count; i++) {
        names[i] = items[i].name;
    }
    return missing_export_message(arena, c, item, checking_sources, names, count);
}
