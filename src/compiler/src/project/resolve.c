/* Import resolution (project.h): confined, canonical paths for the imports of a project. Port of
 * crates/ms-driver/src/project/paths.rs. The macOS and Windows letter-case check (`exact_case`) is not ported yet. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L /* lstat; libms.c defines it first for the whole unit */
#endif
#include <errno.h>
#include <string.h>
#include <sys/stat.h>

#include "ms/project.h"

const char *ms_project_quote(MsArena *a, const char *text) {
    MsBuf out = {0};
    ms_buf_putc(&out, '"');
    const size_t length = strlen(text);
    for (size_t i = 0; i < length;) {
        uint32_t c;
        const int n = ms_utf8_decode(text + i, length - i, &c);
        i += (size_t)n;
        switch (c) {
        case '"': ms_buf_puts(&out, "\\\""); break;
        case '\\': ms_buf_puts(&out, "\\\\"); break;
        case '\a': ms_buf_puts(&out, "\\a"); break;
        case '\b': ms_buf_puts(&out, "\\b"); break;
        case '\f': ms_buf_puts(&out, "\\f"); break;
        case '\n': ms_buf_puts(&out, "\\n"); break;
        case '\r': ms_buf_puts(&out, "\\r"); break;
        case '\t': ms_buf_puts(&out, "\\t"); break;
        case '\v': ms_buf_puts(&out, "\\v"); break;
        case 0xfffd: ms_buf_puts(&out, "\\ufffd"); break;
        default:
            if (c < 0x20 || c == 0x7f) {
                ms_buf_printf(&out, "\\x%02x", c);
            } else if (c >= 0x80 && c < 0xa0) {
                ms_buf_printf(&out, "\\u%04x", c);
            } else {
                ms_buf_put(&out, text + i - (size_t)n, (size_t)n);
            }
        }
    }
    ms_buf_putc(&out, '"');
    char *quoted = ms_arena_strndup(a, out.data, out.len);
    ms_buf_free(&out);
    return quoted;
}

/* The value of the hex digit `c`, or -1. */
static int resolve_hex_digit(char c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    return -1;
}

/* Value of the `count` hex digits at text[at..], or -1. */
static int64_t resolve_hex(const char *text, size_t length, size_t at, size_t count) {
    if (at + count > length) {
        return -1;
    }
    int64_t value = 0;
    for (size_t i = 0; i < count; i++) {
        const int digit = resolve_hex_digit(text[at + i]);
        if (digit < 0) {
            return -1;
        }
        value = value * 16 + digit;
    }
    return value;
}

/* One escape whose backslash precedes `at`; returns the index after it, or 0 for a syntax error. */
static size_t resolve_unescape(const char *text, size_t length, size_t at, MsBuf *out) {
    if (at >= length) {
        return 0;
    }
    const char c = text[at];
    const char *simple = "abfnrtv\\\"";
    const char *found = c == 0 ? NULL : strchr(simple, c);
    if (found != NULL) {
        ms_buf_putc(out, "\a\b\f\n\r\t\v\\\""[found - simple]);
        return at + 1;
    }
    if (c == 'x') {
        const int64_t byte = resolve_hex(text, length, at + 1, 2);
        if (byte < 0) {
            return 0;
        }
        ms_buf_putc(out, (char)byte);
        return at + 3;
    }
    if (c == 'u' || c == 'U') {
        const size_t digits = c == 'u' ? 4 : 8;
        const int64_t scalar = resolve_hex(text, length, at + 1, digits);
        if (scalar < 0 || scalar > 0x10ffff || (scalar >= 0xd800 && scalar < 0xe000)) {
            return 0;
        }
        ms_utf8_put(out, (uint32_t)scalar);
        return at + 1 + digits;
    }
    if (c >= '0' && c <= '7') {
        if (at + 3 > length) {
            return 0;
        }
        uint32_t value = 0;
        for (size_t i = 0; i < 3; i++) {
            if (text[at + i] < '0' || text[at + i] > '7') {
                return 0;
            }
            value = value * 8 + (uint32_t)(text[at + i] - '0');
        }
        if (value > 255) {
            return 0;
        }
        ms_buf_putc(out, (char)value);
        return at + 3;
    }
    return 0;
}

