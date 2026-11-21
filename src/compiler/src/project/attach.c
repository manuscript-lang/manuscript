/* Package dependencies of a project (project.h): every `[dependencies]` url is resolved through ms.lock and the
 * read-only package cache, recursively, so a locked project builds offline. Port of `attach` and its helpers in
 * crates/ms-driver/src/project/packages.rs. Path dependencies and workspaces are not covered. */
#include <string.h>

#include "ms/packages.h"
#include "project/host.h"

#define ATTACH_MAX_DEPTH 8

typedef struct Attach {
    MsArena *arena;
    const MsLock *lock;
    const MsWorkspace *workspace; /* NULL for a project outside any workspace */
    const char *cache;
    MsBuf loaded; /* MsPackage *, in the order loaded */
    MsBuf chain;  /* const char *: the copy ids on the path from the project, to catch cycles */
} Attach;

static bool attach_fail(MsProjectError *err, const char *message) {
    ms_project_error_message(err, message);
    return false;
}

/* ---- effects ---- */

/* Whether the effect pattern `declared` is inside what the pattern `allowed` permits. */
static bool attach_pattern_covers(const char *allowed, const char *declared) {
    const size_t length = strlen(allowed);
    if (strcmp(allowed, "*") == 0 || strcmp(allowed, declared) == 0) {
        return true;
    }
    if (length >= 2 && strcmp(allowed + length - 2, ".*") == 0) {
        const size_t prefix = length - 2;
        const size_t declared_length = strlen(declared);
        return (declared_length == prefix && memcmp(declared, allowed, prefix) == 0) ||
               (declared_length > prefix && memcmp(declared, allowed, prefix) == 0 && declared[prefix] == '.');
    }
    if (strncmp(allowed, "*.", 2) == 0) {
        const size_t suffix = length - 1; /* ".name" */
        const size_t declared_length = strlen(declared);
        return strchr(declared, '*') == NULL && declared_length >= suffix && strcmp(declared + declared_length - suffix, allowed + 1) == 0;
    }
    return false;
}

/* An effect in `declared` that no pattern in `allowed` covers, or NULL. */
static const char *attach_uncovered(const char *const *allowed, uint32_t allowed_count, const char *const *declared, uint32_t declared_count) {
    for (uint32_t i = 0; i < declared_count; i++) {
        bool covered = false;
        for (uint32_t k = 0; k < allowed_count && !covered; k++) {
            covered = attach_pattern_covers(allowed[k], declared[i]);
        }
        if (!covered) {
            return declared[i];
        }
    }
    return NULL;
}

static const MsEffectRule *attach_rule(const MsProject *scope, const char *alias) {
    for (uint32_t i = 0; i < scope->allowed_effect_count; i++) {
        if (strcmp(scope->allowed_effects[i].name, alias) == 0) {
            return &scope->allowed_effects[i];
        }
    }
    return NULL;
}

/* What a project allows a dependency, and what a package may hand on. */
static bool attach_check_effects(MsArena *a, const MsProject *scope, const char *alias, const char *id, const char *asker, const MsProject *package, MsProjectError *err) {
    const char *label = strncmp(id, "workspace/", 10) == 0 ? ms_arena_fmt(a, "workspace member %s", id + 10).ptr : ms_arena_fmt(a, "package %s", id).ptr;
    const MsEffectRule *rule = attach_rule(scope, alias);
    const char *missing = attach_uncovered(rule != NULL ? rule->patterns : NULL, rule != NULL ? rule->count : 0, package->effects, package->effect_count);
    if (missing != NULL && asker[0] == 0) {
        return attach_fail(err, ms_arena_fmt(a, "%s may use %s, which this project does not allow; add `%s = [\"%s\"]` under [effects] in ms.toml if you trust it", label, missing, alias, missing).ptr);
    }
    if (missing != NULL) {
        return attach_fail(err, ms_arena_fmt(a, "%s may use %s, which %s does not allow for %s; %s would have to allow it under [effects], so ask its author, or require a version of %s that does not use %s", label, missing, asker, alias, asker, id, missing).ptr);
    }
    missing = asker[0] == 0 ? NULL : attach_uncovered(scope->effects, scope->effect_count, package->effects, package->effect_count);
    if (missing != NULL) {
        MsBuf declared = {0};
        ms_buf_putc(&declared, '[');
        for (uint32_t i = 0; i < scope->effect_count; i++) {
            ms_buf_printf(&declared, "%s%s", i > 0 ? ", " : "", ms_debug_quote(a, scope->effects[i]));
        }
        ms_buf_putc(&declared, ']');
        const char *text = ms_arena_strndup(a, declared.data, declared.len);
        ms_buf_free(&declared);
        return attach_fail(err, ms_arena_fmt(a, "%s may use %s, but %s declares only %s; a package cannot hand a dependency effects it does not have itself", label, missing, asker, text).ptr);
    }
    return true;
}

