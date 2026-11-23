/* cli/test_command.h: `ms test <input>... [selection options] [--json] [-- program arguments]`. */
#ifndef MS_CLI_TEST_COMMAND_H
#define MS_CLI_TEST_COMMAND_H

/* `argv` holds the arguments after the command. Returns the process status. */
int ms_test_command(int argc, char **argv);

#endif
