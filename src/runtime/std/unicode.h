/* runtime/std/unicode.h: the @std/unicode natives, on PCRE2's Unicode tables. A property of a value that is
 * not a Unicode scalar is false. */
#ifndef MS_RUNTIME_STD_UNICODE_H
#define MS_RUNTIME_STD_UNICODE_H

#include "abi/status.h"
#include "base/list.h"
#include "base/string.h"

/* The columns the text takes in a terminal (ambiguous characters narrow); control characters and the line and
 * paragraph separators are STATUS_INVALID_DATA. */
/* ms-sig: msstd_unicode_display_width(text: *const StrVal, out: *mut i64) -> u8 @domain=unicode */
uint8_t msstd_unicode_display_width(const MsString *text, int64_t *out);
/* Whether the scalar has the Unicode general category "P", "S" or "M"; any other category is false. */
/* ms-sig: msstd_unicode_in_category(value: i64, category: *const StrVal) -> u8 @domain=regular expression
 * */
uint8_t msstd_unicode_in_category(int64_t value, const MsString *category);
/* ms-sig: msstd_unicode_is_alphabetic(value: i64) -> u8 @domain=unicode */
uint8_t msstd_unicode_is_alphabetic(int64_t value);
/* ms-sig: msstd_unicode_is_alphanumeric(value: i64) -> u8 @domain=unicode */
uint8_t msstd_unicode_is_alphanumeric(int64_t value);
/* ms-sig: msstd_unicode_is_ascii(value: i64) -> u8 @domain=unicode */
uint8_t msstd_unicode_is_ascii(int64_t value);
/* ms-sig: msstd_unicode_is_control(value: i64) -> u8 @domain=unicode */
uint8_t msstd_unicode_is_control(int64_t value);
/* ms-sig: msstd_unicode_is_lowercase(value: i64) -> u8 @domain=unicode */
uint8_t msstd_unicode_is_lowercase(int64_t value);
/* ms-sig: msstd_unicode_is_numeric(value: i64) -> u8 @domain=unicode */
uint8_t msstd_unicode_is_numeric(int64_t value);
/* ms-sig: msstd_unicode_is_uppercase(value: i64) -> u8 @domain=unicode */
uint8_t msstd_unicode_is_uppercase(int64_t value);
/* ms-sig: msstd_unicode_is_whitespace(value: i64) -> u8 @domain=unicode */
uint8_t msstd_unicode_is_whitespace(int64_t value);
/* ms-sig: msstd_utf8_is_valid(data: *const VecVal) -> u8 @domain=utf8 */
uint8_t msstd_utf8_is_valid(const MsList *data);

#endif