/* ---- the lock ---- */

/* The lock entry a dependency names: the copy of its repository with that pin, or the one whose compatibility range
 * holds the requirement. */
static const MsLockEntry *attach_locked(Attach *t, const MsDependency *dep, MsProjectError *err) {
    MsArena *a = t->arena;
    const char *repo = ms_repo_key(a, dep->url);
    const MsLockEntry *found = NULL;
    if (dep->kind != MS_DEP_VERSION) {
        found = ms_lock_find(t->lock, ms_copy_id(a, dep->url, dep->reference));
    } else {
        const char *prefix = ms_arena_fmt(a, "%s@", repo).ptr;
        const MsBucket want = ms_requirement_bucket(&dep->requirement);
        for (uint32_t i = 0; i < t->lock->count && found == NULL; i++) {
            const MsLockEntry *entry = &t->lock->entries[i];
            MsVersion version;
            if (strncmp(entry->key, prefix, strlen(prefix)) == 0 && ms_lock_entry_version(a, entry, &version) &&
                ms_bucket_equal(ms_version_bucket(&version), want) && ms_requirement_matches(&dep->requirement, &version)) {
                found = entry;
            }
        }
    }
    if (found == NULL) {
        attach_fail(err, ms_arena_fmt(a, "ms.lock has no copy of %s for %s = %s; run `ms install` to resolve and pin it", repo, dep->alias, ms_dependency_describe(a, dep)).ptr);
    }
    return found;
}

/* The files of the stored index with the hash `hash`, checked to be the one the lock names. */
static bool attach_read_index(Attach *t, const char *hash, const char *id, MsPackage *out, MsProjectError *err) {
    MsArena *a = t->arena;
    size_t length = 0;
    const char *text = ms_project_read_file(a, MS_PATH_JOIN(a, t->cache, ms_arena_fmt(a, "%s.index", hash).ptr), &length, err);
    if (text == NULL) {
        return false;
    }
    if (strcmp(ms_package_hash(a, (MsStr){text, (uint32_t)length}), hash) != 0) {
        return attach_fail(err, ms_arena_fmt(a, "the index of package %s does not match ms.lock; run `ms install` to restore it", id).ptr);
    }
    MsBuf files = {0};
    MsBuf hashes = {0};
    for (size_t at = 0; at < length;) {
        const char *end = memchr(text + at, '\n', length - at);
        const size_t line_end = end != NULL ? (size_t)(end - text) : length;
        const char *zero = memchr(text + at, 0, line_end - at);
        if (zero != NULL) {
            const char *path = ms_arena_strndup(a, text + at, (size_t)(zero - (text + at)));
            const char *digest = ms_arena_strndup(a, zero + 1, line_end - (size_t)(zero + 1 - text));
            MS_VEC_PUSH(files, const char *, path);
            MS_VEC_PUSH(hashes, const char *, digest);
        }
        at = line_end + 1;
    }
    out->file_count = (uint32_t)MS_VEC_LEN(files, const char *);
    const char **kept_files = MS_NEW_N(a, const char *, out->file_count + 1);
    const char **kept_hashes = MS_NEW_N(a, const char *, out->file_count + 1);
    for (uint32_t i = 0; i < out->file_count; i++) {
        kept_files[i] = MS_VEC_AT(files, const char *, i);
        kept_hashes[i] = MS_VEC_AT(hashes, const char *, i);
    }
    out->files = kept_files;
    out->hashes = kept_hashes;
    ms_buf_free(&files);
    ms_buf_free(&hashes);
    return true;
}

