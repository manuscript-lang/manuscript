/* base/safe.h: the checked building blocks every C source uses instead of raw pointer arithmetic and
 * unchecked size arithmetic (documentation/contributing/c-style.md in the archive; src/README.md here).
 *
 * Header-only and stateless; it needs only the compiler's memmove and memcmp.
 *
 *  - attributes: the compiler rejects an ignored result, a null argument or a mismatched format string;
 *  - sizes: add, subtract and multiply that report overflow instead of wrapping;
 *  - spans: a borrowed pointer always travels with its length, and every index or slice is checked.
 *
 * A function that can fail returns bool (true is success) and writes its result through an out pointer, so
 * MS_NODISCARD makes forgetting the check a compile error. On failure the out value is left as it was.
 * A span is borrowed: it never frees. The owned byte buffer of Manuscript programs is MsBytes (base/value).
 */
#ifndef MS_BASE_SAFE_H
#define MS_BASE_SAFE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* ---- attributes ---- */

#define MS_NODISCARD __attribute__((warn_unused_result))
#define MS_NONNULL __attribute__((nonnull))                        /* every pointer parameter */
#define MS_NONNULL_ARGS(...) __attribute__((nonnull(__VA_ARGS__))) /* the listed parameters, counted from 1  \
                                                                    */
#define MS_RETURNS_NONNULL __attribute__((returns_nonnull))
#define MS_PRINTF(format_index, first_arg) __attribute__((format(printf, format_index, first_arg)))
#define MS_NORETURN _Noreturn
#define MS_FALLTHROUGH __attribute__((fallthrough))
#define MS_UNUSED __attribute__((unused))
#define MS_ALWAYS_INLINE                                                                                     \
  __attribute__((always_inline)) /* a hot probe loop that must be specialised into its caller */

/* Compiles only when `array` is a real array: a pointer has the same type as the address of its first
 * element. */
