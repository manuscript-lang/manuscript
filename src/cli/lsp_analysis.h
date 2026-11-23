/* cli/lsp_analysis.h: the open documents of a language-server session and what the checker says about them. */
#ifndef MS_CLI_LSP_ANALYSIS_H
#define MS_CLI_LSP_ANALYSIS_H

#include "base/list.h"
#include "base/arena.h"
#include "base/string.h"
#include "cli/checked_input.h"
#include "compiler/project/project.h"
#include "tooling/occurrence.h"
#include "base/strbuild.h"

typedef struct LspDoc {
  MsString uri, path, text;
  int64_t version;
  bool dirty;         /* changed since its diagnostics were last sent */
  MsString published; /* the diagnostics last sent, as JSON, to send only changes */
} LspDoc;

MS_LIST_DEFINE(LspDocList, lsp_doc_list, LspDoc)

/* What the checker established about one open document and the files it imports. Initialise with lsp_analyze and end with
 * lsp_analysis_release; the open documents must not change in between. */
typedef struct LspAnalysis {
  MsArena *arena;      /* shared by every copy of a cached analysis */
  bool cached;         /* the analysis belongs to the cache: releasing it keeps it */
  MsCheckedInput checked;
  MsOccurrences index; /* empty unless `resolved` */
  MsWrittenTypes written;
  MsSpan *paths;       /* the file of each user module of the program */
  void *overlay;       /* the open documents' text, as the loader reads it */
  bool resolved;       /* the program was checked, with or without diagnostics */
} LspAnalysis;

/* Checks `doc` as the entry of its own graph, with every open document's text in place of disk. The latest result is kept
 * until an open document's text changes, so successive requests share one check. */
void lsp_analyze(const LspDocList *docs, const LspDoc *doc, LspAnalysis *out);
/* The same with `count` files of `changed` taking the place of the open documents' text (or of disk). */
void lsp_analyze_changed(const LspDocList *docs, const LspDoc *doc, const MsOverlayFile *changed, size_t count,
                         LspAnalysis *out);
/* Whether the workspace of `doc` checks cleanly and still does with `changed` applied; else says why in `error`. */
bool lsp_rename_stays_checked(const LspDocList *docs, const LspDoc *doc, const MsOverlayFile *changed, size_t count,
                              MsStrBuild *error);
void lsp_analysis_release(LspAnalysis *analysis);
/* Forgets the cached analysis: a file changed on disk. Open documents' edits need no call; their versions key the cache. */
void lsp_analysis_invalidate(void);

/* The file `path` of a checked module's name as the editor spells it: absolute. */
MsSpan lsp_absolute_file(MsArena *arena, MsSpan source_root, MsSpan file);

/* The URI an editor opened `path` under, else its `file:` URI; copied into `arena`. */
MsSpan lsp_path_uri(const LspDocList *docs, MsArena *arena, MsSpan path);

LspDoc *lsp_doc_find(const LspDocList *docs, MsSpan uri);
/* Stores the document, replacing an earlier version. */
void lsp_doc_set(LspDocList *docs, MsSpan uri, int64_t version, MsSpan text);
void lsp_doc_remove(LspDocList *docs, MsSpan uri);

/* Sends `textDocument/publishDiagnostics` for each open document whose diagnostics changed since they were last sent,
 * in URI order. `send` takes ownership of the message. */
void lsp_publish_diagnostics(LspDocList *docs, void (*send)(MsStrBuild *message));
/* Sends an empty set for a closed document. */
void lsp_publish_empty(MsSpan uri, void (*send)(MsStrBuild *message));

#endif
