/* ms_rt/string.h: the string value and the string primitives that allocate nothing (runtime/core/string.c). */
#ifndef MS_RT_STRING_H
#define MS_RT_STRING_H

#include "ms_rt/base.h"

/* A string value: two words (crates/ms-rt-abi StrVal). The top bits of `tagged` say what the bytes are:
 * 00 owned allocation at `ptr_word`, 01 inline (bytes start at the value's own address, length in
 * bits 56..59), 10 static, 11 view. Inline strings keep the bytes past their length zero. */
typedef struct MsStr {
    uint8_t *ptr_word;
    uint64_t tagged;
} MsStr;

#define MS_STR_INLINE_SHIFT 56
#define MS_STR_INLINE_MAX 15
#define MS_STR_LEN_MASK ((UINT64_C(1) << 31) - 1)
/* Flag in the second word of an owned, static or view string: every byte is ASCII (clear means unknown). */
#define MS_STR_ASCII (UINT64_C(1) << 61)

static inline bool ms_str_is_inline(const MsStr *s) { return (s->tagged >> 62) == 1; }

static inline size_t ms_str_len(const MsStr *s) {
    return ms_str_is_inline(s) ? (size_t)((s->tagged >> MS_STR_INLINE_SHIFT) & 15) : (size_t)(s->tagged & MS_STR_LEN_MASK);
}

static inline const uint8_t *ms_str_data(const MsStr *s) {
    return ms_str_is_inline(s) ? (const uint8_t *)s : s->ptr_word;
}

int64_t msrt_string_compare(const MsStr *a, const MsStr *b);
int64_t msrt_string_hash(const MsStr *s);
uint8_t msrt_string_eq(const MsStr *a, const MsStr *b);
uint8_t msrt_string_is_empty(const MsStr *s);
int64_t msrt_string_length(const MsStr *s);
uint8_t msrt_string_contains(const MsStr *a, const MsStr *v);
uint8_t msrt_string_contains_multi(const MsStr *a, const MsStr *v);
int64_t msrt_string_count(const MsStr *a, const MsStr *v);
int64_t msrt_string_scalar_length(const MsStr *s);
int64_t msrt_string_char_width(const MsStr *s, int64_t at);
int64_t msrt_string_scalar_step(const MsStr *s, int64_t at);
int64_t msrt_string_scalar_at_byte(const MsStr *s, int64_t at);
uint8_t msrt_string_starts_with(const MsStr *a, const MsStr *v);
uint8_t msrt_string_ends_with(const MsStr *a, const MsStr *v);

void msrt_string_split(const MsStr *s, const MsStr *sep, MsVec *out);
void msrt_string_split_view(const MsStr *s, const MsStr *sep, MsVec *out);
void msrt_string_split_view_into(const MsStr *s, const MsStr *sep, MsStr *buf, MsVec *out);
void msrt_string_split_first(const MsStr *s, const MsStr *sep, MsStr *out);
void msrt_string_replace(const MsStr *s, const MsStr *old, const MsStr *replacement, MsStr *out);
void msrt_string_replace_first(const MsStr *s, const MsStr *old, const MsStr *replacement, MsStr *out);
void msrt_string_replace_take(MsStr *s, const MsStr *old, const MsStr *replacement, MsStr *out);

#endif
