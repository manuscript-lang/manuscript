/* The lexer with layout. A port of crates/ms-syntax/src/lexer.rs: the same tokens, the same
 * messages, the same positions. A scan function that fails records the diagnostic and returns
 * false, and every caller passes the false on; everything is allocated from the caller's arena, so
 * nothing needs cleaning up. */
#include <stdlib.h>
#include <string.h>

#include "ms/lex.h"
#include "ms_rt/chars.h"

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
    MsDiag *diag;
} Scanner;


static bool bindigit(uint8_t b) {
    return b == '0' || b == '1';
}
static bool graphic(uint8_t b) {
    return b > 0x20 && b < 0x7f;
}
static bool is_word_byte(uint8_t b) {
    return ms_ascii_is_ident_start(b) || ms_ascii_is_digit(b);
}

/* ---- errors ---- */

static MsPos spos(const Scanner *s) {
    uint32_t offset = (uint32_t)s->offset + s->base_offset;
    if (s->line_offsets != NULL) {
        offset += s->line_offsets[s->line - s->base_line - 1];
    }
    return (MsPos){.offset = offset, .line = s->line, .column = s->column};
}

/* Starts the diagnostic for the scan in progress; the caller fills the optional range and fix. */
static MsDiag *new_diag(Scanner *s, MsPos pos, MsStr message) {
    memset(s->diag, 0, sizeof *s->diag);
    s->diag->pos = pos;
    s->diag->message = message;
    return s->diag;
}

/* The fail_* functions record a diagnostic and return false, so a scanner function reports its
 * failure with `return fail_...(...)` and every caller passes that false on. */
static bool fail_at_str(Scanner *s, MsPos pos, MsStr message) {
    new_diag(s, pos, message);
    return false;
}

static bool fail_str(Scanner *s, MsStr message) {
    return fail_at_str(s, spos(s), message);
}

static bool fail_fmt(Scanner *s, const char *format, ...) MS_PRINTF(2, 3);
static bool fail_fmt(Scanner *s, const char *format, ...) {
    va_list args;
    va_start(args, format);
    MsStr message = ms_arena_vfmt(s->arena, format, args);
    va_end(args);
    return fail_str(s, message);
}

static bool fail_at_fmt(Scanner *s, MsPos pos, const char *format, ...) MS_PRINTF(3, 4);
static bool fail_at_fmt(Scanner *s, MsPos pos, const char *format, ...) {
    va_list args;
    va_start(args, format);
    MsStr message = ms_arena_vfmt(s->arena, format, args);
    va_end(args);
    return fail_at_str(s, pos, message);
}

#define LIT(text) ((MsStr){(text), (uint32_t)(sizeof(text) - 1)})

/* Reports a character whose first byte was just consumed: the cursor may be inside its UTF-8
 * encoding, so it is not itself a diagnostic boundary. */
static bool fail_previous_byte(Scanner *s, MsStr message) {
    MsPos pos = spos(s);
    pos.offset -= 1;
    pos.column -= 1;
    return fail_at_str(s, pos, message);
}

/* Fails on the single ASCII character at the cursor, with its range and the fix when one exists. */
static bool fail_char(Scanner *s, MsStr message, const char *replacement) {
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
    return false;
}

/* Fails on the source range [start, cursor). */
static bool fail_range(Scanner *s, MsPos start, MsStr message) {
    MsDiag *d = new_diag(s, start, message);
    d->has_end = true;
    d->end = spos(s);
    return false;
}

/* ---- Rust's `{:?}` for a char ---- */

static const uint32_t debug_escaped[][2] = {
#include "syntax/unicode_debug.inc"
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
    return i <= s->n && ms_bytes_starts_with(ms_bytes_of((const uint8_t *)s->src + i, s->n - i), ms_bytes_of((const uint8_t *)lit, strlen(lit)));
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
    MS_VEC_PUSH(s->tokens, MsToken, t);
}

static void emit_layout(Scanner *s, MsTok kind) {
    MsPos p = spos(s);
    MsToken t = {p, p, (uint32_t)s->offset, (uint32_t)s->offset, (uint8_t)kind};
    MS_VEC_PUSH(s->tokens, MsToken, t);
}

