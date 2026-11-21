/* ms_rt/string.h: the string value and the string primitives that allocate nothing (runtime/core/string.c). */
#ifndef MS_RT_STRING_H
#define MS_RT_STRING_H

/* ms: domain string */

#include "ms_rt/alloc.h"
#include "ms_rt/base.h"

/* ms: domain string */

/* A string value: two words (crates/ms-rt-abi StrVal). The top bits of `tagged` say what the bytes are:
 * 00 owned allocation at `ptr_word`, 01 inline (the bytes are the value itself, `inline_bytes`, length in bits
 * 56..59 of `tagged`), 10 static and 11 view (`bytes`). Inline strings keep the bytes past their length zero.
 * `low_bits` is the first word as an integer, for comparing, hashing and building inline values. */
typedef struct MsStr MsStr;
struct MsStr {
    union {
        struct {
            union {
                uint8_t *ptr_word;    /* owned: the allocation, freed with msrt_free */
                const uint8_t *bytes; /* static or view: borrowed bytes */
                uint64_t low_bits;
            };
            uint64_t tagged;
        };
        uint8_t inline_bytes[16];
    };
};

_Static_assert(sizeof(MsStr) == 16, "a string value is two words");

#define MS_STR_TAG_SHIFT 62
#define MS_STR_INLINE_SHIFT 56
#define MS_STR_INLINE_MAX 15
#define MS_STR_LEN_MASK ((UINT64_C(1) << 31) - 1)
/* Flag in the second word of an owned, static or view string: every byte is ASCII (clear means unknown). */
#define MS_STR_ASCII (UINT64_C(1) << 61)

static inline bool ms_str_is_inline(const MsStr *s) { return (s->tagged >> MS_STR_TAG_SHIFT) == 1; }

static inline size_t ms_str_len(const MsStr *s) {
    return ms_str_is_inline(s) ? (size_t)((s->tagged >> MS_STR_INLINE_SHIFT) & 15) : (size_t)(s->tagged & MS_STR_LEN_MASK);
}

static inline const uint8_t *ms_str_data(const MsStr *s) {
    return ms_str_is_inline(s) ? s->inline_bytes : s->bytes;
}

/* ms-sig: msrt_string_compare(a: *const StrVal, b: *const StrVal) -> i64 @domain=map @leaf @pure */
int64_t msrt_string_compare(const MsStr *a, const MsStr *b);
/* ms-sig: msrt_string_hash(s: *const StrVal) -> i64 @domain=map @leaf @pure */
int64_t msrt_string_hash(const MsStr *s);
/* ms-sig: msrt_string_eq(a: *const StrVal, b: *const StrVal) -> u8 @domain=string @leaf @pure */
uint8_t msrt_string_eq(const MsStr *a, const MsStr *b);
/* ms-sig: msrt_string_is_empty(s: *const StrVal) -> u8 @domain=string @leaf @pure */
uint8_t msrt_string_is_empty(const MsStr *s);
/* ms-sig: msrt_string_length(s: *const StrVal) -> i64 @domain=string @leaf @pure @op=str.bytes */
int64_t msrt_string_length(const MsStr *s);
/* ms-sig: msrt_string_contains(a: *const StrVal, v: *const StrVal) -> u8 @domain=string @leaf @pure */
uint8_t msrt_string_contains(const MsStr *a, const MsStr *v);
/* ms-sig: msrt_string_contains_multi(a: *const StrVal, v: *const StrVal) -> u8 @domain=string @leaf @pure */
uint8_t msrt_string_contains_multi(const MsStr *a, const MsStr *v);
/* ms-sig: msrt_string_count(a: *const StrVal, v: *const StrVal) -> i64 @domain=string @leaf */
int64_t msrt_string_count(const MsStr *a, const MsStr *v);
/* ms-sig: msrt_string_scalar_length(s: *const StrVal) -> i64 @domain=string @leaf @pure */
int64_t msrt_string_scalar_length(const MsStr *s);
/* ms-sig: msrt_string_char_width(s: *const StrVal, at: i64) -> i64 @domain=string @leaf */
int64_t msrt_string_char_width(const MsStr *s, int64_t at);
/* ms-sig: msrt_string_scalar_step(s: *const StrVal, at: i64) -> i64 @domain=string @leaf */
int64_t msrt_string_scalar_step(const MsStr *s, int64_t at);
/* ms-sig: msrt_string_scalar_at_byte(s: *const StrVal, at: i64) -> i64 @domain=string @leaf */
int64_t msrt_string_scalar_at_byte(const MsStr *s, int64_t at);
/* ms-sig: msrt_string_starts_with(a: *const StrVal, v: *const StrVal) -> u8 @domain=string @leaf @pure */
uint8_t msrt_string_starts_with(const MsStr *a, const MsStr *v);
/* ms-sig: msrt_string_ends_with(a: *const StrVal, v: *const StrVal) -> u8 @domain=string @leaf @pure */
uint8_t msrt_string_ends_with(const MsStr *a, const MsStr *v);

