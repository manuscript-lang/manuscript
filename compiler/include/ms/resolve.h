/* Dependency resolution the way Cargo does it: one copy of a repository per compatible range. Port of
 * crates/ms-driver/src/project/resolve.rs.
 *
 * The resolver reads requirements from the roots and from every package it has picked, picks the highest tag that
 * satisfies all requirements in a bucket (see semver.h), and repeats until the picks stop changing, because a package
 * that is picked no longer asks for what the package it replaced asked for. All network and disk work goes through
 * MsRemote, so the procedure is checked against a table of tags in the tests. Errors are the Rust texts. */
#ifndef MS_RESOLVE_H
#define MS_RESOLVE_H

#include "ms/lock.h"

/* The source as a person would write it: `v1.0.0`, a commit, or `^1.2`. */
const char *ms_dependency_describe(MsArena *a, const MsDependency *d);
/* The `url#reference` a lock line records for a tag or a commit; NULL for a requirement. */
const char *ms_dependency_spec(MsArena *a, const MsDependency *d);

/* What the resolver reads of a manifest. */
typedef struct MsPackageManifest {
    const MsDependency *deps; /* sorted by alias */
    uint32_t ndeps;
    bool has_version; /* [project] version */
    MsVersion version;
} MsPackageManifest;

typedef struct MsFetched {
    MsLockEntry entry;
    MsPackageManifest manifest;
} MsFetched;

/* The network and the cache, which each return false with a message in *error. */
typedef struct MsRemote {
    void *user;
    /* The tag names of the repository at `url`. */
    bool (*tags)(void *user, MsArena *a, const char *url, const char *const **tags, uint32_t *count, const char **error);
    /* Download `url` at `reference` (a tag or a 40-digit commit) and read its manifest. With `locked`, fetch exactly
     * that revision and check its hash. `nested` limits the transport to https. */
    bool (*fetch)(void *user, MsArena *a, const char *url, const char *reference, const MsLockEntry *locked, bool nested,
                  MsFetched *out, const char **error);
} MsRemote;

typedef struct MsRoot {
    const char *name; /* what diagnostics call it: `the project` */
    MsPackageManifest manifest;
} MsRoot;

/* One picked copy of a repository. */
typedef struct MsCopy {
    const char *id;
    const char *url;
    const char *reference; /* the tag or commit it was fetched at */
    MsLockEntry entry;     /* entry.key is the id */
    MsPackageManifest manifest;
} MsCopy;

typedef struct MsRootName {
    const char *alias, *id;
} MsRootName;

typedef struct MsResolved {
    MsCopy *copies; /* sorted by id */
    uint32_t ncopies;
    MsRootName *roots; /* which copy each top-level name reaches, sorted by alias */
    uint32_t nroots;
} MsResolved;

/* Resolves the dependencies of `roots`. `old` is the existing lock, whose picks are kept while they still satisfy every
 * requirement; `update` holds names whose repositories are re-picked. */
MS_NODISCARD bool ms_resolve(MsArena *a, const MsRoot *roots, uint32_t nroots, const MsLock *old, const char *const *update,
                             uint32_t nupdate, const MsRemote *remote, MsResolved *out, const char **error);
/* The lock entries of the copies, in key order, for ms_lock_text. */
MsLockEntry *ms_resolved_lock(MsArena *a, const MsResolved *resolved);

/* A tagged release whose manifest names another version is a mistake in the repository that blocks every user of it;
 * NULL when `manifest` agrees with `reference`, otherwise the message. */
const char *ms_check_version_agrees(MsArena *a, const char *what, const char *url, const char *reference, const MsPackageManifest *manifest);

#endif