static size_t ntokens(const Scanner *s) {
    return MS_VEC_LEN(s->tokens, MsToken);
}
static MsToken *tokat(const Scanner *s, size_t i) {
    return &MS_VEC_AT(s->tokens, MsToken, i);
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

MS_NODISCARD static bool skip_comment(Scanner *s) {
    while (s->offset < s->n && s->src[s->offset] != '\n') {
        if (s->src[s->offset] == '\r') {
            return fail_str(s, LIT("lone carriage returns are not allowed in comments; use line endings of LF or CRLF"));
        }
        if (bidi_control_at(s, s->offset)) {
            return fail_str(s, LIT(BIDI_COMMENT));
        }
        advance(s);
    }
    return true;
}

/* Consumes a block comment, which does not nest, and the blanks and optional `//` comment after
 * its `*​/`; the cursor ends at the line's newline. */
MS_NODISCARD static bool skip_block_comment(Scanner *s) {
    MsPos open = spos(s);
    size_t start = s->offset;
    advance(s);
    advance(s);
    for (;;) {
        if (s->offset >= s->n) {
            return fail_at_str(s, open, LIT("unterminated block comment; close it with '*/'"));
        }
        uint8_t b = s->src[s->offset];
        if (b == '*' && at(s, s->offset + 1) == '/') {
            advance(s);
            advance(s);
            MsRange r = {start, s->offset};
            MS_VEC_PUSH(s->blocks, MsRange, r);
            break;
        }
        if (b == '/' && at(s, s->offset + 1) == '*') {
            return fail_str(s, LIT("block comments do not nest; remove the inner '/*'"));
        }
        if (b == '\r') {
            return fail_str(s, LIT("lone carriage returns are not allowed in comments; use line endings of LF or CRLF"));
        }
        if (bidi_control_at(s, s->offset)) {
            return fail_str(s, LIT(BIDI_COMMENT));
        }
        advance(s);
    }
    while (s->offset < s->n && s->src[s->offset] == ' ') {
        advance(s);
    }
    if (s->offset < s->n && at_line_comment(s)) {
        if (!skip_comment(s)) {
            return false;
        }
        return true;
    }
    if (s->offset < s->n && s->src[s->offset] != '\n') {
        return fail_str(s, LIT("code cannot follow a block comment on the same line; start a new line"));
    }
    return true;
}

/* ---- numbers ---- */

/* Consumes digits accepted by `ok`, allowing `_` only between two digits. */
MS_NODISCARD static bool scan_digits(Scanner *s, bool (*ok)(uint8_t), bool after_digit) {
    while (s->offset < s->n) {
        uint8_t b = s->src[s->offset];
        if (ok(b)) {
            after_digit = true;
        } else if (b == '_') {
            bool next_ok = s->offset + 1 < s->n && ok(s->src[s->offset + 1]);
            if (!after_digit || !next_ok) {
                return fail_str(s, LIT("a digit separator goes between two digits; write e.g. 1_000_000 or 0xFF_FF"));
            }
            after_digit = false;
        } else {
            break;
        }
        advance(s);
    }
    return true;
}

/* A `0x` or `0b` literal: the prefix is at the cursor's `start`, `ok` accepts its digits. */
MS_NODISCARD static bool scan_radix_number(Scanner *s, MsPos p, size_t start, bool (*ok)(uint8_t)) {
    advance(s);
    if (s->offset == s->n || !ok(s->src[s->offset])) {
        return fail_str(s, LIT("a hexadecimal or binary literal requires digits after the prefix; write e.g. 0xFF or 0b1010"));
    }
    if (!scan_digits(s, ok, false)) {
        return false;
    }
    if (s->offset < s->n && is_word_byte(s->src[s->offset])) {
        return fail_str(s, LIT("invalid digit in a hexadecimal or binary literal; 0x takes 0-9 and a-f, 0b takes 0 and 1"));
    }
    emit(s, MS_T_Number, start, s->offset, p);
    return true;
}

/* The digits after the `e` of a floating-point exponent, with an optional sign. */
MS_NODISCARD static bool scan_exponent(Scanner *s) {
    advance(s);
    if (s->offset < s->n && (s->src[s->offset] == '+' || s->src[s->offset] == '-')) {
        advance(s);
    }
    if (s->offset == s->n || !ms_ascii_is_digit(s->src[s->offset])) {
        return fail_str(s, LIT("an exponent requires digits; write e.g. 1e3 or 2.5e-4"));
    }
    while (s->offset < s->n && ms_ascii_is_digit(s->src[s->offset])) {
        advance(s);
    }
    return true;
}

static bool word_has_prefix(const char *word, size_t length, const char *a, const char *b) {
    return length > 1 && (memcmp(word, a, 2) == 0 || memcmp(word, b, 2) == 0);
}

/* A number followed by letters: names what went wrong from the whole word. */
static bool fail_number_suffix(Scanner *s, MsPos p, size_t start) {
    while (s->offset < s->n && is_word_byte(s->src[s->offset])) {
        advance(s);
    }
    const char *word = s->text + start;
    size_t length = s->offset - start;
    if (word_has_prefix(word, length, "0X", "0B")) {
        MsStr message = ms_arena_fmt(s->arena,
            "invalid number %.*s; the prefix is lowercase, so write 0%c%.*s",
            (int)length, word, word[1] + ('a' - 'A'), (int)(length - 2), word + 2);
        return fail_range(s, p, message);
    }
    const char *reason = NULL;
    if (word_has_prefix(word, length, "0o", "0O")) {
        reason = "octal literals do not exist, so write the value in decimal, hexadecimal (0x) or binary (0b)";
    } else if (memchr(word, '_', length) != NULL) {
        reason = "a digit separator goes between two digits of the integer or fraction part, e.g. 1_000_000";
    } else {
        reason = "the only numeric suffix is d for Decimal (1.5d), so put a space or operator after the number";
    }
    return fail_range(s, p, ms_arena_fmt(s->arena, "invalid number %.*s; %s", (int)length, word, reason));
}

MS_NODISCARD static bool scan_number(Scanner *s, MsPos p) {
    size_t start = s->offset;
    advance(s);
    bool zero = s->src[start] == '0' && s->offset < s->n;
    if (zero && s->src[s->offset] == 'x') {
        return scan_radix_number(s, p, start, ms_ascii_is_hex);
    }
    if (zero && s->src[s->offset] == 'b') {
        return scan_radix_number(s, p, start, bindigit);
    }
    if (zero && (ms_ascii_is_digit(s->src[s->offset]) || s->src[s->offset] == '_')) {
        return fail_str(s, LIT("leading zeros are not allowed in numeric literals; write the number without them, e.g. 42 instead of 042"));
    }
    if (!scan_digits(s, ms_ascii_is_digit, true)) {
        return false;
    }
    if (s->offset + 1 < s->n && s->src[s->offset] == '.' && ms_ascii_is_digit(s->src[s->offset + 1])) {
        advance(s);
        if (!scan_digits(s, ms_ascii_is_digit, false)) {
            return false;
        }
    }
    if (s->offset < s->n && (s->src[s->offset] == 'e' || s->src[s->offset] == 'E') && !scan_exponent(s)) {
        return false;
    }
    if (s->offset < s->n && s->src[s->offset] == 'd') {
        advance(s);
    }
    if (s->offset < s->n && ms_ascii_is_ident_start(s->src[s->offset])) {
        return fail_number_suffix(s, p, start);
    }
    emit(s, MS_T_Number, start, s->offset, p);
    return true;
}

/* ---- text ---- */

MS_NODISCARD static bool scan_string(Scanner *s, bool interpolating);
MS_NODISCARD static bool scan_multiline(Scanner *s, bool raw, bool interpolating);

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
MS_NODISCARD static bool scan_escape(Scanner *s, bool interpolating) {
    size_t n = s->n;
    MsPos backslash = spos(s);
    backslash.column -= 1;
    backslash.offset -= 1;
    if (s->offset == n) {
        return fail_str(s, LIT("unterminated text escape; a backslash needs a following character, e.g. \\n"));
    }
    uint8_t c = advance(s);
    if (c == 'u') {
        if (s->offset == n || advance(s) != '{') {
            MsStr message = LIT("Unicode escapes use \\u{H}; write 1 to 6 hexadecimal digits in braces, e.g. \\u{1F600}");
            if (s->src[s->offset - 1] < 0x80) {
                return fail_str(s, message);
            }
            return fail_previous_byte(s, message);
        }
        size_t start = s->offset;
        uint64_t value = 0;
        while (s->offset < n && s->src[s->offset] != '}') {
            uint8_t ch = advance(s);
            uint32_t d = 0;
            if (!ms_hex_digit_value(ch, &d)) {
                MsStr message = LIT("invalid Unicode scalar escape; use only hexadecimal digits 0-9 and a-f inside \\u{...}");
                if (ch < 0x80) {
                    return fail_str(s, message);
                }
                return fail_previous_byte(s, message);
            }
            /* saturating_mul(16).saturating_add(d) */
            value = value > (UINT64_MAX - d) / 16 ? UINT64_MAX : value * 16 + d;
        }
        size_t digits = s->offset - start;
        if (s->offset == n || digits < 1 || digits > 6 || value > 0x10ffff ||
            (value >= 0xd800 && value <= 0xdfff)) {
            return fail_str(s, LIT("invalid Unicode scalar escape; use 1 to 6 hexadecimal digits for a value up to 10FFFF that is not a surrogate (D800-DFFF)"));
        }
        advance(s);
    } else if (!interpolating && (c == '{' || c == '}')) {
        return fail_at_str(s, backslash, LIT(PLAIN_BRACE_ESCAPE));
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
        return fail_at_fmt(s, backslash,
                 "unknown text escape%.*s; valid escapes are \\n \\t \\r \\\\ \\\" %sand \\u{H}",
                 (int)escape.len, escape.ptr, braces);
    }
    return true;
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

MS_NODISCARD static bool interpolation_body(Scanner *s, MsPos open) {
    size_t n = s->n;
    int depth = 1;
    size_t start = s->offset;
    while (s->offset < n) {
        uint8_t b = s->src[s->offset];
        if (b == '\n' || b == '\r' || at_line_comment(s) || at_block_comment(s)) {
            return fail_at_str(s, open, LIT("newlines and comments are not allowed inside interpolation; keep the expression on one line, or bind it to a name first and interpolate the name (" BRACE_HINT ")"));
        }
        if (b == '\\') {
            return fail_at_str(s, open, LIT("a backslash cannot appear in the interpolated expression (" BRACE_HINT ")"));
        }
        if (b == '"') {
            if (!scan_string(s, false)) {
                return false;
            }
            continue;
        }
        bool after_word = s->offset > 0 && (ms_ascii_is_ident_start(s->src[s->offset - 1]) || ms_ascii_is_digit(s->src[s->offset - 1]));
        if (b == 'f' && at(s, s->offset + 1) == '"' && !after_word) {
            advance(s);
            if (!scan_string(s, true)) {
                return false;
            }
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
                    return fail_at_str(s, opened, LIT("unterminated raw text literal; add the closing '\"' on the same line"));
                }
                uint8_t c = advance(s);
                if (c == '"') {
                    break;
                }
                if (c == '\n') {
                    return fail_at_str(s, opened, LIT("unterminated raw text literal; r\"...\" must close on the same line and cannot hold a quote, so add the quote or use r\"\"\" multi-line raw text"));
                }
                if (c < 32) {
                    return fail_str(s, LIT("literal control characters are not allowed in text; use r\"\"\" raw text for tabs, or write an escape such as \\t in non-raw text"));
                }
                if (c == 0xE2 && bidi_control_at(s, s->offset - 1)) {
                    return fail_previous_byte(s, LIT(BIDI_TEXT));
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
                    return fail_str(s, LIT("empty interpolation; put an expression between the braces, or write \\{ for a literal brace"));
                }
                return true;
            }
        }
    }
    return fail_at_str(s, open, LIT("unterminated interpolation; add the closing } before the closing quote (" BRACE_HINT ")"));
    return true;
}

