/* cli/lsp_actions.h: `textDocument/codeAction`: the checker's and the linter's fixes, import organization and the format-all
 * action. Port of crates/ms-lsp/src/actions.rs, apart from adding an import for an unresolved name. */
#ifndef MS_CLI_LSP_ACTIONS_H
#define MS_CLI_LSP_ACTIONS_H

#include "cli/lsp_analysis.h"
#include "cli/lsp_internal.h"

/* Writes the actions for lines `requested`, only of the kinds in `only` (or of any kind when `count` is 0). */
void lsp_code_actions(const LspDocList *docs, const LspDoc *doc, LspRange requested, const MsSpan *only, size_t count,
                      MsStrBuild *out);

#endif
