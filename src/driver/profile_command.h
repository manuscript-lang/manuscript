/* driver/profile_command.h: `ms profile <input> [--out-dir dir] [--top n] [--allocs] [-- program arguments]`. */
#ifndef MS_DRIVER_PROFILE_COMMAND_H
#define MS_DRIVER_PROFILE_COMMAND_H

/* `argv` holds the arguments after the command. Returns the process status. */
int ms_profile_command(int argc, char **argv);

#endif
