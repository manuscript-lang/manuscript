/* cli/help_command.h: `ms help`, `ms --version`, and the help and unknown-command answers every command shares.
 *rs. */
#ifndef MS_CLI_HELP_COMMAND_H
#define MS_CLI_HELP_COMMAND_H

#include <stdbool.h>

#include "base/safe.h"

/* The usage page of `command`, or NULL when it names no command. */
const char *ms_help_page(MsSpan command);

/* Prints the command list. */
void ms_help_print_top(void);

/* Prints "unknown command", the nearest command if any, and the command list to stderr. */
void ms_help_unknown_command(MsSpan name);

/* Whether `argv` (the arguments after a command) asks for help: `-h` or `--help` before any `--`, not as an option's
 * value. */
bool ms_help_requested(int argc, char **argv);

/* `ms help [command | code]` and `ms --version`, with the arguments after the command name. Return the exit
 * status. */
int ms_help_command(int argc, char **argv);
int ms_version_command(int argc, char **argv);

#endif
