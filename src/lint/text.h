/* ms_lint text helpers over NUL-terminated lines. Borrowed pointers only.
 *
 * Local to the lint tool until base/value lands and provides the shared string and span
 * types (plan section 6.2); then this file is deleted. It calls no libc string function. */
#ifndef MS_LINT_TEXT_H
#define MS_LINT_TEXT_H

#include <stdbool.h>
#include <stddef.h>

size_t lint_text_length(const char *text);
bool lint_text_equal(const char *left, const char *right);
bool lint_text_starts_with(const char *text, const char *prefix);
bool lint_text_ends_with(const char *text, const char *suffix);
bool lint_text_contains(const char *text, const char *needle);
/* Removes a trailing newline and carriage return in place. */
void lint_text_chomp(char *line);

/* Calls on_word(context, start, length) for each identifier in code outside string
 * literals and comments; `followed_by_call` tells whether `(` comes next. */
typedef void (*LintWordFn)(void *context, const char *start, size_t length, bool followed_by_call);
void lint_scan_words(const char *line, LintWordFn on_word, void *context);

#endif
