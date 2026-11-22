/* driver/bench_command.h: `ms bench <input> [selection and timing options] [--json] [-- program arguments]`. */
#ifndef MS_DRIVER_BENCH_COMMAND_H
#define MS_DRIVER_BENCH_COMMAND_H

/* `argv` holds the arguments after the command. Returns the process status. */
int ms_bench_command(int argc, char **argv);

#endif
