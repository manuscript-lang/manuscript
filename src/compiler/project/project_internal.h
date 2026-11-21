/* compiler/project/project_internal.h: helpers the loader files share. */
#ifndef MS_PROJECT_INTERNAL_H
#define MS_PROJECT_INTERNAL_H

#include "base/strbuild.h"
#include "compiler/project/project.h"

/* The text of `builder` copied into `arena`; the builder is freed. */
MsSpan ms_project_text(MsArena *arena, MsStrBuild *builder);

void ms_project_error_message(MsProjectError *error, MsSpan message);
void ms_project_error_path(MsProjectError *error, const char *op, MsSpan path, int os_error);

/* The path a local import `path` written in `importer` names, before symbolic links are resolved. */
MS_NODISCARD bool ms_project_import_target(MsArena *arena, MsSpan importer, MsSpan path, MsSpan *target,
                                           MsProjectError *error);

/* Canonicalises `path` (absolute, or below `root`) and confines it to `root`, which is canonical. An overlay
 * may supply a file that is not on disk. */
MS_NODISCARD bool ms_project_source_path(MsArena *arena, MsSpan root, MsSpan path, const MsOverlay *overlay,
                                         MsSpan *canonical, MsProjectError *error);

/* The error as the user should read it: a cause and a fix. `import_path` is the import string when the failure
 * came from an import, else empty. */
MsSpan ms_project_explain(MsArena *arena, const MsProjectError *error, MsSpan import_path);

#endif
