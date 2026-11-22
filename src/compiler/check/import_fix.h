/* compiler/check/import_fix.h: the edit that removes one redundant binding from an import statement.
 *
 * The edit is exact source surgery that keeps comments, neighbouring bindings and line endings; it does not
 * reformat the file. */
#ifndef MS_COMPILER_CHECK_IMPORT_FIX_H
#define MS_COMPILER_CHECK_IMPORT_FIX_H

#include "base/arena.h"
#include "base/string.h"
#include "compiler/syntax/ast.h"

typedef struct MsImportFix {
  MsPos pos, end;
  MsString text; /* owned; usually empty, or the comments the removal keeps */
} MsImportFix;

/* The edit removing `tree->imports[index]` from `source`, or false when the statement cannot be edited. */
bool ms_import_fix(MsArena *arena, const MsModule *tree, uint32_t index, MsSpan source, MsImportFix *fix);

#endif
