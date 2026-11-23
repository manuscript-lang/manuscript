/* compiler/check/suggest.h: near-miss suggestions and name lists for diagnostics.
 *
 * The same rules as the oracle: a name is a near miss of a candidate when the edit distance is at most a
 * third of its length (rounded down), or rounded up when one name extends or truncates the other. */
#ifndef MS_COMPILER_CHECK_SUGGEST_H
#define MS_COMPILER_CHECK_SUGGEST_H

#include "base/intern.h"
#include "base/strbuild.h"

/* The candidate most similar to `name`, or false when none is near enough to be a plausible misspelling. */
bool ms_suggest_closest(MsSpan name, const MsSpanList *candidates, MsSpan *best);

/* Appends `; did you mean 'x'?` for a near miss; false (nothing appended) when there is none. */
bool ms_suggest_did_you_mean(MsStrBuild *out, MsSpan name, const MsSpanList *candidates);

/* Appends the names sorted and de-duplicated, at most `limit` of them, then `, ...` when more were left out. */
void ms_suggest_list(MsStrBuild *out, const MsSpanList *names, size_t limit);


#endif
