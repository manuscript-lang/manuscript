/* cli/invocation.h: the arguments of `ms build`, `ms run` and `ms test`, read and validated. Every text lives in the arena. */
#ifndef MS_CLI_INVOCATION_H
#define MS_CLI_INVOCATION_H

#include "base/arena.h"
#include "base/intern.h"
#include "cli/build_type.h"

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
  MsSpan explain, effect; /* `ms review --explain`, `--effect` */
  bool all;            /* `ms review --all` */
} MsInvocation;

/* Reads `argv` (the arguments after the command name) for `command`: a command that takes a source input. Returns 0, or the exit
 * status after printing the problem. The lists are freed with `ms_invocation_free`. */
int ms_invocation_parse(MsArena *arena, const char *command, int argc, char **argv, MsInvocation *out);

void ms_invocation_free(MsInvocation *invocation);

/* Whether a flag is followed by a value that is not an input: the options above plus `--limit`, `--explain` and
 * `--effect`, which only their own commands parse. */
bool ms_invocation_skips_value(MsSpan flag);

#endif
