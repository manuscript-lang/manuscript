/* driver/findings.h: the diagnostics `ms check` and the commands that compile report, ready to print. */
#ifndef MS_DRIVER_FINDINGS_H
#define MS_DRIVER_FINDINGS_H

#include "base/list.h"
#include "base/strbuild.h"
#include "compiler/check/program.h"
#include "compiler/project/project.h"
#include "compiler/syntax/diag.h"
#include "tooling/lint.h"

/* One diagnostic ready to print: the file it is in, its phase and its text. A lint finding has no phase; it carries
 * its rule's code and whether that rule only warns. */
typedef struct Finding {
  MsSpan file;
  const char *phase;
  MsDiag diag;
  const char *lint_code; /* NULL for a compiler diagnostic */
  bool warning;
} Finding;

MS_LIST_DEFINE(FindingList, finding_list, Finding)

/* The diagnostics of a graph that failed to load, and of a checked program. */
void finding_add_graph(const MsGraph *graph, FindingList *findings);
void finding_add_check(const MsCheckProgram *program, const MsNames *names, FindingList *findings);

/* The findings of `ms lint`. */
void finding_add_lint(const MsLintFindingList *lint, FindingList *findings);

/* The code a finding reports: its lint rule's, or the family of its phase and message. */
const char *finding_code(const Finding *finding);

/* Diagnostics by file, line and column; usable as an `ms_sort` comparator. */
int64_t finding_compare(uint8_t *env, const uint8_t *left, const uint8_t *right);

/* Whether a file is a fetched package's: `@id/path`, which has no place in the project's directory. */
bool finding_is_package_file(MsSpan file);

/* Appends the terminal report: `file:line:col: phase: message`, the excerpt of each, then the counts. With
 * `deny_warnings` the warning count says that warnings fail the command. */
void finding_terminal_text(MsStrBuild *err, MsSpan root, const FindingList *findings, bool deny_warnings);

/* Whether the findings fail the command: any error, or any finding at all under `deny_warnings`. */
bool finding_fails(const FindingList *findings, bool deny_warnings);

#endif
