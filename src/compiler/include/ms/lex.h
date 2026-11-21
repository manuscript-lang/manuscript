/* The lexer with layout: scans UTF-8 source and emits Newline/Indent/Dedent tokens. */
#ifndef MS_LEX_H
#define MS_LEX_H

#include <setjmp.h>

#include "ms/base.h"
#include "ms/token.h"

/* Offsets in the normalised source discovered while validating text once. Sorted by start. */
typedef struct MsRange {
    size_t start, end;
} MsRange;

typedef struct MsBounds {
    MsRange *strings;
    size_t nstrings;
    MsRange *interps;
    size_t ninterps;
    uint32_t *line_offsets; /* CR bytes removed before each line; NULL when the source had no CRLF */
    uint32_t base_line;
} MsBounds;

typedef struct MsLexed {
    const char *source; /* source with CRLF replaced by LF; token text indexes into it */
    size_t source_len;
    MsToken *tokens;
    size_t ntokens;
    MsRange *blocks; /* byte ranges of block comments in `source` */
    size_t nblocks;
    MsBounds bounds;
} MsLexed;

/* Lexes the source; returns false and fills *diag on the first error. Everything allocated comes
 * from `arena`. */
bool ms_lex(MsArena *arena, const char *src, size_t len, MsLexed *out, MsDiag *diag);

/* Lexes the slice of a larger file whose first byte is at original offset base_offset on line
 * base_line + 1. */
bool ms_lex_at(MsArena *arena, const char *src, size_t len, uint32_t base_offset,
               uint32_t base_line, MsLexed *out, MsDiag *diag);

/* Lexes one validated interpolation (`src` is its text between the braces) with a virtual
 * parenthesis around it. `origin` is its offset in the normalised source scanned by the outer
 * lexer. */
bool ms_lex_interpolation(MsArena *arena, const char *src, size_t len, size_t origin,
                          const MsBounds *bounds, MsToken **tokens, size_t *ntokens, MsDiag *diag);

/* End of the interpolation that opens at `start`, or 0 when none does. */
size_t ms_bounds_interp_end(const MsBounds *b, size_t start);
/* Position after advancing from `from` to `to` through normalised text, restoring CR bytes. */
MsPos ms_bounds_restore_offset(const MsBounds *b, MsPos from, MsPos to);

/* Editor recovery. For each physical line start (including the empty line after a final newline),
 * whether lexing the prefix ending there leaves a delimiter open; `stop_at` lines end the pass when
 * they are closed. Returns an arena array of `*count` entries. */
bool *ms_unterminated_prefixes(MsArena *arena, const char *src, size_t len, const bool *stop_at,
                               size_t nstop, size_t *count);
/* Physical lines inside text or block comments, which cannot start recovery chunks. `roots[i]` says
 * line i starts a declaration. */
bool *ms_recovery_continuations(MsArena *arena, const char *src, size_t len, const bool *roots,
                                size_t nroots, size_t *count);

/* Quotes a scalar the way Rust's `{:?}` does for a char. */
void ms_quote_rune(MsBuf *out, uint32_t c);

#endif
