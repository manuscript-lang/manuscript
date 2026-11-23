/* cli/lsp_analysis.h: the open documents of a language-server session and what the checker says about them. */
#ifndef MS_CLI_LSP_ANALYSIS_H
#define MS_CLI_LSP_ANALYSIS_H

#include "base/list.h"
#include "base/string.h"
#include "base/strbuild.h"

typedef struct LspDoc {
  MsString uri, path, text;
  int64_t version;
  bool dirty;         /* changed since its diagnostics were last sent */
  MsString published; /* the diagnostics last sent, as JSON, to send only changes */
} LspDoc;

MS_LIST_DEFINE(LspDocList, lsp_doc_list, LspDoc)

LspDoc *lsp_doc_find(LspDocList *docs, MsSpan uri);
/* Stores the document, replacing an earlier version. */
void lsp_doc_set(LspDocList *docs, MsSpan uri, int64_t version, MsSpan text);
void lsp_doc_remove(LspDocList *docs, MsSpan uri);

/* Sends `textDocument/publishDiagnostics` for each open document whose diagnostics changed since they were last sent,
 * in URI order. `send` takes ownership of the message. */
void lsp_publish_diagnostics(LspDocList *docs, void (*send)(MsStrBuild *message));
/* Sends an empty set for a closed document. */
void lsp_publish_empty(MsSpan uri, void (*send)(MsStrBuild *message));

#endif
