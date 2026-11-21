/* Regular expressions on PCRE2, for @std/regex.ms. The only file that includes pcre2.h is regex.c.
   Dialect: PCRE2 syntax in UTF and Unicode-property mode, without the features that need unbounded backtracking
   or let a pattern run code (back-references, lookaround, recursion and subroutine calls, conditionals, callouts,
   verbs). `$` matches only at the end of the text; a line break is "\n". Every match runs under hard limits
   (match steps, backtracking depth, heap, JIT stack) that a pattern cannot raise; reaching one is MS_RE_LIMIT.
   The text is valid UTF-8, as a Manuscript String always is. */
#ifndef MS_STD_REGEX_H
#define MS_STD_REGEX_H
#include <stddef.h>
#include <stdint.h>

typedef struct MsRegex MsRegex;

/* Limits of one match call (one search from one start offset). */
#define MS_RE_MATCH_LIMIT 10000000u /* steps inside the matcher */
#define MS_RE_DEPTH_LIMIT 250000u   /* backtracking depth */
#define MS_RE_HEAP_KIB 32768u       /* heap the matcher may use, in KiB */
#define MS_RE_JIT_STACK_MAX (64u << 20) /* bytes of JIT stack, beyond the default 32 KiB */
#define MS_RE_PATTERN_MAX (1u << 20)   /* bytes of pattern */

/* Result of a match call. */
enum { MS_RE_NOMATCH = 0, MS_RE_MATCHED = 1, MS_RE_LIMIT = -1, MS_RE_FAULT = -2 };

/* Compiles a pattern. On failure returns NULL and writes "<reason> at column N" (N counts characters, from 1) to
   msg[cap] (NUL terminated). A pattern over MS_RE_PATTERN_MAX bytes or too large to compile is refused the same way. */
MsRegex *ms_re_compile(const char *pattern, size_t len, char *msg, size_t cap);
void ms_re_free(MsRegex *re);

/* Capture groups including the whole match, so the slot array of a match holds 2 * ms_re_slots(re) values. */
size_t ms_re_slots(const MsRegex *re);
/* Name of group i (1-based) or NULL; *len is its byte length. */
const char *ms_re_group_name(const MsRegex *re, size_t i, size_t *len);

/* Searches text[0..len) from byte offset `start` (a character boundary). On MS_RE_MATCHED, slots[2*i], slots[2*i+1]
   are the byte range of group i, -1 and -1 for a group that did not take part. */
int ms_re_match(const MsRegex *re, const char *text, size_t len, size_t start, int64_t *slots);

/* The matches of a whole text, with Go's rule that an empty match right after the previous match is skipped. */
typedef struct { size_t pos, prev_end; void *scratch; } MsRegexIter;
void ms_re_iter_init(MsRegexIter *it);
/* Releases the iterator's scratch memory; call it once, whatever ms_re_next returned. */
void ms_re_iter_done(MsRegexIter *it);
int ms_re_next(const MsRegex *re, const char *text, size_t len, MsRegexIter *it, int64_t *slots);

#endif
