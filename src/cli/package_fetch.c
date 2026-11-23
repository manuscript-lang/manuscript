/* Owns the git-backed remote (package_fetch.h): listing tags, downloading into a temporary directory, hashing, and
 * storing the verified package in the cache. */
#include "cli/package_fetch.h"

#include "cli/package_cache.h"

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "compiler/project/lock.h"
#include "compiler/project/package.h"
#include "compiler/project/project.h"
#include "cli/package_validate.h"

static const char *protocols_for(MsSpan url, bool nested) {
  if (nested || ms_span_starts_with(url, ms_span_of_text("https://"))) {
    return "https";
  }
  return "https:file";
}

/* A C string of `text` in the arena. */
static const char *c_text(MsArena *arena, MsSpan text) {
  uint8_t *bytes = MS_ARENA_NEW_ARRAY(arena, uint8_t, text.len + 1);
  for (size_t i = 0; i < text.len; i++) {
    bytes[i] = text.ptr[i];
  }
  return (const char *)bytes;
}

static bool remote_tags(void *self, MsArena *arena, MsSpan url, MsSpan **tags, size_t *count, MsSpan *error) {
  MsGitRemote *remote = self;
  const char *const args[] = {"ls-remote", "--tags", "--refs", "--", c_text(arena, url)};
  MsSpan listing = {0};
  const bool plain = ms_span_starts_with(url, ms_span_of_text("https://"));
  if (!ms_git_run(&remote->git, (MsSpan){0}, plain ? "https" : "https:file", args, 5, &listing, error)) {
    return false;
  }
  *tags = MS_ARENA_NEW_ARRAY(arena, MsSpan, listing.len / 2 + 1);
  *count = 0;
  const MsSpan marker = ms_span_of_text("\trefs/tags/");
  size_t start = 0;
  for (size_t i = 0; i <= listing.len; i++) {
    if (i < listing.len && listing.ptr[i] != '\n') {
      continue;
    }
    const MsSpan line = ms_span_of(listing.ptr + start, i - start);
    size_t at = 0;
    if (ms_span_find(line, marker, &at)) {
      (*tags)[(*count)++] = ms_span_of(line.ptr + at + marker.len, line.len - at - marker.len);
    }
    start = i + 1;
  }
  return true;
}

/* ---- the cache ---- */

static MsSpan joined(MsArena *arena, MsSpan left, MsSpan right) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, left, right);
  const MsSpan copy = ms_message_from_builder(arena, &path);
  ms_strbuild_free(&path);
  return copy;
}

/* Whether the cache holds the package with `hash` exactly as it was stored: its index is the one the hash names and
 * its files are the ones the index lists. */
static bool cached_intact(MsArena *arena, MsSpan cache, MsSpan hash) {
  MsBytes stored = {0};
  if (!ms_file_read(ms_lock_index_path(arena, cache, hash), &stored)) {
    return false;
  }
  const MsSpan index = ms_arena_copy(arena, ms_bytes_span(&stored));
  ms_bytes_free(&stored);
  MsSpan found = {0};
  MsSpan error = {0};
  return ms_span_equal(ms_lock_hash_index(arena, index), hash) &&
         ms_lock_index_tree(arena, joined(arena, cache, hash), &found, &error) && ms_span_equal(found, index);
}

static bool store(MsArena *arena, MsSpan cache, MsSpan hash, MsSpan index, MsSpan temporary, MsSpan *error) {
  if (cached_intact(arena, cache, hash)) {
    return true;
  }
  /* The index goes first and atomically, so a directory that exists is complete beside its index. */
  const MsSpan index_file = ms_lock_index_path(arena, cache, hash);
  const MsSpan staged = ms_message_format(arena, "%S.staged", index_file);
  const MsSpan destination = joined(arena, cache, hash);
  if (!ms_file_write(staged, index) || !ms_file_rename(staged, index_file)) {
    *error = ms_message_format(arena, "cannot write %S; check that the cache directory is writable", index_file);
    return false;
  }
  if (ms_path_kind(destination) != MS_PATH_MISSING) {
    ms_cache_unprotect(destination);
    ms_path_remove_tree(destination);
  }
  if (!ms_file_rename(temporary, destination) && !cached_intact(arena, cache, hash)) {
    *error = ms_message_format(arena, "store %S: cannot move the package into the cache", destination);
    return false;
  }
  ms_cache_protect(destination);
  return true;
}

