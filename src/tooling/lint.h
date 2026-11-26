/* tooling/lint.h: the advisory findings of `ms check --only lint` over a checked program
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
  bool has_fix; /* an edit `ms check --only lint --fix` applies: replace [fix_pos, fix_end) with `replacement` */
  MsPos fix_pos, fix_end;
  MsSpan replacement;
} MsLintFinding;

MS_LIST_DEFINE(MsLintFindingList, ms_lint_finding_list, MsLintFinding)

/* Everything `ms check --only lint` reports for a checked program, outside `@std/`: lexical findings per module, then
 * semantic ones, ordered by file, line and column. */
void ms_lint_modules(MsArena *arena, const MsCheckProgram *program, MsLintFindingList *findings);

/* The nested matches (MSL107) of a parsed module, which needs no type checking. */
void ms_lint_nested_matches(const MsModule *tree, MsSpan file, MsLintFindingList *findings);

/* The syntax-only findings of `source`, which need parsing and nothing else: nested matches. A `.md` source is
 * its ```ms, ```manuscript and ```text fences, each a module, or, when it declares nothing, the statements of a
 * function; code that does not parse is left to the checks that own it. A line `// manuscript:allow-nested-match
 * <reason>` before a match allows it. Positions are those of `source`. */
void ms_lint_syntax(MsArena *arena, MsSpan file, MsSpan source, MsLintFindingList *findings);

/* The position of byte `offset` in `source`: its line and column, both counted from 1. */
MsPos ms_lint_pos_at(MsSpan source, size_t offset);

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
void ms_lint_terse(MsArena *arena, const MsCheckProgram *program, uint32_t module, MsLintFindingList *findings);
void ms_lint_effects(MsArena *arena, const MsCheckProgram *program, MsLintFindingList *findings);

#endif
