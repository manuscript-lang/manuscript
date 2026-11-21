/* What the formatter's files share (format.c, format_layout.c, format_compact.c): the context of
 * one `ms_format` call, text helpers over non-terminated strings, and the entry points of the
 * passes. A pass takes source text and returns new text; parse and lex results live in a scratch
 * arena the pass frees, so only the strings it returns stay allocated. */
#ifndef MS_FORMAT_INTERNAL_H
#define MS_FORMAT_INTERNAL_H

#include <string.h>

#include "ms/ast.h"
#include "ms/lex.h"
#include "ms/parse.h"
#include "ms/text.h"

enum { FMT_WIDTH = 88, FMT_FLOW_WIDTH = 50 };
#define FMT_NONE SIZE_MAX

typedef MsStr Str;

/* One formatting run: where result strings live, the names the parser interns, and the first
 * syntax error. */
typedef struct Fmt {
    MsArena *arena;
    MsNames *names;
    MsDiag diag;
} Fmt;

/* ---- text ---- */

static inline Str fmt_str(const char *ptr, size_t len) {
    const Str s = {ptr, (uint32_t)len};
    return s;
}

static inline Str fmt_lit(const char *text) { return fmt_str(text, strlen(text)); }

static inline Str fmt_slice(Str s, size_t from, size_t to) { return fmt_str(s.ptr + from, to - from); }

static inline bool fmt_eq(Str a, Str b) { return ms_text_equal(a, b); }

/* Bytewise order: negative, zero or positive. */
static inline int fmt_compare(Str a, Str b) {
    const size_t n = a.len < b.len ? a.len : b.len;
    const int c = n == 0 ? 0 : memcmp(a.ptr, b.ptr, n);
    if (c != 0 || a.len == b.len) {
        return c;
    }
    return a.len < b.len ? -1 : 1;
}

static inline bool fmt_is(Str s, const char *text) { return fmt_eq(s, fmt_lit(text)); }

static inline bool fmt_starts(Str s, const char *prefix) { return ms_str_starts(s, prefix); }

static inline bool fmt_ends(Str s, const char *suffix) { return ms_str_ends(s, suffix); }

/* The offset of the first `needle` in `hay` (an empty needle matches at 0), or FMT_NONE. */
static inline size_t fmt_find(Str hay, Str needle) {
    if (needle.len == 0) {
        return 0;
    }
    for (size_t at = 0; at + needle.len <= hay.len; at++) {
        const char *hit = memchr(hay.ptr + at, needle.ptr[0], hay.len - needle.len + 1 - at);
        if (hit == NULL) {
            return FMT_NONE;
        }
        at = (size_t)(hit - hay.ptr);
        if (memcmp(hit, needle.ptr, needle.len) == 0) {
            return at;
        }
    }
    return FMT_NONE;
}

static inline bool fmt_contains(Str hay, const char *needle) { return fmt_find(hay, fmt_lit(needle)) != FMT_NONE; }

static inline size_t fmt_find_byte(Str s, char byte) {
    const char *at = s.len == 0 ? NULL : memchr(s.ptr, byte, s.len);
    return at == NULL ? FMT_NONE : (size_t)(at - s.ptr);
}

/* The offset of the last `byte`, or FMT_NONE. */
static inline size_t fmt_rfind_byte(Str s, char byte) {
    for (size_t i = s.len; i > 0; i--) {
        if (s.ptr[i - 1] == byte) {
            return i - 1;
        }
    }
    return FMT_NONE;
}

/* ---- scalars ---- */

static inline bool fmt_is_continuation(char byte) { return ((uint8_t)byte & 0xC0u) == 0x80u; }

/* Scalars in the text, as Rust's `chars().count()`. */
static inline size_t fmt_chars(Str s) {
    size_t count = 0;
    for (size_t i = 0; i < s.len; i++) {
        count += !fmt_is_continuation(s.ptr[i]);
    }
    return count;
}

/* Unicode White_Space, as Rust's `char::is_whitespace`. */
/* The scalar at byte `at` of valid UTF-8 and its width. */
static inline size_t fmt_scalar_at(Str s, size_t at, uint32_t *scalar) {
    return (size_t)ms_utf8_decode(s.ptr + at, s.len - at, scalar);
}

/* The scalar that ends at byte `to` and its width. */
static inline size_t fmt_scalar_before(Str s, size_t to, uint32_t *scalar) {
    size_t from = to - 1;
    while (from > 0 && fmt_is_continuation(s.ptr[from])) {
        from--;
    }
    (void)ms_utf8_decode(s.ptr + from, to - from, scalar);
    return to - from;
}

static inline bool fmt_in_set(char c, const char *set) { return c != '\0' && strchr(set, c) != NULL; }

/* Rust's `trim_start_matches` and `trim_end_matches` over a set of ASCII characters. */
static inline Str fmt_trim_start_set(Str s, const char *set) {
    size_t from = 0;
    while (from < s.len && fmt_in_set(s.ptr[from], set)) {
        from++;
    }
    return fmt_slice(s, from, s.len);
}

static inline Str fmt_trim_end_set(Str s, const char *set) {
    size_t to = s.len;
    while (to > 0 && fmt_in_set(s.ptr[to - 1], set)) {
        to--;
    }
    return fmt_slice(s, 0, to);
}

