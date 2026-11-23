/* lsp/lsp_command.h: `ms lsp`, the language server on standard input and output. Port of crates/ms-lsp. */
#ifndef MS_CLI_LSP_COMMAND_H
#define MS_CLI_LSP_COMMAND_H

/* Serves one session; `argv` holds the arguments after the command. Returns the process status. */
int ms_lsp_command(int argc, char **argv);

#endif
