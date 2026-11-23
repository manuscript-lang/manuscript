/* lsp/lsp_input.h: the language server's input read on its own thread, so a `$/cancelRequest` is seen while an earlier
 * request is still being answered and consecutive `textDocument/didChange` messages can be told apart from other work.
 * Port of crates/ms-lsp/src/transport.rs. */
#ifndef MS_CLI_LSP_INPUT_H
#define MS_CLI_LSP_INPUT_H

#include <stdio.h>

#include "lsp/lsp_internal.h"

typedef struct LspInput LspInput;

/* A queue with no reader yet. */
LspInput *lsp_input_create(void);

/* Starts a thread that reads frames from `file` into the queue, each tagged with `source`. With `track`, a
 * `$/cancelRequest` is taken out of the stream and request ids are remembered; without it every frame is queued as is.
 * Reading ends with one end-of-input or failure frame. False when the thread cannot start. */
bool lsp_input_attach(LspInput *input, FILE *file, int source, bool track);

/* The queue of the session's own standard input. NULL when the thread cannot start. */
LspInput *lsp_input_start(FILE *file);

/* Waits for the next frame and replaces `body` with it. A failure names its cause in `error` (static text). `source`
 * may be NULL. */
LspFrameStatus lsp_input_next(LspInput *input, MsStrBuild *body, const char **error, int *source);

/* Whether the next frame already waiting is a `textDocument/didChange` notification or a completion request: the
 * diagnostics of an edit wait behind the first (a later edit supersedes them) and behind the second (the person is
 * typing and wants the list first). */
bool lsp_input_next_defers_publish(LspInput *input);

/* Whether the client canceled the request with this id (a JSON number as written, or a string's decoded text). */
bool lsp_input_canceled(LspInput *input, bool is_string, MsSpan id);

/* Forgets a finished request. */
void lsp_input_done(LspInput *input, bool is_string, MsSpan id);

/* Ends the process without the C library's exit handling: a reader thread blocked in `fread` holds its stream's lock, which
 * would stop `exit` from flushing the streams. Flushes the output first. */
_Noreturn void lsp_input_exit(int status);

#endif
