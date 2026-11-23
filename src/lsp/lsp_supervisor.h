/* lsp/lsp_supervisor.h: crash isolation for `ms lsp`. The server runs as a worker copy of this executable behind a
 * supervisor; when the worker dies, the requests it had not answered fail, a new worker starts and the open documents
 * are replayed. Port of crates/ms-lsp/src/supervise.rs. */
#ifndef MS_CLI_LSP_SUPERVISOR_H
#define MS_CLI_LSP_SUPERVISOR_H

/* Serves the session on standard input and output through restartable workers. Ends the process with the session's status. */
_Noreturn void lsp_supervise(void);

#endif