bool ms_package_verify_file(MsArena *a, const MsPackage *package, const char *canonical, const void *bytes, size_t length, MsProjectError *err) {
    const char *relative;
    MsProjectError ignored;
    if (package->member || !ms_path_rel(a, package->root, canonical, &relative, &ignored)) {
        return true;
    }
    char digest[65];
    ms_sha256_hex(bytes, length, digest);
    for (uint32_t i = 0; i < package->file_count; i++) {
        if (strcmp(package->files[i], relative) != 0) {
            continue;
        }
        if (strcmp(package->hashes[i], digest) == 0) {
            return true;
        }
        return attach_fail(err, ms_arena_fmt(a, "%s/%s in the cache does not match ms.lock; run `ms install` to restore it", package->key, relative).ptr);
    }
    return attach_fail(err, ms_arena_fmt(a, "%s/%s is not in the locked package; run `ms install` to restore it", package->key, relative).ptr);
}

/* ---- wiring ---- */

static bool attach_wire(Attach *t, MsProject *scope, const char *asker, MsProjectError *err);

/* The failure to read a package's manifest: an unsupported form stays so, any other error names the package. */
static bool attach_manifest_failed(MsArena *a, const char *id, const MsProjectError *cause, MsProjectError *err) {
    if (ms_project_error_is_unsupported(cause)) {
        *err = *cause;
        return false;
    }
    return attach_fail(err, ms_arena_fmt(a, "package %s: %s", id, ms_project_error_text(a, cause)).ptr);
}

/* Reads and checks one locked copy, and wires its own dependencies. */
static MsPackage *attach_load_copy(Attach *t, const char *id, const MsLockEntry *entry, MsProjectError *err) {
    MsArena *a = t->arena;
    const char *directory = MS_PATH_JOIN(a, t->cache, entry->sha256);
    MsSysStat info;
    if (ms_sys_fs_stat(directory, true, &info) != 0 || !host_is_dir(&info)) {
        attach_fail(err, ms_arena_fmt(a, "package %s (%s) is not in the cache %s; run `ms install` to download it", id, entry->spec, directory).ptr);
        return NULL;
    }
    MsPackage *package = MS_NEW(a, MsPackage);
    *package = (MsPackage){0}; /* MS_NEW does not zero */
    package->key = ms_arena_fmt(a, "@%s", id).ptr;
    package->spec = entry->spec;
    if (!attach_read_index(t, entry->sha256, id, package, err) || !ms_path_eval_symlinks(a, directory, &package->root, err)) {
        return NULL;
    }
    const char *manifest = MS_PATH_JOIN(a, package->root, "ms.toml");
    size_t length = 0;
    const char *text = ms_project_read_file(a, manifest, &length, err);
    if (text == NULL || !ms_package_verify_file(a, package, manifest, text, length, err)) {
        return NULL;
    }
    MsProjectError cause = {0};
    if (!ms_project_read(a, manifest, &package->project, &cause)) {
        attach_manifest_failed(a, id, &cause, err);
        return NULL;
    }
    MsProject *project = &package->project;
    if (project->embed_count > 0) {
        attach_fail(err, ms_arena_fmt(a, "package %s declares [embed]; a package holds source only", id).ptr);
        return NULL;
    }
    const char *hash = strchr(entry->spec, '#');
    if (hash != NULL) {
        const char *url = ms_arena_strndup(a, entry->spec, (size_t)(hash - entry->spec));
        const MsPackageManifest declared = {.has_version = project->has_version, .version = project->version};
        const char *mismatch = ms_check_version_agrees(a, "package", url, hash + 1, &declared);
        if (mismatch != NULL) {
            attach_fail(err, mismatch);
            return NULL;
        }
    }
    if (project->path_dependency_count > 0 || project->is_workspace) {
        attach_fail(err, ms_arena_fmt(a, "package %s uses a path dependency or [workspace]; a fetched package depends on urls only", id).ptr);
        return NULL;
    }
    MS_VEC_PUSH(t->chain, const char *, id);
    const bool wired = attach_wire(t, project, id, err);
    MS_VEC_POP(t->chain, const char *);
    return wired ? package : NULL;
}

static bool attach_chain_has(const Attach *t, const char *id) {
    for (size_t k = 0; k < MS_VEC_LEN(t->chain, const char *); k++) {
        if (strcmp(MS_VEC_AT(t->chain, const char *, k), id) == 0) {
            return true;
        }
    }
    return false;
}

