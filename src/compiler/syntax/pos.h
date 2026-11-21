/* compiler/syntax/pos.h: source positions and the diagnostic record shared by every compiler stage.
 *
 * `line` and `column` are 1-based, `column` counts bytes, `offset` is a 0-based byte offset into the original
 * source (before CRLF normalisation). A `line` of 0 means "no position". */
#ifndef MS_SYNTAX_POS_H
#define MS_SYNTAX_POS_H

#include "base/arena.h"
#include "base/intern.h"
#include "base/safe.h"

typedef struct MsPos {
  uint32_t offset, line, column;
} MsPos;

/* A half-open byte range of the source. */
typedef struct MsOffsetRange {
  uint32_t start, end;
} MsOffsetRange;

/* One syntax error with its optional range and fix edit. Texts are borrowed from the arena of the call
 * that filled it. */
typedef struct MsDiag {
  MsPos pos;
  bool has_end;
  MsPos end;
  bool has_fix;
  MsPos fix_pos, fix_end;
  MsSpan replacement;
  MsSpan message;
  uint32_t opener_line; /* line of the unclosed delimiter this reports, else 0 */
} MsDiag;

#endif