/* Frees the allocation of an owned string; other strings own nothing. */
static inline void ms_str_release(const MsStr *s) {
    if ((s->tagged >> MS_STR_TAG_SHIFT) == 0) {
        msrt_free(s->ptr_word);
    }
}


/* `to_string` of one value, and `to_string_radix` (a radix outside 2..=36 faults); runtime/core/string_fmt.c. */
/* ms-sig: msrt_int_to_string(v: i64, out: *mut StrVal) @leaf */
void msrt_int_to_string(int64_t v, MsStr *out);
/* ms-sig: msrt_uint_to_string(v: i64, out: *mut StrVal) */
void msrt_uint_to_string(int64_t v, MsStr *out);
/* ms-sig: msrt_int_to_string_radix(v: i64, radix: i64, out: *mut StrVal) @leaf */
void msrt_int_to_string_radix(int64_t v, int64_t radix, MsStr *out);
/* ms-sig: msrt_uint_to_string_radix(v: i64, radix: i64, out: *mut StrVal) */
void msrt_uint_to_string_radix(int64_t v, int64_t radix, MsStr *out);
/* ms-sig: msrt_float_to_string(v: f64, out: *mut StrVal) @leaf */
void msrt_float_to_string(double v, MsStr *out);
/* ms-sig: msrt_float32_to_string(v: f64, out: *mut StrVal) @leaf */
void msrt_float32_to_string(double v, MsStr *out);
/* ms-sig: msrt_bool_to_string(v: u8, out: *mut StrVal) @leaf */
void msrt_bool_to_string(uint8_t v, MsStr *out);

/* f-strings (runtime/core/string_join.c): `msrt_string_fmtN` joins N parts, `msrt_string_append_fmtN` joins them onto
 * an owned `s`. Bit k of `mask` makes part k an Int, otherwise it is the address of a string (for append, `s` is
 * part 0 of the mask). */
