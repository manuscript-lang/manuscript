/* lsp/lsp_completion_internal.h: what the completion files share: the item and the completer state. */
#ifndef MS_CLI_LSP_COMPLETION_INTERNAL_H
#define MS_CLI_LSP_COMPLETION_INTERNAL_H

#include "lsp/lsp_actions.h"
#include "lsp/lsp_analysis.h"
#include "compiler/check/scope_walk.h"
#include "lsp/lsp_internal.h"
#include "compiler/check/program.h"
#include "compiler/syntax/ast.h"

#define MARKER "__manuscript_completion"

typedef struct Item {
  MsString label, detail, documentation, sort, insert, additional; /* additional: the JSON of an extra text edit, or empty */
  int kind, format;
} Item;

MS_LIST_DEFINE(ItemList, item_list, Item)

typedef struct Completer {
  MsSpan source;
  size_t start, end, offset; /* the word under the cursor, and the cursor */
  MsSpan prefix;
  bool member, type_context, snippets;
  LspAnalysis *analysis;
  MsCheckProgram *program;
  uint32_t module; /* the document's module, or UINT32_MAX */
  MsBindingList scope;
  const MsModule *tree; /* the document's parsed module, for placing imports */
  MsNode left; /* the receiver of the member being completed */
  bool has_left;
  ItemList items;
  LspImportSite import_site; /* where an import goes, found on the first import offered */
  bool has_import_site;
} Completer;

static inline bool is_word(uint8_t byte) {
  return byte == '_' || (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || byte >= 0x80;
}

static inline uint8_t lower(uint8_t byte) { return byte >= 'A' && byte <= 'Z' ? (uint8_t)(byte + 32) : byte; }

/* Case-insensitive subsequence match. */
static inline bool name_matches(MsSpan name, MsSpan query) {
  size_t at = 0;
  for (size_t i = 0; i < name.len && at < query.len; i++) {
    if (lower(name.ptr[i]) == lower(query.ptr[at])) at++;
  }
  return at == query.len;
}

static inline bool contains(MsSpan text, const char *needle) {
  size_t at;
  return ms_span_find(text, ms_span_of_text(needle), &at);
}

static inline MsString own(MsSpan text) { return ms_string_from_span(text); }


/* Orders items by sort text, then detail. */
int lsp_completion_compare_item(const void *left, const void *right);

/* Completion inside an `import` declaration: module paths in the string, exported names elsewhere. False outside one. */
bool lsp_import_items(Completer *c, const LspDoc *doc, const LspDocList *docs);

/* Names the bundled library and the project's other files export, offered with the import that makes them visible. */
void lsp_import_suggestions(Completer *c, const LspDocList *docs, const LspDoc *doc);

#endif