MS_NODISCARD static bool scan_interpolation(Scanner *s) {
    size_t start = s->boundary_origin + s->offset - 1;
    MsPos open = spos(s);
    open.column -= 1;
    open.offset -= 1;
    if (MS_VEC_LEN(s->interpolations, MsPos) >= MAX_INTERPOLATION_DEPTH) {
        return fail_at_fmt(s, open,
                 "nesting exceeds %d levels; split the expression, type, or block into named parts",
                 MAX_INTERPOLATION_DEPTH);
    }
    MS_VEC_PUSH(s->interpolations, MsPos, open);
    if (!interpolation_body(s, open)) {
        return false;
    }
    MS_VEC_POP(s->interpolations, MsPos);
    MsRange r = {start, s->boundary_origin + s->offset};
    MS_VEC_PUSH(s->interps, MsRange, r);
    return true;
}

/* Scans `"..."` text, or `f"..."` text when `interpolating` (the caller has consumed the `f`).
 * Braces are plain characters unless interpolating. */
MS_NODISCARD static bool scan_string(Scanner *s, bool interpolating) {
    size_t start = s->offset;
    if (starts_with(s, start, "\"\"\"")) {
        if (!scan_multiline(s, false, interpolating)) {
            return false;
        }
        return true;
    }
    if (s->cached != NULL) {
        const MsRange *r = find_range(s->cached->strings, s->cached->nstrings, s->boundary_origin + start);
        if (r != NULL) {
            s->column += (uint32_t)(r->end - s->boundary_origin - start);
            s->offset = r->end - s->boundary_origin;
            return true;
        }
    }
    size_t n = s->n;
    MsPos opened = spos(s);
    advance(s);
    while (s->offset < n) {
        uint8_t b = advance(s);
        if (b == '"') {
            if (MS_VEC_LEN(s->interpolations, MsPos) != 0) {
                MsRange r = {s->boundary_origin + start, s->boundary_origin + s->offset};
                MS_VEC_PUSH(s->strings, MsRange, r);
            }
            return true;
        }
        if (b == '\n') {
            if (MS_VEC_LEN(s->interpolations, MsPos) != 0) {
                MsPos brace = MS_VEC_LAST(s->interpolations, MsPos);
                return fail_at_str(s, brace, LIT("unterminated interpolation; the quote after this '{' opens a nested text that never closes (" BRACE_HINT ")"));
            }
            return fail_at_str(s, opened, LIT("unterminated text literal; text must close with '\"' on the same line, so add the quote or write \\n for a line break"));
        }
        if (b < 32) {
            return fail_str(s, LIT("literal control characters are not allowed in text; write an escape such as \\t, \\r, or \\u{H}"));
        }
        if (b == 0xE2 && bidi_control_at(s, s->offset - 1)) {
            return fail_previous_byte(s, LIT(BIDI_TEXT));
        }
        if (b == '\\') {
            if (!scan_escape(s, interpolating)) {
                return false;
            }
        } else if (interpolating && b == '{') {
            if (!scan_interpolation(s)) {
                return false;
            }
        } else if (interpolating && b == '}') {
            return fail_str(s, LIT(UNMATCHED_BRACE));
        }
    }
    return fail_at_str(s, opened, LIT("unterminated text literal; add the closing '\"' on the same line"));
    return true;
}

/* Scans one-line raw text `r"..."`: every character is literal up to the first `"`. */
MS_NODISCARD static bool scan_raw_line(Scanner *s) {
    MsPos opened = spos(s);
    advance(s);
    advance(s);
    while (s->offset < s->n) {
        uint8_t b = advance(s);
        if (b == '"') {
            return true;
        }
        if (b == '\n') {
            return fail_at_str(s, opened, LIT("unterminated raw text literal; r\"...\" must close on the same line and cannot hold a quote, so add the quote or use r\"\"\" multi-line raw text"));
        }
        if (b < 32) {
            return fail_str(s, LIT("literal control characters are not allowed in text; use r\"\"\" raw text for tabs, or write an escape such as \\t in non-raw text"));
        }
        if (b == 0xE2 && bidi_control_at(s, s->offset - 1)) {
            return fail_previous_byte(s, LIT(BIDI_TEXT));
        }
    }
    return fail_at_str(s, opened, LIT("unterminated raw text literal; add the closing '\"' on the same line"));
    return true;
}

typedef struct LinePos {
    size_t at;
    MsPos pos;
} LinePos;

static bool blank_line(const uint8_t *line, size_t length) {
    for (size_t i = 0; i < length; i++) {
        if (line[i] != ' ' && line[i] != '\t') {
            return false;
        }
    }
    return true;
}

/* Every content line must carry the closing line's indentation; `quote` is the closing quotes'
 * offset and `indent_len` that indentation's width. */
static bool check_text_indentation(Scanner *s, const MsBuf *lines, size_t quote, size_t indent_len,
                                   size_t line_start) {
    const uint8_t *indent = s->src + line_start;
    for (size_t k = 0; k < MS_VEC_LEN(*lines, LinePos); k++) {
        LinePos line = MS_VEC_AT(*lines, LinePos, k);
        const uint8_t *rest = s->src + line.at;
        size_t rest_len = s->n - line.at;
        const uint8_t *newline = memchr(rest, '\n', rest_len);
        size_t line_len = newline != NULL ? (size_t)(newline - rest) : rest_len;
        bool has_prefix = line_len >= indent_len && memcmp(rest, indent, indent_len) == 0;
        if (line.at < quote && !blank_line(rest, line_len) && !has_prefix) {
            return fail_at_str(s, line.pos, LIT("text line is indented less than the closing '\"\"\"'; indent it to the closing quotes' column, or move the closing quotes left"));
        }
    }
    return true;
}

