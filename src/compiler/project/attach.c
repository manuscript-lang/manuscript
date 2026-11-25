/* Owns attaching the packages a project reaches (package.h): reading the lock, loading each locked copy from the
 * cache, checking it against the index, and wiring its own dependencies. */
#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/sha256.h"
#include "base/sort.h"
#include "compiler/project/attach_internal.h"
#include "compiler/project/lock.h"
#include "compiler/project/solve.h"
#include "compiler/project/workspace.h"

/* The most nested packages one project may pull in a chain. */
enum { kMaxDepth = 8 };

MS_LIST_DEFINE(PackageList, package_list, MsPackage)
MS_LIST_DEFINE(IdList, id_list, MsSpan)

typedef struct Wiring {
  MsArena *arena;
  MsWorkspace workspace;
  bool in_workspace;
  MsLockList lock;
  MsSpan cache;
  PackageList loaded;
  IdList chain; /* the copies and members on the path from the project, to catch cycles */
  MsProjectError *error;
} Wiring;

static bool fail(Wiring *w, MsSpan message) {
  ms_project_error_message(w->error, message);
  return false;
}

static MsSpan joined(MsArena *arena, MsSpan left, MsSpan right) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, left, right);
  return ms_message_take_builder(arena, &path);
}

static const MsPackage *loaded_id(const Wiring *w, MsSpan id) {
  for (size_t i = 0; i < w->loaded.len; i++) {
    if (ms_span_equal(w->loaded.ptr[i].id, id)) {
      return &w->loaded.ptr[i];
    }
  }
  return NULL;
}

static bool on_chain(const Wiring *w, MsSpan id) {
  for (size_t i = 0; i < w->chain.len; i++) {
    if (ms_span_equal(w->chain.ptr[i], id)) {
      return true;
    }
  }
  return false;
}

/* ---- the index ---- */

static bool read_index(Wiring *w, MsSpan hash, MsSpan id, MsPackage *package) {
  const MsSpan path = ms_lock_index_path(w->arena, w->cache, hash);
  MsBytes bytes = {0};
  if (!ms_file_read(path, &bytes)) {
    ms_project_error_path(w->error, "open", path, 2);
    return false;
  }
  const MsSpan text = ms_arena_copy(w->arena, ms_bytes_span(&bytes));
  ms_bytes_free(&bytes);
  if (!ms_span_equal(ms_lock_hash_index(w->arena, text), hash)) {
    return fail(w, ms_message_format(w->arena, "the index of package %S does not match ms.lock; run `ms install` to "
                                               "restore it", id));
  }
  size_t lines = 0;
  for (size_t i = 0; i < text.len; i++) {
    lines += text.ptr[i] == '\n' ? 1 : 0;
  }
  package->files = MS_ARENA_NEW_ARRAY(w->arena, MsPackageFile, lines + 1);
  size_t start = 0;
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] != '\n') {
      continue;
    }
    const MsSpan line = ms_span_of(text.ptr + start, i - start);
    start = i + 1;
    size_t zero = 0;
    while (zero < line.len && line.ptr[zero] != 0) {
      zero++;
    }
    if (zero < line.len) {
      package->files[package->nfiles++] = (MsPackageFile){.path = ms_span_of(line.ptr, zero),
                                                          .hash = ms_span_of(line.ptr + zero + 1, line.len - zero - 1)};
    }
  }
  return true;
}

bool ms_package_verify_file(MsArena *arena, const MsPackage *package, MsSpan relative, MsSpan bytes,
                            MsProjectError *error) {
  if (package->member) {
    return true;
  }
  for (size_t i = 0; i < package->nfiles; i++) {
    if (!ms_span_equal(package->files[i].path, relative)) {
      continue;
    }
    uint8_t digest[MS_SHA256_HEX_LEN];
    ms_sha256_hex(bytes, digest);
    if (ms_span_equal(ms_span_of(digest, sizeof(digest)), package->files[i].hash)) {
      return true;
    }
    ms_project_error_message(error, ms_message_format(arena,
                                                      "%S/%S in the cache does not match ms.lock; run `ms install` "
                                                      "to restore it",
                                                      package->key, relative));
    return false;
  }
  ms_project_error_message(error, ms_message_format(arena,
                                                    "%S/%S is not in the locked package; run `ms install` to "
                                                    "restore it",
                                                    package->key, relative));
  return false;
}

