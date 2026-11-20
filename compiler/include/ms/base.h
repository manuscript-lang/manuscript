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

/* ---- arena ---- */

typedef struct MsChunk MsChunk;
typedef struct MsArena {
    MsChunk *head;
    char *cur, *end;
} MsArena;

void *ms_alloc(MsArena *a, size_t size, size_t align);
void ms_arena_free(MsArena *a);
#define MS_NEW(a, T) ((T *)ms_alloc((a), sizeof(T), _Alignof(T)))
#define MS_NEW_N(a, T, n) ((T *)ms_alloc((a), sizeof(T) * (size_t)(n), _Alignof(T)))

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
