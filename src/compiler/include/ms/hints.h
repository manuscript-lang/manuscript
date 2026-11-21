/* Diagnostic wording helpers: the pure string functions of the Rust checker's hints.rs.
 *
 * Diagnostics read "<cause>; <fix>". The cause comes first and keeps the stable wording rule codes
 * classify; the fix names concrete source to write. Results are allocated in the caller's arena. An
 * empty MsStr means "no hint". Names are compared as bytes and lowercased as ASCII, which is all
 * an identifier can hold. */
#ifndef MS_HINTS_H
#define MS_HINTS_H

#include "ms/base.h"

/* Byte-wise string comparison, which is how Rust orders strings. */
bool ms_str_equal(MsStr a, MsStr b);
int ms_str_compare(MsStr a, MsStr b);
/* The same as a `qsort` comparator over an array of MsStr. */
int ms_str_compare_ptr(const void *a, const void *b);
bool ms_str_starts_with(MsStr s, MsStr prefix);

/* Levenshtein distance over scalar values. */
size_t ms_edit_distance(MsArena *arena, MsStr a, MsStr b);

/* The candidate most similar to `name`, or empty when none is near enough to be a plausible
 * misspelling. */
MsStr ms_closest(MsArena *arena, MsStr name, const MsStr *candidates, size_t count);

/* `; did you mean 'x'?` for a near miss, else empty. */
MsStr ms_did_you_mean(MsArena *arena, MsStr name, const MsStr *candidates, size_t count);

/* The sorted, de-duplicated, non-empty names; returns how many. */
size_t ms_unique_sorted(MsArena *arena, const MsStr *names, size_t count, MsStr **out);

/* At most `limit` sorted names, joined by ", " and followed by ", ..." when more were left out. */
MsStr ms_hint_list(MsArena *arena, const MsStr *names, size_t count, size_t limit);

/* `Name[T1, T2]` for an arity, or `Name with no type arguments`. */
MsStr ms_type_sketch(MsArena *arena, MsStr name, size_t arity);

/* `word` for a count of one, else `words`. */
MsStr ms_plural(MsArena *arena, size_t count, const char *word);

/* The module that replaces the renamed standard module `path`, or NULL. */
const char *ms_renamed_module(MsStr path);

/* The builtin type other languages call by this name, or NULL. */
const char *ms_type_alias(MsStr name);

/* `; did you mean 'x' or 'y'?` from the member names another language uses (`push` for `append`,
 * `fooBar` for `foo_bar`) that exist in `available`, else empty. */
MsStr ms_synonym_hint(MsArena *arena, MsStr name, const MsStr *available, size_t count);

/* A replacement of a source range. */
typedef struct MsFix {
    MsPos pos, end;
    MsStr replacement;
} MsFix;

/* Rewrites the quoted module path `old` that the import clause starting at `from` names to `new`.
 * False unless the quoted path is on the clause's first line. */
MS_NODISCARD bool ms_rename_module_path(MsArena *arena, MsStr source, MsPos from, MsStr old, MsStr new_path,
                                        MsFix *out);

#endif
