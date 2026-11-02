/* Generated from crates/ms-rt-abi/src/lib.rs by the `header_is_current` test; do not edit.
 * Regenerate with: MS_UPDATE_HEADER=1 cargo test -p ms-rt-abi header_is_current
 *
 * The Manuscript ABI for `extern fn` natives (ms-rt/ABI.md, section 1).
 * Int is int64_t, Float is double, Bool is uint8_t (0 or 1). A String argument arrives as a
 * borrowed `const ms_str *`: read it with ms_str_data/ms_str_len and do not keep the pointer
 * after returning. A String result is written through a trailing `ms_str *out` that the native
 * fills with msrt_string_from_bytes; never allocate or free string memory yourself. */
#ifndef MS_ABI_H
#define MS_ABI_H

#include <stddef.h>
#include <stdint.h>

#define MS_ABI_VERSION 3

/* Status byte returned by a fallible native; the ok value goes through the trailing out pointer. */
#define MS_STATUS_OK 0
#define MS_STATUS_INVALID_INPUT 1
#define MS_STATUS_OUT_OF_RANGE 2
#define MS_STATUS_LIMIT_EXCEEDED 3
#define MS_STATUS_INVALID_DATA 4
#define MS_STATUS_NOT_FOUND 5
#define MS_STATUS_ALREADY_EXISTS 6
#define MS_STATUS_NOT_EMPTY 7
#define MS_STATUS_PERMISSION_DENIED 8
#define MS_STATUS_UNSUPPORTED 9
#define MS_STATUS_CLOSED 10
#define MS_STATUS_FAILED 11
#define MS_STATUS_UNAVAILABLE 12
#define MS_STATUS_TIMEOUT 13
#define MS_STATUS_OUTPUT_LIMIT 14
#define MS_STATUS_NOT_TERMINAL 15
#define MS_STATUS_NONE 16
#define MS_STATUS_BUSY 17

#define MS_STR_INLINE_MAX 15

typedef struct ms_str {
    void *ptr_word;
    size_t tagged;
} ms_str;

_Static_assert(sizeof(ms_str) == 16, "ms_str is two words");
_Static_assert(offsetof(ms_str, tagged) == 8, "ms_str layout");

/* Tag in the top two bits of `tagged`: 1 is an inline string whose bytes live in the value. */
static inline int ms_str_is_inline(const ms_str *s) { return (s->tagged >> 62) == 1; }

static inline size_t ms_str_len(const ms_str *s) {
    return ms_str_is_inline(s) ? (s->tagged >> 56) & 15 : s->tagged & (((size_t)1 << 62) - 1);
}

static inline const uint8_t *ms_str_data(const ms_str *s) {
    return ms_str_is_inline(s) ? (const uint8_t *)s : (const uint8_t *)s->ptr_word;
}

/* Builds an owned string from `len` bytes at `ptr` into uninitialised `out`. */
void msrt_string_from_bytes(const uint8_t *ptr, size_t len, ms_str *out);

#endif
