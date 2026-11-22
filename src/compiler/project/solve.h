/* compiler/project/solve.h: dependency resolution the way Cargo does it: one copy of a repository per compatible
 * range. Port of crates/ms-driver/src/project/resolve.rs.
 *
 * The resolver reads requirements from the roots and from every package it has picked, picks the highest tag that
 * satisfies all requirements in a bucket, and repeats until the picks stop changing, because a package that is
 * picked no longer asks for what the package it replaced asked for. All network and disk work goes through
 * MsRemote. */
#ifndef MS_PROJECT_SOLVE_H
#define MS_PROJECT_SOLVE_H

#include "compiler/project/lock.h"
#include "compiler/project/manifest.h"

/* A downloaded package: the lock entry that pins it and its manifest. */
typedef struct MsFetched {
  MsLockEntry entry;
  const MsManifest *manifest;
} MsFetched;

/* What the resolver needs from the network and the cache. Each call fills `*error` when it fails. */
typedef struct MsRemote {
  void *self;
  /* The tag names of the repository at `url`. */
  bool (*tags)(void *self, MsArena *arena, MsSpan url, MsSpan **tags, size_t *count, MsSpan *error);
  /* Downloads `url` at `reference` (a tag or a 40-digit commit) and reads its manifest. With `locked`, fetches exactly
   * that revision and checks its hash. `nested` limits the transport to `https`. */
  bool (*fetch)(void *self, MsArena *arena, MsSpan url, MsSpan reference, const MsLockEntry *locked, bool nested,
                MsFetched *out, MsSpan *error);
} MsRemote;

/* A manifest and the name diagnostics call its asker: `the project` or a workspace member. */
typedef struct MsRoot {
  MsSpan name;
  const MsManifest *manifest;
} MsRoot;

typedef struct MsResolveRequest {
  const MsRoot *roots;
  size_t nroots;
  const MsLockEntry *old; /* the existing lock, sorted by id; its picks are kept while they satisfy every requirement */
  size_t nold;
  const MsSpan *update; /* names whose repositories are picked again */
  size_t nupdate;
  const MsRemote *remote;
} MsResolveRequest;

/* One picked copy of a repository. */
typedef struct MsCopy {
  MsSpan id;
  MsSpan url;
  MsSpan reference; /* the tag or commit it was fetched at */
  MsLockEntry entry;
  const MsManifest *manifest;
} MsCopy;

typedef struct MsRootName {
  MsSpan alias;
  MsSpan id; /* the copy the name reaches */
} MsRootName;

typedef struct MsResolved {
  MsCopy *copies; /* sorted by id */
  size_t ncopies;
  MsRootName *roots; /* sorted by alias */
  size_t nroots;
} MsResolved;

/* Resolves the dependencies of the roots. On failure `*error` says why. Results live in `arena`. */
MS_NODISCARD bool ms_resolve(MsArena *arena, const MsResolveRequest *request, MsResolved *out, MsSpan *error);

/* A tagged release whose manifest names another version is a mistake in the repository that blocks every user of
 * it, so the error says how to get past it. `what` is `package` or `dependency`. */
MS_NODISCARD bool ms_resolve_check_version(MsArena *arena, const char *what, MsSpan url, MsSpan reference,
                                           const MsManifest *manifest, MsSpan *error);

/* The source as a person would write it: `v1.0.0`, a commit, or `^1.2`. */
MsSpan ms_dependency_describe(MsArena *arena, const MsDependency *dependency);

#endif