/* ---- the lock entry a dependency names ---- */

static const MsLockEntry *locked_for(Wiring *w, const MsDependency *dep) {
  const MsSpan repo = ms_lock_repo_key(w->arena, dep->url);
  if (dep->kind != MS_SOURCE_VERSION) {
    const MsSpan id = ms_lock_copy_id(w->arena, dep->url, dep->reference);
    for (size_t i = 0; i < w->lock.len; i++) {
      if (ms_span_equal(w->lock.ptr[i].id, id)) {
        return &w->lock.ptr[i];
      }
    }
    return NULL;
  }
  const MsSpan prefix = ms_message_format(w->arena, "%S@", repo);
  const MsBucket bucket = ms_requirement_bucket(&dep->requirement);
  for (size_t i = 0; i < w->lock.len; i++) {
    MsVersion version = {0};
    if (ms_span_starts_with(w->lock.ptr[i].id, prefix) && ms_lock_entry_version(w->arena, &w->lock.ptr[i], &version) &&
        ms_bucket_equal(ms_version_bucket(&version), bucket) && ms_requirement_matches(&dep->requirement, &version)) {
      return &w->lock.ptr[i];
    }
  }
  return NULL;
}

static bool locked_error(Wiring *w, const MsDependency *dep) {
  return fail(w, ms_message_format(w->arena,
                                   "ms.lock has no copy of %S for %S = %S; run `ms install` to resolve and pin it",
                                   ms_lock_repo_key(w->arena, dep->url), dep->name,
                                   ms_dependency_describe(w->arena, dep)));
}

/* ---- loading ---- */

static bool wire(Wiring *w, MsManifest *scope, MsSpan asker);

static MsManifest *read_package_manifest(Wiring *w, MsSpan id, MsSpan manifest_path) {
  MsManifest *package = MS_ARENA_NEW(w->arena, MsManifest);
  MsProjectError cause = {0};
  if (!ms_manifest_read(w->arena, manifest_path, package, &cause)) {
    fail(w, ms_message_format(w->arena, "package %S: %S", id, ms_project_error_text(w->arena, &cause)));
    return NULL;
  }
  return package;
}

/* The checks on a locked copy's manifest that need no wiring. */
static bool check_copy(Wiring *w, MsSpan id, const MsLockEntry *entry, const MsManifest *package) {
  if (package->embeds.len != 0) {
    return fail(w, ms_message_format(w->arena, "package %S declares [embed]; a package holds source only", id));
  }
  MsSpan url = {0};
  size_t hash = 0;
  while (hash < entry->spec.len && entry->spec.ptr[hash] != '#') {
    hash++;
  }
  if (hash < entry->spec.len) {
    url = ms_span_of(entry->spec.ptr, hash);
    MsSpan message = {0};
    if (!ms_resolve_check_version(w->arena, "package", url,
                                  ms_span_of(entry->spec.ptr + hash + 1, entry->spec.len - hash - 1), package,
                                  &message)) {
      return fail(w, message);
    }
  }
  if (package->path_dependencies.len != 0 || package->is_workspace) {
    return fail(w, ms_message_format(w->arena,
                                     "package %S uses a path dependency or [workspace]; a fetched package depends "
                                     "on urls only",
                                     id));
  }
  return true;
}