bool ms_project_unquote(MsArena *a, const char *text, const char **out) {
    const size_t length = strlen(text);
    if (length < 2 || text[0] != '"') {
        return false;
    }
    MsBuf value = {0};
    size_t i = 1;
    bool closed = false;
    while (i < length && !closed) {
        const char c = text[i];
        if (c == '"') {
            closed = true;
            i++;
        } else if (c == '\n') {
            break;
        } else if (c == '\\') {
            i = resolve_unescape(text, length, i + 1, &value);
            if (i == 0) {
                break;
            }
        } else {
            ms_buf_putc(&value, c);
            i++;
        }
    }
    const bool ok = closed && i == length && ms_utf8_valid(value.data == NULL ? "" : value.data, value.len);
    if (ok) {
        *out = ms_arena_strndup(a, value.data == NULL ? "" : value.data, value.len);
    }
    ms_buf_free(&value);
    return ok;
}

/* ---- source_path ---- */

static bool resolve_source_path_inside(MsArena *a, const char *root, const char *canonical, const char *path, MsProjectError *err) {
    const char *rel;
    MsProjectError ignored;
    if (ms_path_rel(a, root, canonical, &rel, &ignored) && !ms_path_escapes(rel)) {
        return true;
    }
    ms_project_error_message(err, ms_arena_fmt(a, "path escapes project root: %s; keep imported files inside the directory containing ms.toml (or the entry file's directory)", path).ptr);
    return false;
}

const MsOverlayFile *ms_overlay_find(const MsOverlay *overlay, const char *canonical) {
    for (uint32_t i = 0; overlay != NULL && i < overlay->count; i++) {
        if (strcmp(overlay->files[i].path, canonical) == 0) {
            return &overlay->files[i];
        }
    }
    return NULL;
}

typedef enum ResolveNew { RESOLVE_NOT_NEW, RESOLVE_NEW, RESOLVE_NEW_FAILED } ResolveNew;

/* A path that does not exist yet and that the overlay holds: the canonical path of its directory plus its name. */
static ResolveNew resolve_overlay_new(MsArena *a, const char *full, const MsOverlay *overlay, const char **canonical, MsProjectError *err) {
    struct stat info;
    if (lstat(full, &info) == 0 || errno != ENOENT) { /* a dangling link is an existing entry, not a new editor file */
        return RESOLVE_NOT_NEW;
    }
    const char *parent;
    if (!ms_path_eval_symlinks(a, ms_path_dir(a, full), &parent, err)) {
        return RESOLVE_NEW_FAILED;
    }
    const char *joined = MS_PATH_JOIN(a, parent, ms_path_base(a, full));
    if (ms_overlay_find(overlay, ms_path_clean(a, full)) == NULL && ms_overlay_find(overlay, joined) == NULL) {
        return RESOLVE_NOT_NEW;
    }
    *canonical = joined;
    return RESOLVE_NEW;
}

bool ms_project_source_path_overlay(MsArena *a, const char *root, const char *path, const MsOverlay *overlay, const char **out, MsProjectError *err) {
    const char *full = ms_path_is_abs(path) ? path : MS_PATH_JOIN(a, root, path);
    const char *canonical;
    if (!ms_path_eval_symlinks(a, full, &canonical, err)) {
        if (overlay == NULL || overlay->count == 0 || !ms_project_error_not_exist(err)) {
            return false;
        }
        MsProjectError missing = *err;
        const ResolveNew found = resolve_overlay_new(a, full, overlay, &canonical, err);
        if (found != RESOLVE_NEW) {
            if (found == RESOLVE_NOT_NEW) {
                *err = missing;
            }
            return false;
        }
    }
    if (!resolve_source_path_inside(a, root, canonical, full, err)) {
        return false;
    }
    *out = canonical;
    return true;
}

/* ---- imports ---- */

