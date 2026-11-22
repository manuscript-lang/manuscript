/* compiler/project/attach_internal.h: what the package attaching files share. */
#ifndef MS_PROJECT_ATTACH_INTERNAL_H
#define MS_PROJECT_ATTACH_INTERNAL_H

#include "compiler/project/package.h"
#include "compiler/project/project_internal.h"

/* What a project allows a dependency, and what a package may hand on. `asker` is empty for the project. */
bool attach_check_effects(MsArena *arena, const MsManifest *scope, MsSpan alias, MsSpan id, MsSpan asker,
                          const MsManifest *package, MsProjectError *error);

#endif
