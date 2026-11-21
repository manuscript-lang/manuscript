/* Source discovery (project.h): the test and source modules of a directory or project, in lexical order. Port of
 * crates/ms-driver/src/project/discovery.rs and the path selection of `ms fmt`. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#include <stdlib.h>
#include <string.h>

#include "ms/project.h"
#include "project/host.h"

typedef struct Discovery {
    MsArena *arena;
    const MsProject *project;
    const char *scan_root;
    bool all;            /* collect every .ms file, not only tests */
    bool include_source; /* the source tree is scanned separately */
    MsBuf files;         /* const char *, sorted and deduplicated at the end */
    MsProjectError *err;
} Discovery;

static bool discover_skipped_name(const char *name) {
    return name[0] == '.' || strcmp(name, "vendor") == 0 || strcmp(name, "node_modules") == 0;
}

static bool discover_has_suffix(const char *name, const char *suffix) {
    const size_t n = strlen(name), s = strlen(suffix);
    return n >= s && strcmp(name + n - s, suffix) == 0;
}

static bool discover_is_test_name(const char *name) {
    return strcmp(name, "test.ms") == 0 || discover_has_suffix(name, "_test.ms") || strcmp(name, "bench.ms") == 0 ||
           discover_has_suffix(name, "_bench.ms");
}

static bool discover_is_nested_project(Discovery *d, const char *dir) {
    MsSysStat info;
    return ms_sys_fs_stat(MS_PATH_JOIN(d->arena, dir, "ms.toml"), true, &info) == 0 && host_is_reg(&info);
}

/* A symlink to a directory. */
static bool discover_is_directory_link(const char *path, const MsSysStat *link) {
    MsSysStat target;
    return host_is_link(link) && ms_sys_fs_stat(path, true, &target) == 0 && host_is_dir(&target);
}

/* Whether the walk enters this entry; a file is recorded when it is a module of the scan. */
static bool discover_visit(Discovery *d, const char *path, const char *name, bool is_dir) {
    const MsProject *p = d->project;
    if (is_dir) {
        if (d->include_source && !d->all && strcmp(path, p->source) == 0) {
            return false; /* the source walk already collected its tests and modules */
        }
        /* A nested project is selected explicitly, never by its parent. */
        return strcmp(path, d->scan_root) == 0 || strcmp(path, p->root) == 0 ||
               !(discover_skipped_name(name) || discover_is_nested_project(d, path));
    }
    if ((d->all && strcmp(ms_path_ext(name), ".ms") == 0) || discover_is_test_name(name)) {
        MS_VEC_PUSH(d->files, const char *, path);
    }
    return true;
}

typedef struct Child {
    const char *name;
    bool is_dir;
} Child;

/* The entries of `path` that the walk considers, sorted by name; false with the error filled when unreadable. */
static bool discover_children(Discovery *d, const char *path, MsBuf *children) {
    const char *const *names;
    uint32_t count;
    if (!ms_path_list_dir(d->arena, path, "open", &names, &count, d->err)) {
        return false;
    }
    for (uint32_t i = 0; i < count; i++) {
        const char *name = names[i];
        const char *full = MS_PATH_JOIN(d->arena, path, name);
        MsSysStat info;
        const MsSysError failure = ms_sys_fs_stat(full, false, &info);
        if (failure != 0) {
            ms_project_error_path(d->err, d->arena, "lstat", path, failure);
            return false;
        }
        if (discover_is_directory_link(full, &info)) {
            continue; /* a symlink to a directory is skipped, even when its name ends in `.ms` */
        }
        const bool is_dir = host_is_dir(&info);
        if (!ms_utf8_valid(name, strlen(name))) {
            const bool ignored = is_dir ? name[0] == '.' : !(discover_is_test_name(name) || (d->all && discover_has_suffix(name, ".ms")));
            if (ignored) {
                continue;
            }
            ms_project_error_message(d->err, ms_arena_fmt(d->arena, "discovered source path %s is not valid UTF-8; rename the file or directory using valid UTF-8", ms_debug_quote(d->arena, full)).ptr);
            return false;
        }
        Child child = {.name = name, .is_dir = is_dir};
        MS_VEC_PUSH(*children, Child, child);
    }
    return true;
}

