#ifndef MS_CLI_INSPECT_COMMAND_H
#define MS_CLI_INSPECT_COMMAND_H

/* Runs `ms inspect <file.ms|ms.toml> [--json] [-o file]`. A program that does not check reports its diagnostics; the
 * inspection document itself is not ported yet (it needs the oracle's checker-local ids). */
int ms_inspect_command(int argc, char **argv);

#endif
