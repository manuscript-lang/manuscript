/* ms_rt/string.h: the string value and the string primitives that allocate nothing (runtime/core/string.c). */
#ifndef MS_RT_STRING_H
#define MS_RT_STRING_H

#include "ms_rt/base.h"

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

/* Builders (runtime/core/strbuild.c). */
void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out);
void msrt_string_empty(MsStr *out);
void msrt_string_clone(const MsStr *s, MsStr *out);
void msrt_str_copy(const uint8_t *ptr, size_t tagged, MsStr *out);
void msrt_str_free(uint8_t *ptr);
void msrt_string_free(const MsStr *s);
void msrt_string_concat(const MsStr *a, const MsStr *b, MsStr *out);
void msrt_string_concat3(const MsStr *a, const MsStr *b, const MsStr *c, MsStr *out);
void msrt_string_concat4(const MsStr *a, const MsStr *b, const MsStr *c, const MsStr *d, MsStr *out);
void msrt_string_concat5(const MsStr *a, const MsStr *b, const MsStr *c, const MsStr *d, const MsStr *e, MsStr *out);
void msrt_string_concat6(const MsStr *a, const MsStr *b, const MsStr *c, const MsStr *d, const MsStr *e, const MsStr *f, MsStr *out);
void msrt_string_trim_view(const MsStr *s, MsStr *out);
void msrt_string_trim_start_view(const MsStr *s, MsStr *out);
void msrt_string_trim_end_view(const MsStr *s, MsStr *out);
void msrt_string_slice(const MsStr *s, int64_t start, int64_t end, MsStr *out);
void msrt_string_view(const MsStr *s, int64_t start, int64_t end, MsStr *out);

#endif
