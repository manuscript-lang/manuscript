/* lsp/lsp_symbols.h: `textDocument/documentSymbol`, the outline of a checked module. */
#ifndef MS_CLI_LSP_SYMBOLS_H
#define MS_CLI_LSP_SYMBOLS_H

#include "lsp/lsp_analysis.h"

/* Writes the outline of `doc` as a JSON array, `[]` when the document is not checked. */
void lsp_document_symbols(const LspDocList *docs, const LspDoc *doc, MsStrBuild *out);

/* `textDocument/formatting`: one edit replacing the whole document. False with `error` set when the text does not parse. */
bool lsp_format_document(const LspDoc *doc, MsStrBuild *out, MsStrBuild *error);

/* `textDocument/foldingRange`: each indented suite, from its header line to its last code line. */
void lsp_folding_ranges(const LspDoc *doc, MsStrBuild *out);

#endif