/* ms-sig: msrt_string_fmt2(mask: i64, a: usize, b: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_fmt2(int64_t mask, size_t a, size_t b, MsStr *out);
/* ms-sig: msrt_string_fmt3(mask: i64, a: usize, b: usize, c: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_fmt3(int64_t mask, size_t a, size_t b, size_t c, MsStr *out);
/* ms-sig: msrt_string_fmt4(mask: i64, a: usize, b: usize, c: usize, d: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_fmt4(int64_t mask, size_t a, size_t b, size_t c, size_t d, MsStr *out);
/* ms-sig: msrt_string_fmt5(mask: i64, a: usize, b: usize, c: usize, d: usize, e: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_fmt5(int64_t mask, size_t a, size_t b, size_t c, size_t d, size_t e, MsStr *out);
/* ms-sig: msrt_string_fmt6(mask: i64, a: usize, b: usize, c: usize, d: usize, e: usize, f: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_fmt6(int64_t mask, size_t a, size_t b, size_t c, size_t d, size_t e, size_t f, MsStr *out);
/* ms-sig: msrt_string_append_fmt1(s: *const StrVal, mask: i64, a: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_append_fmt1(const MsStr *s, int64_t mask, size_t a, MsStr *out);
/* ms-sig: msrt_string_append_fmt2(s: *const StrVal, mask: i64, a: usize, b: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_append_fmt2(const MsStr *s, int64_t mask, size_t a, size_t b, MsStr *out);
/* ms-sig: msrt_string_append_fmt3(s: *const StrVal, mask: i64, a: usize, b: usize, c: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_append_fmt3(const MsStr *s, int64_t mask, size_t a, size_t b, size_t c, MsStr *out);
/* ms-sig: msrt_string_append_fmt4(s: *const StrVal, mask: i64, a: usize, b: usize, c: usize, d: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_append_fmt4(const MsStr *s, int64_t mask, size_t a, size_t b, size_t c, size_t d, MsStr *out);
/* ms-sig: msrt_string_append_fmt5(s: *const StrVal, mask: i64, a: usize, b: usize, c: usize, d: usize, e: usize, out: *mut StrVal) @fresh @leaf */
void msrt_string_append_fmt5(const MsStr *s, int64_t mask, size_t a, size_t b, size_t c, size_t d, size_t e, MsStr *out);
/* Builders (runtime/core/strbuild.c). */
/* ms-sig: msrt_string_from_bytes(ptr: *const u8, len: usize, out: *mut StrVal) @domain=string @leaf */
void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out);
/* ms-sig: msrt_string_empty(out: *mut StrVal) @domain=string @leaf */
void msrt_string_empty(MsStr *out);
/* ms-sig: msrt_string_clone(s: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf @op=clone @imm=1 */
void msrt_string_clone(const MsStr *s, MsStr *out);
/* ms-sig: msrt_str_copy(ptr: *const u8, tagged: usize, out: *mut StrVal) @domain=string @leaf */
void msrt_str_copy(const uint8_t *ptr, size_t tagged, MsStr *out);
/* ms-sig: msrt_str_free(ptr: *mut u8) @domain=string @leaf */
void msrt_str_free(uint8_t *ptr);
/* ms-sig: msrt_string_free(s: *const StrVal) @domain=string @leaf */
void msrt_string_free(const MsStr *s);
/* ms-sig: msrt_string_concat(a: *const StrVal, b: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf */
void msrt_string_concat(const MsStr *a, const MsStr *b, MsStr *out);
/* ms-sig: msrt_string_append(a: *const StrVal, b: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf */
void msrt_string_append(const MsStr *a, const MsStr *b, MsStr *out);
/* ms-sig: msrt_string_repeat(s: *const StrVal, count: i64, out: *mut StrVal) @domain=string @leaf */
void msrt_string_repeat(const MsStr *s, int64_t count, MsStr *out);
/* ms-sig: msrt_string_reverse(a: *const StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_reverse(const MsStr *s, MsStr *out);
/* ms-sig: msrt_string_concat3(a: *const StrVal, b: *const StrVal, c: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf */
void msrt_string_concat3(const MsStr *a, const MsStr *b, const MsStr *c, MsStr *out);
/* ms-sig: msrt_string_concat4(a: *const StrVal, b: *const StrVal, c: *const StrVal, d: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf */
void msrt_string_concat4(const MsStr *a, const MsStr *b, const MsStr *c, const MsStr *d, MsStr *out);
/* ms-sig: msrt_string_concat5(a: *const StrVal, b: *const StrVal, c: *const StrVal, d: *const StrVal, e: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf */
void msrt_string_concat5(const MsStr *a, const MsStr *b, const MsStr *c, const MsStr *d, const MsStr *e, MsStr *out);
/* ms-sig: msrt_string_concat6(a: *const StrVal, b: *const StrVal, c: *const StrVal, d: *const StrVal, e: *const StrVal, f: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf */
void msrt_string_concat6(const MsStr *a, const MsStr *b, const MsStr *c, const MsStr *d, const MsStr *e, const MsStr *f, MsStr *out);
/* ms-sig: msrt_string_trim_view(s: *const StrVal, out: *mut StrVal) @borrows @domain=string @leaf @view_of=msrt_string_trim */
void msrt_string_trim_view(const MsStr *s, MsStr *out);
/* ms-sig: msrt_string_trim_start_view(s: *const StrVal, out: *mut StrVal) @borrows @domain=string @leaf @view_of=msrt_string_trim_start */
void msrt_string_trim_start_view(const MsStr *s, MsStr *out);
/* ms-sig: msrt_string_trim_end_view(s: *const StrVal, out: *mut StrVal) @borrows @domain=string @leaf @view_of=msrt_string_trim_end */
void msrt_string_trim_end_view(const MsStr *s, MsStr *out);
/* ms-sig: msrt_string_trim(s: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf @takes_self */
void msrt_string_trim(const MsStr *s, MsStr *out);
/* ms-sig: msrt_string_trim_start(s: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf @takes_self */
void msrt_string_trim_start(const MsStr *s, MsStr *out);
/* ms-sig: msrt_string_trim_end(s: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf @takes_self */
void msrt_string_trim_end(const MsStr *s, MsStr *out);
/* ms-sig: msrt_string_trim_take(s: *mut StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_trim_take(MsStr *s, MsStr *out);
/* ms-sig: msrt_string_trim_start_take(s: *mut StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_trim_start_take(MsStr *s, MsStr *out);
/* ms-sig: msrt_string_trim_end_take(s: *mut StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_trim_end_take(MsStr *s, MsStr *out);
/* ms-sig: msrt_string_index_of(a: *const StrVal, v: *const StrVal, out: *mut i64) -> u8 @domain=string @leaf @pure */
uint8_t msrt_string_index_of(const MsStr *a, const MsStr *v, int64_t *out);
/* ms-sig: msrt_string_char_at(s: *const StrVal, at: i64, out: *mut StrVal) @domain=string @leaf */
void msrt_string_char_at(const MsStr *s, int64_t at, MsStr *out);
/* ms-sig: msrt_string_pad_start(s: *const StrVal, target: i64, padding: *const StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_pad_start(const MsStr *s, int64_t target, const MsStr *padding, MsStr *out);
/* ms-sig: msrt_string_pad_end(s: *const StrVal, target: i64, padding: *const StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_pad_end(const MsStr *s, int64_t target, const MsStr *padding, MsStr *out);
/* ms-sig: msrt_string_chars(s: *const StrVal, out: *mut VecVal) @domain=string @leaf */
void msrt_string_chars(const MsStr *s, MsVec *out);
/* ms-sig: msrt_string_lines(s: *const StrVal, out: *mut VecVal) @domain=string @leaf */
void msrt_string_lines(const MsStr *s, MsVec *out);
/* ms-sig: msrt_string_fields(s: *const StrVal, out: *mut VecVal) @domain=string @leaf */
void msrt_string_fields(const MsStr *s, MsVec *out);
/* The state of a split loop (runtime/core/string_split_iter.c). */
typedef struct MsSplitIter MsSplitIter;
/* ms-sig: msrt_string_split_iter(s: *const StrVal, sep: *const StrVal) -> *mut SplitIter @domain=string @iter_of=msrt_string_split @leaf */
MsSplitIter *msrt_string_split_iter(const MsStr *s, const MsStr *sep);
/* ms-sig: msrt_split_next(it: *mut SplitIter, out: *mut StrVal) -> u8 @domain=split @leaf */
uint8_t msrt_split_next(MsSplitIter *iter, MsStr *out);
/* ms-sig: msrt_string_quote(s: *const StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_quote(const MsStr *s, MsStr *out);
/* ms-sig: msrt_string_parse_float(s: *const StrVal, out: *mut f64) -> u8 @domain=string @leaf */
uint8_t msrt_string_parse_float(const MsStr *s, double *out);
/* ms-sig: msrt_string_scalar_at(s: *const StrVal, offset: i64, has_default: HasRaw, default: i64) -> i64 @domain=string @leaf @pure */
int64_t msrt_string_scalar_at(const MsStr *s, int64_t offset, uint8_t has_default, int64_t fallback);
/* ms-sig: msrt_string_index_any(s: *const StrVal, set: *const StrVal, out: *mut i64) -> u8 @domain=string @leaf @pure */
uint8_t msrt_string_index_any(const MsStr *s, const MsStr *set, int64_t *out);
/* ms-sig: msrt_string_trim_chars(s: *const StrVal, set: *const StrVal, from_start: u8, from_end: u8, out: *mut StrVal) @domain=string @leaf */
void msrt_string_trim_chars(const MsStr *s, const MsStr *set, uint8_t from_start, uint8_t from_end, MsStr *out);
/* ms-sig: msrt_string_last_index_of(a: *const StrVal, v: *const StrVal, out: *mut i64) -> u8 @domain=string @leaf */
uint8_t msrt_string_last_index_of(const MsStr *a, const MsStr *v, int64_t *out);
/* ms-sig: msrt_string_scalar_values(s: *const StrVal, out: *mut VecVal) @domain=string @leaf */
void msrt_string_scalar_values(const MsStr *s, MsVec *out);
/* ms-sig: msrt_string_from_scalars(values: *const VecVal, out: *mut StrVal) -> u8 @domain=string @leaf */
uint8_t msrt_string_from_scalars(const MsVec *values, MsStr *out);
/* ms-sig: msrt_string_to_bytes(s: *const StrVal, out: *mut VecVal) @domain=string @leaf */
void msrt_string_to_bytes(const MsStr *s, MsVec *out);
/* ms-sig: msrt_string_view_bytes(s: *const StrVal, out: *mut VecVal) @borrows @domain=string @leaf @pure */
void msrt_string_view_bytes(const MsStr *s, MsVec *out);
/* ms-sig: msrt_string_slice(s: *const StrVal, start: i64, end: i64, out: *mut StrVal) @domain=string @leaf */
void msrt_string_slice(const MsStr *s, int64_t start, int64_t end, MsStr *out);
/* ms-sig: msrt_string_view(s: *const StrVal, start: i64, end: i64, out: *mut StrVal) @borrows @domain=string @leaf @pure */
void msrt_string_view(const MsStr *s, int64_t start, int64_t end, MsStr *out);
/* ms-sig: msrt_string_split(s: *const StrVal, sep: *const StrVal, out: *mut VecVal) @domain=string @leaf */
void msrt_string_split(const MsStr *s, const MsStr *sep, MsVec *out);
/* ms-sig: msrt_string_split_view(s: *const StrVal, sep: *const StrVal, out: *mut VecVal) @domain=string @leaf */
void msrt_string_split_view(const MsStr *s, const MsStr *sep, MsVec *out);
/* ms-sig: msrt_string_split_view_into(s: *const StrVal, sep: *const StrVal, buf: *mut FrameBuf<StrVal, 8>, out: *mut VecVal) @domain=string @leaf @view_of=msrt_string_split */
void msrt_string_split_view_into(const MsStr *s, const MsStr *sep, MsStr *buf, MsVec *out);
/* ms-sig: msrt_string_split_first(s: *const StrVal, sep: *const StrVal, out: *mut StrVal) @domain=string @first_of=msrt_string_split @leaf */
void msrt_string_split_first(const MsStr *s, const MsStr *sep, MsStr *out);
/* ms-sig: msrt_string_replace(s: *const StrVal, old: *const StrVal, new: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf @takes_self */
void msrt_string_replace(const MsStr *s, const MsStr *old, const MsStr *replacement, MsStr *out);
/* ms-sig: msrt_string_replace_first(s: *const StrVal, old: *const StrVal, new: *const StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_replace_first(const MsStr *s, const MsStr *old, const MsStr *replacement, MsStr *out);
/* ms-sig: msrt_string_replace_take(s: *mut StrVal, old: *const StrVal, new: *const StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_replace_take(MsStr *s, const MsStr *old, const MsStr *replacement, MsStr *out);

/* The text builder of the formatters (runtime/core/string_buffer.c): push strings, then finish into the result. */
typedef struct MsStrBuf MsStrBuf;
/* ms-sig: msrt_strbuf_new() -> *mut StrBuf @domain=string @leaf */
MsStrBuf *msrt_strbuf_new(void);
/* ms-sig: msrt_strbuf_push(buf: *mut StrBuf, s: *const StrVal) @domain=string @leaf */
void msrt_strbuf_push(MsStrBuf *buffer, const MsStr *s);
/* ms-sig: msrt_strbuf_finish(buf: *mut StrBuf, out: *mut StrVal) @domain=string @leaf */
void msrt_strbuf_finish(MsStrBuf *buffer, MsStr *out);

