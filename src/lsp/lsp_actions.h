/* lsp/lsp_actions.h: `textDocument/codeAction`: the checker's and the linter's fixes, import organization and the format-all
 * action. Port of crates/ms-lsp/src/actions.rs, apart from adding an import for an unresolved name. */
#ifndef MS_CLI_LSP_ACTIONS_H
#define MS_CLI_LSP_ACTIONS_H

#include "lsp/lsp_analysis.h"
#include "base/arena.h"
#include "lsp/lsp_internal.h"
#include "compiler/syntax/ast.h"

/* Writes the actions for lines `requested`, only of the kinds in `only` (or of any kind when `count` is 0). */
void lsp_code_actions(const LspDocList *docs, const LspDoc *doc, LspRange requested, const MsSpan *only, size_t count,
                      MsStrBuild *out);

/* Where the statement `import ...` goes in `source` (after its leading imports, else after a comment header), as the position and
 * the text to insert there. `module` is the parsed document, or NULL. */
void lsp_import_insertion(MsSpan source, const MsModule *module, MsSpan statement, LspPosition *at, MsStrBuild *text);

/* The import path of `file` written in a file of directory `from_dir`: `./x.ms`, or `../x.ms`. False when it cannot be written. */
bool lsp_relative_import(MsArena *arena, MsSpan from_dir, MsSpan file, MsSpan *path);

#endif
