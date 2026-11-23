/* tooling/search_text.h: the text steps symbol search and the guide search share: blank-separated words, a subsequence
 * test and a bounded edit distance. Texts live in the arena. */
#ifndef MS_TOOLING_SEARCH_TEXT_H
#define MS_TOOLING_SEARCH_TEXT_H

#include "base/arena.h"

/* Whether the byte separates words: a space, tab, carriage return or line feed. */
bool ms_text_is_blank(uint8_t c);

/* The words of `s` joined by one space. */
MsSpan ms_text_one_spaced(MsArena *arena, MsSpan s);

/* Whether the bytes of `needle` appear in order in `haystack`, not necessarily next to each other. */
bool ms_text_is_subsequence(MsSpan needle, MsSpan haystack);

/* The Damerau-Levenshtein distance (adjacent transpositions count one) of `a` and `b` when it is at most `limit`;
 * otherwise some value above `limit`. */
size_t ms_text_edit_distance(MsArena *arena, MsSpan a, MsSpan b, size_t limit);

#endif
