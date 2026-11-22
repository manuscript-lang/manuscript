/* Driver: `ms verify [target] [--no-test] [--deny-warnings]`, check, fmt --check, lint and test in one result
 * (crates/ms-cli/src/verify.rs). Lint covers the effects rule only so far; the test step and --json are not
 * implemented. */
#ifndef MS_DRIVER_VERIFY_COMMAND_H
#define MS_DRIVER_VERIFY_COMMAND_H

/* Runs `ms verify` over the arguments after the command name; returns the process exit status. */
int ms_verify_command(int argc, char **argv);

#endif
