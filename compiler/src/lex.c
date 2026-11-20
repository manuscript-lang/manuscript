/* The lexer with layout. A port of crates/ms-syntax/src/lexer.rs: the same tokens, the same
 * messages, the same positions. Errors unwind with longjmp to the entry point; everything is
 * allocated from the caller's arena, so nothing needs cleaning up. */
#include <stdlib.h>
#include <string.h>

#include "ms/lex.h"

#define MAX_INTERPOLATION_DEPTH 1000

#define BIDI_COMMENT                                                                               \
    "bidirectional text controls (U+202A..U+202E, U+2066..U+2069) are not allowed in comments "    \
    "because they can make source display differently from how it is read; remove the character"
#define BIDI_TEXT                                                                                  \
    "bidirectional text controls (U+202A..U+202E, U+2066..U+2069) are not allowed in text "        \
    "because they can make source display differently from how it is read; write the escape "      \
    "instead, e.g. \\u{202E}"
#define BRACE_HINT                                                                                 \
    "'{' starts an interpolation in f\"...\" text; write \\{ and \\} for literal braces, or drop " \
    "the f"
#define UNMATCHED_BRACE                                                                            \
    "an unmatched closing brace must be escaped in f\"...\" text; write \\} for a literal brace "  \
    "(and \\{ for the opening brace), or drop the f so braces are plain"
#define PLAIN_BRACE_ESCAPE                                                                         \
    "braces are plain characters in \"...\" text, so write { and } without a backslash; only "     \
    "f\"...\" text interpolates and escapes them"

typedef struct Level {
    size_t indent, depth;
} Level;

typedef struct Scanner {
    MsArena *arena;
    const char *text;
    const uint8_t *src;
    size_t n;
    size_t offset;
    uint32_t line, base_line, base_offset, column;
    MsBuf tokens;        /* MsToken */
    MsBuf levels;        /* Level */
    MsBuf delimiters;    /* char */
    MsBuf groups;        /* size_t */
    MsBuf opened;        /* MsPos */
    MsBuf function_depths; /* size_t */
    MsBuf interpolations;  /* MsPos */
    const uint32_t *line_offsets; /* NULL when the source had no CRLF */
    MsBuf strings, interps, blocks; /* MsRange, discovered boundaries */
    const MsBounds *cached;
    size_t boundary_origin;
    bool virtual_paren;
    MsBuf *prefixes; /* bool per physical line: is a delimiter open there (recovery) */
    const bool *stop_at;
    size_t nstop;
    jmp_buf jb;
    MsDiag *diag;
} Scanner;

#define VLEN(b, T) ((b).len / sizeof(T))
#define VAT(b, T, i) (((T *)(b).data)[i])
#define VLAST(b, T) VAT(b, T, VLEN(b, T) - 1)
#define VPUSH(b, T, v)                                                                             \
    do {                                                                                           \
        T v_ = (v);                                                                                \
        ms_buf_put(&(b), &v_, sizeof(T));                                                          \
    } while (0)
#define VPOP(b, T) ((b).len -= sizeof(T))

static bool letter(uint8_t b) {
    return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || b == '_';
}
static bool digit(uint8_t b) {
    return b >= '0' && b <= '9';
}
static bool hexdigit(uint8_t b) {
    return digit(b) || (b >= 'a' && b <= 'f') || (b >= 'A' && b <= 'F');
}
static bool bindigit(uint8_t b) {
    return b == '0' || b == '1';
}
static bool graphic(uint8_t b) {
    return b > 0x20 && b < 0x7f;
}

/* ---- errors ---- */

static void throw_diag(Scanner *s) __attribute__((noreturn));
static void throw_diag(Scanner *s) {
    longjmp(s->jb, 1);
}

static MsPos spos(const Scanner *s) {
    uint32_t offset = (uint32_t)s->offset + s->base_offset;
    if (s->line_offsets != NULL) {
        offset += s->line_offsets[s->line - s->base_line - 1];
    }
    MsPos p = {offset, s->line, s->column};
    return p;
}

static MsDiag *new_diag(Scanner *s, MsPos pos, MsStr message) {
    memset(s->diag, 0, sizeof *s->diag);
    s->diag->pos = pos;
    s->diag->message = message;
    return s->diag;
}

static void fail_at_str(Scanner *s, MsPos pos, MsStr message) __attribute__((noreturn));
static void fail_at_str(Scanner *s, MsPos pos, MsStr message) {
    new_diag(s, pos, message);
    throw_diag(s);
}
static void fail_str(Scanner *s, MsStr message) __attribute__((noreturn));
static void fail_str(Scanner *s, MsStr message) {
    fail_at_str(s, spos(s), message);
}

#define LIT(text) ((MsStr){(text), (uint32_t)(sizeof(text) - 1)})
#define FAIL(s, text) fail_str((s), LIT(text))
#define FAIL_AT(s, pos, text) fail_at_str((s), (pos), LIT(text))
#define FAILF(s, ...) fail_str((s), ms_arena_fmt((s)->arena, __VA_ARGS__))
#define FAIL_ATF(s, pos, ...) fail_at_str((s), (pos), ms_arena_fmt((s)->arena, __VA_ARGS__))

/* Reports a character whose first byte was just consumed: the cursor may be inside its UTF-8
 * encoding, so it is not itself a diagnostic boundary. */
static void fail_previous_byte(Scanner *s, MsStr message) __attribute__((noreturn));
static void fail_previous_byte(Scanner *s, MsStr message) {
    MsPos p = spos(s);
    p.offset -= 1;
    p.column -= 1;
    fail_at_str(s, p, message);
}

/* Fails on the single ASCII character at the cursor, with its range and the fix when one exists. */
static void fail_char(Scanner *s, MsStr message, const char *replacement) __attribute__((noreturn));
static void fail_char(Scanner *s, MsStr message, const char *replacement) {
    MsPos pos = spos(s);
    MsPos end = {pos.offset + 1, pos.line, pos.column + 1};
    MsDiag *d = new_diag(s, pos, message);
    d->has_end = true;
    d->end = end;
    if (replacement != NULL) {
        d->has_fix = true;
        d->fix_pos = pos;
        d->fix_end = end;
        d->replacement.ptr = replacement;
        d->replacement.len = (uint32_t)strlen(replacement);
    }
    throw_diag(s);
}

/* Fails on the source range [start, cursor). */
static void fail_range(Scanner *s, MsPos start, MsStr message) __attribute__((noreturn));
static void fail_range(Scanner *s, MsPos start, MsStr message) {
    MsDiag *d = new_diag(s, start, message);
    d->has_end = true;
    d->end = spos(s);
    throw_diag(s);
}

/* ---- Rust's `{:?}` for a char ---- */

static const uint32_t debug_escaped[][2] = {
#include "unicode_debug.inc"
};

void ms_quote_rune(MsBuf *out, uint32_t c) {
    ms_buf_putc(out, '\'');
    switch (c) {
    case 0:
        ms_buf_puts(out, "\\0");
        break;
    case '\t':
        ms_buf_puts(out, "\\t");
        break;
    case '\r':
        ms_buf_puts(out, "\\r");
        break;
    case '\n':
        ms_buf_puts(out, "\\n");
        break;
    case '\\':
        ms_buf_puts(out, "\\\\");
        break;
    case '\'':
        ms_buf_puts(out, "\\'");
        break;
    default: {
        size_t lo = 0, hi = sizeof debug_escaped / sizeof debug_escaped[0];
        bool escaped = false;
        while (lo < hi) {
            size_t mid = (lo + hi) / 2;
            if (c < debug_escaped[mid][0]) {
                hi = mid;
            } else if (c > debug_escaped[mid][1]) {
                lo = mid + 1;
            } else {
                escaped = true;
                break;
            }
        }
        if (escaped) {
            ms_buf_printf(out, "\\u{%x}", c);
        } else {
            ms_utf8_put(out, c);
        }
    }
    }
    ms_buf_putc(out, '\'');
}

static MsStr quote_rune_str(Scanner *s, uint32_t c) {
    MsBuf b = {0};
    ms_quote_rune(&b, c);
    MsStr r = {ms_arena_strndup(s->arena, b.data, b.len), (uint32_t)b.len};
    ms_buf_free(&b);
    return r;
}

/* ---- cursor ---- */

