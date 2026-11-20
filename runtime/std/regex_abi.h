/* regex_abi.h: the @std/regex natives (runtime/std/regex_abi.c over regex.c, on PCRE2). It moves to ms_rt/ with a
 * symbols list when regex is wired. Every result is plain integers (byte offsets), so no string or map crosses the boundary; stdlib/regex.ms builds texts from the spans.
 * Fallible functions return a status (0 ok, 1 InvalidInput, 3 LimitExceeded, 4 InvalidData, 11 Failed). */
#ifndef MS_STD_REGEX_ABI_H
#define MS_STD_REGEX_ABI_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* On success *out is a new handle object (owned by the caller); on failure *err, when not null, is an owned message. */
uint8_t msstd_regex_compile(const ms_str *pattern, void **out, ms_str *err);
uint8_t msstd_regex_matches(const void *handle, const ms_str *text);
uint8_t msstd_regex_find_span(const void *handle, const ms_str *text, ms_vec *out);
uint8_t msstd_regex_find_all_spans(const void *handle, const ms_str *text, uint8_t has_max, int64_t max, ms_vec *out);
uint8_t msstd_regex_capture_spans(const void *handle, const ms_str *text, uint8_t has_max, int64_t max, ms_vec *out);
uint8_t msstd_regex_capture_all_spans(const void *handle, const ms_str *text, uint8_t has_matches, int64_t max_matches,
                                      uint8_t has_captures, int64_t max_captures, ms_vec *out);

#endif
