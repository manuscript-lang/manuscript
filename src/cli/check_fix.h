/* cli/check_fix.h: `ms check --fix`: applying the edits diagnostics suggest. */
#ifndef MS_CLI_CHECK_FIX_H
#define MS_CLI_CHECK_FIX_H

#include "base/arena.h"
#include "base/list.h"
#include "compiler/syntax/pos.h"

typedef struct CheckFix {
  MsSpan path; /* the file the edit is in, as the file system names it */
  uint32_t start, end;
  MsSpan replacement;
} CheckFix;

MS_LIST_DEFINE(CheckFixList, check_fix_list, CheckFix)

/* A file the fixes could not be applied to, with what to tell the user. */
typedef struct CheckFixProblem {
  MsSpan path;
  MsSpan message;
} CheckFixProblem;

MS_LIST_DEFINE(CheckFixProblemList, check_fix_problem_list, CheckFixProblem)

/* What a whole `--fix` run has done so far. */
typedef struct CheckFixRun {
  size_t fixes;
  CheckFixProblemList problems; /* files that are not tried again in this run */
  MsSpan *edited;               /* distinct files edited */
  size_t edited_count;
  uint64_t *seen_hash; /* every text a file has had, so two fixes undoing each other stop */
  MsSpan *seen_path;
  size_t seen_count, seen_capacity;
} CheckFixRun;

/* Applies `fixes` in place, last edit first so offsets stay valid. A fix that is repeated or overlaps an earlier one
 * waits for the next run. Returns how many were applied. */
size_t check_apply_fixes(MsArena *arena, CheckFixRun *run, CheckFixList *fixes);

void check_fix_run_free(CheckFixRun *run);

#endif
