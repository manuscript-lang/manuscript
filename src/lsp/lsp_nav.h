/* lsp/lsp_nav.h: navigation over the occurrence index: definition, references, highlights and rename. Each writes its JSON result into `out`. */
#ifndef MS_CLI_LSP_NAV_H
#define MS_CLI_LSP_NAV_H

#include "lsp/lsp_analysis.h"
#include "lsp/lsp_internal.h"

void lsp_nav_hover(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out);
void lsp_nav_definition(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out);
void lsp_nav_references(const LspDocList *docs, const LspDoc *doc, LspPosition position, bool include_declaration,
                        MsStrBuild *out);
void lsp_nav_highlight(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out);

/* The prepare answer when `new_name` is empty, else the workspace edit. False with `*error` set when the rename is
 * refused (static text). */
bool lsp_nav_rename(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsSpan new_name, MsStrBuild *out,
                    MsStrBuild *error);

void lsp_nav_type_definition(const LspDocList *docs, const LspDoc *doc, LspPosition position, MsStrBuild *out);
/* The inferred types of unannotated bindings whose names end inside `range`. */
void lsp_nav_inlay_hints(const LspDocList *docs, const LspDoc *doc, LspRange range, MsStrBuild *out);

#endif
