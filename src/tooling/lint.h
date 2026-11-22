/* tooling/lint.h: the advisory findings of `ms lint` over a checked program, as in crates/ms-tooling/src/lint.
 * Lint never changes behavior and finds nothing in a program that has diagnostics.
 *
 * Ownership: every text of a finding is allocated from the arena the caller gives. */
#ifndef MS_TOOLING_LINT_H
#define MS_TOOLING_LINT_H

#include "base/arena.h"
#include "base/list.h"
#include "compiler/check/program.h"
#include "tooling/lint_rules.h"

typedef struct MsLintFinding {
  const char *code; /* a rule of MS_LINT_RULES */
  MsLintSeverity severity;
  MsSpan file;
  MsPos pos;
  MsSpan message;
  bool has_fix; /* an edit `ms lint --fix` applies: replace [fix_pos, fix_end) with `replacement` */
  MsPos fix_pos, fix_end;
  MsSpan replacement;
} MsLintFinding;

MS_LIST_DEFINE(MsLintFindingList, ms_lint_finding_list, MsLintFinding)

/* Everything `ms lint` reports for a checked program, outside `@std/`: lexical findings per module, then
 * semantic ones, ordered by file, line and column. */
void ms_lint_modules(MsArena *arena, const MsCheckProgram *program, MsLintFindingList *findings);

/* Internal to the rule files: appends a finding of `code` with the severity its rule declares. */
MsLintFinding *ms_lint_add(MsLintFindingList *findings, const char *code, MsSpan file, MsPos pos, MsSpan message);

/* Rule groups. `ms_lint_source` is the lexical rules of one file's text. */
void ms_lint_source(MsArena *arena, MsSpan file, MsSpan source, MsLintFindingList *findings);
void ms_lint_imports(MsArena *arena, const MsCheckProgram *program, uint32_t module, MsLintFindingList *findings);
void ms_lint_unreachable(MsArena *arena, const MsCheckProgram *program, uint32_t module, MsLintFindingList *findings);
void ms_lint_matches(MsArena *arena, const MsCheckProgram *program, uint32_t module, MsLintFindingList *findings);
void ms_lint_calls(MsArena *arena, const MsCheckProgram *program, uint32_t module, MsLintFindingList *findings);
void ms_lint_promises(MsArena *arena, const MsCheckProgram *program, uint32_t module, MsLintFindingList *findings);
void ms_lint_recursion(MsArena *arena, const MsCheckProgram *program, uint32_t module, MsLintFindingList *findings);
void ms_lint_effects(MsArena *arena, const MsCheckProgram *program, MsLintFindingList *findings);

#endif
