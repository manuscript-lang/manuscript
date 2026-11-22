/* compiler/check/effects_directives.h: effect directives in comments.
 *
 * `// ms: effect NAME` declares an effect a function performs; `// ms: allow_effect PATTERN` permits effects
 * a function (or, in a file's header comment, every function of the file) may reach. A pattern is `*`, a
 * prefix `a.b.*`, a last segment `*.write`, or an exact name.
 *
 * Ownership: directive texts are views into the source they were read from; the lists are owned by the
 * Directives value (ms_directives_free). */
#ifndef MS_COMPILER_CHECK_EFFECTS_DIRECTIVES_H
#define MS_COMPILER_CHECK_EFFECTS_DIRECTIVES_H

#include "base/intern.h"

typedef struct MsDirectives {
  MsSpanList declared; /* `effect NAME` lines */
  MsSpanList allow;    /* `allow_effect PATTERN` lines */
  bool has_allow;      /* at least one allow line: an absent scope is distinct from an empty one */
} MsDirectives;

void ms_directives_free(MsDirectives *directives);

/* The directives of the file header: `//` lines at the top of the file ended by a blank line. A comment block
 * that runs straight into code belongs to that declaration, not to the file. */
MsDirectives ms_directives_header(MsSpan source);

/* The directives in the `//` lines directly above the 1-based `line`, up to a blank or code line. */
MsDirectives ms_directives_above(MsSpan source, uint32_t line);

/* Whether `effect` matches `pattern`. */
bool ms_effect_matches(MsSpan pattern, MsSpan effect);

#endif
