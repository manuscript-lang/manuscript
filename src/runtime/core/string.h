/* runtime/core/string.h: the string natives that generated code calls (string_make.c, string_cut.c,
 * string_query.c, string_lists.c, string_split.c ...). Each declaration carries its `ms-sig` line, which the
 * back end reads. Strings are MsString (base/string.h); an `out` parameter receives an owned result unless
 * the name says view. */

#ifndef MS_RUNTIME_CORE_STRING_H
#define MS_RUNTIME_CORE_STRING_H

#include "base/list.h"
#include "base/string.h"

/* ms-sig: msrt_string_from_bytes(ptr: *const u8, len: usize, out: *mut StrVal) @domain=string @end */
void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsString *out);
/* ms-sig: msrt_string_empty(out: *mut StrVal) @domain=string @end */
void msrt_string_empty(MsString *out);
/* ms-sig: msrt_string_clone(s: *const StrVal, out: *mut StrVal) @domain=string @op=clone
 */
void msrt_string_clone(const MsString *s, MsString *out);
/* ms-sig: msrt_str_copy(ptr: *const u8, tagged: usize, out: *mut StrVal) @domain=string @end */
void msrt_str_copy(const uint8_t *ptr, size_t tagged, MsString *out);
/* ms-sig: msrt_str_free(ptr: *mut u8) @domain=string @end */
void msrt_str_free(uint8_t *ptr);
/* ms-sig: msrt_string_free(s: *const StrVal) @domain=string @end */
void msrt_string_free(const MsString *s);
/* ms-sig: msrt_string_concat(a: *const StrVal, b: *const StrVal, out: *mut StrVal) @domain=string
 * */
void msrt_string_concat(const MsString *a, const MsString *b, MsString *out);
/* ms-sig: msrt_string_append(a: *const StrVal, b: *const StrVal, out: *mut StrVal) @domain=string
 * */
void msrt_string_append(const MsString *a, const MsString *b, MsString *out);
/* ms-sig: msrt_string_repeat(s: *const StrVal, count: i64, out: *mut StrVal) @domain=string @end */
void msrt_string_repeat(const MsString *s, int64_t count, MsString *out);
/* ms-sig: msrt_string_reverse(a: *const StrVal, out: *mut StrVal) @domain=string @end */
void msrt_string_reverse(const MsString *a, MsString *out);
/* ms-sig: msrt_string_trim(s: *const StrVal, out: *mut StrVal) @borrows @leaf @domain=string */
void msrt_string_trim(const MsString *s, MsString *out);
/* ms-sig: msrt_string_trim_start(s: *const StrVal, out: *mut StrVal) @borrows @leaf @domain=string */
void msrt_string_trim_start(const MsString *s, MsString *out);
/* ms-sig: msrt_string_trim_end(s: *const StrVal, out: *mut StrVal) @borrows @leaf @domain=string */
void msrt_string_trim_end(const MsString *s, MsString *out);
/* ms-sig: msrt_string_char_at(s: *const StrVal, at: i64, out: *mut StrVal) @domain=string @end */
void msrt_string_char_at(const MsString *s, int64_t at, MsString *out);
/* ms-sig: msrt_string_slice(s: *const StrVal, start: i64, end: i64, out: *mut StrVal) @domain=string @end */
void msrt_string_slice(const MsString *s, int64_t start, int64_t end, MsString *out);
/* ms-sig: msrt_string_view(s: *const StrVal, start: i64, end: i64, out: *mut StrVal) @borrows @domain=string
 * */