/* ms-sig: msrt_string_parse_int(s: *const StrVal, out: *mut i64) -> u8 @domain=string @leaf @pure */
uint8_t msrt_string_parse_int(const MsStr *s, int64_t *out);

/* Case mapping and normalization (runtime/core/string_case.c, string_normalize.c, on the tables of ucd.h). `_take` maps
 * a string that dies at the call, ASCII text in place. `normalize` takes the form's spelling (NFC, NFD, NFKC, NFKD;
 * anything else is STATUS_INVALID_INPUT), `normalize_kind` its case index (0 to 3); a negative `max` is
 * STATUS_INVALID_INPUT and a result longer than `max` bytes STATUS_LIMIT_EXCEEDED. */
/* ms-sig: msrt_string_upper(s: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf @takes_self */
void msrt_string_upper(const MsStr *s, MsStr *out);
/* ms-sig: msrt_string_lower(s: *const StrVal, out: *mut StrVal) @domain=string @fresh @leaf @takes_self */
void msrt_string_lower(const MsStr *s, MsStr *out);
/* ms-sig: msrt_string_upper_take(s: *mut StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_upper_take(MsStr *s, MsStr *out);
/* ms-sig: msrt_string_lower_take(s: *mut StrVal, out: *mut StrVal) @domain=string @leaf */
void msrt_string_lower_take(MsStr *s, MsStr *out);
/* ms-sig: msrt_string_normalize(s: *const StrVal, form: *const StrVal, has_max: HasRaw, max: i64, out: *mut StrVal) -> u8 @domain=string @leaf */
uint8_t msrt_string_normalize(const MsStr *s, const MsStr *form, uint8_t has_max, int64_t max, MsStr *out);
/* ms-sig: msrt_string_normalize_kind(s: *const StrVal, kind: i64, has_max: HasRaw, max: i64, out: *mut StrVal) -> u8 @domain=string @leaf */
uint8_t msrt_string_normalize_kind(const MsStr *s, int64_t kind, uint8_t has_max, int64_t max, MsStr *out);

#endif
