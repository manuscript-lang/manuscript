/* cli/check_command.h: `ms check --only types` and `ms check --only lint`. */
#ifndef MS_CLI_CHECK_COMMAND_H
#define MS_CLI_CHECK_COMMAND_H

/* Runs `ms check --only types <file.ms> [--json [--with-text]]`; `argv` holds the arguments after the command. Returns the
 * process status. */
int ms_check_types_command(int argc, char **argv);

/* Runs `ms check --only lint <targets> [--json] [--fix] [--deny-warnings]`: check, then the lint rules. */
int ms_lint_command(int argc, char **argv);

#endif
