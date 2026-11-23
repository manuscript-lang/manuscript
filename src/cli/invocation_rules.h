/* cli/invocation_rules.h: what invocation.c leaves to the rules around the option loop: the default target, the
 * input, workspace roots and the options that may not combine. */
#ifndef MS_CLI_INVOCATION_RULES_H
#define MS_CLI_INVOCATION_RULES_H

#include "cli/invocation.h"

/* The option values the loop collects and `ms_invocation_validate` turns into the request. */
typedef struct MsRawOptions {
  MsSpan build_type_name, timeout, filter;
  MsSpanList test_options;
} MsRawOptions;

/* Prints `message` and returns the usage status 2. */
int ms_usage_error(MsArena *arena, MsSpan message);

/* Reads a decimal integer. */
MS_NODISCARD bool ms_invocation_parse_int(MsSpan text, int64_t *out);

/* `text` in double quotes with `"` and `\` escaped. */
MsSpan ms_invocation_quote(MsArena *arena, MsSpan text);

/* `argv` for `command` as the arguments the option loop reads: the input first. Supplies `ms.toml` when the command
 * names no target, and replaces a directory by its manifest. Returns 0 or the status after printing the problem. */
int ms_invocation_arguments(MsArena *arena, const char *command, int argc, char **argv, MsSpanList *out);

/* A workspace root among the targets of `test` stands for its members; for any other command it is an error. */
int ms_invocation_expand_workspaces(MsArena *arena, MsInvocation *invocation);

/* Rejects option combinations the command does not accept and fills the build type and the program arguments. */
int ms_invocation_validate(MsArena *arena, MsInvocation *invocation, const MsRawOptions *raw);

#endif
