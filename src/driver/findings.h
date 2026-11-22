/* driver/findings.h: the diagnostics `ms check` and the commands that compile report, ready to print. */
#ifndef MS_DRIVER_FINDINGS_H
#define MS_DRIVER_FINDINGS_H

#include "base/list.h"
#include "base/strbuild.h"
#include "compiler/check/program.h"
#include "compiler/project/project.h"
#include "compiler/syntax/diag.h"

/* One diagnostic ready to print: the file it is in, its phase and its text. */
typedef struct Finding {
  MsSpan file;
  const char *phase;
  MsDiag diag;
} Finding;

MS_LIST_DEFINE(FindingList, finding_list, Finding)

/* The diagnostics of a graph that failed to load, and of a checked program. */
void finding_add_graph(const MsGraph *graph, FindingList *findings);
void finding_add_check(const MsCheckProgram *program, const MsNames *names, FindingList *findings);

/* Diagnostics by file, line and column; usable as an `ms_sort` comparator. */
int64_t finding_compare(uint8_t *env, const uint8_t *left, const uint8_t *right);

/* Whether a file is a fetched package's: `@id/path`, which has no place in the project's directory. */
bool finding_is_package_file(MsSpan file);

/* Appends the terminal report: `file:line:col: phase: message`, the excerpt of each, then the count. */
void finding_terminal_text(MsStrBuild *err, MsSpan root, const FindingList *findings);

#endif
