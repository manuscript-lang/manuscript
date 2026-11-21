/* Workspaces (project.h): a root `ms.toml` with `[workspace] members` names directories that each hold a project.
 * Members import one another through `{ path = "../util" }` dependencies and share the root's `ms.lock`. Port of
 * crates/ms-driver/src/project/workspace.rs; the error texts are the Rust ones. */
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "ms/project.h"

static bool workspace_fail(MsProjectError *err, const char *message) {
    ms_project_error_message(err, message);
    return false;
}

static bool workspace_is_file(const char *path) {
    struct stat info;
    return stat(path, &info) == 0 && S_ISREG(info.st_mode);
}

/* Whether `dir` is `root` or below it, by path components. */
static bool workspace_within(const char *root, const char *dir) {
    const size_t length = strlen(root);
    return strncmp(dir, root, length) == 0 && (dir[length] == 0 || dir[length] == '/');
}

/* `dir` below `root`, or `dir` itself for the root or a path with no relative form. */
static const char *workspace_rel_or(MsArena *a, const char *root, const char *dir) {
    const char *rel;
    MsProjectError ignored;
    if (ms_path_rel(a, root, dir, &rel, &ignored) && strcmp(rel, ".") != 0) {
        return rel;
    }
    return dir;
}

const MsMember *ms_workspace_member_at(const MsWorkspace *w, const char *dir) {
    for (uint32_t i = 0; i < w->count; i++) {
        if (strcmp(w->members[i].root, dir) == 0) {
            return &w->members[i];
        }
    }
    return NULL;
}

static int workspace_compare(const void *x, const void *y) { return strcmp(*(const char *const *)x, *(const char *const *)y); }

static bool workspace_bad_pattern(MsArena *a, MsProjectError *err, const char *pattern, const char *why) {
    return workspace_fail(err, ms_arena_fmt(a, "workspace member %s %s; write a directory below the workspace root such as \"app\" or \"libs/*\"", ms_debug_quote(a, pattern), why).ptr);
}

/* The canonical directories `pattern` names under `root`, appended to `dirs`. */
static bool workspace_expand(MsArena *a, const char *root, const char *pattern, MsBuf *dirs, MsProjectError *err) {
    const size_t length = strlen(pattern);
    const bool wildcard = length >= 2 && strcmp(pattern + length - 2, "/*") == 0;
    const char *base = wildcard ? ms_arena_strndup(a, pattern, length - 2) : pattern;
    if (base[0] == 0 || ms_path_is_abs(base) || ms_path_escapes(base) || strchr(base, '*') != NULL) {
        return workspace_bad_pattern(a, err, pattern, "is not a relative directory inside the workspace");
    }
    const char *parent;
    MsProjectError ignored;
    if (!ms_path_eval_symlinks(a, MS_PATH_JOIN(a, root, base), &parent, &ignored)) {
        return workspace_bad_pattern(a, err, pattern, "does not exist");
    }
    if (!workspace_within(root, parent)) {
        return workspace_bad_pattern(a, err, pattern, "leaves the workspace root");
    }
    if (!wildcard) {
        MS_VEC_PUSH(*dirs, const char *, parent);
        return true;
    }
    const char *const *names;
    uint32_t count;
    if (!ms_path_list_dir(a, parent, "read directory", &names, &count, err)) {
        return false;
    }
    MsBuf children = {0};
    for (uint32_t i = 0; i < count; i++) {
        if (names[i][0] == '.') { /* a hidden directory (.git, .cache) is never a member */
            continue;
        }
        const char *path = MS_PATH_JOIN(a, parent, names[i]);
        const char *canonical;
        if (workspace_is_file(MS_PATH_JOIN(a, path, "ms.toml")) && ms_path_eval_symlinks(a, path, &canonical, err)) {
            if (workspace_within(root, canonical)) {
                MS_VEC_PUSH(children, const char *, canonical);
            }
        }
    }
    const size_t found = MS_VEC_LEN(children, const char *);
    if (found > 1) {
        qsort(children.data, found, sizeof(const char *), workspace_compare);
    }
    for (size_t i = 0; i < found; i++) {
        MS_VEC_PUSH(*dirs, const char *, MS_VEC_AT(children, const char *, i));
    }
    ms_buf_free(&children);
    return true;
}

