/* libms base types: arena, positions, names, diagnostics.
 *
 * No global state: every function takes the arena or table it works in. An arena is freed in one
 * call, so a failed parse leaves nothing to clean up. Allocation failure aborts. */
#ifndef MS_BASE_H
#define MS_BASE_H

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "ms_rt/safe.h"

/* ---- arena ---- */

typedef struct MsChunk MsChunk;
typedef struct MsArena {
    MsChunk *head;
    char *cur, *end;
} MsArena;

void *ms_alloc(MsArena *a, size_t size, size_t align);
/* `count` zero-filled elements of `size` bytes, plus one spare element so a count of zero still has an address. */
void *ms_alloc_zeroed(MsArena *a, size_t count, size_t size);
void ms_arena_free(MsArena *a);
/* Forgets everything allocated, keeping the newest chunk for reuse: a scratch arena used once per
 * function costs no malloc and free each time. */
void ms_arena_reset(MsArena *a);
#define MS_NEW(a, T) ((T *)ms_alloc((a), sizeof(T), _Alignof(T)))
#define MS_NEW_N(a, T, n) ((T *)ms_alloc((a), sizeof(T) * (size_t)(n), _Alignof(T)))

/* qsort order for uint32_t elements. */
static inline int ms_cmp_u32(const void *x, const void *y) {
    const uint32_t a = *(const uint32_t *)x, b = *(const uint32_t *)y;
    return a < b ? -1 : a > b;
}

/* qsort order for `const char *` elements. */
static inline int ms_cmp_cstr(const void *x, const void *y) {
    return strcmp(*(const char *const *)x, *(const char *const *)y);
}

/* Whether `x` is among v[0..n]. */
static inline bool ms_u32_contains(const uint32_t *v, uint32_t n, uint32_t x) {
    for (uint32_t i = 0; i < n; i++) {
        if (v[i] == x) {
            return true;
        }
    }
    return false;
}

/* Arrays that grow by doubling. `ms_capacity_for` is the capacity (at least 64, doubling from
 * `current`) that holds `needed` elements; `ms_array_resize` returns `array` resized to that
 * many `element_size`-byte elements, and the caller stores the result. Allocation failure and a
 * size that overflows abort, as the arena does. */
/* Reports that memory ran out and aborts; the library's one policy for allocation failure. */
_Noreturn void ms_oom(void);
uint32_t ms_capacity_for(uint32_t current, uint32_t needed);
void *ms_array_resize(void *array, uint32_t capacity, size_t element_size);

/* A string that is not NUL-terminated. */
typedef struct MsStr {
    const char *ptr;
    uint32_t len;
} MsStr;

char *ms_arena_strndup(MsArena *a, const char *s, size_t n); /* NUL-terminated copy */
MsStr ms_arena_fmt(MsArena *a, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
MsStr ms_arena_vfmt(MsArena *a, const char *fmt, va_list ap) __attribute__((format(printf, 2, 0)));

/* ---- growable byte stack: the scratch space lists are built in before they are copied out ---- */

typedef struct MsBuf {
    char *data;
    size_t len, cap;
} MsBuf;

/* The stored bytes as an untyped pointer, for a vector of aligned elements: realloc storage is
 * aligned for any element, which a typed cast from char * could not state. */
static inline void *ms_buf_items(const MsBuf *b) {
    return b->data;
}

/* A MsBuf used as a stack of T. */
#define MS_VEC_LEN(b, T) ((b).len / sizeof(T))
#define MS_VEC_AT(b, T, i) (((T *)ms_buf_items(&(b)))[i])
#define MS_VEC_LAST(b, T) MS_VEC_AT(b, T, MS_VEC_LEN(b, T) - 1)
#define MS_VEC_PUSH(b, T, v)                                                                       \
    do {                                                                                           \
        T push_value_ = (v);                                                                       \
        ms_buf_put(&(b), &push_value_, sizeof(T));                                                 \
    } while (0)
#define MS_VEC_POP(b, T) ((b).len -= sizeof(T))

void ms_buf_free(MsBuf *b);
void *ms_buf_push(MsBuf *b, size_t n); /* appends n uninitialised bytes and returns them */
void ms_buf_put(MsBuf *b, const void *p, size_t n);
void ms_buf_putc(MsBuf *b, char c);
void ms_buf_puts(MsBuf *b, const char *s);
void ms_buf_printf(MsBuf *b, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

/* ---- positions ---- */

/* `line` and `column` are 1-based, `column` counts bytes, `offset` is a 0-based byte offset into
 * the original source (before CRLF normalisation). A `line` of 0 means "no position". */
typedef struct MsPos {
    uint32_t offset, line, column;
} MsPos;

typedef struct MsSpan {
    uint32_t start, end;
} MsSpan;

/* ---- names: interned identifiers ---- */

typedef uint32_t MsSym; /* index into one MsNames; 0 is the empty string */

typedef struct MsNames {
    MsArena arena;     /* the texts */
    const char **text; /* by symbol */
    uint32_t *len;     /* by symbol */
    uint32_t count, cap;
    uint32_t *table; /* open addressed: symbol + 1, 0 for empty */
    uint32_t mask;
} MsNames;

void ms_names_init(MsNames *n);
void ms_names_free(MsNames *n);
MsSym ms_intern(MsNames *n, const char *s, size_t len);
MsSym ms_intern_cstr(MsNames *n, const char *s);
static inline MsStr ms_name(const MsNames *n, MsSym s) {
    MsStr r = {n->text[s], n->len[s]};
    return r;
}

/* ---- diagnostics ---- */

typedef struct MsDiag {
    MsPos pos;
    bool has_end;
    MsPos end;
    bool has_fix;
    MsPos fix_pos, fix_end;
    MsStr replacement;
    MsStr message;
    uint32_t opener_line; /* line of the unclosed delimiter this reports, else 0 */
} MsDiag;

/* ---- UTF-8 ---- */

bool ms_utf8_valid(const char *s, size_t n);
/* Decodes the scalar at s[0..n); returns its length in bytes. s must hold valid UTF-8. */
int ms_utf8_decode(const char *s, size_t n, uint32_t *scalar);
/* Appends the scalar as UTF-8. */
void ms_utf8_put(MsBuf *b, uint32_t scalar);

#endif
