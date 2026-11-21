/* driver/check_command.h: `ms check`. */
#ifndef MS_DRIVER_CHECK_COMMAND_H
#define MS_DRIVER_CHECK_COMMAND_H

/* Runs `ms check <file.ms> [--json [--with-text]]`; `argv` holds the arguments after the command. Returns the
 * process status. */
int ms_check_command(int argc, char **argv);

#endif
