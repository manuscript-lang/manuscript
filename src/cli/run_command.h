/* cli/run_command.h: `ms run <input> [--build-type T] [--link file]... [--json] [-- program arguments]`. */
#ifndef MS_CLI_RUN_COMMAND_H
#define MS_CLI_RUN_COMMAND_H

/* `argv` holds the arguments after the command. Returns the process status. */
int ms_run_command(int argc, char **argv);

#endif
