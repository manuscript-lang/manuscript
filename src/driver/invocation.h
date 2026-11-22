/* driver/invocation.h: the arguments of `ms build`, `ms run` and `ms test`, read and validated. Port of
 * crates/ms-cli/src/invocation.rs and the argument handling of lib.rs. Every text lives in the arena. */
#ifndef MS_DRIVER_INVOCATION_H
#define MS_DRIVER_INVOCATION_H

#include "base/arena.h"
#include "base/intern.h"
#include "driver/build_type.h"

typedef struct MsInvocation {
  MsSpan command;
  MsSpan filename;     /* the input, a directory already replaced by its ms.toml */
  MsSpanList targets;  /* `ms test` inputs; the first is `filename` */
  MsSpan output;       /* -o; empty for the default */
  MsSpanList link;     /* --link: extra objects and static libraries */
  MsSpanList arguments; /* for the program (run), or the test executable's selection options and `--` arguments */
  MsBuildType build_type;
  bool json, watch, static_libc;
} MsInvocation;

/* Reads `argv` (the arguments after the command name) for `command`: "build", "run" or "test". Returns 0, or the exit
 * status after printing the problem. The lists are freed with `ms_invocation_free`. */
int ms_invocation_parse(MsArena *arena, const char *command, int argc, char **argv, MsInvocation *out);

void ms_invocation_free(MsInvocation *invocation);

#endif
