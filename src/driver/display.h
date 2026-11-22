/* driver/display.h: how the commands show paths and path errors, as crates/ms-cli does. */
#ifndef MS_DRIVER_DISPLAY_H
#define MS_DRIVER_DISPLAY_H

#include "base/arena.h"
#include "base/strbuild.h"
#include "compiler/project/project.h"

/* The canonical absolute spelling of `path` (against the working directory), or false. */
MS_NODISCARD bool ms_display_physical(MsArena *arena, MsSpan path, MsSpan *out);

/* `path` as shown: relative to the working directory when it lies below it, else absolute. */
MsSpan ms_display_of(MsArena *arena, MsSpan path);

/* The message of a failed path operation, naming `shown`: a missing file says how to fix it. */
MsSpan ms_display_path_message(MsArena *arena, const MsProjectError *error, MsSpan shown);

#endif
