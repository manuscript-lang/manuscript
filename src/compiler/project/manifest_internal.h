/* compiler/project/manifest_internal.h: what the manifest reader's files share. */
#ifndef MS_PROJECT_MANIFEST_INTERNAL_H
#define MS_PROJECT_MANIFEST_INTERNAL_H

#include "compiler/project/manifest.h"

typedef struct Reader {
  MsArena *arena;
  MsManifest *out;
  const TomlDocument *document;
  MsProjectError *error;
} Reader;

bool manifest_fail_at(Reader *r, MsPos at, MsSpan message);
/* `format` with %a and %b replaced by the two spans, in the arena. */
MsSpan manifest_formatted(Reader *r, const char *format, MsSpan a, MsSpan b);
bool manifest_valid_alias(MsSpan key);
const TomlEntry *manifest_find_entry(const Reader *r, const char *table, MsSpan key);

/* ---- manifest_packages.c: [dependencies], [effects], [workspace] and the project keys that belong to them ---- */

/* An entry of [dependencies], [effects] or [workspace]. */
bool manifest_package_entry(Reader *r, const TomlTable *table, const TomlEntry *entry);
/* [project] effects: the list of effect patterns. */
bool manifest_project_effects(Reader *r, const TomlEntry *entry);
/* [project] version. */
bool manifest_project_version(Reader *r, const TomlEntry *entry, MsSpan text);
/* Sorts what the sections gathered, so the checks below see names in order. */
void manifest_sort_packages(MsManifest *manifest);
/* The checks that need the whole manifest: collisions with aliases and embeds, and [effects] names. */
bool manifest_check_packages(Reader *r);

#endif
