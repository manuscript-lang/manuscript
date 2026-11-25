/* runtime/core/string_split.h: split, the split iterator and replace (string_split.c). */
#ifndef MS_RUNTIME_CORE_STRING_SPLIT_H
#define MS_RUNTIME_CORE_STRING_SPLIT_H

#include "base/list.h"
#include "base/string.h"

/* ms-sig: msrt_string_split(s: *const StrVal, sep: *const StrVal, out: *mut VecVal) @domain=string @end */
void msrt_string_split(const MsString *s, const MsString *sep, MsList *out);
/* ms-sig: msrt_string_split_view(s: *const StrVal, sep: *const StrVal, out: *mut VecVal) @borrows @twin=split_view @domain=string @end */
void msrt_string_split_view(const MsString *s, const MsString *sep, MsList *out);
/* ms-sig: msrt_string_split_view_into(s: *const StrVal, sep: *const StrVal, buf: *mut FrameBuf<StrVal, 8>,
 * out: *mut VecVal) @borrows @domain=string @end */
void msrt_string_split_view_into(const MsString *s, const MsString *sep, MsString *buffer, MsList *out);
/* ms-sig: msrt_string_split_first(s: *const StrVal, sep: *const StrVal, out: *mut StrVal) @borrows @domain=string
 * */
void msrt_string_split_first(const MsString *s, const MsString *sep, MsString *out);
/* The piece of `s` that starts at byte `at` when it is split at `sep`, a view of `s`: the step of
 * `for piece in s.split(sep)`. */
/* ms-sig: msrt_string_split_at(s: *const StrVal, sep: *const StrVal, at: i64, out: *mut StrVal) @borrows @domain=string @leaf
 * @end */
void msrt_string_split_at(const MsString *s, const MsString *sep, int64_t at, MsString *out);
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
