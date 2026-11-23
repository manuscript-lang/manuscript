/* lsp/lsp_sync.h: reading the JSON of a message and keeping the open documents in step with `textDocument/didOpen` and
 * `didChange`. The session and its supervisor both use it, so a restarted worker replays the same text. */
#ifndef MS_CLI_LSP_SYNC_H
#define MS_CLI_LSP_SYNC_H

#include "tooling/json_value.h"
#include "lsp/lsp_analysis.h"
#include "lsp/lsp_internal.h"

/* The member `key` of an object when it has the kind `kind`, else NULL. */
const MsJson *lsp_json_member(const MsJson *object, const char *key, MsJsonKind kind);
/* A non-negative whole number of at most 15 digits. */
bool lsp_json_integer(const MsJson *value, size_t *out);
bool lsp_json_position(const MsJson *value, LspPosition *position);

/* Stores an opened document, or applies a change transaction to an open one. Stale, empty or malformed transactions are
 * ignored whole. False only when the parameters name no document or an opened one has no text. */
bool lsp_sync_change(LspDocList *docs, bool open, const MsJson *params);

#endif
