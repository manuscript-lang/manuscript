/* Base: the only place that touches C strings.
 *
 * OS strings (argv, environment) enter the program as NUL-terminated pointers. This
 * header is the one wrapper around them; no other file calls the libc string functions.
 * It stays minimal until `base/value` lands and takes over (plan sections 6.2 and 7.1).
 * All pointers are borrowed from the caller. */
#ifndef MS_BASE_CSTR_H
#define MS_BASE_CSTR_H

#include <stdbool.h>

/* True when both NUL-terminated strings hold the same bytes. */
bool ms_cstr_equal(const char *left, const char *right);

#endif