static bool discover_entry(Discovery *d, const char *path, const char *name, bool is_dir) {
    if (!discover_visit(d, path, name, is_dir) || !is_dir) {
        return true;
    }
    MsBuf children = {0};
    bool ok = discover_children(d, path, &children);
    for (size_t i = 0; ok && i < MS_VEC_LEN(children, Child); i++) {
        const Child *child = &MS_VEC_AT(children, Child, i);
        ok = discover_entry(d, MS_PATH_JOIN(d->arena, path, child->name), child->name, child->is_dir);
    }
    ms_buf_free(&children);
    return ok;
}

static bool discover_walk(Discovery *d, const char *root) {
    MsSysStat info;
    const MsSysError failure = ms_sys_fs_stat(root, false, &info);
    if (failure != 0) {
        ms_project_error_path(d->err, d->arena, "lstat", root, failure);
        return false;
    }
    d->scan_root = root;
    if (discover_is_directory_link(root, &info)) {
        return true;
    }
    return discover_entry(d, root, ms_path_base(d->arena, root), host_is_dir(&info));
}

bool ms_project_discover(MsArena *a, const MsProject *project, bool include_source, const char ***paths, uint32_t *count, MsProjectError *err) {
    Discovery d = {.arena = a, .project = project, .include_source = include_source, .err = err};
    bool ok = true;
    if (include_source) {
        d.all = true;
        ok = discover_walk(&d, project->source);
    }
    if (ok) {
        d.all = false;
        ok = discover_walk(&d, project->root);
    }
    const size_t total = MS_VEC_LEN(d.files, const char *);
    const char **found = MS_NEW_N(a, const char *, total + 1);
    size_t unique = 0;
    if (ok && total > 0) {
        qsort(ms_buf_items(&d.files), total, sizeof(const char *), ms_cmp_cstr);
        for (size_t i = 0; i < total; i++) {
            const char *path = MS_VEC_AT(d.files, const char *, i);
            if (unique == 0 || strcmp(found[unique - 1], path) != 0) {
                found[unique++] = path;
            }
        }
    }
    ms_buf_free(&d.files);
    *paths = found;
    *count = (uint32_t)unique;
    return ok;
}

bool ms_project_format_paths(MsArena *a, const char *target, const char ***paths, uint32_t *count, MsProjectError *err) {
    MsSysStat info;
    const MsSysError failure = ms_sys_fs_stat(target, true, &info);
    if (failure != 0) {
        ms_project_error_path(err, a, "stat", target, failure);
        return false;
    }
    if (!host_is_dir(&info) && strcmp(ms_path_base(a, target), "ms.toml") != 0) {
        const char **one = MS_NEW_N(a, const char *, 1);
        one[0] = target;
        *paths = one;
        *count = 1;
        return true;
    }
    MsProject project = {0};
    if (host_is_dir(&info)) {
        const char *absolute;
        if (!ms_path_abs(a, target, &absolute, err) || !ms_path_eval_symlinks(a, absolute, &project.root, err)) {
            return false;
        }
        project.source = project.root;
        project.entry = "";
    } else {
        if (!ms_project_read(a, target, &project, err)) {
            return false;
        }
        if (project.is_workspace && project.name[0] == 0) {
            ms_project_error_unsupported(err, "a workspace root");
            return false;
        }
    }
    const char **found;
    uint32_t n;
    if (!ms_project_discover(a, &project, true, &found, &n, err)) {
        return false;
    }
    const char **all = MS_NEW_N(a, const char *, (size_t)n + 1);
    memcpy(all, found, n * sizeof *found);
    uint32_t total = n;
    if (project.entry[0] != 0) {
        all[total++] = project.entry;
    }
    /* A discovered file symlink must stay inside the selected project or directory. */
    for (uint32_t i = 0; i < total; i++) {
        if (!ms_project_source_path(a, project.root, all[i], &all[i], err)) {
            return false;
        }
    }
    *paths = all;
    *count = total;
    return true;
}
