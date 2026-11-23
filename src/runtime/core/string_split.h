/* runtime/core/string_split.h: split, the split iterator and replace (string_split.c). */
#ifndef MS_RUNTIME_CORE_STRING_SPLIT_H
#define MS_RUNTIME_CORE_STRING_SPLIT_H

#include "base/list.h"
#include "base/string.h"

/* The state of a split loop. */
typedef struct MsSplitIter MsSplitIter;

/* ms-sig: msrt_string_split(s: *const StrVal, sep: *const StrVal, out: *mut VecVal) @domain=string @end */
void msrt_string_split(const MsString *s, const MsString *sep, MsList *out);
/* ms-sig: msrt_string_split_view(s: *const StrVal, sep: *const StrVal, out: *mut VecVal) @borrows @domain=string @end */
void msrt_string_split_view(const MsString *s, const MsString *sep, MsList *out);
/* ms-sig: msrt_string_split_view_into(s: *const StrVal, sep: *const StrVal, buf: *mut FrameBuf<StrVal, 8>,
 * out: *mut VecVal) @borrows @domain=string @end */
void msrt_string_split_view_into(const MsString *s, const MsString *sep, MsString *buffer, MsList *out);
/* ms-sig: msrt_string_split_first(s: *const StrVal, sep: *const StrVal, out: *mut StrVal) @borrows @domain=string
 * */
void msrt_string_split_first(const MsString *s, const MsString *sep, MsString *out);
/* ms-sig: msrt_string_split_iter(s: *const StrVal, sep: *const StrVal) -> *mut SplitIter @domain=string
 * */
MsSplitIter *msrt_string_split_iter(const MsString *s, const MsString *sep);
/* ms-sig: msrt_split_next(it: *mut SplitIter, out: *mut StrVal) -> u8 @domain=split @end */
uint8_t msrt_split_next(MsSplitIter *iter, MsString *out);
/* ms-sig: msrt_string_replace(s: *const StrVal, old: *const StrVal, new: *const StrVal, out: *mut StrVal)
 * @domain=string @end */
void msrt_string_replace(const MsString *s, const MsString *old, const MsString *replacement, MsString *out);
/* ms-sig: msrt_string_replace_first(s: *const StrVal, old: *const StrVal, new: *const StrVal, out: *mut
 * StrVal) @domain=string @end */
void msrt_string_replace_first(const MsString *s, const MsString *old, const MsString *replacement,
                               MsString *out);
/* ms-sig: msrt_string_replace_take(s: *mut StrVal, old: *const StrVal, new: *const StrVal, out: *mut StrVal)
 * @domain=string @end */
void msrt_string_replace_take(MsString *s, const MsString *old, const MsString *replacement, MsString *out);

#endif
