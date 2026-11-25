/* lsp/lsp_completion.h: `textDocument/completion`: members after a dot, the names in scope, types and keywords. */
#ifndef MS_CLI_LSP_COMPLETION_H
#define MS_CLI_LSP_COMPLETION_H

#include "lsp/lsp_analysis.h"
#include "lsp/lsp_internal.h"

/* Writes the completion items at `position` as a JSON array. `snippets` is whether the client takes snippet text. */
void lsp_completion(const LspDocList *docs, const LspDoc *doc, LspPosition position, bool snippets, MsStrBuild *out);

#endif
