/* driver/emit_command.h: `ms emit`. */
#ifndef MS_DRIVER_EMIT_COMMAND_H
#define MS_DRIVER_EMIT_COMMAND_H

/* Runs `ms emit <target> [-o file]`: checks the project and prints (or writes) the MIR of the program. A target
 * that does not check reports exactly what `ms check` would. Returns the process status. */
int ms_emit_command(int argc, char **argv);

#endif
