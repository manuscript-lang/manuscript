/* The Manuscript ABI for `extern fn` natives (ms-rt/ABI.md, section 1).
 *
 * Int is int64_t, Float is double, Bool is uint8_t (0 or 1). A String argument arrives as a
 * borrowed `const ms_str *`: read it with ms_str_data/ms_str_len and do not keep the pointer
 * after returning. A String result is written through a trailing `ms_str *out` that the native
 * fills with msrt_string_from_bytes; never allocate or free string memory yourself.
 * Layout mirrors `StrVal` in crates/ms-rt-abi/src/lib.rs. */
#ifndef MS_ABI_H
#define MS_ABI_H

#include <stddef.h>
#include <stdint.h>

typedef struct ms_str {
    void *ptr_word;
    size_t tagged;
} ms_str;

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