/* The names of `[aliases]` and of the packages the manifest depends on, sorted. */
static uint32_t resolve_declared(MsArena *a, const MsProject *p, const char ***names) {
    const char **all = MS_NEW_N(a, const char *, p->alias_count + p->dep_count + 1);
    uint32_t count = 0;
    for (uint32_t i = 0; i < p->alias_count + p->dep_count; i++) {
        const char *name = i < p->alias_count ? p->aliases[i].name : p->deps[i - p->alias_count].name;
        uint32_t at = 0;
        while (at < count && strcmp(all[at], name) < 0) {
            at++;
        }
        if (at < count && strcmp(all[at], name) == 0) {
            continue;
        }
        memmove(all + at + 1, all + at, (count - at) * sizeof *all);
        all[at] = name;
        count++;
    }
    *names = all;
    return count;
}

/* "; declared aliases: @a, @b", or the advice for a project that declares none. */
static const char *resolve_alias_hint(MsArena *a, const MsProject *p) {
    const char **declared;
    const uint32_t count = resolve_declared(a, p, &declared);
    if (count == 0) {
        return "; this project declares none, so add one under [aliases] in ms.toml, e.g. @lib = \"src/lib\" (use @std/... for the standard library)";
    }
    MsBuf names = {0};
    ms_buf_puts(&names, "; declared aliases: ");
    for (uint32_t i = 0; i < count; i++) {
        if (i > 0) {
            ms_buf_puts(&names, ", ");
        }
        ms_buf_puts(&names, declared[i]);
    }
    char *text = ms_arena_strndup(a, names.data, names.len);
    ms_buf_free(&names);
    return text;
}

/* What `name` names in `[aliases]`, else the source directory of the package it depends on. */
static const char *resolve_find_alias(const MsProject *p, const char *name, size_t length) {
    for (uint32_t i = 0; i < p->alias_count; i++) {
        if (strlen(p->aliases[i].name) == length && memcmp(p->aliases[i].name, name, length) == 0) {
            return p->aliases[i].target;
        }
    }
    for (uint32_t i = 0; i < p->dep_count; i++) {
        if (strlen(p->deps[i].name) == length && memcmp(p->deps[i].name, name, length) == 0) {
            return p->deps[i].target;
        }
    }
    return NULL;
}

static bool resolve_fail_message(MsProjectError *err, const char *message) {
    ms_project_error_message(err, message);
    return false;
}

/* The path a local import names, before symlinks are resolved and confinement is checked. */
static bool resolve_import_target(MsArena *a, const MsProject *project, const char *importer, const char *path, const char **out, bool *generated, MsProjectError *err) {
    const MsProject *p = ms_project_scope(project, importer);
    if (strchr(path, '\\') != NULL) {
        return resolve_fail_message(err, "import paths use / separators; write \"./dir/file.ms\" instead of backslashes");
    }
    if (strncmp(path, "./", 2) == 0 || strncmp(path, "../", 3) == 0) {
        const char *last = strrchr(path, '/') + 1;
        if (last[0] == 0 || strcmp(last, ".") == 0 || strcmp(last, "..") == 0) {
            return resolve_fail_message(err, ms_arena_fmt(a, "import path %s names a directory, not a module; end it with a file such as \"./name.ms\"", ms_project_quote(a, path)).ptr);
        }
        const char *ext = ms_path_ext(path);
        if (strcmp(ext, ".ms") != 0) {
            return resolve_fail_message(err, ms_arena_fmt(a, "import path requires .ms extension; write \"%.*s.ms\"", (int)(ext - path), path).ptr);
        }
        *out = MS_PATH_JOIN(a, ms_path_dir(a, importer), path);
        return true;
    }
    if (path[0] == '@') {
        const char *slash = strchr(path, '/');
        const size_t alias_length = slash != NULL ? (size_t)(slash - path) : strlen(path);
        const char *remainder = slash != NULL ? slash + 1 : "";
        const char *alias = ms_arena_strndup(a, path, alias_length);
        for (uint32_t i = 0; i < p->embed_count; i++) {
            if (strcmp(p->embed[i].name, alias) != 0) {
                continue;
            }
            if (remainder[0] != 0) {
                return resolve_fail_message(err, ms_arena_fmt(a, "embed %s names a generated module, so import it as \"%s\" alone", alias, alias).ptr);
            }
            /* Generated on load; no file exists, so there is nothing to canonicalize. */
            *out = ms_embed_module_path(a, project->root, alias);
            *generated = true;
            return true;
        }
        const char *base = resolve_find_alias(p, alias, alias_length);
        if (base == NULL || base[0] == 0) {
            return resolve_fail_message(err, ms_arena_fmt(a, "unknown import alias %s%s", alias, resolve_alias_hint(a, p)).ptr);
        }
        struct stat info;
        if (stat(base, &info) != 0) {
            ms_project_error_path(err, a, "stat", base, errno);
            return false;
        }
        if (S_ISDIR(info.st_mode)) {
            if (remainder[0] == 0 || strcmp(ms_path_ext(remainder), ".ms") != 0) {
                return resolve_fail_message(err, ms_arena_fmt(a, "directory alias requires a .ms path; write \"%s/<file>.ms\"", alias).ptr);
            }
            *out = MS_PATH_JOIN(a, base, remainder);
            return true;
        }
        if (remainder[0] != 0 || strcmp(ms_path_ext(base), ".ms") != 0) {
            return resolve_fail_message(err, ms_arena_fmt(a, "file alias does not accept a suffix; alias %s names one file, so import it as \"%s\" alone", alias, alias).ptr);
        }
        *out = base;
        return true;
    }
    if (path[0] == '/') {
        return resolve_fail_message(err, "absolute import paths are not supported; write a relative path such as \"../name.ms\" from this file, or declare an alias under [aliases] in ms.toml");
    }
    const bool bare = path[0] == 0 || strcmp(path, ".") == 0 || strcmp(path, "..") == 0;
    return resolve_fail_message(err, ms_arena_fmt(a, "imports require a relative path or alias; write \"./%s\" for a file next to this one, \"@std/name.ms\" for the standard library, or declare an alias under [aliases] in ms.toml", bare ? "name.ms" : path).ptr);
}