static const MsPackage *attach_find_loaded(const Attach *t, const char *id) {
    for (size_t i = 0; i < MS_VEC_LEN(t->loaded, MsPackage *); i++) {
        const MsPackage *p = MS_VEC_AT(t->loaded, MsPackage *, i);
        if (strcmp(p->key + 1, id) == 0) {
            return p;
        }
    }
    return NULL;
}

/* Loads the workspace member at `dir` once and returns its id, or NULL. */
static const char *attach_member(Attach *t, const char *alias, const char *dir, MsProjectError *err) {
    MsArena *a = t->arena;
    if (t->workspace == NULL) {
        attach_fail(err, ms_arena_fmt(a, "%s is a path dependency, but no ancestor ms.toml has [workspace] members listing this project; add a workspace root or use a url dependency", alias).ptr);
        return NULL;
    }
    const MsMember *member = ms_workspace_member_at(t->workspace, dir);
    if (member == NULL) {
        attach_fail(err, ms_arena_fmt(a, "%s points at %s, which is not a workspace member; list it under [workspace] members in %s/ms.toml", alias, dir, t->workspace->root).ptr);
        return NULL;
    }
    const char *id = ms_arena_fmt(a, "workspace/%s", member->name).ptr;
    if (attach_chain_has(t, id)) {
        attach_fail(err, ms_arena_fmt(a, "workspace member %s depends on itself through %s; members cannot form a cycle", member->name, alias).ptr);
        return NULL;
    }
    if (attach_find_loaded(t, id) != NULL) {
        return id;
    }
    MsPackage *package = MS_NEW(a, MsPackage);
    *package = (MsPackage){0}; /* MS_NEW does not zero */
    MsProjectError cause = {0};
    if (!ms_project_read(a, MS_PATH_JOIN(a, member->root, "ms.toml"), &package->project, &cause)) {
        attach_manifest_failed(a, id, &cause, err);
        return NULL;
    }
    MS_VEC_PUSH(t->chain, const char *, id);
    const bool wired = attach_wire(t, &package->project, id, err);
    MS_VEC_POP(t->chain, const char *);
    if (!wired) {
        return NULL;
    }
    package->key = ms_arena_fmt(a, "@%s", id).ptr;
    package->spec = ms_arena_fmt(a, "workspace member %s", member->name).ptr;
    package->root = member->root;
    package->member = true;
    MS_VEC_PUSH(t->loaded, MsPackage *, package);
    return id;
}

static bool attach_wire(Attach *t, MsProject *scope, const char *asker, MsProjectError *err) {
    MsArena *a = t->arena;
    const size_t depth = MS_VEC_LEN(t->chain, const char *);
    if (depth >= ATTACH_MAX_DEPTH) {
        return attach_fail(err, ms_arena_fmt(a, "packages nest more than %d deep at %s", ATTACH_MAX_DEPTH, asker).ptr);
    }
    scope->deps = MS_NEW_N(a, MsAlias, scope->dependency_count + scope->path_dependency_count + 1);
    for (uint32_t i = 0; i < scope->dependency_count; i++) {
        const MsDependency *dep = &scope->dependencies[i];
        const MsLockEntry *entry = attach_locked(t, dep, err);
        if (entry == NULL) {
            return false;
        }
        const char *id = entry->key;
        for (size_t k = 0; k < depth; k++) {
            if (strcmp(MS_VEC_AT(t->chain, const char *, k), id) == 0) {
                return attach_fail(err, ms_arena_fmt(a, "package %s depends on itself", id).ptr);
            }
        }
        const MsPackage *package = attach_find_loaded(t, id);
        if (package == NULL) {
            MsPackage *loaded = attach_load_copy(t, id, entry, err);
            if (loaded == NULL) {
                return false;
            }
            MS_VEC_PUSH(t->loaded, MsPackage *, loaded);
            package = loaded;
        }
        if (!attach_check_effects(a, scope, dep->alias, id, asker, &package->project, err)) {
            return false;
        }
        scope->deps[scope->dep_count++] = (MsAlias){.name = dep->alias, .target = package->project.source};
    }
    for (uint32_t i = 0; i < scope->path_dependency_count; i++) {
        const MsAlias *dep = &scope->path_dependencies[i];
        const char *id = attach_member(t, dep->name, dep->target, err);
        if (id == NULL) {
            return false;
        }
        const MsPackage *package = attach_find_loaded(t, id);
        if (!attach_check_effects(a, scope, dep->name, id, asker, &package->project, err)) {
            return false;
        }
        scope->deps[scope->dep_count++] = (MsAlias){.name = dep->name, .target = package->project.source};
    }
    return true;
}

