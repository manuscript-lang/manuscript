/* cli/build_command.h: `ms build <input> [-o output] [--build-type T] [--link file]... [--json]`. */
#ifndef MS_CLI_BUILD_COMMAND_H
#define MS_CLI_BUILD_COMMAND_H

#include "base/arena.h"
#include "base/safe.h"
#include "cli/build_type.h"

/* `argv` holds the arguments after the command. Returns the process status. */
int ms_build_command(int argc, char **argv);

/* Writes the `.ms-build.json` beside the executable `output`: what built it. False when it cannot be written. */
bool ms_build_metadata_write(MsArena *arena, MsSpan output, MsBuildType type);

#endif
