/* runtime/core/string_split.h: split, the split iterator and replace (string_split.c). */
#ifndef MS_RUNTIME_CORE_STRING_SPLIT_H
#define MS_RUNTIME_CORE_STRING_SPLIT_H

#include "base/list.h"
#include "base/string.h"

/* ms-sig: msrt_string_split(s: *const StrVal, sep: *const StrVal, out: *mut VecVal) @domain=string @end */
void msrt_string_split(const MsString *s, const MsString *sep, MsList *out);
/* The pieces of `s` from byte `at` on, views of `s`: none when `at` is past the pieces. */
/* ms-sig: msrt_string_split_view(s: *const StrVal, sep: *const StrVal, at: i64, out: *mut VecVal) @borrows @twin=split_view @domain=string @end */
void msrt_string_split_view(const MsString *s, const MsString *sep, int64_t at, MsList *out);
/* ms-sig: msrt_string_split_view_into(s: *const StrVal, sep: *const StrVal, at: i64, buf: *mut FrameBuf<StrVal, 8>,
 * out: *mut VecVal) @borrows @domain=string @end */
void msrt_string_split_view_into(const MsString *s, const MsString *sep, int64_t at, MsString *buffer, MsList *out);
/* ms-sig: msrt_string_split_first(s: *const StrVal, sep: *const StrVal, at: i64, out: *mut StrVal) @borrows @domain=string
 * @end */
void msrt_string_split_first(const MsString *s, const MsString *sep, int64_t at, MsString *out);
/* The byte offset where the piece of `s` that starts at `at` ends when `s` is split at `sep`. */
/* ms-sig: msrt_string_split_end(s: *const StrVal, sep: *const StrVal, at: i64) -> i64 @domain=string @leaf @end */
int64_t msrt_string_split_end(const MsString *s, const MsString *sep, int64_t at);
/* ms-sig: msrt_string_piece(s: *const StrVal, start: i64, end: i64, out: *mut StrVal) @borrows @leaf @domain=string @end */
void msrt_string_piece(const MsString *s, int64_t start, int64_t end, MsString *out);
/* ms-sig: msrt_string_replace(s: *const StrVal, old: *const StrVal, new: *const StrVal, out: *mut StrVal)
 * @domain=string @end */
void msrt_string_replace(const MsString *s, const MsString *old, const MsString *replacement, MsString *out);
/* ms-sig: msrt_string_replace_first(s: *const StrVal, old: *const StrVal, new: *const StrVal, out: *mut
 * StrVal) @domain=string @end */
void msrt_string_replace_first(const MsString *s, const MsString *old, const MsString *replacement,
                               MsString *out);
/* ms-sig: msrt_string_replace_take(s: *mut StrVal, old: *const StrVal, new: *const StrVal, out: *mut StrVal)
 * @domain=string @leaf @end */
void msrt_string_replace_take(MsString *s, const MsString *old, const MsString *replacement, MsString *out);

#endif
