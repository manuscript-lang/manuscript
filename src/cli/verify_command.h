/* Driver: `ms verify [target] [--no-test] [--deny-warnings]`, check, fmt --check, lint and test in one result
 * (crates/ms-cli/src/verify.rs). Lint covers the effects rule only so far; the test step and --json are not
 * implemented. */
#ifndef MS_CLI_VERIFY_COMMAND_H
#define MS_CLI_VERIFY_COMMAND_H

/* Runs `ms verify` over the arguments after the command name; returns the process exit status. */
int ms_verify_command(int argc, char **argv);

/* The program the steps run: this one, as the user started it. */
void ms_verify_set_program(const char *program);

#endif