/* ---- downloading ---- */

typedef struct Download {
  MsGitRemote *remote;
  MsArena *arena;
  MsSpan key, url, reference, temporary, cache;
  const MsLockEntry *locked;
  const char *protocols;
} Download;

static bool git_in(const Download *d, const char *const *args, size_t count, MsSpan *error) {
  MsSpan output = {0};
  return ms_git_run(&d->remote->git, d->temporary, d->protocols, args, count, &output, error);
}

static bool fetch_revision(Download *d, MsSpan *error) {
  const char *revision = d->locked != NULL ? c_text(d->arena, d->locked->revision) : c_text(d->arena, d->reference);
  const bool commit = d->locked != NULL || ms_package_is_hex(d->reference, 40);
  const char *refspec = c_text(d->arena, ms_message_format(d->arena, "refs/tags/%S:refs/tags/%S", d->reference,
                                                           d->reference));
  const char *const by_commit[] = {"fetch", "--quiet", "--depth", "1", "--", "origin", revision};
  const char *const by_tag[] = {"fetch", "--quiet", "--depth", "1", "--", "origin", refspec};
  MsSpan said = {0};
  if (git_in(d, commit ? by_commit : by_tag, 7, &said)) {
    return true;
  }
  const bool missing = !commit && ms_span_find(said, ms_span_of_text("couldn't find remote ref"), &(size_t){0});
  *error = missing ? ms_message_format(d->arena, "package %S: %S is not a tag of %S: %S", d->key, d->reference,
                                       d->url, said)
                   : ms_message_format(d->arena, "package %S: %S", d->key, said);
  return false;
}

/* The commit the checkout is at: the first 40-digit line git printed. */
static bool resolve_commit(Download *d, MsSpan *commit, MsSpan *error) {
  const bool head = d->locked != NULL || ms_package_is_hex(d->reference, 40);
  const char *name = head ? "FETCH_HEAD" : c_text(d->arena, ms_message_format(d->arena, "refs/tags/%S^{commit}",
                                                                              d->reference));
  const char *const args[] = {"rev-parse", "--verify", name};
  MsSpan output = {0};
  if (!ms_git_run(&d->remote->git, d->temporary, d->protocols, args, 3, &output,
                  error)) {
    return false;
  }
  size_t start = 0;
  for (size_t i = 0; i <= output.len; i++) {
    if (i == output.len || output.ptr[i] == '\n') {
      const MsSpan line = ms_span_of(output.ptr + start, i - start);
      if (ms_package_is_hex(line, 40)) {
        *commit = line;
        return true;
      }
      start = i + 1;
    }
  }
  *error = ms_span_of_text("git rev-parse printed no commit");
  return false;
}

static bool prepare(Download *d, MsSpan *error) {
  const char *const init[] = {"init", "--quiet"};
  const char *const add[] = {"remote", "add", "--", "origin", c_text(d->arena, d->url)};
  return git_in(d, init, 2, error) && git_in(d, add, 5, error) && fetch_revision(d, error);
}

static bool checkout(Download *d, MsSpan commit, MsSpan *error) {
  const char *const args[] = {"checkout", "--quiet", "--force", c_text(d->arena, commit), "--"};
  return git_in(d, args, 5, error) &&
         ms_package_reject_unportable(&d->remote->git, d->key, d->temporary, d->protocols, error);
}

