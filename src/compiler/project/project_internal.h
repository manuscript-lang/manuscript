/* compiler/project/project_internal.h: helpers the loader files share. */
#ifndef MS_PROJECT_INTERNAL_H
#define MS_PROJECT_INTERNAL_H

#include "base/strbuild.h"
#include "compiler/project/project.h"

/* The text of `builder` copied into `arena`; the builder is freed. */
MsSpan ms_project_text(MsArena *arena, MsStrBuild *builder);

void ms_project_error_message(MsProjectError *error, MsSpan message);
void ms_project_error_path(MsProjectError *error, const char *op, MsSpan path, int os_error);

struct MsManifest;

/* The path an import `path` written in `importer` names, before symbolic links are resolved. `manifest` holds
 * the aliases and embeds, or is NULL for a standalone file. */
MS_NODISCARD bool ms_project_import_target(MsArena *arena, const struct MsManifest *manifest, MsSpan importer,
                                           MsSpan path, MsSpan *target, MsProjectError *error);

/* ms_project_resolve_import with the aliases of `manifest` (NULL for none). */
MS_NODISCARD bool ms_project_resolve_in(MsArena *arena, const struct MsManifest *manifest, MsSpan root,
                                        const MsOverlay *overlay, MsSpan importer, MsSpan path,
                                        MsSpan *canonical, MsProjectError *error);

/* Canonicalises `path` (absolute, or below `root`) and confines it to `root`, which is canonical. An overlay
 * may supply a file that is not on disk. */
MS_NODISCARD bool ms_project_source_path(MsArena *arena, MsSpan root, MsSpan path, const MsOverlay *overlay,
                                         MsSpan *canonical, MsProjectError *error);

/* The error as the user should read it: a cause and a fix. `import_path` is the import string when the failure
 * came from an import, else empty. */
MsSpan ms_project_explain(MsArena *arena, const MsProjectError *error, MsSpan import_path);

#endif
