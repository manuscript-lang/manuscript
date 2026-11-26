/* Driver: `ms check [target] [--test] [--deny-warnings]` with no `--only`: types, fmt --check and lint, and with `--test` the
 * tests, in one result. */
#ifndef MS_CLI_CHECK_ALL_COMMAND_H
#define MS_CLI_CHECK_ALL_COMMAND_H

/* Runs `ms check` without `--only` over the arguments after the command name; returns the process exit status. */
int ms_check_all_command(int argc, char **argv);

/* The program the steps run: this one, as the user started it. */
void ms_check_all_set_program(const char *program);

#endif
