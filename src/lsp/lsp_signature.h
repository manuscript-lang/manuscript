/* lsp/lsp_signature.h: `textDocument/signatureHelp`, the signature of the call around the cursor. Port of
 * crates/ms-lsp/src/completion.rs `signature_help`. */
#ifndef MS_CLI_LSP_SIGNATURE_H
#define MS_CLI_LSP_SIGNATURE_H

#include "lsp/lsp_analysis.h"
#include "lsp/lsp_internal.h"

/* Writes the signature help result for `position`, or `null` when no call surrounds it or its callee is unknown. */
void lsp_signature_help(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out);

#endif
