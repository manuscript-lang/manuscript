/* lsp/lsp_semantic.h: `textDocument/semanticTokens/full`. */
#ifndef MS_CLI_LSP_SEMANTIC_H
#define MS_CLI_LSP_SEMANTIC_H

#include "lsp/lsp_analysis.h"

/* The token types of the legend, comma separated JSON strings, in kind-number order. */
#define LSP_TOKEN_LEGEND                                                                                              \
  "\"keyword\",\"variable\",\"number\",\"string\",\"comment\",\"function\",\"type\",\"property\",\"parameter\"," \
  "\"enumMember\",\"typeParameter\""

/* Writes `{"data": [...]}`: the tokens of a document, classified by the checked index when the document resolves. */
void lsp_semantic_tokens(const LspDocList *docs, const LspDoc *doc, MsStrBuild *out);

#endif
