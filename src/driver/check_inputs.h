/* driver/check_inputs.h: the inputs of `ms check` from its targets. A collection is a set of independent compiler
 * requests, never one combined program. Port of crates/ms-cli/src/analysis.rs. */
#ifndef MS_DRIVER_CHECK_INPUTS_H
#define MS_DRIVER_CHECK_INPUTS_H

#include "base/arena.h"
#include "base/list.h"
#include "compiler/syntax/pos.h"

typedef struct CheckInput {
  MsSpan path;    /* what the loader opens */
  MsSpan display; /* what diagnostics call it */
} CheckInput;

MS_LIST_DEFINE(CheckInputList, check_input_list, CheckInput)

/* A target that could not be selected: a resolution diagnostic at `display` 1:1. */
typedef struct CheckProblem {
  MsSpan display;
  MsSpan message;
} CheckProblem;

MS_LIST_DEFINE(CheckProblemList, check_problem_list, CheckProblem)

typedef struct CheckSelection {
  CheckInputList inputs; /* ordered by display */
  CheckProblemList problems;
  bool collection; /* diagnostics carry paths relative to the working directory */
} CheckSelection;

/* Selects the inputs of `count` targets: a file is itself, a directory with ms.toml is its manifest, and one without
 * stands for the `.ms` files below it (hidden, vendor and node_modules directories and nested projects excluded). */
void check_select_inputs(MsArena *arena, const MsSpan *targets, size_t count, CheckSelection *out);

void check_selection_free(CheckSelection *selection);

#endif