bool ms_project_source_path(MsArena *a, const char *root, const char *path, const char **out, MsProjectError *err) {
    return ms_project_source_path_overlay(a, root, path, NULL, out, err);
}

bool ms_project_resolve_import(MsArena *a, const MsProject *p, const char *importer, const char *path, const char **out, MsProjectError *err) {
    return ms_project_resolve_import_overlay(a, p, NULL, importer, path, out, err);
}

bool ms_project_resolve_import_overlay(MsArena *a, const MsProject *p, const MsOverlay *overlay, const char *importer, const char *path, const char **out, MsProjectError *err) {
    const char *target;
    bool generated = false;
    if (!resolve_import_target(a, p, importer, path, &target, &generated, err)) {
        return false;
    }
    if (generated) {
        *out = target;
        return true;
    }
    return ms_project_source_path_overlay(a, ms_project_confinement_root(p, importer, path, target), target, overlay, out, err);
}

bool ms_overlay_canonical(MsArena *a, const char *root, const MsOverlay *in, MsOverlay *out, MsProjectError *err) {
    MsOverlayFile *files = MS_NEW_N(a, MsOverlayFile, in->count + 1);
    uint32_t count = 0;
    for (uint32_t i = 0; i < in->count; i++) {
        const char *canonical;
        MsProjectError ignored;
        if (!ms_project_source_path_overlay(a, root, in->files[i].path, in, &canonical, &ignored)) {
            continue;
        }
        const MsOverlayFile *previous = NULL;
        for (uint32_t k = 0; k < count && previous == NULL; k++) {
            previous = strcmp(files[k].path, canonical) == 0 ? &files[k] : NULL;
        }
        if (previous == NULL) {
            files[count++] = (MsOverlayFile){.path = canonical, .text = in->files[i].text, .length = in->files[i].length};
        } else if (previous->length != in->files[i].length || memcmp(previous->text, in->files[i].text, previous->length) != 0) {
            ms_project_error_message(err, ms_arena_fmt(a, "conflicting editor overlays for %s; two spellings of one path carry different unsaved contents, so send a single snapshot per file", canonical).ptr);
            return false;
        }
    }
    *out = (MsOverlay){.files = files, .count = count};
    return true;
}
