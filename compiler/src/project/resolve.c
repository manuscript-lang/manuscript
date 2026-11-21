/* Import resolution (project.h): confined, canonical paths for the imports of a project. Port of
 * crates/ms-driver/src/project/paths.rs. The macOS and Windows letter-case check (`exact_case`) is not ported yet. */
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

bool ms_project_source_path(MsArena *a, const char *root, const char *path, const char **out, MsProjectError *err) {
    const char *full = ms_path_is_abs(path) ? path : MS_PATH_JOIN(a, root, path);
    const char *canonical;
    if (!ms_path_eval_symlinks(a, full, &canonical, err)) {
        return false;
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

bool ms_project_resolve_import(MsArena *a, const MsProject *p, const char *importer, const char *path, const char **out, MsProjectError *err) {
    const char *target;
    bool generated = false;
    if (!resolve_import_target(a, p, importer, path, &target, &generated, err)) {
        return false;
    }
    if (generated) {
        *out = target;
        return true;
    }
    return ms_project_source_path(a, ms_project_confinement_root(p, importer, path, target), target, out, err);
}