static uint8_t advance(Scanner *s) {
    uint8_t b = s->src[s->offset++];
    if (b == '\n') {
        s->line++;
        s->column = 1;
    } else {
        s->column++;
    }
    return b;
}

static int at(const Scanner *s, size_t i) {
    return i < s->n ? s->src[i] : -1;
}

static bool starts_with(const Scanner *s, size_t i, const char *lit) {
    size_t n = strlen(lit);
    return i + n <= s->n && memcmp(s->src + i, lit, n) == 0;
}

static bool at_line_comment(const Scanner *s) {
    return s->src[s->offset] == '/' && at(s, s->offset + 1) == '/';
}
static bool at_block_comment(const Scanner *s) {
    return s->src[s->offset] == '/' && at(s, s->offset + 1) == '*';
}

/* Whether the UTF-8 sequence at `i` is a bidirectional text control (U+202A..U+202E,
 * U+2066..U+2069). */
static bool bidi_control_at(const Scanner *s, size_t i) {
    if (i + 3 > s->n) {
        return false;
    }
    const uint8_t *p = s->src + i;
    return (p[0] == 0xE2 && p[1] == 0x80 && p[2] >= 0xAA && p[2] <= 0xAE) ||
           (p[0] == 0xE2 && p[1] == 0x81 && p[2] >= 0xA6 && p[2] <= 0xA9);
}

static void emit(Scanner *s, MsTok kind, size_t lo, size_t hi, MsPos pos) {
    MsToken t = {pos, spos(s), (uint32_t)lo, (uint32_t)hi, (uint8_t)kind};
    VPUSH(s->tokens, MsToken, t);
}

static void emit_layout(Scanner *s, MsTok kind) {
    MsPos p = spos(s);
    MsToken t = {p, p, (uint32_t)s->offset, (uint32_t)s->offset, (uint8_t)kind};
    VPUSH(s->tokens, MsToken, t);
}

static size_t ntokens(const Scanner *s) {
    return VLEN(s->tokens, MsToken);
}
static MsToken *tokat(const Scanner *s, size_t i) {
    return &VAT(s->tokens, MsToken, i);
}
static int last_kind(const Scanner *s) {
    size_t n = ntokens(s);
    return n == 0 ? -1 : tokat(s, n - 1)->kind;
}

/* Whether the word ending at `hi` is a member or field name, where a contextual keyword is an
 * ordinary name: after `.`, or a `name:` label that opens a line or follows `(` or `,`. */
static bool names_a_member(const Scanner *s, size_t hi) {
    int prev = last_kind(s);
    if (prev == MS_T_Dot) {
        return true;
    }
    bool label_start = prev == MS_T_LParen || prev == MS_T_Comma || prev == MS_T_Newline ||
                       prev == MS_T_Indent || prev == MS_T_Dedent || prev == -1;
    size_t j = hi;
    while (at(s, j) == ' ') {
        j++;
    }
    return label_start && at(s, j) == ':' && at(s, j + 1) != '=';
}

/* Whether only whitespace or a `//` comment follows the cursor on its line. */
static bool trailing_semicolon(const Scanner *s) {
    size_t i = s->offset + 1;
    while (i < s->n && (s->src[i] == ' ' || s->src[i] == '\t')) {
        i++;
    }
    if (i >= s->n || s->src[i] == '\n') {
        return true;
    }
    if (s->src[i] == '/' && at(s, i + 1) == '/') {
        return true;
    }
    /* line == "\r" */
    return s->src[i] == '\r' && (i + 1 >= s->n || s->src[i + 1] == '\n');
}

/* ---- comments ---- */

static void skip_comment(Scanner *s) {
    while (s->offset < s->n && s->src[s->offset] != '\n') {
        if (s->src[s->offset] == '\r') {
            FAIL(s, "lone carriage returns are not allowed in comments; use line endings of LF or CRLF");
        }
        if (bidi_control_at(s, s->offset)) {
            FAIL(s, BIDI_COMMENT);
        }
        advance(s);
    }
}

/* Consumes a block comment, which does not nest, and the blanks and optional `//` comment after
 * its `*​/`; the cursor ends at the line's newline. */
static void skip_block_comment(Scanner *s) {
    MsPos open = spos(s);
    size_t start = s->offset;
    advance(s);
    advance(s);
    for (;;) {
        if (s->offset >= s->n) {
            FAIL_AT(s, open, "unterminated block comment; close it with '*/'");
        }
        uint8_t b = s->src[s->offset];
        if (b == '*' && at(s, s->offset + 1) == '/') {
            advance(s);
            advance(s);
            MsRange r = {start, s->offset};
            VPUSH(s->blocks, MsRange, r);
            break;
        }
        if (b == '/' && at(s, s->offset + 1) == '*') {
            FAIL(s, "block comments do not nest; remove the inner '/*'");
        }
        if (b == '\r') {
            FAIL(s, "lone carriage returns are not allowed in comments; use line endings of LF or CRLF");
        }
        if (bidi_control_at(s, s->offset)) {
            FAIL(s, BIDI_COMMENT);
        }
        advance(s);
    }
    while (s->offset < s->n && s->src[s->offset] == ' ') {
        advance(s);
    }
    if (s->offset < s->n && at_line_comment(s)) {
        skip_comment(s);
        return;
    }
    if (s->offset < s->n && s->src[s->offset] != '\n') {
        FAIL(s, "code cannot follow a block comment on the same line; start a new line");
    }
}

/* ---- numbers ---- */

/* Consumes digits accepted by `ok`, allowing `_` only between two digits. */
static void scan_digits(Scanner *s, bool (*ok)(uint8_t), bool after_digit) {
    while (s->offset < s->n) {
        uint8_t b = s->src[s->offset];
        if (ok(b)) {
            after_digit = true;
        } else if (b == '_') {
            bool next_ok = s->offset + 1 < s->n && ok(s->src[s->offset + 1]);
            if (!after_digit || !next_ok) {
                FAIL(s, "a digit separator goes between two digits; write e.g. 1_000_000 or 0xFF_FF");
            }
            after_digit = false;
        } else {
            break;
        }
        advance(s);
    }
}

static void scan_number(Scanner *s, MsPos p) {
    size_t n = s->n;
    size_t start = s->offset;
    advance(s);
    if (s->src[start] == '0' && s->offset < n) {
        bool (*ok)(uint8_t) = NULL;
        if (s->src[s->offset] == 'x') {
            ok = hexdigit;
        } else if (s->src[s->offset] == 'b') {
            ok = bindigit;
        }
        if (ok != NULL) {
            advance(s);
            if (s->offset == n || !ok(s->src[s->offset])) {
                FAIL(s, "a hexadecimal or binary literal requires digits after the prefix; write e.g. 0xFF or 0b1010");
            }
            scan_digits(s, ok, false);
            if (s->offset < n && (letter(s->src[s->offset]) || digit(s->src[s->offset]))) {
                FAIL(s, "invalid digit in a hexadecimal or binary literal; 0x takes 0-9 and a-f, 0b takes 0 and 1");
            }
            emit(s, MS_T_Number, start, s->offset, p);
            return;
        }
    }
    if (s->src[start] == '0' && s->offset < n && (digit(s->src[s->offset]) || s->src[s->offset] == '_')) {
        FAIL(s, "leading zeros are not allowed in numeric literals; write the number without them, e.g. 42 instead of 042");
    }
    scan_digits(s, digit, true);
    if (s->offset + 1 < n && s->src[s->offset] == '.' && digit(s->src[s->offset + 1])) {
        advance(s);
        scan_digits(s, digit, false);
    }
    if (s->offset < n && (s->src[s->offset] == 'e' || s->src[s->offset] == 'E')) {
        advance(s);
        if (s->offset < n && (s->src[s->offset] == '+' || s->src[s->offset] == '-')) {
            advance(s);
        }
        if (s->offset == n || !digit(s->src[s->offset])) {
            FAIL(s, "an exponent requires digits; write e.g. 1e3 or 2.5e-4");
        }
        while (s->offset < n && digit(s->src[s->offset])) {
            advance(s);
        }
    }
    if (s->offset < n && s->src[s->offset] == 'd') {
        advance(s);
    }
    if (s->offset < n && letter(s->src[s->offset])) {
        while (s->offset < n && (letter(s->src[s->offset]) || digit(s->src[s->offset]))) {
            advance(s);
        }
        const char *word = s->text + start;
        size_t wl = s->offset - start;
        bool has_underscore = memchr(word, '_', wl) != NULL;
        MsStr message;
        if (wl > 1 && (memcmp(word, "0X", 2) == 0 || memcmp(word, "0B", 2) == 0)) {
            message = ms_arena_fmt(s->arena,
                                   "invalid number %.*s; the prefix is lowercase, so write 0%c%.*s",
                                   (int)wl, word, word[1] + ('a' - 'A'), (int)(wl - 2), word + 2);
        } else if (wl > 1 && (memcmp(word, "0o", 2) == 0 || memcmp(word, "0O", 2) == 0)) {
            message = ms_arena_fmt(s->arena,
                                   "invalid number %.*s; octal literals do not exist, so write the value in decimal, hexadecimal (0x) or binary (0b)",
                                   (int)wl, word);
        } else if (has_underscore) {
            message = ms_arena_fmt(s->arena,
                                   "invalid number %.*s; a digit separator goes between two digits of the integer or fraction part, e.g. 1_000_000",
                                   (int)wl, word);
        } else {
            message = ms_arena_fmt(s->arena,
                                   "invalid number %.*s; the only numeric suffix is d for Decimal (1.5d), so put a space or operator after the number",
                                   (int)wl, word);
        }
        fail_range(s, p, message);
    }
    emit(s, MS_T_Number, start, s->offset, p);
}

