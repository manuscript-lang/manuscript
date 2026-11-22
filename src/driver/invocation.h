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
  MsSpan format, view, entity, diff; /* `ms diagram`; empty when absent */
  int64_t depth;       /* `ms diagram --depth`; 0 when absent */
  int64_t top;         /* `ms profile --top`; 0 for the default */
  bool json, watch, static_libc;
  bool allocs;         /* `ms profile --allocs` */
} MsInvocation;

/* Reads `argv` (the arguments after the command name) for `command`: a command that takes a source input. Returns 0, or the exit
 * status after printing the problem. The lists are freed with `ms_invocation_free`. */
int ms_invocation_parse(MsArena *arena, const char *command, int argc, char **argv, MsInvocation *out);

void ms_invocation_free(MsInvocation *invocation);

/* Whether `flag` is an option that consumes the next argument as its value. */
bool ms_invocation_takes_value(MsSpan flag);

#endif