void msrt_string_view(const MsString *s, int64_t start, int64_t end, MsString *out);
/* ms-sig: msrt_string_hash(s: *const StrVal) -> i64 @domain=map @end */
int64_t msrt_string_hash(const MsString *s);
/* ms-sig: msrt_string_eq(a: *const StrVal, b: *const StrVal) -> u8 @domain=string @leaf @end */
uint8_t msrt_string_eq(const MsString *a, const MsString *b);
/* ms-sig: msrt_string_compare(a: *const StrVal, b: *const StrVal) -> i64 @domain=map @leaf @end */
int64_t msrt_string_compare(const MsString *a, const MsString *b);
/* ms-sig: msrt_string_is_empty(s: *const StrVal) -> u8 @domain=string @end */
/* ms-op: msrt_string_is_empty str_is_empty */
uint8_t msrt_string_is_empty(const MsString *s);
/* ms-sig: msrt_string_length(s: *const StrVal) -> i64 @domain=string @end */
/* ms-op: msrt_string_length str_bytes */
int64_t msrt_string_length(const MsString *s);
/* ms-sig: msrt_string_starts_with(a: *const StrVal, v: *const StrVal) -> u8 @domain=string @end */
uint8_t msrt_string_starts_with(const MsString *a, const MsString *v);
/* ms-sig: msrt_string_ends_with(a: *const StrVal, v: *const StrVal) -> u8 @domain=string @end */
uint8_t msrt_string_ends_with(const MsString *a, const MsString *v);
/* ms-sig: msrt_string_scalar_length(s: *const StrVal) -> i64 @domain=string @end */
int64_t msrt_string_scalar_length(const MsString *s);
/* ms-sig: msrt_string_char_width(s: *const StrVal, at: i64) -> i64 @domain=string @end */
int64_t msrt_string_char_width(const MsString *s, int64_t at);
/* ms-sig: msrt_string_scalar_step(s: *const StrVal, at: i64) -> i64 @domain=string @end */
int64_t msrt_string_scalar_step(const MsString *s, int64_t at);
/* ms-sig: msrt_string_scalar_at_byte(s: *const StrVal, at: i64) -> i64 @domain=string @end */
int64_t msrt_string_scalar_at_byte(const MsString *s, int64_t at);
/* ms-sig: msrt_string_contains(a: *const StrVal, v: *const StrVal) -> u8 @domain=string @end */
uint8_t msrt_string_contains(const MsString *a, const MsString *v);
/* ms-sig: msrt_string_contains_multi(a: *const StrVal, v: *const StrVal) -> u8 @domain=string @end */
uint8_t msrt_string_contains_multi(const MsString *a, const MsString *v);
/* ms-sig: msrt_string_count(a: *const StrVal, v: *const StrVal) -> i64 @domain=string @end */
int64_t msrt_string_count(const MsString *a, const MsString *v);
/* ms-sig: msrt_string_index_of(a: *const StrVal, v: *const StrVal, out: *mut i64) -> u8 @domain=string
 * */
uint8_t msrt_string_index_of(const MsString *a, const MsString *v, int64_t *out);
/* ms-sig: msrt_string_last_index_of(a: *const StrVal, v: *const StrVal, out: *mut i64) -> u8 @domain=string
 * */
uint8_t msrt_string_last_index_of(const MsString *a, const MsString *v, int64_t *out);
/* The scalar at byte offset `at` of `s` as an inline string; `for c in s.chars()` reads each scalar this way and
 * advances by its length. `at` is the start of a scalar of the valid text. */
void msrt_string_scalar_text(const MsString *s, int64_t at, MsString *out);
/* ms-sig: msrt_string_chars(s: *const StrVal, out: *mut VecVal) @domain=string @end */
void msrt_string_chars(const MsString *s, MsList *out);
/* ms-sig: msrt_string_lines(s: *const StrVal, out: *mut VecVal) @borrows @domain=string @end */
void msrt_string_lines(const MsString *s, MsList *out);
/* ms-sig: msrt_string_fields(s: *const StrVal, out: *mut VecVal) @domain=string @end */
void msrt_string_fields(const MsString *s, MsList *out);
/* ms-sig: msrt_string_scalar_values(s: *const StrVal, out: *mut VecVal) @domain=string @end */
void msrt_string_scalar_values(const MsString *s, MsList *out);
/* ms-sig: msrt_string_from_scalars(values: *const VecVal, out: *mut StrVal) -> u8 @domain=string @end */
uint8_t msrt_string_from_scalars(const MsList *values, MsString *out);
/* ms-sig: msrt_string_to_bytes(s: *const StrVal, out: *mut VecVal) @domain=string @end */
void msrt_string_to_bytes(const MsString *s, MsList *out);
/* ms-sig: msrt_string_view_bytes(s: *const StrVal, out: *mut VecVal) @borrows @domain=string @end */
void msrt_string_view_bytes(const MsString *s, MsList *out);
/* ms-sig: msrt_string_index_any(s: *const StrVal, set: *const StrVal, out: *mut i64) -> u8 @domain=string
 * */
uint8_t msrt_string_index_any(const MsString *s, const MsString *set, int64_t *out);
/* ms-sig: msrt_string_trim_chars(s: *const StrVal, set: *const StrVal, from_start: u8, from_end: u8, out:
 * *mut StrVal) @domain=string @end */
void msrt_string_trim_chars(const MsString *s, const MsString *set, uint8_t from_start, uint8_t from_end,
                            MsString *out);
/* ms-sig: msrt_string_scalar_at(s: *const StrVal, offset: i64, has_default: HasRaw, default: i64) -> i64
 * @domain=string @inline=scalar_at */
int64_t msrt_string_scalar_at(const MsString *s, int64_t offset, uint8_t has_default, int64_t fallback);

#endif
