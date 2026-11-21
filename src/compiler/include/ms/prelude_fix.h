/* The exact-source fix for a redundant prelude import: the port of
 * crates/ms-check/src/prelude_imports.rs and of `Import::in_group` and `Import::group_removal`
 * in crates/ms-syntax/src/ast.rs. The fix removes one binding, keeping comments, neighbouring
 * bindings and the original line endings; it is an exact source edit, not formatting.
 *
 * Whitespace trimming is ASCII; the Rust helper also trims Unicode spaces. */
#ifndef MS_PRELUDE_FIX_H
#define MS_PRELUDE_FIX_H

#include "ms/ast.h"
#include "ms/hints.h"

/* The diagnostic message for the redundant import of `name`. */
MsStr ms_prelude_import_message(MsArena *arena, MsStr name);

/* The fix that removes the binding `item` of `imports` (the module's import list) from `source`;
 * false when the source offers no exact edit. */
MS_NODISCARD bool ms_prelude_import_fix(MsArena *arena, MsStr source, const MsImport *imports,
                                        uint32_t nimports, const MsImport *item, MsFix *out);

#endif