/* Reads the manifest of the member at `dir` and checks it against the others. */
static bool workspace_member(MsArena *a, const char *root, const char *dir, const MsWorkspace *so_far, MsMember *out, MsProjectError *err) {
    MsProject project;
    MsProjectError cause = {0};
    const char *shown = workspace_rel_or(a, root, dir);
    if (!ms_project_read(a, MS_PATH_JOIN(a, dir, "ms.toml"), &project, &cause)) {
        if (ms_project_error_is_unsupported(&cause)) {
            *err = cause;
            return false;
        }
        return workspace_fail(err, ms_arena_fmt(a, "workspace member %s: %s", shown, ms_project_error_text(a, &cause)).ptr);
    }
    if (strcmp(dir, root) != 0 && workspace_is_file(MS_PATH_JOIN(a, dir, "ms.lock"))) {
        return workspace_fail(err, ms_arena_fmt(a, "workspace member %s has its own ms.lock, which is never read; the workspace keeps one ms.lock at %s, so delete the member's", shown, root).ptr);
    }
    if (project.name[0] == 0) {
        return workspace_fail(err, ms_arena_fmt(a, "workspace member %s has no [project]; a member is a project with a name and source", shown).ptr);
    }
    for (uint32_t i = 0; i < so_far->count; i++) {
        if (strcmp(so_far->members[i].name, project.name) == 0) {
            return workspace_fail(err, ms_arena_fmt(a, "workspace members %s and %s are both named %s; rename one in [project]", workspace_rel_or(a, root, so_far->members[i].root), shown, ms_debug_quote(a, project.name)).ptr);
        }
    }
    *out = (MsMember){.name = project.name, .root = dir};
    return true;
}

bool ms_workspace_read(MsArena *a, const MsProject *root_project, MsWorkspace *out, MsProjectError *err) {
    const char *root = root_project->root;
    MsBuf dirs = {0};
    if (root_project->name[0] != 0) { /* the root's own project, when it has one, is a member */
        MS_VEC_PUSH(dirs, const char *, root);
    }
    for (uint32_t i = 0; i < root_project->member_count; i++) {
        if (!workspace_expand(a, root, root_project->members[i], &dirs, err)) {
            ms_buf_free(&dirs);
            return false;
        }
    }
    const size_t wanted = MS_VEC_LEN(dirs, const char *);
    if (wanted == 0) {
        ms_buf_free(&dirs);
        return workspace_fail(err, "workspace lists no members; name each member directory under [workspace], such as members = [\"app\", \"libs/*\"]");
    }
    MsWorkspace found = {.root = root, .members = MS_NEW_N(a, MsMember, wanted + 1)};
    bool ok = true;
    for (size_t i = 0; ok && i < wanted; i++) {
        const char *dir = MS_VEC_AT(dirs, const char *, i);
        if (ms_workspace_member_at(&found, dir) == NULL) {
            ok = workspace_member(a, root, dir, &found, &found.members[found.count], err);
            found.count += ok;
        }
    }
    ms_buf_free(&dirs);
    *out = found;
    return ok;
}

/* Whether the manifest read from `manifest` is a workspace root, or fails as unsupported when that cannot be told. */
static bool workspace_is_root(MsArena *a, const char *manifest, MsProject *project, bool *is_root, MsProjectError *err) {
    MsProjectError cause = {0};
    *is_root = false;
    if (!ms_project_read(a, manifest, project, &cause)) {
        if (ms_project_error_is_unsupported(&cause)) {
            *err = cause;
            return false;
        }
        return true; /* a broken or unrelated manifest is not a workspace; the command reports it itself */
    }
    if (project->is_workspace && project->member_count == 0) {
        ms_project_error_unsupported(err, "a [workspace] without members");
        return false;
    }
    *is_root = project->is_workspace;
    return true;
}

bool ms_workspace_find(MsArena *a, const char *manifest, MsWorkspace *out, bool *found, MsProjectError *err) {
    const char *absolute;
    const char *here;
    *found = false;
    if (!ms_path_abs(a, manifest, &absolute, err) || !ms_path_eval_symlinks(a, ms_path_dir(a, absolute), &here, err)) {
        return false;
    }
    const char *dir = here;
    for (;;) {
        const char *candidate = MS_PATH_JOIN(a, dir, "ms.toml");
        MsProject root;
        bool is_root;
        if (workspace_is_file(candidate)) {
            if (!workspace_is_root(a, candidate, &root, &is_root, err)) {
                return false;
            }
            if (is_root) {
                if (!ms_workspace_read(a, &root, out, err)) {
                    return false;
                }
                *found = strcmp(dir, here) == 0 || ms_workspace_member_at(out, here) != NULL;
                return true;
            }
        }
        const char *parent = ms_path_dir(a, dir);
        if (strcmp(parent, dir) == 0) {
            return true;
        }
        dir = parent;
    }
}

bool ms_workspace_root_members(MsArena *a, const char *manifest, MsWorkspace *out, bool *found, MsProjectError *err) {
    *found = false;
    if (strcmp(ms_path_base(a, manifest), "ms.toml") != 0 || !workspace_is_file(manifest)) {
        return true;
    }
    MsProject root;
    bool is_root;
    if (!workspace_is_root(a, manifest, &root, &is_root, err)) {
        return false;
    }
    if (!is_root || root.name[0] != 0) {
        return true;
    }
    *found = ms_workspace_read(a, &root, out, err);
    return *found;
}
