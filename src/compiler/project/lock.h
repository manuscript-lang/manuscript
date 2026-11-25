/* compiler/project/lock.h: ms.lock, the package cache and the content hash of a package.rs.
 *
 * `ms install` is the only code that uses the network. Everything here reads the lock and the cache, so a locked
 * project builds offline. */
#ifndef MS_PROJECT_LOCK_H
#define MS_PROJECT_LOCK_H

#include "base/arena.h"
#include "base/list.h"
#include "base/safe.h"
#include "compiler/project/semver.h"

/* One line of ms.lock. */
typedef struct MsLockEntry {
  MsSpan id;       /* the key: `github.com/acme/wire@v1.4.2` */
  MsSpan spec;     /* the manifest value, `url#tag` */
  MsSpan revision; /* the full commit the tag pointed to, 40 lowercase hex digits */
  MsSpan sha256;   /* the hash of the package files, 64 lowercase hex digits */
} MsLockEntry;

MS_LIST_DEFINE(MsLockList, ms_lock_list, MsLockEntry)

/* `github.com/acme/wire` for any spelling of the repository URL: the scheme is dropped, the host is lowercase, and
 * a trailing `/` and `.git` are removed. A `file://` URL keeps its path as `file/path`. */
MsSpan ms_lock_repo_key(MsArena *arena, MsSpan url);
/* The id of the copy of `url` fetched at `reference`, the tag as the repository spells it or the commit:
 * `github.com/acme/wire@v1.4.2`. */
MsSpan ms_lock_copy_id(MsArena *arena, MsSpan url, MsSpan reference);
/* The id a `url#reference` spec names; false when it has no `#`. */
MS_NODISCARD bool ms_lock_id_of_spec(MsArena *arena, MsSpan spec, MsSpan *id);
/* The version a lock entry's tag names, if it is a version tag. */
MS_NODISCARD bool ms_lock_entry_version(MsArena *arena, const MsLockEntry *entry, MsVersion *out);

/* Parses `<root>/ms.lock` into entries sorted by id. A missing file is an empty lock. On failure `*error` says why. */
MS_NODISCARD bool ms_lock_read(MsArena *arena, MsSpan root, MsLockList *out, MsSpan *error);
/* The text of ms.lock for entries sorted by id. */
MsSpan ms_lock_text(MsArena *arena, const MsLockEntry *entries, size_t count);

/* The directory holding fetched packages, one subdirectory per content hash. */
MsSpan ms_lock_cache_dir(MsArena *arena);
/* `<cache>/<hash>.index`, where the index of a package is stored beside its directory. */
MsSpan ms_lock_index_path(MsArena *arena, MsSpan cache, MsSpan hash);

/* The index of the files under `directory`, ignoring a top-level `.git`: one line per file in byte order of its `/`
 * path, holding the path, a zero byte and the SHA-256 of its bytes. Its own SHA-256 is the package hash. */
MS_NODISCARD bool ms_lock_index_tree(MsArena *arena, MsSpan directory, MsSpan *index, MsSpan *error);
/* The package hash: the SHA-256 of the index, as 64 hexadecimal digits. */
MsSpan ms_lock_hash_index(MsArena *arena, MsSpan index);

#endif
