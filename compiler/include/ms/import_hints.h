/* Import diagnostics that read the standard library: which standard module exports a name, and why
 * an import failed. The import_hint, type_import_hint and export_message of
 * crates/ms-check/src/hints.rs over the checker tables. */
#ifndef MS_IMPORT_HINTS_H
#define MS_IMPORT_HINTS_H

#include "ms/ast.h"
#include "ms/tables.h"

/* The source-backed prelude names (the standard library declares them, so no import is needed). */
extern const char *const ms_prelude_names[];
extern const size_t ms_prelude_name_count;

/* `; add: import Name from "@std/..."` naming the first standard module (in path order) that
 * exports `name`, or `; use the prelude Name declaration directly; ...` for a prelude name, else
 * empty. `checking_sources` is true while the checker is inside a bundled source module, when no
 * module may be searched. */
MsStr ms_import_hint(MsArena *arena, const MsCheck *c, MsStr name, bool checking_sources);

/* The same, for a name used in a type annotation: only types qualify. */
MsStr ms_type_import_hint(MsArena *arena, const MsCheck *c, MsStr name, bool checking_sources);

/* What the importing module can see of a local module an import names: the names it exports and
 * whether the imported name is declared there without `export`. Unused for `@std/` imports. */
typedef struct MsExportList {
    const MsStr *names;
    size_t count;
    bool name_is_private;
} MsExportList;

/* Why `item` failed: the module does not exist (a standard module), does not export the name, or
 * declares it privately. `local` describes the target of a non-standard import. */
MsStr ms_export_message(MsArena *arena, const MsCheck *c, const MsImport *item, bool checking_sources,
                        const MsExportList *local);

/* Whether the standard module `path` exists and exports `name`: the import is fine. */
bool ms_standard_import_ok(MsArena *arena, const MsCheck *c, MsStr path, MsStr name);

#endif