bool ms_project_attach(MsArena *a, MsProject *p, MsProjectError *err) {
    if (p->dependency_count == 0 && p->path_dependency_count == 0) {
        return true;
    }
    MsWorkspace workspace = {0};
    bool in_workspace;
    if (!ms_workspace_find(a, MS_PATH_JOIN(a, p->root, "ms.toml"), &workspace, &in_workspace, err)) {
        return false;
    }
    /* Package files are named `@name/...`; a project path with that spelling would be mistaken for package code. */
    for (uint32_t i = 0; i < p->dependency_count + p->path_dependency_count; i++) {
        const char *alias = i < p->dependency_count ? p->dependencies[i].alias : p->path_dependencies[i - p->dependency_count].name;
        MsSysStat info;
        if (ms_sys_fs_stat(MS_PATH_JOIN(a, p->root, alias), true, &info) == 0) {
            return attach_fail(err, ms_arena_fmt(a, "the project has a file or directory named %s, which is also a dependency name; rename it, names starting with @ are reserved for packages", alias).ptr);
        }
    }
    MsLock lock;
    if (!ms_lock_read(a, in_workspace ? workspace.root : p->root, &lock, err)) { /* a workspace shares the lock at its root */
        return false;
    }
    Attach t = {.arena = a, .lock = &lock, .workspace = in_workspace ? &workspace : NULL, .cache = ms_package_cache_dir(a)};
    const bool wired = attach_wire(&t, p, "", err);
    if (wired) {
        const uint32_t count = (uint32_t)MS_VEC_LEN(t.loaded, MsPackage *);
        p->packages = MS_NEW_N(a, MsPackage, count + 1);
        p->package_count = count;
        for (uint32_t i = 0; i < count; i++) {
            p->packages[i] = *MS_VEC_AT(t.loaded, MsPackage *, i);
        }
        /* Sorted by key, as the Rust map iterates. */
        for (uint32_t i = 1; i < count; i++) {
            const MsPackage moved = p->packages[i];
            uint32_t k = i;
            for (; k > 0 && strcmp(p->packages[k - 1].key, moved.key) > 0; k--) {
                p->packages[k] = p->packages[k - 1];
            }
            p->packages[k] = moved;
        }
    }
    ms_buf_free(&t.loaded);
    ms_buf_free(&t.chain);
    return wired;
}

/* ---- scopes ---- */

static bool attach_inside(const char *root, const char *path) {
    const size_t length = strlen(root);
    return strncmp(path, root, length) == 0 && (path[length] == 0 || path[length] == '/');
}

const MsPackage *ms_project_package_of(const MsProject *p, const char *path) {
    const MsPackage *best = NULL;
    for (uint32_t i = 0; i < p->package_count; i++) {
        if (attach_inside(p->packages[i].root, path) && (best == NULL || strlen(p->packages[i].root) > strlen(best->root))) {
            best = &p->packages[i];
        }
    }
    return best;
}

const MsProject *ms_project_scope(const MsProject *p, const char *importer) {
    const MsPackage *package = ms_project_package_of(p, importer);
    return package != NULL ? &package->project : p;
}

const char *ms_project_confinement_root(const MsProject *p, const char *importer, const char *path, const char *target) {
    const MsPackage *own = ms_project_package_of(p, importer);
    const char *root = own != NULL ? own->root : p->root;
    if (path[0] != '@') {
        return root;
    }
    const MsPackage *held = ms_project_package_of(p, target);
    return held != NULL ? held->root : root;
}

bool ms_project_logical(MsArena *a, const MsProject *p, const char *canonical, const char **out, MsProjectError *err) {
    const MsPackage *package = ms_project_package_of(p, canonical);
    if (package == NULL) {
        return ms_path_rel(a, p->root, canonical, out, err);
    }
    const char *relative;
    if (!ms_path_rel(a, package->root, canonical, &relative, err)) {
        return false;
    }
    *out = ms_arena_fmt(a, "%s/%s", package->key, relative).ptr;
    return true;
}
