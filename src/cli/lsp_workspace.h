/* cli/lsp_workspace.h: the files of a project and the queries that read all of them: workspace symbols and, through
 * lsp_nav, references and rename across files. Port of crates/ms-lsp/src/workspace.rs. */
#ifndef MS_CLI_LSP_WORKSPACE_H
#define MS_CLI_LSP_WORKSPACE_H

#include "base/arena.h"
#include "cli/lsp_analysis.h"
#include "cli/lsp_internal.h"

/* Appends the `.ms` files of the project `file` is in: below its nearest `ms.toml`, else below its own directory. Paths are
 * absolute and sorted; names that start with a dot are not entered. */
void lsp_workspace_files(MsArena *arena, MsSpan file, MsSpanList *out);

/* The nearest ancestor directory of `dir` that holds `ms.toml`, or `dir` itself. */
MsSpan lsp_project_root(MsArena *arena, MsSpan dir);

/* Writes the declarations whose name contains `query` (ignoring case), across the open documents' projects and `roots`. */
void lsp_workspace_symbols(const LspDocList *docs, const MsSpan *roots, size_t root_count, MsSpan query, MsStrBuild *out);

/* Whether `text` holds `needle`, ignoring ASCII case. */
bool lsp_text_mentions(MsSpan text, MsSpan needle);

#endif