/* The cursor is just past the first closing quote: checks the closing line and consumes the rest. */
static bool finish_multiline(Scanner *s, const MsBuf *lines, size_t line_start) {
    size_t quote = s->offset - 1;
    size_t indent_len = quote - line_start;
    if (!blank_line(s->src + line_start, indent_len)) {
        return fail_previous_byte(s, LIT("multi-line text closes with '\"\"\"' alone on its own line; move the closing quotes to a new line (a '\"\"\"' inside the text is not allowed, so write \\\" for a quote in non-raw text)"));
    }
    if (!check_text_indentation(s, lines, quote, indent_len, line_start)) {
        return false;
    }
    advance(s);
    advance(s);
    return true;
}

/* The body of a multi-line text; `lines` collects where each content line starts. */
MS_NODISCARD static bool scan_multiline_body(Scanner *s, bool raw, bool interpolating, MsPos opened,
                                             MsBuf *lines) {
    size_t line_start = s->offset + 1;
    while (s->offset < s->n) {
        uint8_t b = advance(s);
        if (b == '\n') {
            line_start = s->offset;
            MS_VEC_PUSH(*lines, LinePos, ((LinePos){line_start, spos(s)}));
        } else if (b == '"' && starts_with(s, s->offset, "\"\"")) {
            return finish_multiline(s, lines, line_start);
        } else if (b < 32 && b != '\t') {
            return fail_str(s, LIT("literal control characters are not allowed in text; write an escape such as \\t, \\r, or \\u{H}"));
        } else if (b == 0xE2 && bidi_control_at(s, s->offset - 1)) {
            return fail_previous_byte(s, LIT(BIDI_TEXT));
        } else if (raw) {
            continue;
        } else if (b == '\\') {
            if (!scan_escape(s, interpolating)) {
                return false;
            }
        } else if (interpolating && b == '{') {
            if (!scan_interpolation(s)) {
                return false;
            }
        } else if (interpolating && b == '}') {
            return fail_str(s, LIT(UNMATCHED_BRACE));
        }
    }
    return fail_at_str(s, opened, LIT("unterminated multi-line text; close it with '\"\"\"' alone on its own line"));
}

/* Scans `"""` text (and `r"""` raw text when `raw`): the opening quotes end their line, the
 * closing quotes start theirs, and every content line carries the closing line's indentation. */
