/* Driver: `ms fmt`, the source formatter command. */
#ifndef MS_CLI_FMT_COMMAND_H
#define MS_CLI_FMT_COMMAND_H

/* Runs `ms fmt` over the arguments after the command name; returns the process exit status. Targets are
 * .ms files; directories and ms.toml are not supported yet. */
int ms_fmt_command(int argc, char **argv);

#endif
