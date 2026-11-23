/* cli/init_command.h: `ms init [--lib | --workspace] [directory]`. */
#ifndef MS_CLI_INIT_COMMAND_H
#define MS_CLI_INIT_COMMAND_H

/* `argv` holds the arguments after the command. Returns the process status. */
int ms_init_command(int argc, char **argv);

#endif