/* ---- text ---- */

static void scan_string(Scanner *s, bool interpolating);
static void scan_multiline(Scanner *s, bool raw, bool interpolating);

static const MsRange *find_range(const MsRange *r, size_t n, size_t start) {
    size_t lo = 0, hi = n;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (r[mid].start < start) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    return lo < n && r[lo].start == start ? &r[lo] : NULL;
}

size_t ms_bounds_interp_end(const MsBounds *b, size_t start) {
    const MsRange *r = find_range(b->interps, b->ninterps, start);
    return r != NULL ? r->end : 0;
}

MsPos ms_bounds_restore_offset(const MsBounds *b, MsPos from, MsPos to) {
    if (b->line_offsets != NULL) {
        uint32_t before = from.line - b->base_line - 1;
        uint32_t after = to.line - b->base_line - 1;
        to.offset += b->line_offsets[after] - b->line_offsets[before];
    }
    return to;
}

/* Validates the escape after a consumed backslash. */
static void scan_escape(Scanner *s, bool interpolating) {
    size_t n = s->n;
    MsPos backslash = spos(s);
    backslash.column -= 1;
    backslash.offset -= 1;
    if (s->offset == n) {
        FAIL(s, "unterminated text escape; a backslash needs a following character, e.g. \\n");
    }
    uint8_t c = advance(s);
    if (c == 'u') {
        if (s->offset == n || advance(s) != '{') {
            MsStr message = LIT("Unicode escapes use \\u{H}; write 1 to 6 hexadecimal digits in braces, e.g. \\u{1F600}");
            if (s->src[s->offset - 1] < 0x80) {
                fail_str(s, message);
            }
            fail_previous_byte(s, message);
        }
        size_t start = s->offset;
        uint64_t value = 0;
        while (s->offset < n && s->src[s->offset] != '}') {
            uint8_t ch = advance(s);
            uint64_t d;
            if (ch >= '0' && ch <= '9') {
                d = ch - '0';
            } else if (ch >= 'a' && ch <= 'f') {
                d = ch - 'a' + 10;
            } else if (ch >= 'A' && ch <= 'F') {
                d = ch - 'A' + 10;
            } else {
                MsStr message = LIT("invalid Unicode scalar escape; use only hexadecimal digits 0-9 and a-f inside \\u{...}");
                if (ch < 0x80) {
                    fail_str(s, message);
                }
                fail_previous_byte(s, message);
            }
            /* saturating_mul(16).saturating_add(d) */
            value = value > (UINT64_MAX - d) / 16 ? UINT64_MAX : value * 16 + d;
        }
        size_t digits = s->offset - start;
        if (s->offset == n || digits < 1 || digits > 6 || value > 0x10ffff ||
            (value >= 0xd800 && value <= 0xdfff)) {
            FAIL(s, "invalid Unicode scalar escape; use 1 to 6 hexadecimal digits for a value up to 10FFFF that is not a surrogate (D800-DFFF)");
        }
        advance(s);
    } else if (!interpolating && (c == '{' || c == '}')) {
        FAIL_AT(s, backslash, PLAIN_BRACE_ESCAPE);
    } else if (!(c != 0 && strchr("\"\\nrt{}", c) != NULL)) {
        MsStr escape;
        if (graphic(c)) {
            escape = ms_arena_fmt(s->arena, " \\%c", c);
        } else {
            uint32_t full;
            ms_utf8_decode(s->text + s->offset - 1, s->n - (s->offset - 1), &full);
            MsStr q = quote_rune_str(s, full);
            escape = ms_arena_fmt(s->arena, ": a backslash followed by %.*s", (int)q.len, q.ptr);
        }
        const char *braces = interpolating ? "\\{ \\} (f text only) " : "";
        FAIL_ATF(s, backslash,
                 "unknown text escape%.*s; valid escapes are \\n \\t \\r \\\\ \\\" %sand \\u{H}",
                 (int)escape.len, escape.ptr, braces);
    }
}

