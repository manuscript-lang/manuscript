/* cli/command_routes.h: the commands that choose among several implementations by an option, so one command name covers
 * what used to be several: `ms check` (`--only`), `ms build` (`--emit`), `ms run` (`--profile`), `ms map` (`--view`),
 * `ms help` (a diagnostic code) and `ms dev`. Each takes the arguments after the command name and returns the exit status. */
#ifndef MS_CLI_COMMAND_ROUTES_H
#define MS_CLI_COMMAND_ROUTES_H

int ms_check_command(int argc, char **argv);
int ms_build_route(int argc, char **argv);
int ms_run_route(int argc, char **argv);
int ms_map_command(int argc, char **argv);
int ms_dev_command(int argc, char **argv);

#endif
