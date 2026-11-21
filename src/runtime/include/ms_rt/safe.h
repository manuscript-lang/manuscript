/* ms_rt/safe.h: the checked building blocks every C source in src/runtime/ and src/compiler/ uses instead of raw
 * pointer arithmetic and unchecked size arithmetic (documentation/contributing/c-style.md).
 *
 * Header-only and stateless. It needs only the compiler's memmove and memcmp (libc or the freestanding
 * runtime supplies them), so the compiler core includes it too, with -Iruntime/include.
 *
 *  - attributes: the compiler rejects an ignored result, a null argument or a mismatched format string;
 *  - sizes: add and multiply that report overflow instead of wrapping;
 *  - spans: a pointer always travels with its length, and every index or slice is checked.
 *
 * A function that can fail returns bool (true is success) and writes its result through an out pointer, so
 * MS_NODISCARD makes forgetting the check a compile error. On failure the out value is left as it was.
 * `ptr` and `len` are the field names of every span in this codebase.
 */
#ifndef MS_RT_SAFE_H
#define MS_RT_SAFE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* ---- attributes ---- */

#define MS_NODISCARD __attribute__((warn_unused_result))
#define MS_NONNULL __attribute__((nonnull))                  /* every pointer parameter */
#define MS_NONNULL_ARGS(...) __attribute__((nonnull(__VA_ARGS__))) /* the listed parameters, counted from 1 */
#define MS_RETURNS_NONNULL __attribute__((returns_nonnull))
#define MS_PRINTF(format_index, first_arg) __attribute__((format(printf, format_index, first_arg)))
#define MS_NORETURN _Noreturn
#define MS_FALLTHROUGH __attribute__((fallthrough))
#define MS_UNUSED __attribute__((unused))
#define MS_ALWAYS_INLINE __attribute__((always_inline)) /* a hot probe loop that must be specialised into its caller */

/* Compiles only when `array` is a real array: a pointer has the same type as the address of its first element. */
#define MS_MUST_BE_ARRAY(array) \
    (0 * sizeof(struct { \
        _Static_assert(!__builtin_types_compatible_p(__typeof__(array), __typeof__(&(array)[0])), \
                       "an array is needed here, not a pointer"); \
        int unused; \
    }))

/* Number of elements of a real array; a pointer does not compile. */
#define MS_COUNT_OF(array) (sizeof(array) / sizeof((array)[0]) + MS_MUST_BE_ARRAY(array))

/* ---- checked sizes ---- */

/* out = a + b; false when the sum does not fit. */
MS_NODISCARD MS_NONNULL static inline bool ms_size_add(size_t a, size_t b, size_t *out) {
    size_t result = 0;
    if (__builtin_add_overflow(a, b, &result)) {
        return false;
    }
    *out = result;
    return true;
}

/* out = a * b; false when the product does not fit. Use it for every `count * sizeof(T)`. */
MS_NODISCARD MS_NONNULL static inline bool ms_size_mul(size_t a, size_t b, size_t *out) {
    size_t result = 0;
    if (__builtin_mul_overflow(a, b, &result)) {
        return false;
    }
    *out = result;
    return true;
}

/* out = a - b; false when b is larger than a. */
MS_NODISCARD MS_NONNULL static inline bool ms_size_sub(size_t a, size_t b, size_t *out) {
    size_t result = 0;
    if (__builtin_sub_overflow(a, b, &result)) {
        return false;
    }
    *out = result;
    return true;
}

/* ---- word loads ---- */

/* The native-endian word at p, read with memcpy so alignment and aliasing never matter. The caller guarantees
 * that 8 (or 4) bytes are readable. */
static inline uint64_t ms_load64(const uint8_t *p) {
    uint64_t v;
    __builtin_memcpy(&v, p, sizeof v);
    return v;
}

static inline uint32_t ms_load32(const uint8_t *p) {
    uint32_t v;
    __builtin_memcpy(&v, p, sizeof v);
    return v;
}

/* ---- spans ---- */