/* Reads and checks one locked copy, and wires its own dependencies. */
static bool load_copy(Wiring *w, MsSpan id, const MsLockEntry *entry, MsPackage *out) {
  const MsSpan directory = joined(w->arena, w->cache, entry->sha256);
  if (!ms_dir_exists(directory)) {
    return fail(w, ms_message_format(w->arena, "package %S (%S) is not in the cache %S; run `ms install` to download it",
                                     id, entry->spec, directory));
  }
  *out = (MsPackage){.id = id, .key = ms_message_format(w->arena, "@%S", id), .spec = entry->spec};
  MsString real = ms_string_empty();
  if (!read_index(w, entry->sha256, id, out)) {
    return false;
  }
  if (!ms_file_real_path(directory, &real)) {
    ms_project_error_path(w->error, "lstat", directory, 2);
    return false;
  }
  out->root = ms_arena_copy(w->arena, ms_string_span(&real));
  ms_string_release(&real);
  const MsSpan manifest_path = joined(w->arena, out->root, ms_span_of_text("ms.toml"));
  MsBytes bytes = {0};
  if (!ms_file_read(manifest_path, &bytes)) {
    ms_project_error_path(w->error, "open", manifest_path, 2);
    return false;
  }
  const bool verified = ms_package_verify_file(w->arena, out, ms_span_of_text("ms.toml"), ms_bytes_span(&bytes), w->error);
  ms_bytes_free(&bytes);
  out->manifest = verified ? read_package_manifest(w, id, manifest_path) : NULL;
  if (out->manifest == NULL || !check_copy(w, id, entry, out->manifest)) {
    return false;
  }
  id_list_push(&w->chain, id);
  const bool wired = wire(w, out->manifest, id);
  w->chain.len--;
  return wired;
}

/* Loads the workspace member at `directory` once and returns its id. */
static bool load_member(Wiring *w, MsSpan alias, MsSpan directory, MsSpan *id) {
  if (!w->in_workspace) {
    return fail(w, ms_message_format(w->arena,
                                     "%S is a path dependency, but no ancestor ms.toml has [workspace] members "
                                     "listing this project; add a workspace root or use a url dependency",
                                     alias));
  }
  const MsWorkspaceMember *member = ms_workspace_member_at(&w->workspace, directory);
  if (member == NULL) {
    return fail(w, ms_message_format(w->arena,
                                     "%S points at %S, which is not a workspace member; list it under [workspace] "
                                     "members in %S/ms.toml",
                                     alias, directory, w->workspace.root));
  }
  *id = ms_message_format(w->arena, "workspace/%S", member->name);
  if (on_chain(w, *id)) {
    return fail(w, ms_message_format(w->arena,
                                     "workspace member %S depends on itself through %S; members cannot form a "
                                     "cycle",
                                     member->name, alias));
  }
  if (loaded_id(w, *id) != NULL) {
    return true;
  }
  MsPackage package = {.id = *id, .key = ms_message_format(w->arena, "@%S", *id),
                       .spec = ms_message_format(w->arena, "workspace member %S", member->name),
                       .root = member->root, .member = true};
  package.manifest = read_package_manifest(w, *id, ms_workspace_manifest(w->arena, member));
  if (package.manifest == NULL) {
    return false;
  }
  id_list_push(&w->chain, *id);
  const bool wired = wire(w, package.manifest, *id);
  w->chain.len--;
  if (wired) {
    package_list_push(&w->loaded, package);
  }
  return wired;
}

static void add_dep(Wiring *w, MsManifest *scope, MsSpan alias, const MsManifest *package) {
  manifest_name_list_push(&scope->deps, (MsManifestName){.name = alias, .target = package->source});
  (void)w;
}

static bool wire_url(Wiring *w, MsManifest *scope, const MsDependency *dep, MsSpan asker) {
  const MsLockEntry *entry = locked_for(w, dep);
  if (entry == NULL) {
    return locked_error(w, dep);
  }
  if (on_chain(w, entry->id)) {
    return fail(w, ms_message_format(w->arena, "package %S depends on itself", entry->id));
  }
  if (loaded_id(w, entry->id) == NULL) {
    MsPackage package = {0};
    if (!load_copy(w, entry->id, entry, &package)) {
      return false;
    }
    package_list_push(&w->loaded, package);
  }
  const MsPackage *package = loaded_id(w, entry->id);
  if (!attach_check_effects(w->arena, scope, dep->name, entry->id, asker, package->manifest, w->error)) {
    return false;
  }
  add_dep(w, scope, dep->name, package->manifest);
  return true;
}

