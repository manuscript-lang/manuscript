/* runtime/std/regex.h: the @std/regex natives (regex_abi.c, regex_text.c and regex_replace.c, over the engine
 * in regex_engine.c). Fallible functions return a status (0 ok, 1 InvalidInput, 3 LimitExceeded, 4
 * InvalidData, 11 Failed) and write their result through `out` only on success. A `has_*`/`max` pair is an
 * optional budget: a negative one is InvalidInput and one that more output would pass is LimitExceeded.
 * Offsets are UTF-8 byte offsets. */
#ifndef MS_RUNTIME_STD_REGEX_H
#define MS_RUNTIME_STD_REGEX_H

#include "abi/status.h"
#include "base/list.h"
#include "base/string.h"

/* On success *out is a new handle object the caller owns; on failure *err, when not null, is an owned
 * message. */
/* ms-sig: msstd_regex_compile(pattern: *const StrVal, out: *mut *mut ObjCell<Regex>, err: ErrSlot) -> u8 */
uint8_t msstd_regex_compile(const MsString *pattern, void **out, MsString *err);
/* A match that reaches an engine limit reads as no match: the result is a plain Bool. */
/* ms-sig: msstd_regex_matches(handle re: *const ObjCell<Regex>, text: *const StrVal) -> u8 @leaf */
uint8_t msstd_regex_matches(const void *re, const MsString *text);

/* Offsets: [start, end] of the first match (0 when there is none), then every match as flat pairs, then the
 * first match's slots (the slot count, then a pair per group, -1 and -1 for a group that did not take part)
 * and the slots of every match (the slot count once, then each match's pairs). */
/* ms-sig: msstd_regex_find_span(handle re: *const ObjCell<Regex>, text: *const StrVal, out: *mut VecVal) ->
 * u8 @leaf */
uint8_t msstd_regex_find_span(const void *re, const MsString *text, MsList *out);
/* ms-sig: msstd_regex_find_all_spans(handle re: *const ObjCell<Regex>, text: *const StrVal, has_max: HasRaw,
 * max: i64, out: *mut VecVal) -> u8 @leaf */
uint8_t msstd_regex_find_all_spans(const void *re, const MsString *text, uint8_t has_max, int64_t max,
                                   MsList *out);
/* ms-sig: msstd_regex_capture_spans(handle re: *const ObjCell<Regex>, text: *const StrVal, has_max: HasRaw,
 * max: i64, out: *mut VecVal) -> u8 @leaf */
uint8_t msstd_regex_capture_spans(const void *re, const MsString *text, uint8_t has_max, int64_t max,
                                  MsList *out);
/* ms-sig: msstd_regex_capture_all_spans(handle re: *const ObjCell<Regex>, text: *const StrVal, has_matches:
 * HasRaw, max_matches: i64, has_captures: HasRaw, max_captures: i64, out: *mut VecVal) -> u8 @leaf */
uint8_t msstd_regex_capture_all_spans(const void *re, const MsString *text, uint8_t has_matches,
                                      int64_t max_matches, uint8_t has_captures, int64_t max_captures,
                                      MsList *out);

/* Texts: the matched texts, a group's texts ("" for a group that did not take part), and the pieces between
 * matches. The budget of `find_all`, `captures_all` and `split` is the match or piece count. */
/* ms-sig: msstd_regex_find_all(handle re: *const ObjCell<Regex>, text: *const StrVal, has_max: HasRaw, max:
 * i64, out: *mut VecVal) -> u8 @leaf */
uint8_t msstd_regex_find_all(const void *re, const MsString *text, uint8_t has_max, int64_t max, MsList *out);
/* ms-sig: msstd_regex_captures(handle re: *const ObjCell<Regex>, text: *const StrVal, out: *mut VecVal) @leaf
 */
void msstd_regex_captures(const void *re, const MsString *text, MsList *out);
/* ms-sig: msstd_regex_captures_all(handle re: *const ObjCell<Regex>, text: *const StrVal, has_max: HasRaw,
 * max: i64, out: *mut VecVal) -> u8 @leaf */
uint8_t msstd_regex_captures_all(const void *re, const MsString *text, uint8_t has_max, int64_t max,
                                 MsList *out);
/* The first match's named groups that took part, as name, text, name, text, ... in group order. */
/* ms-sig: msstd_regex_named_capture_pairs(handle re: *const ObjCell<Regex>, text: *const StrVal, out: *mut
 * VecVal) @leaf */
void msstd_regex_named_capture_pairs(const void *re, const MsString *text, MsList *out);
/* ms-sig: msstd_regex_split(handle re: *const ObjCell<Regex>, text: *const StrVal, has_max: HasRaw, max: i64,
 * out: *mut VecVal) -> u8 @leaf */
uint8_t msstd_regex_split(const void *re, const MsString *text, uint8_t has_max, int64_t max, MsList *out);

/* Replacements; `max` bounds the UTF-8 bytes of the result. The template expands `$1`, `${name}` and `$$`. */
/* ms-sig: msstd_regex_replace_all(handle re: *const ObjCell<Regex>, text: *const StrVal, replacement: *const
 * StrVal, has_max: HasRaw, max: i64, out: *mut StrVal) -> u8 @leaf */
uint8_t msstd_regex_replace_all(const void *re, const MsString *text, const MsString *replacement,
                                uint8_t has_max, int64_t max, MsString *out);
/* ms-sig: msstd_regex_replace_template(handle re: *const ObjCell<Regex>, text: *const StrVal, template:
 * *const StrVal, has_max: HasRaw, max: i64, out: *mut StrVal) -> u8 @leaf */
uint8_t msstd_regex_replace_template(const void *re, const MsString *text, const MsString *template_text,
                                     uint8_t has_max, int64_t max, MsString *out);

#endif
