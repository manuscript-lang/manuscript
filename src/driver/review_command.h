#ifndef MS_DRIVER_REVIEW_COMMAND_H
#define MS_DRIVER_REVIEW_COMMAND_H

/* Runs `ms review <file.ms|ms.toml> [--diff f] [--format ascii|markdown] [--json] [--all] [--effect e] [--explain n]`:
 * the review report of a project or of a change. `argv` holds the arguments after the command. */
int ms_review_command(int argc, char **argv);

#endif