MS_NODISCARD static bool scan_multiline(Scanner *s, bool raw, bool interpolating) {
    MsPos opened = spos(s);
    if (MS_VEC_LEN(s->interpolations, MsPos) != 0) {
        return fail_str(s, LIT("multi-line text cannot appear inside an interpolation; bind it to a name first and interpolate the name"));
    }
    for (int i = 0; i < (raw ? 4 : 3); i++) {
        advance(s);
    }
    if (s->offset == s->n || s->src[s->offset] != '\n') {
        return fail_at_str(s, opened, LIT("multi-line text must start on the line after its opening '\"\"\"'; add a line break after the opening quotes"));
    }
    MsBuf lines = {0}; /* LinePos */
    bool ok = scan_multiline_body(s, raw, interpolating, opened, &lines);
    ms_buf_free(&lines);
    return ok;
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
            return j + 1 < n && !ms_ascii_is_digit(s->src[j + 1]) && s->src[j + 1] != '.';
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

/* What the layout rules carry from one line to the next. */
typedef struct LineLayout {
    size_t header_indent;    /* indentation of the line that ended with ':' */
    size_t header_start;     /* where that header's statement began, when it spans lines */
    size_t pending_depth;    /* delimiter depth at that header */
    size_t statement_indent; /* indentation of the statement being scanned */
    bool pending;            /* the previous line ended with ':' and a suite may start */
    bool continuing;         /* the next line starts with '.' or '|' and continues this statement */
} LineLayout;

/* What the token scan of one line needs to know about its indentation. */
typedef struct LineInfo {
    size_t leading;
    size_t top_indent; /* indentation of the innermost open suite */
    size_t top_depth;  /* delimiter depth at which that suite opened */
} LineInfo;

static size_t open_delimiters(const Scanner *s) {
    return MS_VEC_LEN(s->delimiters, char);
}

static char closer_of(char open) {
    switch (open) {
    case '(':
        return ')';
    case '[':
        return ']';
    default:
        return '}';
    }
}

/* Recovery's per-line flag: whether a delimiter is open there. */
static void put_prefix_flag(MsBuf *prefixes, bool open) {
    ms_buf_putc(prefixes, open ? '\1' : '\0');
}

/* Lines inside a multi-line text were consumed by one token, so they count as open. */
static void pad_prefix_flags(const Scanner *s) {
    size_t line = s->line - s->base_line - 1;
    while (s->prefixes->len < line) {
        put_prefix_flag(s->prefixes, true);
    }
}

/* In recovery mode, records whether a delimiter is open at the start of this line. Returns true
 * when the pass should stop here. */
static bool prefix_pass_stops(Scanner *s) {
    if (s->prefixes == NULL) {
        return false;
    }
    bool open = open_delimiters(s) != 0;
    pad_prefix_flags(s);
    put_prefix_flag(s->prefixes, open);
    size_t index = s->prefixes->len - 1;
    return index < s->nstop && s->stop_at[index] && !open;
}

/* Measures the indentation: a tab is one indent level of four columns. */
static bool read_leading_space(Scanner *s, size_t *leading) {
    bool spaced = false;
    *leading = 0;
    while (s->offset < s->n && (s->src[s->offset] == ' ' || s->src[s->offset] == '\t')) {
        if (s->src[s->offset] == '\t') {
            if (spaced) {
                return fail_str(s, LIT("a tab cannot follow spaces in indentation; indent with tabs, then align with spaces"));
            }
            advance(s);
            s->column += 3;
            *leading += 4;
        } else {
            advance(s);
            spaced = true;
            *leading += 1;
        }
    }
    return true;
}

/* Consumes a line that holds no code (a comment or an empty line) and sets *skipped. */
static bool skip_blank_line(Scanner *s, bool *skipped) {
    *skipped = true;
    if (at_line_comment(s)) {
        if (!skip_comment(s)) {
            return false;
        }
    } else if (at_block_comment(s)) {
        if (!skip_block_comment(s)) {
            return false;
        }
    } else if (s->src[s->offset] != '\n') {
        *skipped = false;
        return true;
    }
    if (s->offset < s->n) {
        advance(s);
    }
    return true;
}

static bool fail_indent_width(Scanner *s, size_t leading) {
    const char *inside = open_delimiters(s) == 0 ? ""
        : "; a line inside brackets is indented by fours too, so do not align it with the opening bracket";
    return fail_fmt(s, "indentation must be a multiple of four spaces, found %zu; use %zu or %zu%s",
                    leading, leading / 4 * 4, leading / 4 * 4 + 4, inside);
}

/* The line after a ':' header: it opens the suite, or it is an empty declaration suite. */
static bool resolve_pending_suite(Scanner *s, LineLayout *layout, size_t leading, bool *started) {
    if (leading == layout->header_indent + 4) {
        MS_VEC_PUSH(s->levels, Level, ((Level){leading, layout->pending_depth}));
        emit_layout(s, MS_T_Indent);
        *started = true;
    } else if (leading > layout->header_start && leading <= layout->header_indent) {
        return fail_fmt(s, "a suite begins four spaces after the line that ends with ':' (at %zu spaces); indent this line to %zu, or move that closing line back to %zu spaces",
                        layout->header_indent, layout->header_indent + 4, layout->header_start);
    } else if (leading <= layout->header_indent) {
        /* An empty declaration suite has the same layout boundaries as a populated one. */
        emit_layout(s, MS_T_Indent);
        emit_layout(s, MS_T_Dedent);
    } else {
        return fail_fmt(s, "a suite must begin exactly four spaces after its header; the header is at %zu spaces, so indent this line to %zu",
                        layout->header_indent, layout->header_indent + 4);
    }
    layout->pending = false;
    return true;
}

static bool fail_unexpected_indent(Scanner *s, size_t leading, size_t expected) {
    if (missing_colon(s)) {
        return false;
    }
    const char *hint = continuation_hint(s);
    return fail_fmt(s, "unexpected indentation, %zu spaces where %zu are expected; the previous line must end with ':' to open a block (fn, if, else, for, while, match, type, impl headers), otherwise align this line with it%s",
                    leading, expected, hint);
}

/* Closes the suites this line dedents out of, then checks it lines up with the one it is in. */
static bool align_to_level(Scanner *s, size_t leading) {
    /* A continuation line inside delimiters opened within a level does not close that level; only
     * suites opened inside the open delimiters can. */
    while (MS_VEC_LEN(s->levels, Level) > 1) {
        Level top = MS_VEC_LAST(s->levels, Level);
        if (!(leading < top.indent && top.depth >= open_delimiters(s))) {
            break;
        }
        MS_VEC_POP(s->levels, Level);
        emit_layout(s, MS_T_Dedent);
    }
    Level top = MS_VEC_LAST(s->levels, Level);
    if (open_delimiters(s) != top.depth || leading == top.indent) {
        return true;
    }
    if (leading > top.indent) {
        return fail_unexpected_indent(s, leading, top.indent);
    }
    return fail_fmt(s, "inconsistent dedent to %zu spaces; enclosing blocks are indented at %zu or %zu spaces, so align with one of them",
                    leading, top.indent, top.indent >= 4 ? top.indent - 4 : 0);
}

/* Opens or closes suites for a line of code with `leading` columns of indentation. */
static bool apply_layout(Scanner *s, LineLayout *layout, size_t leading) {
    if (!s->virtual_paren && leading % 4 != 0) {
        return fail_indent_width(s, leading);
    }
    if (layout->continuing) {
        if (leading != layout->statement_indent + 4) {
            return fail_fmt(s, "a line starting with '.' or '|' continues the previous statement and must be indented four spaces past it, to %zu spaces, found %zu",
                            layout->statement_indent + 4, leading);
        }
        layout->continuing = false;
        return true;
    }
    if (open_delimiters(s) == MS_VEC_LAST(s->levels, Level).depth) {
        layout->statement_indent = leading;
    }
    bool started_suite = false;
    if (layout->pending && !resolve_pending_suite(s, layout, leading, &started_suite)) {
        return false;
    }
    return started_suite || align_to_level(s, leading);
}

/* ---- tokens ---- */

static void scan_word(Scanner *s, MsPos pos) {
    size_t start = s->offset;
    size_t end = start;
    while (end < s->n && is_word_byte(s->src[end])) {
        end++;
    }
    s->column += (uint32_t)(end - start);
    s->offset = end;
    MsTok kind = ms_tok_from_word(s->text + start, end - start);
    if (ms_tok_is_contextual(kind) && names_a_member(s, end)) {
        kind = MS_T_Name;
    }
    if (kind == MS_T_Fn || kind == MS_T_Match) {
        MS_VEC_PUSH(s->function_depths, size_t, open_delimiters(s));
    }
    emit(s, kind, start, end, pos);
}

static bool scan_raw_text_token(Scanner *s, MsPos pos) {
    size_t start = s->offset;
    bool ok = starts_with(s, s->offset + 1, "\"\"\"") ? scan_multiline(s, true, false) : scan_raw_line(s);
    if (ok) {
        emit(s, MS_T_String, start, s->offset, pos);
    }
    return ok;
}

static bool scan_text_token(Scanner *s, MsPos pos) {
    size_t start = s->offset;
    bool formatted = s->src[start] == 'f';
    if (formatted) {
        advance(s);
    }
    if (!scan_string(s, formatted)) {
        return false;
    }
    emit(s, MS_T_String, start, s->offset, pos);
    return true;
}

/* The two-character operator at the cursor, or -1. */
static int two_char_kind(uint8_t first, int second) {
    switch (first) {
    case '.': return second == '.' ? MS_T_DotDot : -1;
    case '-': return second == '>' ? MS_T_Arrow : -1;
    case ':': return second == '=' ? MS_T_ColonAssign : -1;
    case '=': return second == '=' ? MS_T_EqEq : -1;
    case '!': return second == '=' ? MS_T_NotEq : -1;
    case '<': return second == '=' ? MS_T_Le : -1;
    case '>': return second == '=' ? MS_T_Ge : -1;
    default: return -1;
    }
}

static bool scan_operator_token(Scanner *s, MsPos pos, size_t length, MsTok kind) {
    size_t start = s->offset;
    for (size_t i = 0; i < length; i++) {
        advance(s);
    }
    emit(s, kind, start, start + length, pos);
    return true;
}

/* `!` directly after a type-ending character is the Result suffix of `T!` or `T!E`; anywhere else
 * it stays the removed negation. */
static bool bang_is_result_suffix(const Scanner *s) {
    if (s->offset == 0 || ntokens(s) == 0) {
        return false;
    }
    int last = last_kind(s);
    uint8_t before = s->src[s->offset - 1];
    bool after_type = last == MS_T_Name || last == MS_T_RBracket || last == MS_T_RParen ||
                      last == MS_T_Question || last == MS_T_Bang;
    return after_type && (is_word_byte(before) || before == ']' || before == ')' || before == '?' || before == '!');
}

/* The kind of a single-character token, or MS_T_Eof when the character is not one. */
static MsTok single_char_kind(uint8_t b) {
    switch (b) {
    case '(': return MS_T_LParen;
    case ')': return MS_T_RParen;
    case '[': return MS_T_LBracket;
    case ']': return MS_T_RBracket;
    case '{': return MS_T_LBrace;
    case '}': return MS_T_RBrace;
    case ':': return MS_T_Colon;
    case ',': return MS_T_Comma;
    case '.': return MS_T_Dot;
    case '?': return MS_T_Question;
    case '+': return MS_T_Plus;
    case '-': return MS_T_Minus;
    case '*': return MS_T_Star;
    case '/': return MS_T_Slash;
    case '%': return MS_T_Percent;
    case '<': return MS_T_Lt;
    case '>': return MS_T_Gt;
    case '=': return MS_T_Assign;
    case '&': return MS_T_Amp;
    case '|': return MS_T_Pipe;
    default: return MS_T_Eof;
    }
}

static bool fail_unexpected_char(Scanner *s, uint8_t b) {
    if (b >= 0x80) {
        uint32_t scalar = 0;
        ms_utf8_decode(s->text + s->offset, s->n - s->offset, &scalar);
        MsStr quoted = quote_rune_str(s, scalar);
        return fail_fmt(s, "unexpected source character %.*s; non-ASCII characters are only allowed inside text and comments, and identifiers are ASCII",
                        (int)quoted.len, quoted.ptr);
    }
    MsStr quoted = quote_rune_str(s, b);
    const char *replacement = NULL;
    if (b == ';' && trailing_semicolon(s)) {
        replacement = ""; /* removing a mid-line `;` would fuse two statements */
    } else if (b == '!') {
        replacement = "not ";
    } else if (b == '#') {
        replacement = "//";
    }
    MsStr message = ms_arena_fmt(s->arena, "unexpected source character %.*s%s", (int)quoted.len, quoted.ptr,
                                 character_hint(b));
    return fail_char(s, message, replacement);
}

static void open_delimiter(Scanner *s, MsPos pos, uint8_t b) {
    MS_VEC_PUSH(s->delimiters, char, (char)b);
    MS_VEC_PUSH(s->opened, MsPos, pos);
    if (b == '(' && last_kind(s) == MS_T_Var) {
        MS_VEC_PUSH(s->groups, size_t, open_delimiters(s));
    }
}

static bool close_delimiter(Scanner *s, const LineInfo *info, uint8_t b) {
    if (s->virtual_paren && open_delimiters(s) == 1 && MS_VEC_AT(s->delimiters, char, 0) == '(' && b == ')') {
        /* The physical wrapper would leave its own closing parenthesis unmatched; use that path
         * for its exact error. */
        return fail_str(s, LIT("interpolation closes the virtual parenthesis"));
    }
    if (open_delimiters(s) == 0) {
        /* A lone `}` left behind by a braced block is removed by the fix. */
        const char *fix = (b == '}' && trailing_semicolon(s)) ? "" : NULL;
        MsStr message = ms_arena_fmt(s->arena, "unmatched closing delimiter '%c'; remove it or add the matching opener before it", b);
        return fail_char(s, message, fix);
    }
    if (MS_VEC_LEN(s->levels, Level) > 1 && open_delimiters(s) <= info->top_depth && info->leading >= info->top_indent) {
        return fail_str(s, LIT("an outer delimiter cannot close inside a function suite; close the bracket on the line where the function body ends, or dedent the body"));
    }
    char open = MS_VEC_LAST(s->delimiters, char);
    if ((char)b != closer_of(open)) {
        MsPos opener = MS_VEC_LAST(s->opened, MsPos);
        return fail_fmt(s, "mismatched closing delimiter '%c'; the '%c' opened at line %u:%u needs '%c'",
                        b, open, opener.line, opener.column, closer_of(open));
    }
    if (MS_VEC_LEN(s->groups, size_t) != 0 && MS_VEC_LAST(s->groups, size_t) == open_delimiters(s)) {
        MS_VEC_POP(s->groups, size_t);
    }
    MS_VEC_POP(s->delimiters, char);
    MS_VEC_POP(s->opened, MsPos);
    while (MS_VEC_LEN(s->function_depths, size_t) != 0 && MS_VEC_LAST(s->function_depths, size_t) > open_delimiters(s)) {
        MS_VEC_POP(s->function_depths, size_t);
    }
    return true;
}

/* Scans a punctuation token: an operator, a delimiter, or a character that is not Manuscript. */
static bool scan_symbol(Scanner *s, const LineInfo *info, MsPos pos, uint8_t b) {
    if (b == '.' && at(s, s->offset + 1) == '.' && at(s, s->offset + 2) == '.') {
        return scan_operator_token(s, pos, 3, MS_T_Ellipsis);
    }
    int two = two_char_kind(b, at(s, s->offset + 1));
    if (two >= 0) {
        return scan_operator_token(s, pos, 2, (MsTok)two);
    }
    MsTok kind = single_char_kind(b);
    if (b == '!' && bang_is_result_suffix(s)) {
        kind = MS_T_Bang;
    }
    if (kind == MS_T_Eof) {
        return fail_unexpected_char(s, b);
    }
    if (b == '(' || b == '[' || b == '{') {
        open_delimiter(s, pos, b);
    } else if ((b == ')' || b == ']' || b == '}') && !close_delimiter(s, info, b)) {
        return false;
    }
    return scan_operator_token(s, pos, 1, kind);
}

/* Scans one token or blank at the cursor; sets *line_done when a comment ends the line. */
static bool scan_token(Scanner *s, const LineInfo *info, bool *line_done) {
    uint8_t b = s->src[s->offset];
    MsPos pos = spos(s);
    if (b == ' ') {
        advance(s);
        return true;
    }
    if (at_line_comment(s)) {
        *line_done = true;
        return skip_comment(s);
    }
    if (at_block_comment(s)) {
        return fail_str(s, LIT("a block comment must start its own line; write a trailing comment with '//'"));
    }
    if (b == '\t' || b == '\r') {
        return fail_str(s, LIT("tabs are allowed only in indentation, and lone carriage returns not at all; use spaces between tokens, and line endings of LF or CRLF"));
    }
    if (b == 'r' && at(s, s->offset + 1) == '"') {
        return scan_raw_text_token(s, pos);
    }
    if (b == '"' || (b == 'f' && at(s, s->offset + 1) == '"')) {
        return scan_text_token(s, pos);
    }
    if (ms_ascii_is_ident_start(b)) {
        scan_word(s, pos);
        return true;
    }
    if (ms_ascii_is_digit(b)) {
        return scan_number(s, pos);
    }
    return scan_symbol(s, info, pos, b);
}

static bool scan_line_tokens(Scanner *s, const LineInfo *info) {
    bool line_done = false;
    while (!line_done && s->offset < s->n && s->src[s->offset] != '\n') {
        if (!scan_token(s, info, &line_done)) {
            return false;
        }
    }
    return true;
}

/* ---- end of a line ---- */

static bool function_open_at_depth(const Scanner *s) {
    for (size_t i = 0; i < MS_VEC_LEN(s->function_depths, size_t); i++) {
        if (MS_VEC_AT(s->function_depths, size_t, i) == open_delimiters(s)) {
            return true;
        }
    }
    return false;
}

/* The wrapper's closing parenthesis ends an interpolation's tokens. */
static bool close_virtual_paren(Scanner *s) {
    if (!s->virtual_paren || s->offset != s->n) {
        return true;
    }
    if (!(open_delimiters(s) == 1 && MS_VEC_AT(s->delimiters, char, 0) == '(')) {
        /* The wrapper's closing parenthesis reports this error. */
        return fail_str(s, LIT("interpolation leaves a delimiter open"));
    }
    MS_VEC_POP(s->delimiters, char);
    MS_VEC_POP(s->opened, MsPos);
    s->groups.len = 0;
    s->function_depths.len = 0;
    emit_layout(s, MS_T_RParen);
    return true;
}

/* Ends the line: it opens a suite (`:`), continues (`.` or `|` next), or ends its statement. */
static void end_line(Scanner *s, LineLayout *layout, const LineInfo *info, size_t line_start,
                     size_t leading) {
    if (ntokens(s) <= line_start) {
        return;
    }
    if (last_kind(s) == MS_T_Colon && (open_delimiters(s) == info->top_depth || function_open_at_depth(s))) {
        layout->pending = true;
        layout->header_indent = leading;
        layout->header_start = layout->statement_indent;
        layout->pending_depth = open_delimiters(s);
        emit_layout(s, MS_T_Newline);
        s->function_depths.len = 0;
    } else if (open_delimiters(s) == info->top_depth) {
        s->function_depths.len = 0;
        if (continues_next(s)) {
            layout->continuing = true;
        } else {
            emit_layout(s, MS_T_Newline);
        }
    } else if (MS_VEC_LEN(s->groups, size_t) != 0 && MS_VEC_LAST(s->groups, size_t) == open_delimiters(s)) {
        /* A `var (` group holds one binding per line, so its lines end like statements even
         * though a delimiter is open. */
        emit_layout(s, MS_T_Newline);
    }
}

static bool fail_unterminated_delimiter(Scanner *s) {
    char open = MS_VEC_LAST(s->delimiters, char);
    MsPos opener = MS_VEC_LAST(s->opened, MsPos);
    MsStr message = ms_arena_fmt(s->arena,
        "unterminated delimiter '%c' opened at line %u:%u; add the matching '%c' before the end of the file",
        open, opener.line, opener.column, closer_of(open));
    new_diag(s, spos(s), message)->opener_line = opener.line;
    return false;
}

static bool finish_input(Scanner *s, const LineLayout *layout) {
    if (layout->pending) {
        emit_layout(s, MS_T_Indent);
        emit_layout(s, MS_T_Dedent);
    }
    if (s->prefixes != NULL) {
        pad_prefix_flags(s);
        put_prefix_flag(s->prefixes, open_delimiters(s) != 0);
    }
    if (open_delimiters(s) != 0) {
        return fail_unterminated_delimiter(s);
    }
    while (MS_VEC_LEN(s->levels, Level) > 1) {
        MS_VEC_POP(s->levels, Level);
        emit_layout(s, MS_T_Dedent);
    }
    emit_layout(s, MS_T_Eof);
    return true;
}

/* Scans the whole source. Returns false with the diagnostic in s->diag on the first error. */
MS_NODISCARD static bool run(Scanner *s) {
    LineLayout layout = {0};
    while (s->offset < s->n) {
        if (prefix_pass_stops(s)) {
            return true;
        }
        size_t leading = 0;
        if (!read_leading_space(s, &leading)) {
            return false;
        }
        if (s->offset == s->n) {
            break;
        }
        bool skipped = false;
        if (!skip_blank_line(s, &skipped)) {
            return false;
        }
        if (skipped) {
            continue;
        }
        if (!apply_layout(s, &layout, leading)) {
            return false;
        }
        Level top = MS_VEC_LAST(s->levels, Level);
        LineInfo info = {.leading = leading, .top_indent = top.indent, .top_depth = top.depth};
        if (ntokens(s) != 0 && last_kind(s) == MS_T_Dedent && open_delimiters(s) == top.depth) {
            emit_layout(s, MS_T_Newline);
        }
        size_t line_start = ntokens(s);
        if (!scan_line_tokens(s, &info) || !close_virtual_paren(s)) {
            return false;
        }
        end_line(s, &layout, &info, line_start, leading);
        if (s->offset < s->n) {
            advance(s);
        }
    }
    return finish_input(s, &layout);
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
    MS_VEC_PUSH(s->levels, Level, ((Level){0, 0}));
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

/* Copies a scratch vector into the arena; the result is never NULL. */
static void *copy_out(MsArena *a, const MsBuf *b, size_t align) {
    void *p = ms_alloc(a, b->len ? b->len : 1, align);
    if (b->len != 0) {
        memcpy(p, b->data, b->len);
    }
    return p;
}

static size_t count_newlines(const char *src, size_t len) {
    size_t n = 0;
    for (size_t i = 0; i < len; i++) {
        n += src[i] == '\n';
    }
    return n;
}

static bool has_crlf(const char *src, size_t len) {
    for (size_t i = 1; i < len; i++) {
        if (src[i] == '\n' && src[i - 1] == '\r') {
            return true;
        }
    }
    return false;
}

/* Replaces CRLF with LF and records, per normalised line, how many CR bytes precede it. The result
 * is `src` itself, with no offsets, when the source has no CRLF. */
static const char *normalize(MsArena *a, const char *src, size_t len, size_t *out_len, uint32_t **offsets) {
    *offsets = NULL;
    if (!has_crlf(src, len)) {
        *out_len = len;
        return src;
    }
    char *dst = ms_alloc(a, len + 1, 1);
    uint32_t *offs = MS_NEW_N(a, uint32_t, count_newlines(src, len) + 1);
    size_t written = 0;
    size_t lines = 0;
    uint32_t removed = 0;
    offs[lines++] = 0;
    for (size_t i = 0; i < len; i++) {
        if (src[i] == '\r' && i + 1 < len && src[i + 1] == '\n') {
            continue; /* the LF follows */
        }
        dst[written++] = src[i];
        if (src[i] == '\n') {
            removed += i > 0 && src[i - 1] == '\r';
            offs[lines++] = removed;
        }
    }
    dst[written] = 0;
    *out_len = written;
    *offsets = offs;
    return dst;
}

static void sort_ranges(MsBuf *ranges) {
    if (ranges->len != 0) {
        qsort(ranges->data, MS_VEC_LEN(*ranges, MsRange), sizeof(MsRange), range_cmp);
    }
}

static void export_lexed(Scanner *s, uint32_t *offsets, MsLexed *out) {
    sort_ranges(&s->strings);
    sort_ranges(&s->interps);
    out->source = s->text;
    out->source_len = s->n;
    out->tokens = copy_out(s->arena, &s->tokens, _Alignof(MsToken));
    out->ntokens = ntokens(s);
    out->blocks = copy_out(s->arena, &s->blocks, _Alignof(MsRange));
    out->nblocks = MS_VEC_LEN(s->blocks, MsRange);
    out->bounds.strings = copy_out(s->arena, &s->strings, _Alignof(MsRange));
    out->bounds.nstrings = MS_VEC_LEN(s->strings, MsRange);
    out->bounds.interps = copy_out(s->arena, &s->interps, _Alignof(MsRange));
    out->bounds.ninterps = MS_VEC_LEN(s->interps, MsRange);
    out->bounds.line_offsets = offsets;
    out->bounds.base_line = s->base_line;
}

static bool lex_run(MsArena *arena, const char *text, size_t nlen, uint32_t base_offset, uint32_t base_line,
                    uint32_t *offsets, MsLexed *out, MsDiag *diag) {
    Scanner s;
    scanner_init(&s, arena, text, nlen, base_offset, base_line, offsets, diag);
    bool ok = run(&s);
    if (ok) {
        export_lexed(&s, offsets, out);
    }
    scanner_free(&s);
    return ok;
}

static bool fail_source(MsDiag *diag, MsPos pos, MsStr message) {
    memset(diag, 0, sizeof *diag);
    diag->pos = pos;
    diag->message = message;
    return false;
}

static bool has_byte_order_mark(const char *src, size_t len) {
    return len >= 3 && memcmp(src, "\xEF\xBB\xBF", 3) == 0;
}

bool ms_lex_at(MsArena *arena, const char *src, size_t len, uint32_t base_offset, uint32_t base_line,
               MsLexed *out, MsDiag *diag) {
    memset(out, 0, sizeof *out);
    if (!ms_utf8_valid(src, len)) {
        return fail_source(diag, (MsPos){0, 1, 1},
                           LIT("source must be valid UTF-8; re-save the file with UTF-8 encoding"));
    }
    if (has_byte_order_mark(src, len)) {
        return fail_source(diag, (MsPos){base_offset, base_line + 1, 1},
                           LIT("a byte-order mark is not allowed; save the file as UTF-8 without BOM"));
    }
    size_t nlen = 0;
    uint32_t *offsets = NULL;
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
    MS_VEC_PUSH(s.delimiters, char, '(');
    MS_VEC_PUSH(s.opened, MsPos, ((MsPos){0, 1, 1}));
    if (!run(&s)) {
        scanner_free(&s);
        return false;
    }
    /* Drop the wrapper's closing parenthesis: it sits just before Newline and Eof. */
    size_t total = ntokens(&s);
    size_t closing = total - 3;
    memmove(tokat(&s, closing), tokat(&s, closing + 1), (total - closing - 1) * sizeof(MsToken));
    s.tokens.len -= sizeof(MsToken);
    *tokens = copy_out(arena, &s.tokens, _Alignof(MsToken));
    *count = ntokens(&s);
    scanner_free(&s);
    return true;
}

/* ---- editor recovery ---- */

/* Recovery reads past lexical errors; the strict parse is the one that reports them. */
static void ignore_failure(bool ok) {
    (void)ok;
}

/* One flag per physical line, all false. */
static bool *new_line_flags(MsArena *arena, const char *src, size_t len, size_t *count) {
    size_t lines = count_newlines(src, len) + 1;
    bool *flags = MS_NEW_N(arena, bool, lines);
    memset(flags, 0, lines);
    *count = lines;
    return flags;
}

bool *ms_unterminated_prefixes(MsArena *arena, const char *src, size_t len, const bool *stop_at,
                               size_t nstop, size_t *count) {
    bool *out = new_line_flags(arena, src, len, count);
    if (has_byte_order_mark(src, len)) {
        return out;
    }
    size_t nlen = 0;
    uint32_t *offsets = NULL;
    const char *text = normalize(arena, src, len, &nlen, &offsets);
    MsDiag diag;
    MsBuf prefixes = {0};
    Scanner s;
    scanner_init(&s, arena, text, nlen, 0, 0, offsets, &diag);
    s.prefixes = &prefixes;
    s.stop_at = stop_at;
    s.nstop = nstop;
    /* A lexical error ends the pass; the flags gathered so far are what recovery needs. */
    ignore_failure(run(&s));
    const bool *seen = (const bool *)prefixes.data;
    for (size_t i = 0; i < *count && i < prefixes.len; i++) {
        out[i] = seen[i];
    }
    scanner_free(&s);
    ms_buf_free(&prefixes);
    return out;
}

/* Walks the source the way recovery needs: it only tracks bracket depth and where texts end. */
typedef struct Walk {
    Scanner scanner;
    size_t depth;
    bool invalid_text_header;
    uint32_t leading_line; /* the line whose first token is known */
    size_t first_token;    /* offset of that first token */
} Walk;

static bool after_word_byte(const Scanner *s, size_t distance) {
    return s->offset >= distance && is_word_byte(s->src[s->offset - distance]);
}

static void skip_opaque_line_comment(Scanner *s) {
    while (s->offset < s->n && s->src[s->offset] != '\n') {
        advance(s);
    }
}

/* Comments do not nest. Even a malformed comment remains opaque up to its first closer (or EOF);
 * strict lexing reports the error. */
static void skip_opaque_block_comment(Scanner *s) {
    advance(s);
    advance(s);
    while (s->offset < s->n) {
        bool closes = starts_with(s, s->offset, "*/");
        advance(s);
        if (closes) {
            advance(s);
            return;
        }
    }
}

/* One-line raw text ends at its first quote; no escapes. */
static void skip_opaque_raw_line(Scanner *s) {
    advance(s);
    advance(s);
    while (s->offset < s->n) {
        uint8_t byte = advance(s);
        if (byte == '"' || byte == '\n') {
            return;
        }
    }
}

static void note_first_token(Walk *w) {
    Scanner *s = &w->scanner;
    if (w->leading_line == s->line) {
        return;
    }
    w->leading_line = s->line;
    size_t k = s->offset - (s->column - 1);
    while (k < s->n && (s->src[k] == ' ' || s->src[k] == '\t')) {
        k++;
    }
    w->first_token = k;
}

static void skip_opaque_triple_body(Scanner *s, bool raw) {
    while (s->offset < s->n) {
        if (starts_with(s, s->offset, "\"\"\"")) {
            advance(s);
            advance(s);
            advance(s);
            return;
        }
        uint8_t byte = advance(s);
        if (!raw && byte == '\\' && s->offset < s->n) {
            advance(s);
        }
    }
}

static void skip_opaque_triple_text(Walk *w) {
    Scanner *s = &w->scanner;
    bool raw = s->src[s->offset] == 'r';
    note_first_token(w);
    bool standalone = s->offset == w->first_token;
    for (int k = 0; k < (raw ? 4 : 3); k++) {
        advance(s);
    }
    /* A malformed header's standalone closer must not become a fresh opener. A literal in a new
     * expression (including a standalone delimiter continuation) supersedes that malformed
     * header. */
    bool body = at(s, s->offset) == '\n';
    bool closing_invalid = w->invalid_text_header && standalone && !raw && w->depth == 0;
    w->invalid_text_header = !body;
    if (body && !closing_invalid) {
        skip_opaque_triple_body(s, raw);
    }
}

/* Recovery looks only at where a text ends; its lexical errors are the strict parse's to report. */
static void skip_quoted_text(Scanner *s) {
    bool formatted = s->offset > 0 && s->src[s->offset - 1] == 'f' && !after_word_byte(s, 2);
    ignore_failure(scan_string(s, formatted));
}

static void count_bracket(Walk *w) {
    uint8_t b = advance(&w->scanner);
    if (b == '(' || b == '[' || b == '{') {
        w->depth++;
    } else if ((b == ')' || b == ']' || b == '}') && w->depth > 0) {
        w->depth--;
    }
}

/* Consumes one lexical element at the cursor. */
static void walk_step(Walk *w) {
    Scanner *s = &w->scanner;
    if (at_line_comment(s)) {
        skip_opaque_line_comment(s);
    } else if (at_block_comment(s)) {
        skip_opaque_block_comment(s);
    } else if (starts_with(s, s->offset, "f\"") && !after_word_byte(s, 1)) {
        advance(s); /* the prefix of interpolating text; the quote is handled next */
    } else if (starts_with(s, s->offset, "r\"") && !starts_with(s, s->offset + 2, "\"\"") &&
               !after_word_byte(s, 1)) {
        skip_opaque_raw_line(s);
    } else if (starts_with(s, s->offset, "r\"\"\"") || starts_with(s, s->offset, "\"\"\"")) {
        skip_opaque_triple_text(w);
    } else if (s->src[s->offset] == '"') {
        skip_quoted_text(s);
    } else {
        count_bracket(w);
    }
}

bool *ms_recovery_continuations(MsArena *arena, const char *src, size_t len, const bool *roots,
                                size_t nroots, size_t *count) {
    bool *out = new_line_flags(arena, src, len, count);
    size_t nlen = 0;
    uint32_t *offsets = NULL;
    const char *text = normalize(arena, src, len, &nlen, &offsets);
    MsDiag diag;
    Walk w = {0};
    Scanner *s = &w.scanner;
    scanner_init(s, arena, text, nlen, 0, 0, offsets, &diag);
    while (s->offset < s->n) {
        size_t first = s->line - 1;
        if (s->column == 1 && first < nroots && roots[first]) {
            w.depth = 0;
        }
        walk_step(&w);
        /* An invalid single-line string may consume its newline before failing; the following
         * line still starts independently. */
        size_t last = s->line - 1 - (s->column == 1);
        for (size_t i = first + 1; i <= last && i < *count; i++) {
            out[i] = true;
        }
    }
    scanner_free(s);
    return out;
}
