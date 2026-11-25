/* compiler/project/package.h: package dependencies: the spec a dependency value pins, the lock file, the package
 * cache and the content hash. */
#ifndef MS_PROJECT_PACKAGE_H
#define MS_PROJECT_PACKAGE_H

#include "base/arena.h"
#include "base/safe.h"

/* Whether `text` is `len` lowercase hexadecimal digits. */
bool ms_package_is_hex(MsSpan text, size_t len);

/* A dependency value is `url#tag`: an `https://` or `file://` URL, never one that starts with `-` or names another
 * git transport, and a tag or commit that is not an option or a path. On failure `*why` says what is wrong. */
MS_NODISCARD bool ms_package_check_spec(MsArena *arena, MsSpan spec, MsSpan *why);

#endif

/* ---- attaching the packages a project reaches (attach.c) ---- */

#include "compiler/project/manifest.h"

/* Whether the effect pattern `declared` is inside what the pattern `allowed` permits. */
bool ms_package_pattern_covers(MsSpan allowed, MsSpan declared);

/* An effect in `declared` that no pattern in `allowed` covers; false when all are covered. */
bool ms_package_uncovered(const MsSpan *allowed, size_t nallowed, const MsSpan *declared, size_t ndeclared,
                          MsSpan *missing);

/* Resolves every dependency of `project` through its lock and the cache, recursively, and fills its deps and
 * packages. Each copy of a repository is loaded once, however many names reach it. */
MS_NODISCARD bool ms_package_attach(MsArena *arena, MsManifest *project, MsProjectError *error);

/* Whether `bytes`, read from `relative` in this package, are what the lock pinned. */
MS_NODISCARD bool ms_package_verify_file(MsArena *arena, const MsPackage *package, MsSpan relative, MsSpan bytes,
                                         MsProjectError *error);
