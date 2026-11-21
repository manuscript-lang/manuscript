/* driver/fmt_targets.h: the files `ms fmt` formats, from its targets. */
#ifndef MS_DRIVER_FMT_TARGETS_H
#define MS_DRIVER_FMT_TARGETS_H

#include "base/arena.h"
#include "base/list.h"
#include "compiler/syntax/pos.h"

typedef struct FmtFile {
  MsSpan path;    /* canonical */
  MsSpan display; /* relative to the working directory when below it */
} FmtFile;

MS_LIST_DEFINE(FmtFileList, fmt_file_list, FmtFile)

/* A target that could not be turned into files. */
typedef struct FmtProblem {
  MsSpan display;
  MsSpan message;
  bool manifest; /* a manifest error: phase resolution, at `position` */
  MsPos position;
} FmtProblem;

MS_LIST_DEFINE(FmtProblemList, fmt_problem_list, FmtProblem)

/* Expands every target: a directory or ms.toml to its project's files, a file to itself. Files come back
 * deduplicated by physical path and ordered by display; texts live in `arena`. */
void fmt_resolve_targets(MsArena *arena, const MsSpan *targets, size_t count, FmtFileList *files,
                         FmtProblemList *problems);

#endif
