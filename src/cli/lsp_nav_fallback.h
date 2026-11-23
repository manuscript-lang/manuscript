/* cli/lsp_nav_fallback.h: hover for literals and operators. */
#ifndef MS_CLI_LSP_NAV_FALLBACK_H
#define MS_CLI_LSP_NAV_FALLBACK_H

#include "base/intern.h"
#include "compiler/syntax/ast.h"

typedef struct LspHoverFallback {
  uint32_t node; /* the expression's node id */
  MsSpan text;   /* the token the expression is hovered by */
  size_t offset, end;
} LspHoverFallback;

/* The smallest literal or operator token of `tree` containing `offset`. */
bool lsp_hover_fallback(const MsNames *names, const MsModule *tree, size_t offset, LspHoverFallback *out);

#endif