/* Downloads into `d->temporary`, checks it and stores it in the cache. */
static bool download_into(Download *d, MsLockEntry *entry, MsSpan *error) {
  MsSpan commit = {0};
  MsSpan index = {0};
  if (!prepare(d, error) || !resolve_commit(d, &commit, error) || !checkout(d, commit, error)) {
    return false;
  }
  ms_path_remove_tree(joined(d->arena, d->temporary, ms_span_of_text(".git")));
  MsSpan problem = {0};
  if (!ms_lock_index_tree(d->arena, d->temporary, &index, &problem)) {
    *error = ms_message_format(d->arena, "package %S: %S", d->key, problem);
    return false;
  }
  const MsSpan hash = ms_lock_hash_index(d->arena, index);
  if (d->locked != NULL && !ms_span_equal(d->locked->sha256, hash)) {
    *error = ms_message_format(d->arena,
                               "package %S at %S no longer matches ms.lock (locked %S, got %S); the source changed, "
                               "so review it and run `ms install --update %S` if you trust it",
                               d->key, d->locked->revision, d->locked->sha256, hash, d->key);
    return false;
  }
  if (!ms_package_validate(d->arena, d->key, d->temporary, error) ||
      !store(d->arena, d->cache, hash, index, d->temporary, error)) {
    return false;
  }
  *entry = (MsLockEntry){.revision = commit, .sha256 = hash};
  return true;
}

static bool download(MsGitRemote *remote, MsArena *arena, Download *d, MsLockEntry *entry, MsSpan *error) {
  d->remote = remote;
  d->arena = arena;
  d->cache = ms_lock_cache_dir(arena);
  if (!ms_dir_make_all(d->cache)) {
    *error = ms_message_format(arena, "cannot create the cache directory %S; check that its parent is writable", d->cache);
    return false;
  }
  MsString temporary = ms_string_empty();
  if (!ms_dir_make_temp(d->cache, ms_span_of_text(".tmp-"), &temporary)) {
    *error = ms_message_format(arena, "create %S: cannot make a temporary directory", d->cache);
    return false;
  }
  d->temporary = ms_arena_copy(arena, ms_string_span(&temporary));
  ms_string_release(&temporary);
  const bool ok = download_into(d, entry, error);
  ms_path_remove_tree(d->temporary);
  return ok;
}

static bool remote_fetch(void *self, MsArena *arena, MsSpan url, MsSpan reference, const MsLockEntry *locked,
                         bool nested, MsFetched *out, MsSpan *error) {
  MsGitRemote *remote = self;
  const MsSpan cache = ms_lock_cache_dir(arena);
  MsLockEntry entry = {0};
  if (locked != NULL && cached_intact(arena, cache, locked->sha256)) {
    entry = *locked;
  } else {
    Download d = {.key = url, .url = url, .reference = reference, .locked = locked,
                  .protocols = protocols_for(url, nested)};
    if (!download(remote, arena, &d, &entry, error)) {
      return false;
    }
  }
  entry.spec = ms_message_format(arena, "%S#%S", url, reference);
  const MsSpan manifest_path = joined(arena, joined(arena, cache, entry.sha256), ms_span_of_text("ms.toml"));
  MsManifest *manifest = MS_ARENA_NEW(arena, MsManifest);
  MsProjectError problem = {0};
  if (!ms_manifest_read(arena, manifest_path, manifest, &problem)) {
    *error = ms_message_format(arena, "package %S: %S", url, ms_project_error_text(arena, &problem));
    return false;
  }
  *out = (MsFetched){.entry = entry, .manifest = manifest};
  return true;
}

bool ms_git_remote_open(MsGitRemote *remote, MsArena *arena, MsSpan *error) {
  if (!ms_git_open(&remote->git, arena, error)) {
    return false;
  }
  remote->remote = (MsRemote){.self = remote, .tags = remote_tags, .fetch = remote_fetch};
  return true;
}

void ms_git_remote_close(MsGitRemote *remote) {
  ms_git_close(&remote->git);
}