static bool wire(Wiring *w, MsManifest *scope, MsSpan asker) {
  if (w->chain.len >= kMaxDepth) {
    return fail(w, ms_message_format(w->arena, "packages nest more than %u deep at %S", (unsigned)kMaxDepth, asker));
  }
  for (size_t i = 0; i < scope->dependencies.len; i++) {
    if (!wire_url(w, scope, &scope->dependencies.ptr[i], asker)) {
      return false;
    }
  }
  for (size_t i = 0; i < scope->path_dependencies.len; i++) {
    MsSpan id = {0};
    const MsManifestName *dep = &scope->path_dependencies.ptr[i];
    if (!load_member(w, dep->name, dep->target, &id)) {
      return false;
    }
    const MsPackage *package = loaded_id(w, id);
    if (!attach_check_effects(w->arena, scope, dep->name, id, asker, package->manifest, w->error)) {
      return false;
    }
    add_dep(w, scope, dep->name, package->manifest);
  }
  return true;
}

/* Package files are named `@name/...`; a project path with that spelling would be mistaken for package code. */
static bool check_alias_collisions(Wiring *w, const MsManifest *project) {
  for (size_t round = 0; round < 2; round++) {
    const size_t count = round == 0 ? project->dependencies.len : project->path_dependencies.len;
    for (size_t i = 0; i < count; i++) {
      const MsSpan alias = round == 0 ? project->dependencies.ptr[i].name : project->path_dependencies.ptr[i].name;
      if (ms_path_kind(joined(w->arena, project->root, alias)) != MS_PATH_MISSING) {
        return fail(w, ms_message_format(w->arena,
                                         "the project has a file or directory named %S, which is also a dependency "
                                         "name; rename it, names starting with @ are reserved for packages",
                                         alias));
      }
    }
  }
  return true;
}

static int64_t compare_packages(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsSpan x = ((const MsPackage *)(const void *)a)->id;
  const MsSpan y = ((const MsPackage *)(const void *)b)->id;
  const size_t common = x.len < y.len ? x.len : y.len;
  for (size_t i = 0; i < common; i++) {
    if (x.ptr[i] != y.ptr[i]) {
      return x.ptr[i] < y.ptr[i] ? -1 : 1;
    }
  }
  return x.len == y.len ? 0 : (x.len < y.len ? -1 : 1);
}

static bool attach_in(Wiring *w, MsManifest *project) {
  MsSpan lock_error = {0};
  const MsSpan manifest_path = joined(w->arena, project->root, ms_span_of_text("ms.toml"));
  if (!ms_workspace_find(w->arena, manifest_path, &w->workspace, &w->in_workspace, w->error) ||
      !check_alias_collisions(w, project)) {
    return false;
  }
  /* A workspace shares the lock at its root. */
  if (!ms_lock_read(w->arena, w->in_workspace ? w->workspace.root : project->root, &w->lock, &lock_error)) {
    return fail(w, lock_error);
  }
  w->cache = ms_lock_cache_dir(w->arena);
  if (!wire(w, project, (MsSpan){0})) {
    return false;
  }
  ms_sort((uint8_t *)w->loaded.ptr, w->loaded.len, sizeof(MsPackage), compare_packages, NULL);
  project->packages = MS_ARENA_NEW_ARRAY(w->arena, MsPackage, w->loaded.len + 1);
  for (size_t i = 0; i < w->loaded.len; i++) {
    project->packages[i] = w->loaded.ptr[i];
  }
  project->npackages = w->loaded.len;
  return true;
}

bool ms_package_attach(MsArena *arena, MsManifest *project, MsProjectError *error) {
  if (project->dependencies.len == 0 && project->path_dependencies.len == 0) {
    return true;
  }
  Wiring w = {.arena = arena, .error = error};
  const bool ok = attach_in(&w, project);
  package_list_free(&w.loaded);
  id_list_free(&w.chain);
  ms_lock_list_free(&w.lock);
  return ok;
}
