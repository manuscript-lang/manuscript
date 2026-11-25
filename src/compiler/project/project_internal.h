/* compiler/project/project_internal.h: helpers the loader files share. */
#ifndef MS_PROJECT_INTERNAL_H
#define MS_PROJECT_INTERNAL_H

#include "base/strbuild.h"
#include "base/intern.h"
#include "compiler/project/project.h"

/* The absolute, cleaned spelling of `target`; false, with `error` set, when the working directory is unknown. */
MS_NODISCARD bool ms_project_absolute_path(MsArena *arena, MsSpan target, MsSpan *absolute, MsProjectError *error);

/* `text` in double quotes with the escapes of Rust's `{:?}`. */
MsSpan ms_project_quote(MsArena *arena, MsSpan text);

void ms_project_error_message(MsProjectError *error, MsSpan message);
void ms_project_error_path(MsProjectError *error, const char *op, MsSpan path, int os_error);

struct MsManifest;

/* The canonical file a local import `path` written in the file `importer` names, confined to the project root
 * (`root`, canonical), with the aliases of `manifest` (NULL for none). `overlay` may be NULL. False with *error
 * filled when the file cannot be named or read. */
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
/* The same naming the file by its full path, for an editor whose working directory means nothing. */
MsSpan ms_project_explain_absolute(MsArena *arena, const MsProjectError *error, MsSpan import_path);

/* The `.ms` files under `source` (when `include_source`) and the test and bench files under `root`, sorted
 * and without repeats, as absolute paths. */
MS_NODISCARD bool ms_project_discover(MsArena *arena, MsSpan root, MsSpan source, bool include_source,
                                      MsSpanList *files, MsProjectError *error);

/* The module an `[embed]` directory generates: its source (for `name`, an `@assets`), and the logical path under
 * the project root that an import of the embed resolves to. */
MS_NODISCARD bool ms_project_embed_generate(MsArena *arena, MsSpan name, MsSpan directory, MsSpan *source,
                                            MsProjectError *error);
MsSpan ms_project_embed_module_path(MsArena *arena, MsSpan root, MsSpan name);
/* Whether `canonical` is the generated module of one of the manifest's embeds. */
MS_NODISCARD bool ms_project_embed_of(MsArena *arena, const struct MsManifest *manifest, MsSpan canonical,
                                      MsSpan *name, MsSpan *directory);

#endif