static bool text_is_blank(const char *p, size_t n) {
    /* trim_matches(char::is_whitespace).is_empty() */
    size_t i = 0;
    while (i < n) {
        uint32_t c;
        int w = ms_utf8_decode(p + i, n - i, &c);
        bool ws = (c >= 0x09 && c <= 0x0D) || c == 0x20 || c == 0x85 || c == 0xA0 || c == 0x1680 ||
                  (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F ||
                  c == 0x205F || c == 0x3000;
        if (!ws) {
            return false;
        }
        i += (size_t)w;
    }
    return true;
}

static void interpolation_body(Scanner *s, MsPos open) {
    size_t n = s->n;
    int depth = 1;
    size_t start = s->offset;
    while (s->offset < n) {
        uint8_t b = s->src[s->offset];
        if (b == '\n' || b == '\r' || at_line_comment(s) || at_block_comment(s)) {
            FAIL_AT(s, open, "newlines and comments are not allowed inside interpolation; keep the expression on one line, or bind it to a name first and interpolate the name (" BRACE_HINT ")");
        }
        if (b == '\\') {
            FAIL_AT(s, open, "a backslash cannot appear in the interpolated expression (" BRACE_HINT ")");
        }
        if (b == '"') {
            scan_string(s, false);
            continue;
        }
        bool after_word = s->offset > 0 && (letter(s->src[s->offset - 1]) || digit(s->src[s->offset - 1]));
        if (b == 'f' && at(s, s->offset + 1) == '"' && !after_word) {
            advance(s);
            scan_string(s, true);
            continue;
        }
        if (b == 'r' && at(s, s->offset + 1) == '"' && !starts_with(s, s->offset + 2, "\"\"") &&
            !after_word) {
            /* scan_raw_line */
            MsPos opened = spos(s);
            advance(s);
            advance(s);
            for (;;) {
                if (s->offset >= n) {
                    FAIL_AT(s, opened, "unterminated raw text literal; add the closing '\"' on the same line");
                }
                uint8_t c = advance(s);
                if (c == '"') {
                    break;
                }
                if (c == '\n') {
                    FAIL_AT(s, opened, "unterminated raw text literal; r\"...\" must close on the same line and cannot hold a quote, so add the quote or use r\"\"\" multi-line raw text");
                }
                if (c < 32) {
                    FAIL(s, "literal control characters are not allowed in text; use r\"\"\" raw text for tabs, or write an escape such as \\t in non-raw text");
                }
                if (c == 0xE2 && bidi_control_at(s, s->offset - 1)) {
                    fail_previous_byte(s, LIT(BIDI_TEXT));
                }
            }
            continue;
        }
        advance(s);
        if (b == '{') {
            depth++;
        }
        if (b == '}') {
            depth--;
            if (depth == 0) {
                if (text_is_blank(s->text + start, s->offset - 1 - start)) {
                    FAIL(s, "empty interpolation; put an expression between the braces, or write \\{ for a literal brace");
                }
                return;
            }
        }
    }
    FAIL_AT(s, open, "unterminated interpolation; add the closing } before the closing quote (" BRACE_HINT ")");
}

static void scan_interpolation(Scanner *s) {
    size_t start = s->boundary_origin + s->offset - 1;
    MsPos open = spos(s);
    open.column -= 1;
    open.offset -= 1;
    if (VLEN(s->interpolations, MsPos) >= MAX_INTERPOLATION_DEPTH) {
        FAIL_ATF(s, open,
                 "nesting exceeds %d levels; split the expression, type, or block into named parts",
                 MAX_INTERPOLATION_DEPTH);
    }
    VPUSH(s->interpolations, MsPos, open);
    interpolation_body(s, open);
    VPOP(s->interpolations, MsPos);
    MsRange r = {start, s->boundary_origin + s->offset};
    VPUSH(s->interps, MsRange, r);
}

/* Scans `"..."` text, or `f"..."` text when `interpolating` (the caller has consumed the `f`).
 * Braces are plain characters unless interpolating. */
static void scan_string(Scanner *s, bool interpolating) {
    size_t start = s->offset;
    if (starts_with(s, start, "\"\"\"")) {
        scan_multiline(s, false, interpolating);
        return;
    }
    if (s->cached != NULL) {
        const MsRange *r = find_range(s->cached->strings, s->cached->nstrings, s->boundary_origin + start);
        if (r != NULL) {
            s->column += (uint32_t)(r->end - s->boundary_origin - start);
            s->offset = r->end - s->boundary_origin;
            return;
        }
    }
    size_t n = s->n;
    MsPos opened = spos(s);
    advance(s);
    while (s->offset < n) {
        uint8_t b = advance(s);
        if (b == '"') {
            if (VLEN(s->interpolations, MsPos) != 0) {
                MsRange r = {s->boundary_origin + start, s->boundary_origin + s->offset};
                VPUSH(s->strings, MsRange, r);
            }
            return;
        }
        if (b == '\n') {
            if (VLEN(s->interpolations, MsPos) != 0) {
                MsPos at_ = VLAST(s->interpolations, MsPos);
                FAIL_AT(s, at_, "unterminated interpolation; the quote after this '{' opens a nested text that never closes (" BRACE_HINT ")");
            }
            FAIL_AT(s, opened, "unterminated text literal; text must close with '\"' on the same line, so add the quote or write \\n for a line break");
        }
        if (b < 32) {
            FAIL(s, "literal control characters are not allowed in text; write an escape such as \\t, \\r, or \\u{H}");
        }
        if (b == 0xE2 && bidi_control_at(s, s->offset - 1)) {
            fail_previous_byte(s, LIT(BIDI_TEXT));
        }
        if (b == '\\') {
            scan_escape(s, interpolating);
        } else if (interpolating && b == '{') {
            scan_interpolation(s);
        } else if (interpolating && b == '}') {
            FAIL(s, UNMATCHED_BRACE);
        }
    }
    FAIL_AT(s, opened, "unterminated text literal; add the closing '\"' on the same line");
}

/* Scans one-line raw text `r"..."`: every character is literal up to the first `"`. */
static void scan_raw_line(Scanner *s) {
    MsPos opened = spos(s);
    advance(s);
    advance(s);
    while (s->offset < s->n) {
        uint8_t b = advance(s);
        if (b == '"') {
            return;
        }
        if (b == '\n') {
            FAIL_AT(s, opened, "unterminated raw text literal; r\"...\" must close on the same line and cannot hold a quote, so add the quote or use r\"\"\" multi-line raw text");
        }
        if (b < 32) {
            FAIL(s, "literal control characters are not allowed in text; use r\"\"\" raw text for tabs, or write an escape such as \\t in non-raw text");
        }
        if (b == 0xE2 && bidi_control_at(s, s->offset - 1)) {
            fail_previous_byte(s, LIT(BIDI_TEXT));
        }
    }
    FAIL_AT(s, opened, "unterminated raw text literal; add the closing '\"' on the same line");
}

typedef struct LinePos {
    size_t at;
    MsPos pos;
} LinePos;

/* Scans `"""` text (and `r"""` raw text when `raw`): the opening quotes end their line, the
 * closing quotes start theirs, and every content line carries the closing line's indentation. */
static void scan_multiline(Scanner *s, bool raw, bool interpolating) {
    MsPos opened = spos(s);
    if (VLEN(s->interpolations, MsPos) != 0) {
        FAIL(s, "multi-line text cannot appear inside an interpolation; bind it to a name first and interpolate the name");
    }
    size_t n = s->n;
    for (int i = 0; i < (raw ? 4 : 3); i++) {
        advance(s);
    }
    if (s->offset == n || s->src[s->offset] != '\n') {
        FAIL_AT(s, opened, "multi-line text must start on the line after its opening '\"\"\"'; add a line break after the opening quotes");
    }
    size_t line_start = s->offset + 1;
    MsBuf lines = {0};
    while (s->offset < n) {
        uint8_t b = advance(s);
        if (b == '\n') {
            line_start = s->offset;
            LinePos lp = {line_start, spos(s)};
            VPUSH(lines, LinePos, lp);
            continue;
        }
        if (b == '"' && starts_with(s, s->offset, "\"\"")) {
            size_t quote = s->offset - 1;
            const uint8_t *indent = s->src + line_start;
            size_t indent_len = quote - line_start;
            for (size_t i = 0; i < indent_len; i++) {
                if (indent[i] != ' ' && indent[i] != '\t') {
                    ms_buf_free(&lines);
                    fail_previous_byte(s, LIT("multi-line text closes with '\"\"\"' alone on its own line; move the closing quotes to a new line (a '\"\"\"' inside the text is not allowed, so write \\\" for a quote in non-raw text)"));
                }
            }
            for (size_t k = 0; k < VLEN(lines, LinePos); k++) {
                LinePos lp = VAT(lines, LinePos, k);
                const uint8_t *rest = s->src + lp.at;
                size_t rest_len = n - lp.at;
                const uint8_t *nl = memchr(rest, '\n', rest_len);
                size_t line_len = nl != NULL ? (size_t)(nl - rest) : rest_len;
                bool blank = true;
                for (size_t i = 0; i < line_len; i++) {
                    if (rest[i] != ' ' && rest[i] != '\t') {
                        blank = false;
                        break;
                    }
                }
                bool has_prefix = line_len >= indent_len && memcmp(rest, indent, indent_len) == 0;
                if (lp.at < quote && !blank && !has_prefix) {
                    ms_buf_free(&lines);
                    fail_at_str(s, lp.pos, LIT("text line is indented less than the closing '\"\"\"'; indent it to the closing quotes' column, or move the closing quotes left"));
                }
            }
            ms_buf_free(&lines);
            advance(s);
            advance(s);
            return;
        }
        if (b < 32 && b != '\t') {
            ms_buf_free(&lines);
            FAIL(s, "literal control characters are not allowed in text; write an escape such as \\t, \\r, or \\u{H}");
        }
        if (b == 0xE2 && bidi_control_at(s, s->offset - 1)) {
            ms_buf_free(&lines);
            fail_previous_byte(s, LIT(BIDI_TEXT));
        }
        if (raw) {
            continue;
        }
        if (b == '\\') {
            scan_escape(s, interpolating);
        } else if (interpolating && b == '{') {
            scan_interpolation(s);
        } else if (interpolating && b == '}') {
            ms_buf_free(&lines);
            FAIL(s, UNMATCHED_BRACE);
        }
    }
    ms_buf_free(&lines);
    FAIL_AT(s, opened, "unterminated multi-line text; close it with '\"\"\"' alone on its own line");
}

/* ---- layout helpers ---- */

/* Whether the next code line begins with '.' or '|', which continues the statement on the current
 * line. Blank and comment-only lines are skipped. */
static bool continues_next(const Scanner *s) {
    size_t n = s->n;
    size_t i = s->offset;
    if (i >= n) {
        return false;
    }
    i++;
    while (i < n) {
        size_t j = i;
        while (j < n && (s->src[j] == ' ' || s->src[j] == '\t')) {
            j++;
        }
        if (j >= n) {
            return false;
        }
        uint8_t c = s->src[j];
        if (c == '\n') {
            i = j + 1;
        } else if (c == '/' && at(s, j + 1) == '/') {
            while (j < n && s->src[j] != '\n') {
                j++;
            }
            i = j + 1;
        } else if (c == '/' && at(s, j + 1) == '*') {
            size_t k = j + 2;
            bool found = false;
            while (k + 1 < n) {
                if (s->src[k] == '*' && s->src[k + 1] == '/') {
                    found = true;
                    break;
                }
                k++;
            }
            if (!found) {
                return false;
            }
            j = k + 2;
            while (j < n && s->src[j] != '\n') {
                j++;
            }
            i = j + 1;
        } else if (c == '|') {
            return true;
        } else if (c == '.') {
            return j + 1 < n && !digit(s->src[j + 1]) && s->src[j + 1] != '.';
        } else {
            return false;
        }
    }
    return false;
}

/* A block header on the previous line that lacks its closing ':' when an indented line follows
 * it, with the fix that inserts the ':'. Returns false when there is none. */
static bool missing_colon(Scanner *s) {
    size_t nt = ntokens(s);
    size_t li = nt;
    while (li > 0 && (tokat(s, li - 1)->kind == MS_T_Newline || tokat(s, li - 1)->kind == MS_T_Comment)) {
        li--;
    }
    if (li == 0) {
        return false;
    }
    const MsToken *last = tokat(s, li - 1);
    if (last->kind == MS_T_Colon || last->kind == MS_T_Indent || last->kind == MS_T_Dedent) {
        return false;
    }
    size_t i = nt;
    while (i > 0 && tokat(s, i - 1)->kind == MS_T_Newline) {
        i--;
    }
    size_t j = i;
    while (j > 0) {
        int k = tokat(s, j - 1)->kind;
        if (k == MS_T_Newline || k == MS_T_Indent || k == MS_T_Dedent) {
            break;
        }
        j--;
    }
    if (j == i) {
        return false;
    }
    const MsToken *first = tokat(s, j);
    if (first->pos.line != last->end.line) {
        return false;
    }
    switch (first->kind) {
    case MS_T_Fn: case MS_T_If: case MS_T_Else: case MS_T_For: case MS_T_While: case MS_T_Match:
    case MS_T_Type: case MS_T_Enum: case MS_T_Impl: case MS_T_Test: case MS_T_Interface:
        break;
    default:
        return false;
    }
    /* A ':' outside brackets already opened an inline body (`if x: return`), so an indented line
     * after it is over-indented, not a missing ':'. */
    int depth = 0;
    for (size_t k = 0; k < nt; k++) {
        const MsToken *t = tokat(s, k);
        if (t->pos.line != first->pos.line) {
            continue;
        }
        switch (t->kind) {
        case MS_T_LParen: case MS_T_LBracket: case MS_T_LBrace:
            depth++;
            break;
        case MS_T_RParen: case MS_T_RBracket: case MS_T_RBrace:
            depth--;
            break;
        case MS_T_Colon:
            if (depth == 0) {
                return false;
            }
            break;
        default:
            break;
        }
    }
    MsPos end = last->end;
    MsStr message = ms_arena_fmt(s->arena,
        "the '%s' block header on line %u does not end with ':'; add ':' at the end of that line so the indented lines below become its body",
        ms_tok_str((MsTok)first->kind), first->pos.line);
    MsDiag *d = new_diag(s, end, message);
    d->has_end = true;
    d->end = end;
    d->has_fix = true;
    d->fix_pos = end;
    d->fix_end = end;
    d->replacement = LIT(":");
    return true;
}

/* Explains the usual cause of an over-indented line that starts with a binary operator. */
static const char *continuation_hint(const Scanner *s) {
    for (size_t i = ntokens(s); i > 0; i--) {
        int k = tokat(s, i - 1)->kind;
        if (k == MS_T_Newline || k == MS_T_Indent || k == MS_T_Dedent) {
            continue;
        }
        if (k == MS_T_Pipe) {
            return "; a pipe step cannot follow the '|' on the next line, so end the previous line before '|' and start the continuation line with '|'";
        }
        break;
    }
    size_t end = s->offset;
    while (end < s->n && s->src[end] != ' ' && s->src[end] != '\n') {
        end++;
    }
    size_t len = end - s->offset;
    static const char *const ops[] = {"and", "or", "+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">="};
    for (size_t i = 0; i < sizeof ops / sizeof ops[0]; i++) {
        if (strlen(ops[i]) == len && memcmp(ops[i], s->text + s->offset, len) == 0) {
            return "; to continue an expression on the next line, wrap the whole expression in parentheses";
        }
    }
    return "";
}

static const char *character_hint(uint8_t b) {
    switch (b) {
    case ';':
        return "; Manuscript ends a statement at the end of the line, so remove the semicolon";
    case '\'':
        return "; text uses double quotes, e.g. \"text\"";
    case '!':
        return "; write 'not x' for negation and '!=' for inequality";
    case '`':
        return "; text uses double quotes with {expression} interpolation";
    case '#':
        return "; comments start with '//' (or '/* */' for a block)";
    case '$': case '@': case '\\': case '^': case '~':
        return "; this character is not part of Manuscript's syntax outside text";
    default:
        return "; this character is not part of Manuscript's syntax";
    }
}

/* ---- the main loop ---- */

static void run(Scanner *s) {
    size_t n = s->n;
    bool pending = false;
    size_t header_indent = 0, pending_depth = 0, header_start = 0;
    bool continuing = false;
    size_t statement_indent = 0;
    while (s->offset < n) {
        if (s->prefixes != NULL) {
            bool open = VLEN(s->delimiters, char) != 0;
            /* Lines inside a multi-line text were consumed by one token. */
            size_t line = s->line - s->base_line - 1;
            while (s->prefixes->len < line) {
                ms_buf_putc(s->prefixes, 1);
            }
            ms_buf_putc(s->prefixes, open);
            if (s->prefixes->len - 1 < s->nstop && s->stop_at[s->prefixes->len - 1] && !open) {
                return;
            }
        }
        /* A leading tab is one indent level: four columns. */
        size_t leading = 0;
        bool spaced = false;
        while (s->offset < n && (s->src[s->offset] == ' ' || s->src[s->offset] == '\t')) {
            if (s->src[s->offset] == '\t') {
                if (spaced) {
                    FAIL(s, "a tab cannot follow spaces in indentation; indent with tabs, then align with spaces");
                }
                advance(s);
                s->column += 3;
                leading += 4;
            } else {
                advance(s);
                spaced = true;
                leading += 1;
            }
        }
        if (s->offset == n) {
            break;
        }
        if (at_line_comment(s)) {
            skip_comment(s);
            if (s->offset < n) {
                advance(s);
            }
            continue;
        }
        if (at_block_comment(s)) {
            skip_block_comment(s);
            if (s->offset < n) {
                advance(s);
            }
            continue;
        }
        if (s->src[s->offset] == '\n') {
            advance(s);
            continue;
        }
        if (!s->virtual_paren && leading % 4 != 0) {
            const char *inside = VLEN(s->delimiters, char) == 0 ? ""
                : "; a line inside brackets is indented by fours too, so do not align it with the opening bracket";
            FAILF(s, "indentation must be a multiple of four spaces, found %zu; use %zu or %zu%s",
                  leading, leading / 4 * 4, leading / 4 * 4 + 4, inside);
        }
        if (continuing) {
            if (leading != statement_indent + 4) {
                FAILF(s, "a line starting with '.' or '|' continues the previous statement and must be indented four spaces past it, to %zu spaces, found %zu",
                      statement_indent + 4, leading);
            }
            continuing = false;
        } else {
            if (VLEN(s->delimiters, char) == VLAST(s->levels, Level).depth) {
                statement_indent = leading;
            }
            bool started_suite = false;
            if (pending) {
                if (leading == header_indent + 4) {
                    Level lv = {leading, pending_depth};
                    VPUSH(s->levels, Level, lv);
                    emit_layout(s, MS_T_Indent);
                    started_suite = true;
                } else if (leading > header_start && leading <= header_indent) {
                    FAILF(s, "a suite begins four spaces after the line that ends with ':' (at %zu spaces); indent this line to %zu, or move that closing line back to %zu spaces",
                          header_indent, header_indent + 4, header_start);
                } else if (leading <= header_indent) {
                    /* An empty declaration suite has the same layout boundaries as a populated one. */
                    emit_layout(s, MS_T_Indent);
                    emit_layout(s, MS_T_Dedent);
                } else {
                    FAILF(s, "a suite must begin exactly four spaces after its header; the header is at %zu spaces, so indent this line to %zu",
                          header_indent, header_indent + 4);
                }
                pending = false;
            }
            if (!started_suite) {
                /* A continuation line inside delimiters opened within a level does not close that
                 * level; only suites opened inside the open delimiters can. */
                while (VLEN(s->levels, Level) > 1) {
                    Level top = VLAST(s->levels, Level);
                    if (!(leading < top.indent && top.depth >= VLEN(s->delimiters, char))) {
                        break;
                    }
                    VPOP(s->levels, Level);
                    emit_layout(s, MS_T_Dedent);
                }
                Level top = VLAST(s->levels, Level);
                if (VLEN(s->delimiters, char) == top.depth && leading != top.indent) {
                    if (leading > top.indent) {
                        if (missing_colon(s)) {
                            throw_diag(s);
                        }
                        const char *hint = continuation_hint(s);
                        FAILF(s, "unexpected indentation, %zu spaces where %zu are expected; the previous line must end with ':' to open a block (fn, if, else, for, while, match, type, impl headers), otherwise align this line with it%s",
                              leading, top.indent, hint);
                    }
                    FAILF(s, "inconsistent dedent to %zu spaces; enclosing blocks are indented at %zu or %zu spaces, so align with one of them",
                          leading, top.indent, top.indent >= 4 ? top.indent - 4 : 0);
                }
            }
        }
        Level top = VLAST(s->levels, Level);
        size_t top_indent = top.indent, top_depth = top.depth;
        if (ntokens(s) != 0 && last_kind(s) == MS_T_Dedent && VLEN(s->delimiters, char) == top_depth) {
            emit_layout(s, MS_T_Newline);
        }
        size_t line_start = ntokens(s);
        while (s->offset < n && s->src[s->offset] != '\n') {
            uint8_t b = s->src[s->offset];
            MsPos p = spos(s);
            if (b == ' ') {
                advance(s);
                continue;
            }
            if (at_line_comment(s)) {
                skip_comment(s);
                break;
            }
            if (at_block_comment(s)) {
                FAIL(s, "a block comment must start its own line; write a trailing comment with '//'");
            }
            if (b == '\t' || b == '\r') {
                FAIL(s, "tabs are allowed only in indentation, and lone carriage returns not at all; use spaces between tokens, and line endings of LF or CRLF");
            }
            if (b == 'r' && at(s, s->offset + 1) == '"') {
                size_t start = s->offset;
                if (starts_with(s, s->offset + 1, "\"\"\"")) {
                    scan_multiline(s, true, false);
                } else {
                    scan_raw_line(s);
                }
                emit(s, MS_T_String, start, s->offset, p);
                continue;
            }
            if (b == '"' || (b == 'f' && at(s, s->offset + 1) == '"')) {
                size_t start = s->offset;
                bool formatted = b == 'f';
                if (formatted) {
                    advance(s);
                }
                scan_string(s, formatted);
                emit(s, MS_T_String, start, s->offset, p);
                continue;
            }
            if (letter(b)) {
                size_t start = s->offset;
                size_t i = start;
                while (i < n && (letter(s->src[i]) || digit(s->src[i]))) {
                    i++;
                }
                s->column += (uint32_t)(i - start);
                s->offset = i;
                MsTok kind = ms_tok_from_word(s->text + start, i - start);
                if (ms_tok_is_contextual(kind) && names_a_member(s, i)) {
                    kind = MS_T_Name;
                }
                if (kind == MS_T_Fn || kind == MS_T_Match) {
                    VPUSH(s->function_depths, size_t, VLEN(s->delimiters, char));
                }
                emit(s, kind, start, i, p);
                continue;
            }
            if (digit(b)) {
                scan_number(s, p);
                continue;
            }
            if (b == '.' && at(s, s->offset + 1) == '.' && at(s, s->offset + 2) == '.') {
                size_t start = s->offset;
                advance(s);
                advance(s);
                advance(s);
                emit(s, MS_T_Ellipsis, start, start + 3, p);
                continue;
            }
            int two = -1;
            int nx = at(s, s->offset + 1);
            if (b == '.' && nx == '.') {
                two = MS_T_DotDot;
            } else if (b == '-' && nx == '>') {
                two = MS_T_Arrow;
            } else if (b == ':' && nx == '=') {
                two = MS_T_ColonAssign;
            } else if (b == '=' && nx == '=') {
                two = MS_T_EqEq;
            } else if (b == '!' && nx == '=') {
                two = MS_T_NotEq;
            } else if (b == '<' && nx == '=') {
                two = MS_T_Le;
            } else if (b == '>' && nx == '=') {
                two = MS_T_Ge;
            }
            if (two >= 0) {
                size_t start = s->offset;
                advance(s);
                advance(s);
                emit(s, (MsTok)two, start, start + 2, p);
                continue;
            }
            /* `!` directly after a type-ending character is the Result suffix of `T!` or `T!E`;
             * anywhere else it stays the removed negation. */
            bool result_suffix = false;
            if (b == '!' && s->offset > 0 && ntokens(s) != 0) {
                int lk = last_kind(s);
                uint8_t pb = s->src[s->offset - 1];
                result_suffix =
                    (lk == MS_T_Name || lk == MS_T_RBracket || lk == MS_T_RParen ||
                     lk == MS_T_Question || lk == MS_T_Bang) &&
                    (letter(pb) || digit(pb) || pb == ']' || pb == ')' || pb == '?' || pb == '!');
            }
            MsTok kind;
            switch (b) {
            case '!':
                if (!result_suffix) {
                    goto unexpected;
                }
                kind = MS_T_Bang;
                break;
            case '(': kind = MS_T_LParen; break;
            case ')': kind = MS_T_RParen; break;
            case '[': kind = MS_T_LBracket; break;
            case ']': kind = MS_T_RBracket; break;
            case '{': kind = MS_T_LBrace; break;
            case '}': kind = MS_T_RBrace; break;
            case ':': kind = MS_T_Colon; break;
            case ',': kind = MS_T_Comma; break;
            case '.': kind = MS_T_Dot; break;
            case '?': kind = MS_T_Question; break;
            case '+': kind = MS_T_Plus; break;
            case '-': kind = MS_T_Minus; break;
            case '*': kind = MS_T_Star; break;
            case '/': kind = MS_T_Slash; break;
            case '%': kind = MS_T_Percent; break;
            case '<': kind = MS_T_Lt; break;
            case '>': kind = MS_T_Gt; break;
            case '=': kind = MS_T_Assign; break;
            case '&': kind = MS_T_Amp; break;
            case '|': kind = MS_T_Pipe; break;
            default:
            unexpected: {
                if (b >= 0x80) {
                    uint32_t c;
                    ms_utf8_decode(s->text + s->offset, n - s->offset, &c);
                    MsStr q = quote_rune_str(s, c);
                    FAILF(s, "unexpected source character %.*s; non-ASCII characters are only allowed inside text and comments, and identifiers are ASCII",
                          (int)q.len, q.ptr);
                }
                MsStr q = quote_rune_str(s, b);
                const char *replacement = NULL;
                if (b == ';' && trailing_semicolon(s)) {
                    replacement = ""; /* removing a mid-line `;` would fuse two statements */
                } else if (b == '!') {
                    replacement = "not ";
                } else if (b == '#') {
                    replacement = "//";
                }
                fail_char(s, ms_arena_fmt(s->arena, "unexpected source character %.*s%s", (int)q.len, q.ptr,
                                          character_hint(b)), replacement);
            }
            }
            if (b == '(' || b == '[' || b == '{') {
                VPUSH(s->delimiters, char, (char)b);
                VPUSH(s->opened, MsPos, p);
                if (b == '(' && last_kind(s) == MS_T_Var) {
                    VPUSH(s->groups, size_t, VLEN(s->delimiters, char));
                }
            }
            if (b == ')' || b == ']' || b == '}') {
                if (s->virtual_paren && VLEN(s->delimiters, char) == 1 && VAT(s->delimiters, char, 0) == '(' && b == ')') {
                    /* The physical wrapper would leave its own closing parenthesis unmatched; use
                     * that path for its exact error. */
                    FAIL(s, "interpolation closes the virtual parenthesis");
                }
                if (VLEN(s->delimiters, char) == 0) {
                    /* A lone `}` left behind by a braced block is removed by the fix. */
                    const char *fix = (b == '}' && trailing_semicolon(s)) ? "" : NULL;
                    fail_char(s, ms_arena_fmt(s->arena, "unmatched closing delimiter '%c'; remove it or add the matching opener before it", b), fix);
                }
                if (VLEN(s->levels, Level) > 1 && VLEN(s->delimiters, char) <= top_depth && leading >= top_indent) {
                    FAIL(s, "an outer delimiter cannot close inside a function suite; close the bracket on the line where the function body ends, or dedent the body");
                }
                char open = VLAST(s->delimiters, char);
                char want = open == '(' ? ')' : open == '[' ? ']' : '}';
                if ((char)b != want) {
                    MsPos where_ = VLAST(s->opened, MsPos);
                    FAILF(s, "mismatched closing delimiter '%c'; the '%c' opened at line %u:%u needs '%c'",
                          b, open, where_.line, where_.column, want);
                }
                if (VLEN(s->groups, size_t) != 0 && VLAST(s->groups, size_t) == VLEN(s->delimiters, char)) {
                    VPOP(s->groups, size_t);
                }
                VPOP(s->delimiters, char);
                VPOP(s->opened, MsPos);
                while (VLEN(s->function_depths, size_t) != 0 &&
                       VLAST(s->function_depths, size_t) > VLEN(s->delimiters, char)) {
                    VPOP(s->function_depths, size_t);
                }
            }
            size_t start = s->offset;
            advance(s);
            emit(s, kind, start, start + 1, p);
        }
        if (s->virtual_paren && s->offset == n) {
            if (!(VLEN(s->delimiters, char) == 1 && VAT(s->delimiters, char, 0) == '(')) {
                /* The wrapper's closing parenthesis reports this error. */
                FAIL(s, "interpolation leaves a delimiter open");
            }
            VPOP(s->delimiters, char);
            VPOP(s->opened, MsPos);
            s->groups.len = 0;
            s->function_depths.len = 0;
            emit_layout(s, MS_T_RParen);
        }
        if (ntokens(s) > line_start) {
            int lk = last_kind(s);
            bool has_function = false;
            for (size_t i = 0; i < VLEN(s->function_depths, size_t); i++) {
                if (VAT(s->function_depths, size_t, i) == VLEN(s->delimiters, char)) {
                    has_function = true;
                    break;
                }
            }
            if (lk == MS_T_Colon && (VLEN(s->delimiters, char) == top_depth || has_function)) {
                pending = true;
                header_indent = leading;
                header_start = statement_indent;
                pending_depth = VLEN(s->delimiters, char);
                emit_layout(s, MS_T_Newline);
                s->function_depths.len = 0;
            } else if (VLEN(s->delimiters, char) == top_depth) {
                s->function_depths.len = 0;
                if (continues_next(s)) {
                    continuing = true;
                } else {
                    emit_layout(s, MS_T_Newline);
                }
            } else if (VLEN(s->groups, size_t) != 0 && VLAST(s->groups, size_t) == VLEN(s->delimiters, char)) {
                /* A `var (` group holds one binding per line, so its lines end like statements
                 * even though a delimiter is open. */
                emit_layout(s, MS_T_Newline);
            }
        }
        if (s->offset < n) {
            advance(s);
        }
    }
    if (pending) {
        emit_layout(s, MS_T_Indent);
        emit_layout(s, MS_T_Dedent);
    }
    if (s->prefixes != NULL) {
        /* Lines consumed by a final multi-line text token are inside it. */
        size_t line = s->line - s->base_line - 1;
        while (s->prefixes->len < line) {
            ms_buf_putc(s->prefixes, 1);
        }
        ms_buf_putc(s->prefixes, VLEN(s->delimiters, char) != 0);
    }
    if (VLEN(s->delimiters, char) != 0) {
        char open = VLAST(s->delimiters, char);
        MsPos where_ = VLAST(s->opened, MsPos);
        char close = open == '(' ? ')' : open == '[' ? ']' : '}';
        MsDiag *d = new_diag(s, spos(s),
            ms_arena_fmt(s->arena, "unterminated delimiter '%c' opened at line %u:%u; add the matching '%c' before the end of the file",
                         open, where_.line, where_.column, close));
        d->opener_line = where_.line;
        throw_diag(s);
    }
    while (VLEN(s->levels, Level) > 1) {
        VPOP(s->levels, Level);
        emit_layout(s, MS_T_Dedent);
    }
    emit_layout(s, MS_T_Eof);
}

/* ---- entry points ---- */

static int range_cmp(const void *a, const void *b) {
    size_t x = ((const MsRange *)a)->start, y = ((const MsRange *)b)->start;
    return x < y ? -1 : x > y;
}

static void scanner_init(Scanner *s, MsArena *arena, const char *text, size_t len, uint32_t base_offset,
                         uint32_t base_line, const uint32_t *line_offsets, MsDiag *diag) {
    memset(s, 0, sizeof *s);
    s->arena = arena;
    s->text = text;
    s->src = (const uint8_t *)text;
    s->n = len;
    s->line = base_line + 1;
    s->base_line = base_line;
    s->base_offset = base_offset;
    s->column = 1;
    s->line_offsets = line_offsets;
    s->diag = diag;
    Level base = {0, 0};
    VPUSH(s->levels, Level, base);
}

static void scanner_free(Scanner *s) {
    ms_buf_free(&s->tokens);
    ms_buf_free(&s->levels);
    ms_buf_free(&s->delimiters);
    ms_buf_free(&s->groups);
    ms_buf_free(&s->opened);
    ms_buf_free(&s->function_depths);
    ms_buf_free(&s->interpolations);
    ms_buf_free(&s->strings);
    ms_buf_free(&s->interps);
    ms_buf_free(&s->blocks);
}

static void *copy_out(MsArena *a, const MsBuf *b, size_t align) {
    void *p = ms_alloc(a, b->len ? b->len : 1, align);
    if (b->len != 0) {
        memcpy(p, b->data, b->len);
    }
    return p;
}

/* Replaces CRLF with LF and records, per normalised line, how many CR bytes precede it. */
static const char *normalize(MsArena *a, const char *src, size_t len, size_t *out_len, uint32_t **offsets) {
    *offsets = NULL;
    bool crlf = false;
    size_t newlines = 0;
    for (size_t i = 0; i < len; i++) {
        if (src[i] == '\n') {
            newlines++;
            if (i > 0 && src[i - 1] == '\r') {
                crlf = true;
            }
        }
    }
    if (!crlf) {
        *out_len = len;
        return src;
    }
    char *dst = ms_alloc(a, len + 1, 1);
    uint32_t *offs = MS_NEW_N(a, uint32_t, newlines + 1);
    size_t w = 0, k = 0;
    uint32_t removed = 0;
    offs[k++] = 0;
    for (size_t i = 0; i < len; i++) {
        if (src[i] == '\r' && i + 1 < len && src[i + 1] == '\n') {
            continue; /* the LF follows */
        }
        dst[w++] = src[i];
        if (src[i] == '\n') {
            if (i > 0 && src[i - 1] == '\r') {
                removed++;
            }
            offs[k++] = removed;
        }
    }
    dst[w] = 0;
    *out_len = w;
    *offsets = offs;
    return dst;
}

static bool lex_run(MsArena *arena, const char *text, size_t nlen, uint32_t base_offset, uint32_t base_line,
                    uint32_t *offsets, MsLexed *out, MsDiag *diag) {
    Scanner s;
    scanner_init(&s, arena, text, nlen, base_offset, base_line, offsets, diag);
    if (setjmp(s.jb) != 0) {
        scanner_free(&s);
        return false;
    }
    run(&s);
    if (s.strings.len != 0) {
        qsort(s.strings.data, VLEN(s.strings, MsRange), sizeof(MsRange), range_cmp);
    }
    if (s.interps.len != 0) {
        qsort(s.interps.data, VLEN(s.interps, MsRange), sizeof(MsRange), range_cmp);
    }
    out->source = text;
    out->source_len = nlen;
    out->tokens = copy_out(arena, &s.tokens, _Alignof(MsToken));
    out->ntokens = ntokens(&s);
    out->blocks = copy_out(arena, &s.blocks, _Alignof(MsRange));
    out->nblocks = VLEN(s.blocks, MsRange);
    out->bounds.strings = copy_out(arena, &s.strings, _Alignof(MsRange));
    out->bounds.nstrings = VLEN(s.strings, MsRange);
    out->bounds.interps = copy_out(arena, &s.interps, _Alignof(MsRange));
    out->bounds.ninterps = VLEN(s.interps, MsRange);
    out->bounds.line_offsets = offsets;
    out->bounds.base_line = base_line;
    scanner_free(&s);
    return true;
}

bool ms_lex_at(MsArena *arena, const char *src, size_t len, uint32_t base_offset, uint32_t base_line,
               MsLexed *out, MsDiag *diag) {
    memset(out, 0, sizeof *out);
    if (!ms_utf8_valid(src, len)) {
        memset(diag, 0, sizeof *diag);
        diag->pos = (MsPos){0, 1, 1};
        diag->message = LIT("source must be valid UTF-8; re-save the file with UTF-8 encoding");
        return false;
    }
    if (len >= 3 && memcmp(src, "\xEF\xBB\xBF", 3) == 0) {
        memset(diag, 0, sizeof *diag);
        diag->pos = (MsPos){base_offset, base_line + 1, 1};
        diag->message = LIT("a byte-order mark is not allowed; save the file as UTF-8 without BOM");
        return false;
    }
    size_t nlen;
    uint32_t *offsets;
    const char *text = normalize(arena, src, len, &nlen, &offsets);
    return lex_run(arena, text, nlen, base_offset, base_line, offsets, out, diag);
}

bool ms_lex(MsArena *arena, const char *src, size_t len, MsLexed *out, MsDiag *diag) {
    return ms_lex_at(arena, src, len, 0, 0, out, diag);
}

bool ms_lex_interpolation(MsArena *arena, const char *src, size_t len, size_t origin,
                          const MsBounds *bounds, MsToken **tokens, size_t *count, MsDiag *diag) {
    Scanner s;
    scanner_init(&s, arena, src, len, 0, 0, NULL, diag);
    s.cached = bounds;
    s.boundary_origin = origin;
    s.virtual_paren = true;
    VPUSH(s.delimiters, char, '(');
    VPUSH(s.opened, MsPos, ((MsPos){0, 1, 1}));
    if (setjmp(s.jb) != 0) {
        scanner_free(&s);
        return false;
    }
    run(&s);
    size_t nt = ntokens(&s);
    size_t closing = nt - 3;
    memmove(tokat(&s, closing), tokat(&s, closing + 1), (nt - closing - 1) * sizeof(MsToken));
    s.tokens.len -= sizeof(MsToken);
    *tokens = copy_out(arena, &s.tokens, _Alignof(MsToken));
    *count = ntokens(&s);
    scanner_free(&s);
    return true;
}

/* ---- editor recovery ---- */

static size_t count_newlines(const char *src, size_t len) {
    size_t n = 0;
    for (size_t i = 0; i < len; i++) {
        n += src[i] == '\n';
    }
    return n;
}

bool *ms_unterminated_prefixes(MsArena *arena, const char *src, size_t len, const bool *stop_at,
                               size_t nstop, size_t *count) {
    size_t lines = count_newlines(src, len) + 1;
    bool *out = MS_NEW_N(arena, bool, lines);
    memset(out, 0, lines);
    *count = lines;
    if (len >= 3 && memcmp(src, "\xEF\xBB\xBF", 3) == 0) {
        return out;
    }
    size_t nlen;
    uint32_t *offsets;
    const char *text = normalize(arena, src, len, &nlen, &offsets);
    MsDiag diag;
    MsBuf prefixes = {0};
    Scanner s;
    scanner_init(&s, arena, text, nlen, 0, 0, offsets, &diag);
    s.prefixes = &prefixes;
    s.stop_at = stop_at;
    s.nstop = nstop;
    if (setjmp(s.jb) == 0) {
        run(&s);
    }
    for (size_t i = 0; i < lines && i < prefixes.len; i++) {
        out[i] = ((const bool *)prefixes.data)[i];
    }
    scanner_free(&s);
    ms_buf_free(&prefixes);
    return out;
}

/* Recovery looks only at where a text ends; its lexical errors are the strict parse's to report. */
static void scan_string_ignoring_errors(Scanner *s, bool formatted) {
    if (setjmp(s->jb) == 0) {
        scan_string(s, formatted);
    }
}

bool *ms_recovery_continuations(MsArena *arena, const char *src, size_t len, const bool *roots,
                                size_t nroots, size_t *count) {
    size_t lines = count_newlines(src, len) + 1;
    bool *out = MS_NEW_N(arena, bool, lines);
    memset(out, 0, lines);
    *count = lines;
    size_t nlen;
    uint32_t *offsets;
    const char *text = normalize(arena, src, len, &nlen, &offsets);
    MsDiag diag;
    Scanner s;
    scanner_init(&s, arena, text, nlen, 0, 0, offsets, &diag);
    size_t depth = 0;
    bool invalid_text_header = false;
    uint32_t leading_line = 0;
    size_t first_token = 0;
    while (s.offset < s.n) {
        size_t first = s.line - 1;
        if (s.column == 1 && first < nroots && roots[first]) {
            depth = 0;
        }
        if (at_line_comment(&s)) {
            while (s.offset < s.n && s.src[s.offset] != '\n') {
                advance(&s);
            }
        } else if (at_block_comment(&s)) {
            advance(&s);
            advance(&s);
            /* Comments do not nest. Even a malformed comment remains opaque up to its first
             * closer (or EOF); strict lexing reports the error. */
            while (s.offset < s.n) {
                if (starts_with(&s, s.offset, "*/")) {
                    advance(&s);
                    advance(&s);
                    break;
                }
                advance(&s);
            }
        } else if (starts_with(&s, s.offset, "f\"") &&
                   !(s.offset > 0 && (letter(s.src[s.offset - 1]) || digit(s.src[s.offset - 1])))) {
            /* The prefix of interpolating text; the quote is handled next. */
            advance(&s);
        } else if (starts_with(&s, s.offset, "r\"") && !starts_with(&s, s.offset + 2, "\"\"") &&
                   !(s.offset > 0 && (letter(s.src[s.offset - 1]) || digit(s.src[s.offset - 1])))) {
            /* One-line raw text ends at its first quote; no escapes. */
            advance(&s);
            advance(&s);
            while (s.offset < s.n) {
                uint8_t byte = advance(&s);
                if (byte == '"' || byte == '\n') {
                    break;
                }
            }
        } else if (starts_with(&s, s.offset, "r\"\"\"") || starts_with(&s, s.offset, "\"\"\"")) {
            bool raw = s.src[s.offset] == 'r';
            if (leading_line != s.line) {
                leading_line = s.line;
                size_t line_start = s.offset - (s.column - 1);
                size_t k = line_start;
                while (k < s.n && (s.src[k] == ' ' || s.src[k] == '\t')) {
                    k++;
                }
                first_token = k;
            }
            bool standalone = s.offset == first_token;
            for (int k = 0; k < (raw ? 4 : 3); k++) {
                advance(&s);
            }
            /* A malformed header's standalone closer must not become a fresh opener. A literal in
             * a new expression (including a standalone delimiter continuation) supersedes that
             * malformed header. */
            bool body = at(&s, s.offset) == '\n';
            bool closing_invalid = invalid_text_header && standalone && !raw && depth == 0;
            invalid_text_header = !body;
            if (body && !closing_invalid) {
                while (s.offset < s.n) {
                    if (starts_with(&s, s.offset, "\"\"\"")) {
                        for (int k = 0; k < 3; k++) {
                            advance(&s);
                        }
                        break;
                    }
                    uint8_t byte = advance(&s);
                    if (!raw && byte == '\\' && s.offset < s.n) {
                        advance(&s);
                    }
                }
            }
        } else if (s.src[s.offset] == '"') {
            bool formatted = s.offset > 0 && s.src[s.offset - 1] == 'f' &&
                             !(s.offset > 1 && (letter(s.src[s.offset - 2]) || digit(s.src[s.offset - 2])));
            scan_string_ignoring_errors(&s, formatted);
        } else {
            uint8_t b = advance(&s);
            if (b == '(' || b == '[' || b == '{') {
                depth++;
            } else if ((b == ')' || b == ']' || b == '}') && depth > 0) {
                depth--;
            }
        }
        /* An invalid single-line string may consume its newline before failing; the following
         * line still starts independently. */
        size_t last = s.line - 1 - (s.column == 1);
        for (size_t i = first + 1; i <= last && i < lines; i++) {
            out[i] = true;
        }
    }
    scanner_free(&s);
    return out;
}
