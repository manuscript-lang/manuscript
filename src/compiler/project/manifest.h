/* compiler/project/manifest.h: ms.toml read and validated: [project], [aliases], [embed], [dependencies],
 * [effects] and [workspace]. */
#ifndef MS_PROJECT_MANIFEST_H
#define MS_PROJECT_MANIFEST_H

#include "compiler/project/project_internal.h"
#include "compiler/project/semver.h"
#include "compiler/project/toml.h"

typedef struct MsManifestName {
  MsSpan name;   /* `@lib` */
  MsSpan target; /* canonical file or directory */
} MsManifestName;

MS_LIST_DEFINE(ManifestNameList, manifest_name_list, MsManifestName)

/* Where a dependency comes from: a tag, a commit, or a semver requirement on the repository's tags. */
typedef enum MsSourceKind { MS_SOURCE_TAG, MS_SOURCE_SHA, MS_SOURCE_VERSION } MsSourceKind;

/* One git entry of `[dependencies]`: `@pg = { url = "...", version = "1.0" }`. */
typedef struct MsDependency {
  MsSpan name;
  MsSpan url;
  MsSourceKind kind;
  MsSpan reference;           /* the tag or the commit */
  MsRequirement requirement;  /* MS_SOURCE_VERSION */
} MsDependency;

MS_LIST_DEFINE(DependencyList, dependency_list, MsDependency)

/* `[effects]`: the effects this project allows one dependency. */
typedef struct MsAllowedEffects {
  MsSpan name;
  const MsSpan *patterns;
  size_t count;
} MsAllowedEffects;

MS_LIST_DEFINE(AllowedEffectsList, allowed_effects_list, MsAllowedEffects)
MS_LIST_DEFINE(ManifestSpanList, manifest_span_list, MsSpan)

/* A package a project reaches: a fetched copy checked against the lock, or a workspace member. */
typedef struct MsPackageFile {
  MsSpan path; /* below the package root, `/` separated */
  MsSpan hash; /* the expected SHA-256, lowercase hex */
} MsPackageFile;

typedef struct MsPackage {
  MsSpan id;   /* `github.com/acme/wire@v1.4.2`, or `workspace/<member>` */
  MsSpan key;  /* what diagnostics call the copy: `@` and its id */
  MsSpan spec; /* the lock's `url#tag`, or `workspace member <name>` */
  MsSpan root; /* the canonical directory holding the package files */
  struct MsManifest *manifest;
  MsPackageFile *files; /* the verified index; none for a member */
  size_t nfiles;
  bool member; /* a workspace member: its files are the project's own, so they are not hashed */
} MsPackage;

typedef struct MsManifest {
  MsSpan root;          /* canonical directory of the manifest */
  MsSpan file;          /* the manifest's file name */
  MsSpan configuration; /* the text as read */
  MsSpan name;
  MsSpan source;        /* canonical source directory */
  MsSpan entry;         /* canonical entry file; empty for a library */
  MsPos location;       /* the [project] header, or 1:1 */
  ManifestNameList aliases;
  ManifestNameList embeds;
  DependencyList dependencies;          /* sorted by name */
  ManifestNameList path_dependencies;   /* `{ path = "../util" }`: name and canonical member directory, sorted */
  AllowedEffectsList allowed_effects;   /* sorted by name */
  ManifestNameList deps;                /* dependency names and the source directory of the package each reaches */
  MsPackage *packages;                  /* every package reached, however deep, sorted by id; only in a project */
  size_t npackages;
  bool is_workspace;                    /* a [workspace] table is present */
  ManifestSpanList members;             /* [workspace] members, as written */
  bool has_version;                     /* [project] version */
  MsVersion version;
  const MsSpan *effects;                /* [project] effects */
  size_t neffects;
} MsManifest;

/* Reads and validates the manifest at `filename` (absolute). False with *error filled. */
MS_NODISCARD bool ms_manifest_read(MsArena *arena, MsSpan filename, MsManifest *out, MsProjectError *error);

void ms_manifest_free(MsManifest *manifest);

/* The package that holds `path` (the longest matching root), or NULL. */
const MsPackage *ms_manifest_package_of(const MsManifest *manifest, MsSpan path);

/* The manifest whose aliases and dependencies apply to imports written in `importer`. */
const MsManifest *ms_manifest_scope(const MsManifest *manifest, MsSpan importer);

/* The target of alias or embed `name` (with its `@`), or false. */
MS_NODISCARD bool ms_manifest_find(const ManifestNameList *list, MsSpan name, MsSpan *target);

#endif
