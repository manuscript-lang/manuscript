/* compiler/project/manifest.h: ms.toml read and validated. Only [project] (name, source, entry), [aliases] and
 * [embed] are read; [dependencies], [effects], [workspace], a version and effects are not implemented. */
#ifndef MS_PROJECT_MANIFEST_H
#define MS_PROJECT_MANIFEST_H

#include "compiler/project/project_internal.h"
#include "compiler/project/toml.h"

typedef struct MsManifestName {
  MsSpan name;   /* `@lib` */
  MsSpan target; /* canonical file or directory */
} MsManifestName;

MS_LIST_DEFINE(ManifestNameList, manifest_name_list, MsManifestName)

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
} MsManifest;

/* Reads and validates the manifest at `filename` (absolute). False with *error filled. */
MS_NODISCARD bool ms_manifest_read(MsArena *arena, MsSpan filename, MsManifest *out, MsProjectError *error);

void ms_manifest_free(MsManifest *manifest);

/* The target of alias or embed `name` (with its `@`), or false. */
MS_NODISCARD bool ms_manifest_find(const ManifestNameList *list, MsSpan name, MsSpan *target);

#endif