/* Rust's `trim_start`, `trim_end` and `trim`: Unicode White_Space. */
static inline Str fmt_trim_start(Str s) {
    size_t from = 0;
    while (from < s.len) {
        uint32_t scalar;
        const size_t width = fmt_scalar_at(s, from, &scalar);
        if (!ms_text_is_unicode_space(scalar)) {
            break;
        }
        from += width;
    }
    return fmt_slice(s, from, s.len);
}

static inline Str fmt_trim_end(Str s) {
    size_t to = s.len;
    while (to > 0) {
        uint32_t scalar;
        const size_t width = fmt_scalar_before(s, to, &scalar);
        if (!ms_text_is_unicode_space(scalar)) {
            break;
        }
        to -= width;
    }
    return fmt_slice(s, 0, to);
}

static inline Str fmt_trim(Str s) { return fmt_trim_end(fmt_trim_start(s)); }

static inline bool fmt_is_blank(Str s) { return fmt_trim(s).len == 0; }

/* Leading spaces of a line. */
static inline size_t fmt_indent_of(Str line) { return line.len - fmt_trim_start_set(line, " ").len; }

/* ---- building strings ---- */

/* A copy of `s` in the arena. */
static inline Str fmt_copy(Fmt *f, Str s) {
    return fmt_str(ms_arena_strndup(f->arena, s.len == 0 ? "" : s.ptr, s.len), s.len);
}

/* The buffer's text moved into the arena; the buffer is freed. */
static inline Str fmt_take(Fmt *f, MsBuf *b) {
    const Str s = fmt_copy(f, fmt_str(b->data == NULL ? "" : b->data, b->len));
    ms_buf_free(b);
    return s;
}

static inline void fmt_put(MsBuf *b, Str s) {
    if (s.len != 0) {
        ms_buf_put(b, s.ptr, s.len);
    }
}

static inline void fmt_spaces(MsBuf *b, size_t n) {
    if (n != 0) {
        memset(ms_buf_push(b, n), ' ', n);
    }
}

/* The bytes of the buffer after offset `from`. */
static inline Str fmt_tail(const MsBuf *b, size_t from) {
    return fmt_str(b->data == NULL ? "" : b->data + from, b->len - from);
}

/* ---- tokens ---- */

static inline bool fmt_layout_token(MsTok kind) {
    return kind == MS_T_Newline || kind == MS_T_Indent || kind == MS_T_Dedent || kind == MS_T_Eof;
}

static inline Str fmt_token_text(Str source, const MsToken *t) { return fmt_slice(source, t->lo, t->hi); }

static inline bool fmt_is_comparison(MsTok k) {
    return k == MS_T_EqEq || k == MS_T_NotEq || k == MS_T_Lt || k == MS_T_Gt || k == MS_T_Le || k == MS_T_Ge;
}

static inline bool fmt_is_arith(MsTok k) {
    return k == MS_T_Plus || k == MS_T_Minus || k == MS_T_Star || k == MS_T_Slash || k == MS_T_Percent;
}

static inline bool fmt_is_open(MsTok k) { return k == MS_T_LParen || k == MS_T_LBracket || k == MS_T_LBrace; }

/* Whether a space separates `tokens[at - 1]` and `tokens[at]` on one line of code. */
bool fmt_token_space(const MsToken *tokens, size_t at);

/* ---- parsing and lexing ---- */

/* Copies the text of a diagnostic out of the scratch arena that is about to be freed. */
static inline bool fmt_failed(Fmt *f) {
    f->diag.message = fmt_copy(f, f->diag.message);
    f->diag.replacement = fmt_copy(f, f->diag.replacement);
    return false;
}

/* Parses `source` into `module`, whose nodes live in `scratch`. False with f->diag filled on error. */
static inline bool fmt_parse(Fmt *f, MsArena *scratch, Str source, MsModule *module) {
    return ms_parse(scratch, f->names, source.ptr, source.len, module, &f->diag) || fmt_failed(f);
}

static inline bool fmt_lex(Fmt *f, MsArena *scratch, Str source, MsLexed *lexed) {
    return ms_lex(scratch, source.ptr, source.len, lexed, &f->diag) || fmt_failed(f);
}

/* ---- syntax helpers shared by the passes ---- */

/* The statements of a lambda body without the bindings the parser made for destructured
 * parameters (`written_body`). */
MsStmts fmt_written_body(const MsExpr *lambda);
/* A lambda whose body is a suite of several statements. */
bool fmt_block_lambda(const MsExpr *e);
/* The statement's value expression, or NULL. */
const MsExpr *fmt_statement_value(const MsStmt *s);
/* A lambda or a written match, seen through prefix operators. */
bool fmt_suite_expression(const MsExpr *e);
/* A written `match`, not the Bool match an `if` expression stands for. */
bool fmt_is_written_match(const MsExpr *e);
/* Whether the parser made this binding for a destructuring `for` or lambda parameter. */
bool fmt_is_destructure_head(const MsStmt *s);

/* ---- edits ---- */

/* A source edit: replace [from, to) with `text`. */
typedef struct FmtEdit {
    size_t from, to;
    Str text;
} FmtEdit;

/* The source with source-ordered, nonoverlapping edits applied. */
Str fmt_apply_edits(Fmt *f, Str source, const FmtEdit *edits, size_t count);

/* ---- passes ---- */

/* Statement compaction (format_compact.c): the compacted source, or false when nothing changes. */
bool fmt_compact(Fmt *f, const MsModule *module, Str source, Str *out);
/* Expression layout (format_layout.c). False with f->diag filled when the text stops parsing. */
bool fmt_expression_layout(Fmt *f, Str source, Str *out);

#endif
