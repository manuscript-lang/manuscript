/* cli/build_command.h: `ms build <input> [-o output] [--build-type T] [--link file]... [--json]`. */
#ifndef MS_CLI_BUILD_COMMAND_H
#define MS_CLI_BUILD_COMMAND_H

/* `argv` holds the arguments after the command. Returns the process status. */
int ms_build_command(int argc, char **argv);

#endif
