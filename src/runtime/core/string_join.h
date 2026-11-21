/* runtime/core/string_join.h: the f-string natives (string_join.c). `msrt_string_fmtN` joins N parts;
 * `msrt_string_append_fmtN` joins them onto an owned `s`. Bit k of `mask` makes part k an Int, otherwise it
 * is the address of a string (for append, `s` is part 0 of the mask). */
#ifndef MS_RUNTIME_CORE_STRING_JOIN_H
#define MS_RUNTIME_CORE_STRING_JOIN_H

#include "base/string.h"

/* ms-sig: msrt_string_fmt2(mask: i64, a: usize, b: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_fmt2(int64_t mask, size_t a, size_t b, MsString *out);
/* ms-sig: msrt_string_fmt3(mask: i64, a: usize, b: usize, c: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_fmt3(int64_t mask, size_t a, size_t b, size_t c, MsString *out);
/* ms-sig: msrt_string_fmt4(mask: i64, a: usize, b: usize, c: usize, d: usize, out: *mut StrVal) @fresh @leaf
 */
void msrt_string_fmt4(int64_t mask, size_t a, size_t b, size_t c, size_t d, MsString *out);
/* ms-sig: msrt_string_fmt5(mask: i64, a: usize, b: usize, c: usize, d: usize, e: usize, out: *mut StrVal)
 * @fresh @leaf */
void msrt_string_fmt5(int64_t mask, size_t a, size_t b, size_t c, size_t d, size_t e, MsString *out);
/* ms-sig: msrt_string_fmt6(mask: i64, a: usize, b: usize, c: usize, d: usize, e: usize, f: usize, out: *mut
 * StrVal) @fresh @leaf */
void msrt_string_fmt6(int64_t mask, size_t a, size_t b, size_t c, size_t d, size_t e, size_t f,
                      MsString *out);
/* ms-sig: msrt_string_append_fmt1(s: *const StrVal, mask: i64, a: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_append_fmt1(const MsString *s, int64_t mask, size_t a, MsString *out);
/* ms-sig: msrt_string_append_fmt2(s: *const StrVal, mask: i64, a: usize, b: usize, out: *mut StrVal) @fresh
 * @leaf */
void msrt_string_append_fmt2(const MsString *s, int64_t mask, size_t a, size_t b, MsString *out);
/* ms-sig: msrt_string_append_fmt3(s: *const StrVal, mask: i64, a: usize, b: usize, c: usize, out: *mut
 * StrVal) @fresh @leaf */
void msrt_string_append_fmt3(const MsString *s, int64_t mask, size_t a, size_t b, size_t c, MsString *out);
/* ms-sig: msrt_string_append_fmt4(s: *const StrVal, mask: i64, a: usize, b: usize, c: usize, d: usize, out:
 * *mut StrVal) @fresh @leaf */
void msrt_string_append_fmt4(const MsString *s, int64_t mask, size_t a, size_t b, size_t c, size_t d,
                             MsString *out);
/* ms-sig: msrt_string_append_fmt5(s: *const StrVal, mask: i64, a: usize, b: usize, c: usize, d: usize, e:
 * usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_append_fmt5(const MsString *s, int64_t mask, size_t a, size_t b, size_t c, size_t d,
                             size_t e, MsString *out);

#endif
