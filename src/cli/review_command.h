#ifndef MS_CLI_REVIEW_COMMAND_H
#define MS_CLI_REVIEW_COMMAND_H

/* Runs `ms review <file.ms|ms.toml> [--diff f] [--format ascii|markdown] [--json] [--all] [--effect e] [--explain n]`:
 * the review report of a project or of a change. `argv` holds the arguments after the command. */
int ms_review_command(int argc, char **argv);

#include "base/arena.h"
#include "tooling/checked_input.h"
#include "cli/invocation.h"
#include "tooling/review.h"

/* Reads the invocation's diff and rebuilds the base program from it. Returns 0, or the status of a problem already
 * reported. `base` is checked only when `input->base_checked`. */
int ms_review_diff_inputs(MsArena *arena, const MsCheckedInput *head, const MsInvocation *invocation, MsDiffInput *input,
                          MsFactModel *base_facts, MsCheckedInput *base);

#endif
