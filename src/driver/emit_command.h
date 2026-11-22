/* driver/emit_command.h: `ms emit`. */
#ifndef MS_DRIVER_EMIT_COMMAND_H
#define MS_DRIVER_EMIT_COMMAND_H

/* Runs `ms emit <file.ms> [--ir]`: lowers the program and prints its MIR (or, with `--ir`, the LLVM IR the back
 * end emits). `argv` holds the arguments after the command. Returns the process status. */
int ms_emit_command(int argc, char **argv);

#endif
