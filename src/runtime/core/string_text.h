/* runtime/core/string_text.h: case mapping, normalization and quoting (string_case.c, string_normalize.c,
 * string_quote.c). `_take` maps a string that dies at the call, ASCII text in place. `normalize` takes the
 * form's spelling (NFC, NFD, NFKC, NFKD; anything else is STATUS_INVALID_INPUT), `normalize_kind` its case
 * index (0 to 3); a negative `max` is STATUS_INVALID_INPUT and a result longer than `max` bytes
 * STATUS_LIMIT_EXCEEDED. */
#ifndef MS_RUNTIME_CORE_STRING_TEXT_H
#define MS_RUNTIME_CORE_STRING_TEXT_H

#include "base/string.h"

/* ms-sig: msrt_string_upper(s: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf @takes_self */
void msrt_string_upper(const MsString *s, MsString *out);
/* ms-sig: msrt_string_lower(s: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf @takes_self */
void msrt_string_lower(const MsString *s, MsString *out);
/* ms-sig: msrt_string_upper_take(s: *mut StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_upper_take(MsString *s, MsString *out);
/* ms-sig: msrt_string_lower_take(s: *mut StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_lower_take(MsString *s, MsString *out);
/* ms-sig: msrt_string_normalize(s: *const StrVal, form: *const StrVal, has_max: HasRaw, max: i64, out: *mut
 * StrVal) -> u8 @domain=string @leaf */
uint8_t msrt_string_normalize(const MsString *s, const MsString *form, uint8_t has_max, int64_t max,
                              MsString *out);
/* ms-sig: msrt_string_normalize_kind(s: *const StrVal, kind: i64, has_max: HasRaw, max: i64, out: *mut
 * StrVal) -> u8 @domain=string @leaf */
uint8_t msrt_string_normalize_kind(const MsString *s, int64_t kind, uint8_t has_max, int64_t max,
                                   MsString *out);
/* ms-sig: msrt_string_quote(s: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf */
void msrt_string_quote(const MsString *s, MsString *out);

#endif