/* Read-only bytes: borrowed, never freed through the span. `ptr` may be null only when `len` is 0. */
typedef struct MsBytes {
    const uint8_t *ptr;
    size_t len;
} MsBytes;

/* Writable bytes: borrowed from the caller, who keeps ownership. */
typedef struct MsBytesMut {
    uint8_t *ptr;
    size_t len;
} MsBytesMut;

static inline MsBytes ms_bytes_of(const uint8_t *ptr, size_t len) {
    return (MsBytes){.ptr = ptr, .len = len};
}

static inline MsBytesMut ms_bytes_mut(uint8_t *ptr, size_t len) {
    return (MsBytesMut){.ptr = ptr, .len = len};
}

static inline MsBytes ms_bytes_view(MsBytesMut bytes) {
    return (MsBytes){.ptr = bytes.ptr, .len = bytes.len};
}

/* out = bytes[index]; false when index is past the end. */
MS_NODISCARD MS_NONNULL static inline bool ms_bytes_get(MsBytes bytes, size_t index, uint8_t *out) {
    if (index >= bytes.len) {
        return false;
    }
    *out = bytes.ptr[index];
    return true;
}

/* out = bytes[start..end]; false unless start <= end <= len. */
MS_NODISCARD MS_NONNULL static inline bool ms_bytes_slice(MsBytes bytes, size_t start, size_t end, MsBytes *out) {
    if (start > end || end > bytes.len) {
        return false;
    }
    *out = (MsBytes){.ptr = bytes.len == 0 ? bytes.ptr : bytes.ptr + start, .len = end - start};
    return true;
}

/* Writable form of ms_bytes_slice. */
MS_NODISCARD MS_NONNULL static inline bool ms_bytes_mut_slice(MsBytesMut bytes, size_t start, size_t end, MsBytesMut *out) {
    if (start > end || end > bytes.len) {
        return false;
    }
    *out = (MsBytesMut){.ptr = bytes.len == 0 ? bytes.ptr : bytes.ptr + start, .len = end - start};
    return true;
}

/* Copies all of `source` to the start of `destination`; false, copying nothing, when it does not fit.
 * The two may overlap. */
MS_NODISCARD static inline bool ms_bytes_copy(MsBytesMut destination, MsBytes source) {
    if (source.len > destination.len) {
        return false;
    }
    if (source.len != 0) {
        __builtin_memmove(destination.ptr, source.ptr, source.len);
    }
    return true;
}

static inline bool ms_bytes_equal(MsBytes a, MsBytes b) {
    return a.len == b.len && (a.len == 0 || __builtin_memcmp(a.ptr, b.ptr, a.len) == 0);
}

/* Whether `bytes` is exactly the C string `text`. */
static inline bool ms_bytes_is_text(MsBytes bytes, const char *text) {
    return ms_bytes_equal(bytes, ms_bytes_of((const uint8_t *)text, __builtin_strlen(text)));
}

static inline bool ms_bytes_starts_with(MsBytes bytes, MsBytes prefix) {
    return bytes.len >= prefix.len && ms_bytes_equal(ms_bytes_of(bytes.ptr, prefix.len), prefix);
}

MS_NODISCARD static inline bool ms_bytes_ends_with(MsBytes bytes, MsBytes suffix) {
    return bytes.len >= suffix.len && ms_bytes_equal(ms_bytes_of(bytes.ptr + (bytes.len - suffix.len), suffix.len), suffix);
}

/* The offset of the first occurrence of `needle` in `hay` (an empty needle matches at 0). A plain scan for the
 * compiler and tools; the runtime's hot paths use ms_find in ms_rt/search.h. False when absent, `at` untouched. */
MS_NODISCARD MS_NONNULL static inline bool ms_bytes_find(MsBytes hay, MsBytes needle, size_t *at) {
    for (size_t i = 0; i + needle.len <= hay.len; i++) {
        if (ms_bytes_equal(ms_bytes_of(hay.ptr + i, needle.len), needle)) {
            *at = i;
            return true;
        }
    }
    return false;
}

#endif