#define MS_MUST_BE_ARRAY(array)                                                                              \
  (0 * sizeof(struct {                                                                                       \
     _Static_assert(!__builtin_types_compatible_p(__typeof__(array), __typeof__(&(array)[0])),               \
                    "an array is needed here, not a pointer");                                               \
     int unused;                                                                                             \
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
  uint64_t value = 0;
  __builtin_memcpy(&value, p, sizeof value);
  return value;
}

static inline uint32_t ms_load32(const uint8_t *p) {
  uint32_t value = 0;
  __builtin_memcpy(&value, p, sizeof value);
  return value;
}

static inline void ms_store64(uint8_t *p, uint64_t value) {
  __builtin_memcpy(p, &value, sizeof value);
}

/* Copies one slot (an element, a key, a value): `size` bytes that do not overlap. Slots are usually one to three whole words,
 * which copy as inline moves, not a call to memcpy per slot. The size is a runtime value, so without this each copy is a call. */
static inline void ms_copy_slot(void *to, const void *from, size_t size) {
  if (size == 8) {
    __builtin_memcpy(to, from, 8);
  } else if (size == 16) {
    __builtin_memcpy(to, from, 16);
  } else if (size == 24) {
    __builtin_memcpy(to, from, 24);
  } else {
    __builtin_memcpy(to, from, size);
  }
}

/* ---- spans ---- */

/* Read-only bytes, borrowed: never freed through the span. `ptr` may be null only when `len` is 0. */
typedef struct MsSpan {
  const uint8_t *ptr;
  size_t len;
} MsSpan;

/* Writable bytes, borrowed from the caller, who keeps ownership. */
typedef struct MsSpanMut {
  uint8_t *ptr;
  size_t len;
} MsSpanMut;

static inline MsSpan ms_span_of(const uint8_t *ptr, size_t len) {
  return (MsSpan){.ptr = ptr, .len = len};
}

static inline MsSpanMut ms_span_mut_of(uint8_t *ptr, size_t len) {
  return (MsSpanMut){.ptr = ptr, .len = len};
}

static inline MsSpan ms_span_view(MsSpanMut span) {
  return (MsSpan){.ptr = span.ptr, .len = span.len};
}

/* out = span[index]; false when index is past the end. */
MS_NODISCARD MS_NONNULL static inline bool ms_span_get(MsSpan span, size_t index, uint8_t *out) {
  if (index >= span.len) {
    return false;
  }
  *out = span.ptr[index];
  return true;
}

/* out = span[start..end]; false unless start <= end <= len. */
MS_NODISCARD MS_NONNULL static inline bool ms_span_slice(MsSpan span, size_t start, size_t end, MsSpan *out) {
  if (start > end || end > span.len) {
    return false;
  }
  *out = (MsSpan){.ptr = span.len == 0 ? span.ptr : span.ptr + start, .len = end - start};
  return true;
}

/* Writable form of ms_span_slice. */
MS_NODISCARD MS_NONNULL static inline bool ms_span_mut_slice(MsSpanMut span, size_t start, size_t end,
                                                             MsSpanMut *out) {
  if (start > end || end > span.len) {
    return false;
  }
  *out = (MsSpanMut){.ptr = span.len == 0 ? span.ptr : span.ptr + start, .len = end - start};
  return true;
}

/* Copies all of `source` to the start of `destination`; false, copying nothing, when it does not fit.
 * The two may overlap. */
MS_NODISCARD static inline bool ms_span_copy(MsSpanMut destination, MsSpan source) {
  if (source.len > destination.len) {
    return false;
  }
  if (source.len != 0) {
    __builtin_memmove(destination.ptr, source.ptr, source.len);
  }
  return true;
}

static inline bool ms_span_equal(MsSpan a, MsSpan b) {
  return a.len == b.len && (a.len == 0 || __builtin_memcmp(a.ptr, b.ptr, a.len) == 0);
}

/* Byte order of two texts: -1, 0 or 1. */
static inline int ms_span_compare(MsSpan a, MsSpan b) {
  const size_t common = a.len < b.len ? a.len : b.len;
  const int order = common == 0 ? 0 : __builtin_memcmp(a.ptr, b.ptr, common);
  if (order != 0) {
    return order < 0 ? -1 : 1;
  }
  return a.len == b.len ? 0 : (a.len < b.len ? -1 : 1);
}

/* Whether `span` is exactly the C string `text`. This and ms_span_of_text are the only places a C string
 * becomes a span: the entry point of an OS or libc string. */
static inline MsSpan ms_span_of_text(const char *text) {
  return ms_span_of((const uint8_t *)text, __builtin_strlen(text));
}

static inline bool ms_span_is_text(MsSpan span, const char *text) {
  return ms_span_equal(span, ms_span_of_text(text));
}

static inline bool ms_span_starts_with(MsSpan span, MsSpan prefix) {
  return span.len >= prefix.len && ms_span_equal(ms_span_of(span.ptr, prefix.len), prefix);
}

static inline bool ms_span_ends_with(MsSpan span, MsSpan suffix) {
  return span.len >= suffix.len &&
         ms_span_equal(ms_span_of(span.ptr + (span.len - suffix.len), suffix.len), suffix);
}

static inline bool ms_span_starts_with_text(MsSpan span, const char *prefix) {
  return ms_span_starts_with(span, ms_span_of_text(prefix));
}

static inline bool ms_span_ends_with_text(MsSpan span, const char *suffix) {
  return ms_span_ends_with(span, ms_span_of_text(suffix));
}

/* The offset of the first `byte` in `text`; false when absent, `at` untouched. */
MS_NODISCARD MS_NONNULL static inline bool ms_span_find_byte(MsSpan text, uint8_t byte, size_t *at) {
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == byte) {
      *at = i;
      return true;
    }
  }
  return false;
}

/* Whether `text` holds `byte`. */
static inline bool ms_span_has_byte(MsSpan text, uint8_t byte) {
  size_t at = 0;
  return ms_span_find_byte(text, byte, &at);
}

/* The offset of the first occurrence of `needle` in `hay` (an empty needle matches at 0). False when absent,
 * `at` untouched. */
MS_NODISCARD MS_NONNULL static inline bool ms_span_find(MsSpan hay, MsSpan needle, size_t *at) {
  for (size_t offset = 0; offset + needle.len <= hay.len; offset++) {
    if (ms_span_equal(ms_span_of(hay.ptr + offset, needle.len), needle)) {
      *at = offset;
      return true;
    }
  }
  return false;
}

#endif
