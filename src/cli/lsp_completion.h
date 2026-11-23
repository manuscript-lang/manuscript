/* cli/lsp_completion.h: `textDocument/completion`: members after a dot, the names in scope, types and keywords. Port of
 * crates/ms-lsp/src/completion.rs, apart from import-path completion and suggesting imports of unimported names. */
#ifndef MS_CLI_LSP_COMPLETION_H
#define MS_CLI_LSP_COMPLETION_H

#include "cli/lsp_analysis.h"
#include "cli/lsp_internal.h"

/* Writes the completion items at `position` as a JSON array. `snippets` is whether the client takes snippet text. */
void lsp_completion(const LspDocList *docs, const LspDoc *doc, LspPosition position, bool snippets, MsStrBuild *out);

#endif
