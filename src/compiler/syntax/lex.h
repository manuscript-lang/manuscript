/* syntax/lex.h: the lexer with layout. Scans UTF-8 source and emits Newline/Indent/Dedent tokens. */
#ifndef MS_SYNTAX_LEX_H
#define MS_SYNTAX_LEX_H

#include "base/strbuild.h"
#include "compiler/syntax/pos.h"
#include "compiler/syntax/token.h"

/* Offsets in the normalised source discovered while validating text once. Sorted by start. */
typedef struct MsByteRange {
  size_t start, end;
} MsByteRange;

typedef struct MsBounds {
  const MsByteRange *strings;
  size_t nstrings;
  const MsByteRange *interps;
  size_t ninterps;
  const uint32_t *line_offsets; /* CR bytes removed before each line; NULL when the source had no CRLF */
  uint32_t base_line;           /* lines before the first one of a slice of a larger file */
} MsBounds;

typedef struct MsLexed {
  MsSpan source; /* source with CRLF replaced by LF; token text indexes into it */
  MsToken *tokens;
  size_t ntokens;
  const MsByteRange *blocks; /* byte ranges of block comments in `source` */
  size_t nblocks;
  MsBounds bounds;
} MsLexed;

/* Lexes the source; returns false and fills *diag on the first error. Everything allocated comes from
 * `arena`. */
bool ms_lex(MsArena *arena, MsSpan source, MsLexed *out, MsDiag *diag);

/* Lexes a slice of a larger file: its first byte is at original offset `base_offset` and it starts on line
 * `base_line + 1`. Positions are reported in the larger file. */
bool ms_lex_at(MsArena *arena, MsSpan source, uint32_t base_offset, uint32_t base_line, MsLexed *out,
               MsDiag *diag);

/* For each physical line of `source` (one more than its newlines), whether it lies inside a text or block
 * comment that began earlier, so it cannot start a recovery chunk. `roots` marks the lines that start a
 * declaration; one resets the delimiter depth. The result has `nlines` entries from `arena`. */
bool *ms_lex_continuations(MsArena *arena, MsSpan source, const bool *roots, size_t nroots, size_t *nlines);

/* Lexes one validated interpolation (`source` is its text between the braces) with a virtual parenthesis
 * around it. `origin` is its offset in the normalised source scanned by the outer lexer. */
bool ms_lex_interpolation(MsArena *arena, MsSpan source, size_t origin, const MsBounds *bounds,
                          MsToken **tokens, size_t *count, MsDiag *diag);

/* End of the interpolation that opens at `start`, or 0 when none does. */
size_t ms_bounds_interp_end(const MsBounds *bounds, size_t start);

/* Position after advancing from `from` to `to` through normalised text, restoring CR bytes. */
MsPos ms_bounds_restore_offset(const MsBounds *bounds, MsPos from, MsPos to);

/* Appends `scalar` quoted the way Rust's `{:?}` does for a char. */
void ms_quote_rune(MsStrBuild *out, uint32_t scalar);

#endif
