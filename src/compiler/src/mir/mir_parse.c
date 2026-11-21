/* The MIR text parser (parse.rs): one item per line except `fn`, whose body runs to a line holding
 * only `}`. Items may refer to each other in any order; names inside a function are arbitrary
 * identifiers and are renumbered when printed. Errors unwind with longjmp to mir_parse.
 *
 * Differences from the Rust parser, by design: error messages do not quote tokens, non-ASCII
 * outside string literals is rejected (Rust also accepts Unicode whitespace), and a function
 * header with a stray token is an error where the Rust parser loops. */
#include <ctype.h>
#include <errno.h>
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/chars.h"

#include "ms/mir.h"
#include "ms/text.h"

typedef enum { MPT_IDENT, MPT_VAL, MPT_AT, MPT_NUM, MPT_STR, MPT_LOC, MPT_ARROW, MPT_P } MpTokKind;

typedef struct MpTok {
    uint8_t k;
    char ch; /* MPT_P */
    const char *s;
    uint32_t n;
    MirLoc loc;
} MpTok;

typedef struct MpLine {
    uint32_t no; /* 1-based */
    const char *s;
    uint32_t n;
} MpLine;

typedef struct MpItem {
    uint32_t no;
    const char *s; /* the trimmed line */
    uint32_t n;
    MpTok *t;
    uint32_t nt;
} MpItem;

typedef struct MpFnSrc {
    MpLine header;
    MpLine *body;
    uint32_t nbody, cbody;
} MpFnSrc;

typedef struct MpParser {
    MirModule *m;
    jmp_buf jb;
    uint32_t err_line;
    MsStr err_msg;
    /* function-local names */
    MsNames vnames, bnames;
    uint32_t *val_of, *val_gen, nval_cap;
    uint32_t *blk_of, *blk_gen, nblk_cap;
    uint32_t gen;
    uint8_t *defined;
    uint32_t ndefined, cdefined;
    uint8_t *terminated;
} MpParser;

static void mpa_perr(MpParser *p, uint32_t line, const char *fmt, ...) __attribute__((noreturn, format(printf, 3, 4)));
static void mpa_perr(MpParser *p, uint32_t line, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    p->err_msg = ms_arena_vfmt(&p->m->arena, fmt, ap);
    va_end(ap);
    p->err_line = line;
    longjmp(p->jb, 1);
}

/* ---- numbers ---- */

static bool mpa_parse_i64(const char *s, size_t n, int64_t *out) {
    size_t i = 0;
    bool neg = false;
    if (n > 0 && s[0] == '-') {
        neg = true;
        i = 1;
    }
    if (i >= n) {
        return false;
    }
    uint64_t v = 0;
    for (; i < n; i++) {
        if (s[i] < '0' || s[i] > '9') {
            return false;
        }
        uint64_t d = (uint64_t)(s[i] - '0');
        if (v > (UINT64_MAX - d) / 10) {
            return false;
        }
        v = v * 10 + d;
    }
    if (neg ? v > (uint64_t)INT64_MAX + 1 : v > (uint64_t)INT64_MAX) {
        return false;
    }
    *out = neg ? (int64_t)(0 - v) : (int64_t)v;
    return true;
}

static bool mpa_parse_u32(const char *s, size_t n, uint32_t *out) {
    int64_t v;
    if (n == 0 || s[0] == '-' || !mpa_parse_i64(s, n, &v) || v > UINT32_MAX) {
        return false;
    }
    *out = (uint32_t)v;
    return true;
}

static bool mpa_parse_hex_u64(const char *s, size_t n, uint64_t *out) {
    if (n == 0 || n > 16) {
        /* Rust accepts leading zeros past 16 digits; none are produced. */
        if (n == 0) {
            return false;
        }
    }
    uint64_t v = 0;
    for (size_t i = 0; i < n; i++) {
        uint32_t d = 0;
        if (!ms_hex_digit_value((uint8_t)s[i], &d)) {
            return false;
        }
        if (v >> 60) {
            return false;
        }
        v = v << 4 | (uint64_t)d;
    }
    *out = v;
    return true;
}

/* ---- tokenizer ---- */

static bool mpa_ident_char(unsigned char c) { return ms_ascii_is_ident(c) || c == '.' || c == '$'; }
static bool mpa_ws_char(unsigned char c) { return c == ' ' || (c >= '\t' && c <= '\r'); }

/* A line being tokenized: `text[position]` is the next character. */
typedef struct MpLexer {
    MpParser *p;
    const char *text;
    size_t length;
    size_t position;
    uint32_t line;
} MpLexer;

static bool mpa_lex_more(const MpLexer *lx) { return lx->position < lx->length; }
static char mpa_lex_at(const MpLexer *lx, size_t ahead) {
    size_t index = lx->position + ahead;
    if (index >= lx->length) {
        return '\0';
    }
    return lx->text[index];
}

/* The value of the two characters after `\x`: Rust reads two chars and parses them as hex, which also
 * takes "+h". Returns -1 when they are not a byte. */
static int mpa_hex_escape(const MpLexer *lx) {
    char high = mpa_lex_at(lx, 0);
    char low = mpa_lex_at(lx, 1);
    if (lx->position + 2 > lx->length || ms_text_digit_value(low) < 0) {
        return -1;
    }
    if (ms_text_digit_value(high) >= 0) {
        return ms_text_digit_value(high) * 16 + ms_text_digit_value(low);
    }
    return high == '+' ? ms_text_digit_value(low) : -1;
}

/* Reads one escape after a backslash into `out`. */
static void mpa_lex_escape(MpLexer *lx, MsBuf *out) {
    if (!mpa_lex_more(lx)) {
        ms_buf_free(out);
        mpa_perr(lx->p, lx->line, "bad escape");
    }
    char escape = lx->text[lx->position++];
    switch (escape) {
    case 'n': ms_buf_putc(out, '\n'); return;
    case 't': ms_buf_putc(out, '\t'); return;
    case 'r': ms_buf_putc(out, '\r'); return;
    case '"': ms_buf_putc(out, '"'); return;
    case '\\': ms_buf_putc(out, '\\'); return;
    case 'x': {
        int byte = mpa_hex_escape(lx);
        if (byte < 0) {
            ms_buf_free(out);
            mpa_perr(lx->p, lx->line, "bad \\x escape");
        }
        lx->position += 2;
        ms_utf8_put(out, (uint32_t)byte);
        return;
    }
    default:
        ms_buf_free(out);
        mpa_perr(lx->p, lx->line, "unknown escape");
    }
}

/* A string literal; the opening quote is already consumed. */
static MpTok mpa_lex_string(MpLexer *lx) {
    MsBuf bytes = {0};
    for (;;) {
        if (!mpa_lex_more(lx)) {
            ms_buf_free(&bytes);
            mpa_perr(lx->p, lx->line, "unterminated string");
        }
        char c = lx->text[lx->position++];
        if (c == '"') {
            break;
        }
        if (c == '\\') {
            mpa_lex_escape(lx, &bytes);
        } else {
            ms_buf_putc(&bytes, c);
        }
    }
    const char *copy = ms_arena_strndup(&lx->p->m->arena, bytes.data ? bytes.data : "", bytes.len);
    MpTok token = {.k = MPT_STR, .s = copy, .n = (uint32_t)bytes.len};
    ms_buf_free(&bytes);
    return token;
}

/* `%name` or `@name`; the sigil is at the current position. */
static MpTok mpa_lex_name(MpLexer *lx) {
    char sigil = lx->text[lx->position++];
    size_t start = lx->position;
    while (mpa_lex_more(lx) && mpa_ident_char((unsigned char)lx->text[lx->position])) {
        lx->position++;
    }
    if (lx->position == start) {
        mpa_perr(lx->p, lx->line, "empty name");
    }
    return (MpTok){.k = sigil == '%' ? MPT_VAL : MPT_AT, .s = lx->text + start,
                   .n = (uint32_t)(lx->position - start)};
}

/* `!file:line:col`; the bang is at the current position. */
static MpTok mpa_lex_location(MpLexer *lx) {
    size_t start = ++lx->position;
    while (mpa_lex_more(lx) && (ms_ascii_is_digit((uint8_t)lx->text[lx->position]) || lx->text[lx->position] == ':')) {
        lx->position++;
    }
    uint32_t fields[4] = {0};
    size_t count = 0;
    size_t field_start = start;
    for (size_t k = start; k <= lx->position; k++) {
        if (k != lx->position && lx->text[k] != ':') {
            continue;
        }
        if (count < 4 && !mpa_parse_u32(lx->text + field_start, k - field_start, &fields[count])) {
            mpa_perr(lx->p, lx->line, count >= 2 ? "bad location" : "location must be !file:line:col");
        }
        count++;
        field_start = k + 1;
    }
    if (count != 3 && count != 4) {
        mpa_perr(lx->p, lx->line, "location must be !file:line:col or !file:line:col:scope");
    }
    MpTok token = {.k = MPT_LOC};
    token.loc.file = fields[0];
    token.loc.line = fields[1];
    token.loc.col = fields[2];
    token.loc.scope = count == 4 ? fields[3] : 0;
    return token;
}

static MpTok mpa_lex_number(MpLexer *lx) {
    size_t start = lx->position++;
    if (lx->text[start] == '0' && mpa_lex_at(lx, 0) == 'x') {
        lx->position++;
        while (mpa_lex_more(lx) && ms_ascii_is_hex((uint8_t)lx->text[lx->position])) {
            lx->position++;
        }
    } else {
        while (mpa_lex_more(lx)) {
            char c = lx->text[lx->position];
            char before = lx->text[lx->position - 1];
            bool exponent_sign = (c == '+' || c == '-') && (before == 'e' || before == 'E');
            if (!ms_ascii_is_digit((uint8_t)c) && c != '.' && c != 'e' && c != 'E' && !exponent_sign) {
                break;
            }
            lx->position++;
        }
    }
    return (MpTok){.k = MPT_NUM, .s = lx->text + start, .n = (uint32_t)(lx->position - start)};
}

/* An identifier. A generic type's name is printed with its arguments (`Result[Void, Error]`); a
 * `[` right after identifier characters starts such a suffix, which belongs to the name up to its
 * matching `]` (the `[` of a switch or a blob is always set off by a space). The Rust parser does
 * not read these names. */
static MpTok mpa_lex_identifier(MpLexer *lx) {
    size_t start = lx->position;
    while (mpa_lex_more(lx) && mpa_ident_char((unsigned char)lx->text[lx->position])) {
        lx->position++;
    }
    /* `Result[List[Int], Error].ok.value`: bracketed arguments may be followed by more of the path. */
    while (lx->position > start && mpa_lex_more(lx) && lx->text[lx->position] == '[') {
        size_t depth = 0;
        size_t at = lx->position;
        bool closed = false;
        while (at < lx->length && lx->text[at] != '\n') {
            depth += lx->text[at] == '[';
            depth -= lx->text[at] == ']';
            at++;
            if (depth == 0) {
                closed = true;
                break;
            }
        }
        if (!closed) {
            break;
        }
        lx->position = at;
        while (mpa_lex_more(lx) && mpa_ident_char((unsigned char)lx->text[lx->position])) {
            lx->position++;
        }
    }
    return (MpTok){.k = MPT_IDENT, .s = lx->text + start, .n = (uint32_t)(lx->position - start)};
}

/* The token at the current position (not whitespace, not a comment). */
static MpTok mpa_lex_token(MpLexer *lx) {
    unsigned char c = (unsigned char)lx->text[lx->position];
    unsigned char next = (unsigned char)mpa_lex_at(lx, 1);
    if (c == '"') {
        lx->position++;
        return mpa_lex_string(lx);
    }
    if (c == '%' || c == '@') {
        return mpa_lex_name(lx);
    }
    if (c == '!') {
        return mpa_lex_location(lx);
    }
    if (c == '-' && next == '>') {
        lx->position += 2;
        return (MpTok){.k = MPT_ARROW};
    }
    if (ms_ascii_is_digit((uint8_t)c) || (c == '-' && ms_ascii_is_digit((uint8_t)next))) {
        return mpa_lex_number(lx);
    }
    if (ms_ascii_is_ident_start((uint8_t)c)) {
        return mpa_lex_identifier(lx);
    }
    if (c != 0 && strchr("(){}<>[],:=", c) != NULL) {
        lx->position++;
        return (MpTok){.k = MPT_P, .ch = (char)c};
    }
    mpa_perr(lx->p, lx->line, "unexpected character");
}

static MpTok *mpa_tokenize(MpParser *p, const char *s, size_t n, uint32_t no, uint32_t *count) {
    MpLexer lx = {p, s, n, 0, no};
    MpTok *tokens = NULL;
    uint32_t used = 0, capacity = 0;
    while (mpa_lex_more(&lx)) {
        unsigned char c = (unsigned char)s[lx.position];
        if (mpa_ws_char(c)) {
            lx.position++;
            continue;
        }
        if (c == ';') {
            break;
        }
        MpTok token = mpa_lex_token(&lx);
        MIR_PUSH(p->m, tokens, used, capacity, MpTok, token);
    }
    *count = used;
    return tokens;
}

/* ---- cursor ---- */

typedef struct MpCur {
    MpParser *p;
    const MpTok *t;
    uint32_t n, pos, line;
} MpCur;

static const MpTok *mpa_c_peek(const MpCur *c) { return c->pos < c->n ? &c->t[c->pos] : NULL; }
static bool mpa_c_done(const MpCur *c) { return c->pos >= c->n; }
static bool mpa_c_peek_p(const MpCur *c, char ch) {
    const MpTok *t = mpa_c_peek(c);
    return t && t->k == MPT_P && t->ch == ch;
}
static bool mpa_c_peek_kind(const MpCur *c, MpTokKind k) {
    const MpTok *t = mpa_c_peek(c);
    return t && t->k == k;
}
static bool mpa_c_eat_p(MpCur *c, char ch) {
    if (mpa_c_peek_p(c, ch)) {
        c->pos++;
        return true;
    }
    return false;
}
static void mpa_c_expect_p(MpCur *c, char ch) {
    if (!mpa_c_eat_p(c, ch)) {
        mpa_perr(c->p, c->line, "expected '%c'", ch);
    }
}
static MpTok mpa_c_take(MpCur *c, MpTokKind k, const char *what) {
    const MpTok *t = mpa_c_peek(c);
    if (t == NULL || t->k != k) {
        mpa_perr(c->p, c->line, "expected %s", what);
    }
    c->pos++;
    return *t;
}
static MpTok mpa_c_ident(MpCur *c) { return mpa_c_take(c, MPT_IDENT, "identifier"); }
static MpTok mpa_c_at(MpCur *c) { return mpa_c_take(c, MPT_AT, "@name"); }
static MpTok mpa_c_val(MpCur *c) { return mpa_c_take(c, MPT_VAL, "%value"); }
static MpTok mpa_c_num(MpCur *c) { return mpa_c_take(c, MPT_NUM, "a number"); }
static MpTok mpa_c_string(MpCur *c) { return mpa_c_take(c, MPT_STR, "a string"); }
static bool mpa_tok_is(const MpTok *t, const char *s) {
    return t->k == MPT_IDENT && strlen(s) == t->n && memcmp(t->s, s, t->n) == 0;
}
static bool mpa_c_eat_ident(MpCur *c, const char *s) {
    const MpTok *t = mpa_c_peek(c);
    if (t && mpa_tok_is(t, s)) {
        c->pos++;
        return true;
    }
    return false;
}
static MsSym mpa_tsym(const MpCur *c, MpTok t) { return mir_name(c->p->m, t.s, t.n); }

/* ---- types ---- */

static MirTy mpa_parse_ty(MpCur *c);
static MirTy mpa_parse_ty_base(MpCur *c);

static MirTy mpa_parse_fn_ty(MpCur *c) {
    MirTy *ps = NULL;
    uint32_t n = 0, cap = 0;
    uint64_t owned = 0;
    mpa_c_expect_p(c, '(');
    while (!mpa_c_eat_p(c, ')')) {
        if (mpa_c_eat_ident(c, "move") && n < 64) {
            owned |= 1ull << n;
        }
        MirTy t = mpa_parse_ty(c);
        MIR_PUSH(c->p->m, ps, n, cap, MirTy, t);
        mpa_c_eat_p(c, ',');
    }
    if (!mpa_c_peek_kind(c, MPT_ARROW)) {
        mpa_perr(c->p, c->line, "expected '->' in function type");
    }
    c->pos++;
    MirTy r = mpa_parse_ty(c);
    return mir_ty_fn(c->p->m, ps, n, r, owned);
}

/* A type, then the implementation scope the printer appends as `@N` (digits only, so a function
 * name that follows a type is not taken for one). */
static MirTy mpa_parse_ty(MpCur *c) {
    const MirTy base = mpa_parse_ty_base(c);
    const MpTok *next = mpa_c_peek(c);
    if (next == NULL || next->k != MPT_AT || next->n == 0) {
        return base;
    }
    uint32_t scope = 0;
    for (uint32_t i = 0; i < next->n; i++) {
        if (!ms_ascii_is_digit((uint8_t)next->s[i])) {
            return base;
        }
    }
    if (!mpa_parse_u32(next->s, next->n, &scope)) {
        return base;
    }
    c->pos++;
    return mir_ty_unscoped(base) | scope << MIR_SCOPE_SHIFT;
}

static MirTy mpa_parse_ty_base(MpCur *c) {
    MirModule *m = c->p->m;
    MpTok nt = mpa_c_ident(c);
    static const char *const builtin[MIR_BUILTIN_TYPES] = {
        "void", "bool", "int", "float", "str", "bytes", "ptr", "int8", "int16", "int32", "float32",
        "uint8", "uint16", "uint32", "uint64"};
    for (int i = 0; i < MIR_BUILTIN_TYPES; i++) {
        if (mpa_tok_is(&nt, builtin[i])) {
            return (MirTy)i;
        }
    }
    if (mpa_tok_is(&nt, "list") || mpa_tok_is(&nt, "opt")) {
        bool list = mpa_tok_is(&nt, "list");
        mpa_c_expect_p(c, '<');
        MirTy inner = mpa_parse_ty(c);
        mpa_c_expect_p(c, '>');
        return list ? mir_ty_list(m, inner) : mir_ty_opt(m, inner);
    }
    if (mpa_tok_is(&nt, "fn")) {
        return mpa_parse_fn_ty(c);
    }
    if (mpa_tok_is(&nt, "dyn")) {
        MpTok n = mpa_c_ident(c);
        uint32_t id = mir_iface_by_name(m, mpa_tsym(c, n));
        if (id == MIR_NONE) {
            mpa_perr(c->p, c->line, "unknown interface %.*s", (int)n.n, n.s);
        }
        return mir_ty_iface(m, id);
    }
    if (mpa_tok_is(&nt, "obj")) {
        MpTok n = mpa_c_ident(c);
        return mir_ty_obj(m, mpa_tsym(c, n), NULL, 0);
    }
    MsSym sym = mpa_tsym(c, nt);
    if (mpa_c_eat_p(c, '<')) {
        MirTy *args = NULL;
        uint32_t n = 0, cap = 0;
        while (!mpa_c_eat_p(c, '>')) {
            MirTy a = mpa_parse_ty(c);
            MIR_PUSH(m, args, n, cap, MirTy, a);
            mpa_c_eat_p(c, ',');
        }
        return mir_ty_obj(m, sym, args, n);
    }
    uint32_t id = mir_type_by_name(m, sym);
    if (id != MIR_NONE) {
        return mir_ty_type(m, id);
    }
    id = mir_alt_by_name(m, sym);
    if (id != MIR_NONE) {
        return mir_ty_alt(m, id);
    }
    mpa_perr(c->p, c->line, "unknown type '%.*s'", (int)nt.n, nt.s);
}

static uint8_t mpa_parse_std(MpCur *c) {
    if (mpa_c_done(c)) {
        return MSTD_NONE;
    }
    MpTok n = mpa_c_ident(c);
    if (mpa_tok_is(&n, "result")) return MSTD_RESULT;
    if (mpa_tok_is(&n, "comparable")) return MSTD_COMPARABLE;
    if (mpa_tok_is(&n, "equal")) return MSTD_EQUAL;
    mpa_perr(c->p, c->line, "unknown type attribute %.*s", (int)n.n, n.s);
}

/* ---- function bodies ---- */

/* realloc that aborts on failure, as every libms allocation does. */
static void *mpa_realloc(void *memory, size_t size) {
    void *grown = realloc(memory, size);
    if (grown == NULL) {
        abort();
    }
    return grown;
}

static uint32_t mpa_vname_lookup(MpParser *p, MsSym s) {
    return s < p->nval_cap && p->val_gen[s] == p->gen ? p->val_of[s] : MIR_NONE;
}

static void mpa_grow_names(uint32_t **of, uint32_t **gen, uint32_t *cap, uint32_t need) {
    if (need < *cap) {
        return;
    }
    uint32_t ncap = *cap ? *cap : 64;
    while (ncap <= need) {
        ncap *= 2;
    }
    *of = mpa_realloc(*of, sizeof(uint32_t) * ncap);
    *gen = mpa_realloc(*gen, sizeof(uint32_t) * ncap);
    for (uint32_t i = *cap; i < ncap; i++) {
        (*gen)[i] = 0;
    }
    *cap = ncap;
}

static MirValue mpa_value_of(MpParser *p, MirFunc *f, MpTok name) {
    MsSym s = ms_intern(&p->vnames, name.s, name.n);
    uint32_t v = mpa_vname_lookup(p, s);
    if (v != MIR_NONE) {
        return v;
    }
    mpa_grow_names(&p->val_of, &p->val_gen, &p->nval_cap, s);
    v = mir_new_value(p->m, f, MIR_VOID);
    p->val_of[s] = v;
    p->val_gen[s] = p->gen;
    return v;
}

static MirValue mpa_define(MpCur *c, MirFunc *f, MpTok name, MirTy ty) {
    MpParser *p = c->p;
    MirValue v = mpa_value_of(p, f, name);
    if (p->cdefined < f->nvalues) {
        uint32_t ncap = f->nvalues * 2;
        p->defined = mpa_realloc(p->defined, ncap);
        memset(p->defined + p->cdefined, 0, ncap - p->cdefined);
        p->cdefined = ncap;
    }
    if (p->defined[v]) {
        mpa_perr(p, c->line, "%%%.*s defined twice", (int)name.n, name.s);
    }
    p->defined[v] = 1;
    f->values[v] = ty;
    return v;
}

static MirTarget mpa_parse_target(MpCur *c, MirFunc *f) {
    MpParser *p = c->p;
    MpTok name = mpa_c_ident(c);
    MsSym s = ms_intern(&p->bnames, name.s, name.n);
    if (s >= p->nblk_cap || p->blk_gen[s] != p->gen) {
        mpa_perr(p, c->line, "unknown block %.*s", (int)name.n, name.s);
    }
    MirTarget t = {.block = p->blk_of[s]};
    MirValue *args = NULL;
    uint32_t n = 0, cap = 0;
    mpa_c_expect_p(c, '(');
    while (!mpa_c_eat_p(c, ')')) {
        MpTok v = mpa_c_val(c);
        MirValue x = mpa_value_of(p, f, v);
        MIR_PUSH(p->m, args, n, cap, MirValue, x);
        mpa_c_eat_p(c, ',');
    }
    t.args = args;
    t.nargs = n;
    return t;
}

static int64_t mpa_imm_int(MpCur *c) {
    MpTok s = mpa_c_num(c);
    int64_t v;
    if (!mpa_parse_i64(s.s, s.n, &v)) {
        mpa_perr(c->p, c->line, "bad integer %.*s", (int)s.n, s.s);
    }
    return v;
}

static uint32_t mpa_imm_u32(MpCur *c, const char *what) {
    MpTok s = mpa_c_num(c);
    uint32_t v;
    if (!mpa_parse_u32(s.s, s.n, &v)) {
        mpa_perr(c->p, c->line, "bad %s", what);
    }
    return v;
}


/* Splits `s` at its dots into at most `max` parts; returns the count (counting all dots). */
static int mpa_split_dots(MpTok t, const char **part, size_t *len, int max) {
    int np = 0;
    size_t ps = 0;
    for (size_t k = 0; k <= t.n; k++) {
        if (k == t.n || t.s[k] == '.') {
            if (np < max) {
                part[np] = t.s + ps;
                len[np] = k - ps;
            }
            np++;
            ps = k + 1;
        }
    }
    return np;
}

typedef struct MpSlice {
    const char *ptr;
    size_t len;
} MpSlice;

static uint32_t mpa_find_field(const MirModule *m, const MirField *fs, uint32_t n, const char *s,
                           size_t len) {
    for (uint32_t i = 0; i < n; i++) {
        MsStr nm = ms_name(&m->names, fs[i].name);
        if (nm.len == len && memcmp(nm.ptr, s, len) == 0) {
            return i;
        }
    }
    return MIR_NONE;
}

static uint32_t mpa_find_case(const MirModule *m, const MirAltDef *a, const char *s, size_t len) {
    for (uint32_t i = 0; i < a->ncases; i++) {
        MsStr nm = ms_name(&m->names, a->cases[i].name);
        if (nm.len == len && memcmp(nm.ptr, s, len) == 0) {
            return i;
        }
    }
    return MIR_NONE;
}

static MsSym mpa_psym(MpCur *c, const char *s, size_t n) { return mir_name(c->p->m, s, n); }

/* An identifier split at its dots (`Alt.Case.field`). */
typedef struct MpPath {
    MpTok token;
    const char *part[64];
    size_t length[64];
    int count; /* every dot counts, even past the 64 parts kept */
} MpPath;

static MpPath mpa_read_path(MpCur *c) {
    MpPath path = {.token = mpa_c_ident(c)};
    path.count = mpa_split_dots(path.token, path.part, path.length, 64);
    return path;
}

static int mpa_path_parts(const MpPath *path) { return path->count < 64 ? path->count : 64; }

static MpSlice mpa_path_slice(const MpPath *path, int index) {
    return (MpSlice){path->part[index], path->length[index]};
}

static uint32_t mpa_path_type(MpCur *c, const MpPath *path) {
    MpSlice name = mpa_path_slice(path, 0);
    uint32_t type = mir_type_by_name(c->p->m, mpa_psym(c, name.ptr, name.len));
    if (type == MIR_NONE) {
        mpa_perr(c->p, c->line, "unknown type %.*s", (int)name.len, name.ptr);
    }
    return type;
}

static uint32_t mpa_path_alt(MpCur *c, const MpPath *path) {
    MpSlice name = mpa_path_slice(path, 0);
    uint32_t alt = mir_alt_by_name(c->p->m, mpa_psym(c, name.ptr, name.len));
    if (alt == MIR_NONE) {
        mpa_perr(c->p, c->line, "unknown alternative %.*s", (int)name.len, name.ptr);
    }
    return alt;
}

static uint32_t mpa_path_case(MpCur *c, const MpPath *path, uint32_t alt) {
    MpSlice name = mpa_path_slice(path, 1);
    uint32_t index = mpa_find_case(c->p->m, &c->p->m->alts[alt], name.ptr, name.len);
    if (index == MIR_NONE) {
        mpa_perr(c->p, c->line, "unknown case %.*s", (int)path->token.n, path->token.s);
    }
    return index;
}

/* The bit set of the fields named by parts `first` onwards. */
static uint32_t mpa_path_field_mask(MpCur *c, const MpPath *path, int first, const MirField *fields,
                                    uint32_t field_count) {
    uint32_t mask = 0;
    for (int k = first; k < mpa_path_parts(path); k++) {
        MpSlice name = mpa_path_slice(path, k);
        uint32_t index = mpa_find_field(c->p->m, fields, field_count, name.ptr, name.len);
        if (index == MIR_NONE) {
            mpa_perr(c->p, c->line, "unknown field %.*s", (int)path->token.n, path->token.s);
        }
        mask |= 1u << index;
    }
    return mask;
}

static uint32_t mpa_path_field(MpCur *c, const MpPath *path, int part, const MirField *fields,
                               uint32_t field_count) {
    MpSlice name = mpa_path_slice(path, part);
    uint32_t index = mpa_find_field(c->p->m, fields, field_count, name.ptr, name.len);
    if (index == MIR_NONE) {
        mpa_perr(c->p, c->line, "unknown field %.*s", (int)path->token.n, path->token.s);
    }
    return index;
}

static MirImm mpa_imm_type_field(MpCur *c) {
    MpPath path = mpa_read_path(c);
    if (path.count != 2) {
        mpa_perr(c->p, c->line, "expected Type.field");
    }
    uint32_t type = mpa_path_type(c, &path);
    const MirTypeDef *def = &c->p->m->type_defs[type];
    uint32_t field = mpa_path_field(c, &path, 1, def->fields, def->nfields);
    return (MirImm){.tag = MI_FIELD, .a = type, .b = field};
}

static MirImm mpa_imm_alt_case(MpCur *c) {
    MpPath path = mpa_read_path(c);
    if (path.count != 2) {
        mpa_perr(c->p, c->line, "expected Alt.Case");
    }
    uint32_t alt = mpa_path_alt(c, &path);
    return (MirImm){.tag = MI_CASE, .a = alt, .b = mpa_path_case(c, &path, alt)};
}

static MirImm mpa_imm_alt_field(MpCur *c) {
    MpPath path = mpa_read_path(c);
    if (path.count != 3) {
        mpa_perr(c->p, c->line, "expected Alt.Case.field");
    }
    uint32_t alt = mpa_path_alt(c, &path);
    uint32_t index = mpa_path_case(c, &path, alt);
    const MirCaseDef *def = &c->p->m->alts[alt].cases[index];
    uint32_t field = mpa_path_field(c, &path, 2, def->fields, def->nfields);
    return (MirImm){.tag = MI_ALTFIELD, .a = alt, .b = index, .c = field};
}

static MirImm mpa_imm_alt_mask(MpCur *c) {
    MpPath path = mpa_read_path(c);
    if (path.count < 2) {
        mpa_perr(c->p, c->line, "expected Alt.Case.field...");
    }
    uint32_t alt = mpa_path_alt(c, &path);
    uint32_t index = mpa_path_case(c, &path, alt);
    const MirCaseDef *def = &c->p->m->alts[alt].cases[index];
    uint32_t mask = mpa_path_field_mask(c, &path, 2, def->fields, def->nfields);
    return (MirImm){.tag = MI_ALTMASK, .a = alt, .b = index, .c = mask};
}

static MirImm mpa_imm_type_mask(MpCur *c) {
    MpPath path = mpa_read_path(c);
    uint32_t type = mpa_path_type(c, &path);
    const MirTypeDef *def = &c->p->m->type_defs[type];
    uint32_t mask = mpa_path_field_mask(c, &path, 1, def->fields, def->nfields);
    return (MirImm){.tag = MI_TYPEMASK, .a = type, .b = mask};
}

static MirImm mpa_imm_method(MpCur *c) {
    MpPath path = mpa_read_path(c);
    if (path.count < 2) {
        mpa_perr(c->p, c->line, "expected Interface.method");
    }
    MpSlice iface_name = mpa_path_slice(&path, 0);
    MpSlice method_name = {path.part[1], path.token.n - iface_name.len - 1};
    uint32_t iface = mir_iface_by_name(c->p->m, mpa_psym(c, iface_name.ptr, iface_name.len));
    if (iface == MIR_NONE) {
        mpa_perr(c->p, c->line, "unknown interface %.*s", (int)iface_name.len, iface_name.ptr);
    }
    const MirIfaceDef *def = &c->p->m->ifaces[iface];
    for (uint32_t k = 0; k < def->nmethods; k++) {
        MsStr name = ms_name(&c->p->m->names, def->methods[k].name);
        if (name.len == method_name.len && memcmp(name.ptr, method_name.ptr, name.len) == 0) {
            return (MirImm){.tag = MI_METHOD, .a = iface, .b = k};
        }
    }
    mpa_perr(c->p, c->line, "unknown method %.*s", (int)path.token.n, path.token.s);
}

/* `@name` resolved against one of the module's declaration tables. */
static MirImm mpa_imm_at(MpCur *c, uint8_t tag, uint32_t (*lookup)(const MirModule *, MsSym),
                         const char *what) {
    MpTok name = mpa_c_at(c);
    uint32_t id = lookup(c->p->m, mpa_tsym(c, name));
    if (id == MIR_NONE) {
        mpa_perr(c->p, c->line, "unknown %s @%.*s", what, (int)name.n, name.s);
    }
    return (MirImm){.tag = tag, .a = id};
}

static MirImm mpa_imm_float(MpCur *c) {
    MpTok text = mpa_c_num(c);
    MirImm im = {.tag = MI_FLOAT};
    if (text.n >= 2 && text.s[0] == '0' && text.s[1] == 'x') {
        uint64_t bits = 0;
        if (!mpa_parse_hex_u64(text.s + 2, text.n - 2, &bits)) {
            mpa_perr(c->p, c->line, "bad float bits %.*s", (int)text.n, text.s);
        }
        im.i = (int64_t)bits;
        return im;
    }
    char buffer[128];
    if (text.n >= sizeof buffer) {
        mpa_perr(c->p, c->line, "bad float %.*s", (int)text.n, text.s);
    }
    memcpy(buffer, text.s, text.n);
    buffer[text.n] = 0;
    char *end = buffer;
    double value = strtod(buffer, &end);
    if (*end != 0) {
        mpa_perr(c->p, c->line, "bad float %.*s", (int)text.n, text.s);
    }
    uint64_t bits = 0;
    memcpy(&bits, &value, sizeof bits);
    im.i = (int64_t)bits;
    return im;
}

static MirImm mpa_imm_bool(MpCur *c) {
    MpTok word = mpa_c_ident(c);
    if (!mpa_tok_is(&word, "true") && !mpa_tok_is(&word, "false")) {
        mpa_perr(c->p, c->line, "expected true or false, found %.*s", (int)word.n, word.s);
    }
    return (MirImm){.tag = MI_BOOL, .a = mpa_tok_is(&word, "true") ? 1u : 0u};
}

static MirImm mpa_imm_type_name(MpCur *c) {
    MpTok name = mpa_c_ident(c);
    uint32_t type = mir_type_by_name(c->p->m, mpa_tsym(c, name));
    if (type == MIR_NONE) {
        mpa_perr(c->p, c->line, "unknown type %.*s", (int)name.n, name.s);
    }
    return (MirImm){.tag = MI_TYPE, .a = type};
}

/* The immediates that need no declaration lookup. `cc` is the comparison suffix of the mnemonic,
 * or -1 when it had none. */
static MirImm mpa_parse_imm_plain(MpCur *c, MirOp op, int cc, MpTok mnemonic) {
    switch ((MirImmKind)mir_op_info[op].imm) {
    case MIR_K_NONE:
        if (op == MOP_Clone && mpa_c_peek_kind(c, MPT_NUM)) {
            return (MirImm){.tag = MI_INT, .i = mpa_imm_int(c)};
        }
        return (MirImm){.tag = MI_NONE};
    case MIR_K_CC:
        if (cc < 0) {
            mpa_perr(c->p, c->line, "%.*s needs a condition such as %.*s.eq", (int)mnemonic.n,
                     mnemonic.s, (int)mnemonic.n, mnemonic.s);
        }
        return (MirImm){.tag = MI_CC, .a = (uint32_t)cc};
    case MIR_K_INT: return (MirImm){.tag = MI_INT, .i = mpa_imm_int(c)};
    case MIR_K_FLOAT: return mpa_imm_float(c);
    case MIR_K_BOOL: return mpa_imm_bool(c);
    case MIR_K_STR: {
        MpTok text = mpa_c_string(c);
        return (MirImm){.tag = MI_STR, .a = mir_add_string(c->p->m, text.s, text.n)};
    }
    case MIR_K_TY: return (MirImm){.tag = MI_TY, .a = mpa_parse_ty(c)};
    case MIR_K_SCOPE: {
        uint32_t first = mpa_imm_u32(c, "scope number");
        return (MirImm){.tag = MI_SCOPE, .a = first, .b = mpa_imm_u32(c, "scope number")};
    }
    case MIR_K_IDX: return (MirImm){.tag = MI_IDX, .a = mpa_imm_u32(c, "index")};
    default: break;
    }
    return (MirImm){.tag = MI_NONE};
}

static MirImm mpa_parse_imm(MpCur *c, MirOp op, int cc, MpTok mnemonic) {
    switch ((MirImmKind)mir_op_info[op].imm) {
    case MIR_K_FUNC: return mpa_imm_at(c, MI_FUNC, mir_func_by_name, "function");
    case MIR_K_EXT: return mpa_imm_at(c, MI_EXT, mir_extern_by_name, "extern");
    case MIR_K_VTABLE: return mpa_imm_at(c, MI_VTABLE, mir_vtable_by_name, "vtable");
    case MIR_K_GLOBAL: return mpa_imm_at(c, MI_GLOBAL, mir_global_by_name, "global");
    case MIR_K_TYPE: return mpa_imm_type_name(c);
    case MIR_K_FIELD: return mpa_imm_type_field(c);
    case MIR_K_CASE: return mpa_imm_alt_case(c);
    case MIR_K_ALTFIELD: return mpa_imm_alt_field(c);
    case MIR_K_ALTMASK: return mpa_imm_alt_mask(c);
    case MIR_K_TYPEMASK: return mpa_imm_type_mask(c);
    case MIR_K_METHOD: return mpa_imm_method(c);
    case MIR_K_NONE: case MIR_K_INT: case MIR_K_FLOAT: case MIR_K_BOOL: case MIR_K_STR:
    case MIR_K_TY: case MIR_K_CC: case MIR_K_IDX: case MIR_K_SCOPE:
        break;
    }
    return mpa_parse_imm_plain(c, op, cc, mnemonic);
}

static MirTerm mpa_term_switch(MpCur *c, MirFunc *f) {
    MirTerm term = {.kind = MT_SWITCH};
    term.value = mpa_value_of(c->p, f, mpa_c_val(c));
    mpa_c_expect_p(c, '[');
    MirCase *cases = NULL;
    uint32_t used = 0, capacity = 0;
    while (!mpa_c_eat_p(c, ']')) {
        MpTok key = mpa_c_num(c);
        int64_t constant = 0;
        if (!mpa_parse_i64(key.s, key.n, &constant)) {
            mpa_perr(c->p, c->line, "bad switch constant");
        }
        mpa_c_expect_p(c, ':');
        MirCase entry = {constant, mpa_parse_target(c, f)};
        MIR_PUSH(c->p->m, cases, used, capacity, MirCase, entry);
        mpa_c_eat_p(c, ',');
    }
    if (!mpa_c_eat_ident(c, "default")) {
        mpa_perr(c->p, c->line, "expected 'default'");
    }
    term.b = mpa_parse_target(c, f);
    term.cases = cases;
    term.ncases = used;
    return term;
}

static MirTerm mpa_term_fault(MpCur *c) {
    static const char *const kind_names[] = {"int_overflow", "div_by_zero", "index_out_of_range",
                                             "none_unwrap", "cancelled", "call_depth",
                                             "unreachable_code"};
    MirTerm term = {.kind = MT_FAULT, .value = MIR_NONE};
    const MpTok *token = mpa_c_peek(c);
    if (token == NULL || (token->k != MPT_STR && token->k != MPT_IDENT)) {
        mpa_perr(c->p, c->line, "expected fault kind");
    }
    c->pos++;
    if (token->k == MPT_STR) {
        term.fault = MF_MESSAGE;
        term.fault_str = mir_add_string(c->p->m, token->s, token->n);
        return term;
    }
    for (size_t i = 0; i < sizeof kind_names / sizeof kind_names[0]; i++) {
        if (mpa_tok_is(token, kind_names[i])) {
            term.fault = (uint8_t)i;
            return term;
        }
    }
    mpa_perr(c->p, c->line, "unknown fault kind %.*s", (int)token->n, token->s);
}

/* The terminator named by `mnemonic`; false when it names an instruction instead. */
static bool mpa_parse_terminator(MpCur *c, MirFunc *f, MpTok mnemonic, MirTerm *term) {
    *term = (MirTerm){.value = MIR_NONE};
    if (mpa_tok_is(&mnemonic, "br")) {
        term->kind = MT_BR;
        term->a = mpa_parse_target(c, f);
    } else if (mpa_tok_is(&mnemonic, "br_if")) {
        term->kind = MT_CONDBR;
        term->value = mpa_value_of(c->p, f, mpa_c_val(c));
        mpa_c_expect_p(c, ',');
        term->a = mpa_parse_target(c, f);
        mpa_c_expect_p(c, ',');
        term->b = mpa_parse_target(c, f);
    } else if (mpa_tok_is(&mnemonic, "switch")) {
        *term = mpa_term_switch(c, f);
    } else if (mpa_tok_is(&mnemonic, "ret")) {
        term->kind = MT_RET;
        if (mpa_c_peek_kind(c, MPT_VAL)) {
            term->value = mpa_value_of(c->p, f, mpa_c_val(c));
        }
    } else if (mpa_tok_is(&mnemonic, "unreachable")) {
        term->kind = MT_UNREACHABLE;
    } else if (mpa_tok_is(&mnemonic, "fault")) {
        *term = mpa_term_fault(c);
    } else {
        return false;
    }
    return true;
}

static MirLoc mpa_optional_location(MpCur *c) {
    if (!mpa_c_peek_kind(c, MPT_LOC)) {
        return MIR_LOC_NONE;
    }
    MirLoc location = mpa_c_peek(c)->loc;
    c->pos++;
    return location;
}

/* The comparison suffix of a mnemonic such as `icmp.lt`, or -1. */
static int mpa_condition_suffix(const char *text, size_t length) {
    for (int i = 0; i < 6; i++) {
        if (strlen(mir_cc_name[i]) == length && memcmp(mir_cc_name[i], text, length) == 0) {
            return i;
        }
    }
    return -1;
}

/* The opcode a mnemonic names, with the condition of `icmp.lt` and its kin in `*cc` (else -1). */
static MirOp mpa_resolve_op(const MpCur *c, MpTok mnemonic, int *cc) {
    *cc = -1;
    int op = mir_op_from_name(mnemonic.s, mnemonic.n);
    if (op >= 0) {
        return (MirOp)op;
    }
    size_t dot = mnemonic.n;
    while (dot > 0 && mnemonic.s[dot - 1] != '.') {
        dot--;
    }
    if (dot > 0) {
        int head = mir_op_from_name(mnemonic.s, dot - 1);
        *cc = mpa_condition_suffix(mnemonic.s + dot, mnemonic.n - dot);
        if ((head == MOP_ICmp || head == MOP_UICmp || head == MOP_FCmp) && *cc >= 0) {
            return (MirOp)head;
        }
    }
    mpa_perr(c->p, c->line, "unknown instruction '%.*s'", (int)mnemonic.n, mnemonic.s);
}

typedef struct MpResult {
    bool present;
    MpTok name;
    MirTy type;
} MpResult;

static MpResult mpa_parse_result(MpCur *c) {
    MpResult result = {0};
    if (!mpa_c_peek_kind(c, MPT_VAL)) {
        return result;
    }
    result.present = true;
    result.name = mpa_c_val(c);
    mpa_c_expect_p(c, ':');
    result.type = mpa_parse_ty(c);
    mpa_c_expect_p(c, '=');
    return result;
}

/* The runtime declares one symbol once per instantiation (`msrt_map_new` for each map type), and the
 * text names only the symbol, so the extern a call means is the one of that name whose signature
 * its operands and result match. The first of the name stays when none (or all) match. */
static uint32_t mpa_pick_extern(const MirModule *m, const MirFunc *f, const MirInst *inst,
                                const MpResult *result) {
    const uint32_t first = inst->imm.a;
    const MirTy want = result->present ? result->type : MIR_VOID;
    for (uint32_t e = 0; e < m->nexterns; e++) {
        const MirExtern *x = &m->externs[e];
        if (x->name != m->externs[first].name || x->nparams != inst->nargs || x->ret != want) {
            continue;
        }
        bool same = true;
        for (uint32_t k = 0; k < x->nparams && same; k++) {
            same = inst->args[k] < f->nvalues && f->values[inst->args[k]] == x->params[k].ty;
        }
        if (same) {
            return e;
        }
    }
    return first;
}

static void mpa_parse_instruction(MpCur *c, MirFunc *f, MirBlock b, MpTok mnemonic,
                                  const MpResult *result) {
    MirModule *m = c->p->m;
    int cc = -1;
    MirOp op = mpa_resolve_op(c, mnemonic, &cc);
    if ((bool)mir_op_info[op].has_result != result->present) {
        if (mir_op_info[op].has_result) {
            mpa_perr(c->p, c->line, "%.*s needs a result: %%v: type = %.*s ...", (int)mnemonic.n,
                     mnemonic.s, (int)mnemonic.n, mnemonic.s);
        }
        mpa_perr(c->p, c->line, "%.*s has no result", (int)mnemonic.n, mnemonic.s);
    }
    MirInst inst = {.op = (uint8_t)op, .res = MIR_NONE};
    inst.imm = mpa_parse_imm(c, op, cc, mnemonic);
    bool parenthesized = mir_op_is_call(op);
    if (parenthesized) {
        mpa_c_expect_p(c, '(');
    }
    uint32_t capacity = 0;
    MirValue *args = NULL;
    while (mpa_c_peek_kind(c, MPT_VAL)) {
        MirValue arg = mpa_value_of(c->p, f, mpa_c_val(c));
        MIR_PUSH(m, args, inst.nargs, capacity, MirValue, arg);
        if (!mpa_c_eat_p(c, ',')) {
            break;
        }
    }
    inst.args = args;
    if (parenthesized) {
        mpa_c_expect_p(c, ')');
    }
    inst.loc = mpa_optional_location(c);
    if (!mpa_c_done(c)) {
        mpa_perr(c->p, c->line, "unexpected token after instruction");
    }
    if (inst.imm.tag == MI_EXT) {
        inst.imm.a = mpa_pick_extern(m, f, &inst, result);
    }
    if (result->present) {
        inst.res = mpa_define(c, f, result->name, result->type);
    }
    MirBlockData *block = &f->blocks[b];
    MIR_PUSH(m, block->insts, block->ninsts, block->cinsts, MirInst, inst);
}

static void mpa_parse_line(MpCur *c, MirFunc *f, MirBlock b) {
    MpResult result = mpa_parse_result(c);
    MpTok mnemonic = mpa_c_ident(c);
    MirTerm term;
    if (!mpa_parse_terminator(c, f, mnemonic, &term)) {
        mpa_parse_instruction(c, f, b, mnemonic, &result);
        return;
    }
    if (result.present) {
        mpa_perr(c->p, c->line, "terminators have no result");
    }
    MirLoc location = mpa_optional_location(c);
    if (!mpa_c_done(c)) {
        mpa_perr(c->p, c->line, "unexpected tokens after terminator");
    }
    f->blocks[b].term = term;
    f->blocks[b].term_loc = location;
    c->p->terminated[b] = 1;
}

static bool mpa_is_label(const MpTok *t, uint32_t n) {
    return n > 0 && t[0].k == MPT_IDENT && t[n - 1].k == MPT_P && t[n - 1].ch == ':' && !mpa_tok_is(&t[0], "switch");
}

/* A trailing fact line: `scope`, `name` or `exact` (no instruction is called that). */
static bool mpa_is_fact(const MpTok *t, uint32_t n) {
    return n > 0 && t[0].k == MPT_IDENT &&
           (mpa_tok_is(&t[0], "scope") || mpa_tok_is(&t[0], "name") || mpa_tok_is(&t[0], "exact"));
}

typedef struct MpBodyLine {
    uint32_t no;
    MpTok *t;
    uint32_t nt;
} MpBodyLine;

/* The function's parameters are the entry block's; their names go in the value table. */
static void mpa_declare_params(MpParser *p, MirFunc *f, const MpTok *names, uint32_t count,
                               uint32_t line0) {
    for (uint32_t i = 0; i < count; i++) {
        MsSym sym = ms_intern(&p->vnames, names[i].s, names[i].n);
        if (mpa_vname_lookup(p, sym) != MIR_NONE) {
            mpa_perr(p, line0, "parameter %%%.*s defined twice", (int)names[i].n, names[i].s);
        }
        mpa_grow_names(&p->val_of, &p->val_gen, &p->nval_cap, sym);
        MirValue value = f->blocks[0].params[i].value;
        p->val_of[sym] = value;
        p->val_gen[sym] = p->gen;
        p->defined[value] = 1;
    }
}

/* Tokenizes the body lines, dropping the ones that are empty or only a comment. */
static MpBodyLine *mpa_tokenize_body(MpParser *p, const MpFnSrc *src, uint32_t *count) {
    MpBodyLine *lines = NULL;
    uint32_t used = 0, capacity = 0;
    for (uint32_t i = 0; i < src->nbody; i++) {
        MpBodyLine line = {.no = src->body[i].no};
        line.t = mpa_tokenize(p, src->body[i].s, src->body[i].n, line.no, &line.nt);
        if (line.nt > 0) {
            MIR_PUSH(p->m, lines, used, capacity, MpBodyLine, line);
        }
    }
    *count = used;
    return lines;
}

/* Creates a block for every label, so a branch may name a block that comes later. */
static void mpa_declare_blocks(MpParser *p, MirFunc *f, const MpBodyLine *lines, uint32_t count) {
    bool first = true;
    for (uint32_t i = 0; i < count; i++) {
        if (!mpa_is_label(lines[i].t, lines[i].nt)) {
            if (first && !mpa_is_fact(lines[i].t, lines[i].nt)) {
                mpa_perr(p, lines[i].no, "function body must start with a block label");
            }
            continue;
        }
        MpTok name = lines[i].t[0];
        MsSym sym = ms_intern(&p->bnames, name.s, name.n);
        bool taken = sym < p->nblk_cap && p->blk_gen[sym] == p->gen;
        if (taken && !first) {
            mpa_perr(p, lines[i].no, "block %.*s defined twice", (int)name.n, name.s);
        }
        mpa_grow_names(&p->blk_of, &p->blk_gen, &p->nblk_cap, sym);
        p->blk_of[sym] = first ? 0 : mir_new_block(p->m, f);
        p->blk_gen[sym] = p->gen;
        first = false;
    }
}

/* A label line, `name:` or `name(%v: type, ...):`; returns the block it opens. */
static MirBlock mpa_parse_label(MpCur *c, MirFunc *f) {
    MpParser *p = c->p;
    MpTok name = mpa_c_ident(c);
    MirBlock block = p->blk_of[ms_intern(&p->bnames, name.s, name.n)];
    if (block == 0) {
        if (mpa_c_eat_p(c, '(')) {
            mpa_perr(p, c->line, "the entry block takes the function parameters");
        }
        return block;
    }
    if (!mpa_c_eat_p(c, '(')) {
        return block;
    }
    MirBlockData *data = &f->blocks[block];
    while (!mpa_c_eat_p(c, ')')) {
        MpTok value_name = mpa_c_val(c);
        mpa_c_expect_p(c, ':');
        bool owned = mpa_c_eat_ident(c, "move");
        MirTy type = mpa_parse_ty(c);
        MirBlockParam param = {mpa_define(c, f, value_name, type), owned ? MM_MOVE : MM_BORROW};
        MIR_PUSH(p->m, data->params, data->nparams, data->cparams, MirBlockParam, param);
        mpa_c_eat_p(c, ',');
    }
    return block;
}

/* `scope "name" file parent call_line`, `name %v "text" param|local scope` and `exact %v`. */
static void mpa_parse_fact(MpCur *c, MirFunc *f) {
    MpParser *p = c->p;
    MirModule *m = p->m;
    const MpTok keyword = mpa_c_ident(c);
    if (mpa_tok_is(&keyword, "scope")) {
        const MpTok name = mpa_c_string(c);
        MirScope scope = {.name = mir_name(m, name.s, name.n)};
        scope.file = mpa_imm_u32(c, "scope number");
        scope.parent = mpa_imm_u32(c, "scope number");
        scope.call_line = mpa_imm_u32(c, "scope number");
        MIR_PUSH(m, f->scopes, f->nscopes, f->cscopes, MirScope, scope);
        return;
    }
    const MpTok value_name = mpa_c_val(c);
    const uint32_t value = mpa_vname_lookup(p, ms_intern(&p->vnames, value_name.s, value_name.n));
    if (value == MIR_NONE || value >= p->cdefined || !p->defined[value]) {
        mpa_perr(p, c->line, "%%%.*s is not defined", (int)value_name.n, value_name.s);
    }
    if (mpa_tok_is(&keyword, "exact")) {
        const uint32_t words = (f->nvalues + 63) / 64;
        if (f->nexact < words) {
            uint64_t *grown = MS_NEW_N(&m->arena, uint64_t, words);
            memset(grown, 0, (size_t)words * sizeof *grown);
            if (f->nexact != 0) {
                memcpy(grown, f->exact, (size_t)f->nexact * sizeof *grown);
            }
            f->exact = grown;
            f->nexact = words;
        }
        f->exact[value >> 6] |= UINT64_C(1) << (value & 63);
        return;
    }
    const MpTok text = mpa_c_string(c);
    const MpTok kind = mpa_c_ident(c);
    if (!mpa_tok_is(&kind, "param") && !mpa_tok_is(&kind, "local")) {
        mpa_perr(p, c->line, "expected param or local, found %.*s", (int)kind.n, kind.s);
    }
    MirNamedValue named = {.value = value, .name = mir_name(m, text.s, text.n),
                           .param = mpa_tok_is(&kind, "param")};
    named.scope = mpa_imm_u32(c, "scope number");
    MIR_PUSH(m, f->names, f->nnames, f->cnames, MirNamedValue, named);
}

/* Every block must end in a terminator and every value used must be defined. */
static void mpa_check_complete(MpParser *p, const MirFunc *f, uint32_t line0) {
    MsStr function = ms_name(&p->m->names, f->name);
    for (uint32_t i = 0; i < f->nblocks; i++) {
        if (!p->terminated[i]) {
            mpa_perr(p, line0, "block b%u of @%.*s has no terminator", i,
                     (int)function.len, function.ptr);
        }
    }
    for (uint32_t sym = 0; sym < p->nval_cap; sym++) {
        if (p->val_gen[sym] != p->gen) {
            continue;
        }
        uint32_t value = p->val_of[sym];
        if (value >= p->cdefined || !p->defined[value]) {
            MsStr name = ms_name(&p->vnames, sym);
            mpa_perr(p, line0, "%%%.*s is used but never defined in @%.*s", (int)name.len,
                     name.ptr, (int)function.len, function.ptr);
        }
    }
}

static void mpa_parse_body(MpParser *p, uint32_t id, const MpFnSrc *src, const MpTok *param_names,
                           uint32_t param_count) {
    MirFunc *f = &p->m->funcs[id];
    p->gen++;
    uint32_t line0 = src->nbody ? src->body[0].no : 0;
    uint32_t needed = f->nvalues * 2 + 8;
    if (p->cdefined < needed) {
        p->defined = mpa_realloc(p->defined, needed);
        p->cdefined = needed;
    }
    memset(p->defined, 0, p->cdefined);
    mpa_declare_params(p, f, param_names, param_count, line0);
    uint32_t line_count = 0;
    const MpBodyLine *lines = mpa_tokenize_body(p, src, &line_count);
    mpa_declare_blocks(p, f, lines, line_count);
    p->terminated = mpa_realloc(NULL, f->nblocks + 1);
    memset(p->terminated, 0, f->nblocks + 1);
    MirBlock current = MIR_NONE;
    for (uint32_t i = 0; i < line_count; i++) {
        MpCur c = {p, lines[i].t, lines[i].nt, 0, lines[i].no};
        if (mpa_is_label(c.t, c.n)) {
            current = mpa_parse_label(&c, f);
            continue;
        }
        if (mpa_is_fact(c.t, c.n)) {
            continue; /* read once every value is defined */
        }
        if (p->terminated[current]) {
            mpa_perr(p, c.line, "instruction after the block terminator");
        }
        mpa_parse_line(&c, f, current);
    }
    for (uint32_t i = 0; i < line_count; i++) {
        if (mpa_is_fact(lines[i].t, lines[i].nt)) {
            MpCur c = {p, lines[i].t, lines[i].nt, 0, lines[i].no};
            mpa_parse_fact(&c, f);
        }
    }
    mpa_check_complete(p, f, line0);
    free(p->terminated);
    p->terminated = NULL;
}

/* ---- top level ---- */

static MpLine mpa_trim_line(const char *s, size_t n) {
    while (n > 0 && mpa_ws_char((unsigned char)s[0])) {
        s++;
        n--;
    }
    while (n > 0 && mpa_ws_char((unsigned char)s[n - 1])) {
        n--;
    }
    return (MpLine){0, s, (uint32_t)n};
}

static bool mpa_line_starts(MpLine l, const char *pre) {
    size_t n = strlen(pre);
    return l.n >= n && memcmp(l.s, pre, n) == 0;
}

/* Everything the parser reads from the text: item lines, and function sources. */
/* The function names a header gives `slot_result` and `close_exit`, resolved once every function
 * is declared. */
typedef struct MpFnRefs {
    uint32_t id;
    bool has_slot, has_exit;
    MpTok slot, exit[2];
    MpTok *closers; /* capture index and function name, alternating */
    uint32_t nclosers, cclosers;
} MpFnRefs;

typedef struct MpUnit {
    MpFnRefs *refs; /* by function */
    MpItem *items;
    uint32_t item_count, item_capacity;
    MpFnSrc *fns;
    uint32_t fn_count, fn_capacity;
    MpTok **param_names; /* by function */
    uint32_t *param_counts;
    bool has_entry;
    MpTok entry_name;
    uint32_t entry_line;
    bool has_close;
    MpTok close_name;
    uint32_t close_line;
} MpUnit;

/* Reads the next line of `src` from `*pos`, without its line ending. */
static MpLine mpa_next_line(const char *src, size_t len, size_t *pos, uint32_t *number) {
    size_t start = *pos;
    const char *newline = memchr(src + start, '\n', len - start);
    size_t end = newline != NULL ? (size_t)(newline - src) : len;
    *pos = newline != NULL ? end + 1 : len;
    if (end > start && src[end - 1] == '\r') {
        end--;
    }
    (*number)++;
    return (MpLine){*number, src + start, (uint32_t)(end - start)};
}

/* A function's body: the lines up to one holding only `}`. */
static MpFnSrc mpa_read_function(MpParser *p, MpLine header, const char *src, size_t len,
                                 size_t *pos, uint32_t *number) {
    MpFnSrc fn = {.header = header};
    while (*pos < len) {
        MpLine raw = mpa_next_line(src, len, pos, number);
        MpLine trimmed = mpa_trim_line(raw.s, raw.n);
        if (trimmed.n == 1 && trimmed.s[0] == '}') {
            return fn;
        }
        MIR_PUSH(p->m, fn.body, fn.nbody, fn.cbody, MpLine, raw);
    }
    mpa_perr(p, header.no, "function body is not closed with '}'");
}

/* Groups lines into items (one line each) and functions (a header and a body). */
static void mpa_split_lines(MpParser *p, const char *src, size_t len, MpUnit *unit) {
    size_t pos = 0;
    uint32_t number = 0;
    while (pos < len) {
        MpLine raw = mpa_next_line(src, len, &pos, &number);
        MpLine line = mpa_trim_line(raw.s, raw.n);
        line.no = raw.no;
        if (line.n == 0 || line.s[0] == ';') {
            continue;
        }
        if (mpa_line_starts(line, "fn ")) {
            MpFnSrc fn = mpa_read_function(p, line, src, len, &pos, &number);
            MIR_PUSH(p->m, unit->fns, unit->fn_count, unit->fn_capacity, MpFnSrc, fn);
        } else {
            MpItem item = {.no = line.no, .s = line.s, .n = line.n};
            MIR_PUSH(p->m, unit->items, unit->item_count, unit->item_capacity, MpItem, item);
        }
    }
    for (uint32_t i = 0; i < unit->item_count; i++) {
        MpItem *item = &unit->items[i];
        item->t = mpa_tokenize(p, item->s, item->n, item->no, &item->nt);
    }
}

static MpCur mpa_item_cursor(MpParser *p, const MpItem *item) {
    return (MpCur){p, item->t, item->nt, 0, item->no};
}

/* Pass A: the names of types, alternatives and interfaces, so declarations may refer to each other. */
static void mpa_declare_names(MpParser *p, const MpUnit *unit) {
    for (uint32_t i = 0; i < unit->item_count; i++) {
        MpCur c = mpa_item_cursor(p, &unit->items[i]);
        MpTok keyword = mpa_c_ident(&c);
        if (!mpa_tok_is(&keyword, "type") && !mpa_tok_is(&keyword, "alt") &&
            !mpa_tok_is(&keyword, "iface")) {
            continue;
        }
        MsSym name = mpa_tsym(&c, mpa_c_ident(&c));
        if (mpa_tok_is(&keyword, "type")) {
            const uint32_t id = mir_add_type(p->m, name);
            p->m->type_defs[id].indirect = mpa_c_eat_ident(&c, "indirect");
        } else if (mpa_tok_is(&keyword, "alt")) {
            mir_add_alt(p->m, name);
        } else {
            mir_add_iface(p->m, name);
        }
    }
}

static MirField mpa_parse_field(MpCur *c) {
    MpTok name = mpa_c_ident(c);
    mpa_c_expect_p(c, ':');
    return (MirField){mpa_tsym(c, name), mpa_parse_ty(c)};
}

static void mpa_define_type(MpCur *c) {
    MirModule *m = c->p->m;
    uint32_t id = mir_type_by_name(m, mpa_tsym(c, mpa_c_ident(c)));
    (void)mpa_c_eat_ident(c, "indirect"); /* read by the first pass */
    mpa_c_expect_p(c, '{');
    MirField *fields = NULL;
    uint32_t used = 0, capacity = 0;
    while (!mpa_c_eat_p(c, '}')) {
        MirField field = mpa_parse_field(c);
        MIR_PUSH(m, fields, used, capacity, MirField, field);
        mpa_c_eat_p(c, ',');
    }
    m->type_defs[id].fields = fields;
    m->type_defs[id].nfields = used;
}

static MirCaseDef mpa_parse_case(MpCur *c) {
    MirCaseDef def = {.name = mpa_tsym(c, mpa_c_ident(c))};
    uint32_t capacity = 0;
    if (mpa_c_eat_p(c, '(')) {
        while (!mpa_c_eat_p(c, ')')) {
            MirField field = mpa_parse_field(c);
            MIR_PUSH(c->p->m, def.fields, def.nfields, capacity, MirField, field);
            mpa_c_eat_p(c, ',');
        }
    }
    return def;
}

static void mpa_define_alt(MpCur *c) {
    MirModule *m = c->p->m;
    uint32_t id = mir_alt_by_name(m, mpa_tsym(c, mpa_c_ident(c)));
    if (mpa_c_eat_ident(c, "borrowed")) {
        MpTok mask = mpa_c_num(c);
        uint32_t bits = 0; /* a bit per case; a variant has fewer than 32 */
        if (!mpa_parse_u32(mask.s, mask.n, &bits)) {
            mpa_perr(c->p, c->line, "bad borrowed mask");
        }
        m->alts[id].borrowed = bits;
    }
    mpa_c_expect_p(c, '{');
    MirCaseDef *cases = NULL;
    uint32_t used = 0, capacity = 0;
    while (!mpa_c_eat_p(c, '}')) {
        MirCaseDef def = mpa_parse_case(c);
        MIR_PUSH(m, cases, used, capacity, MirCaseDef, def);
        mpa_c_eat_p(c, ',');
    }
    m->alts[id].cases = cases;
    m->alts[id].ncases = used;
    m->alts[id].std = mpa_parse_std(c);
}

static MirMethodSig mpa_parse_method_sig(MpCur *c) {
    MirMethodSig sig = {.name = mpa_tsym(c, mpa_c_ident(c)), .ret = MIR_VOID};
    uint32_t capacity = 0;
    mpa_c_expect_p(c, '(');
    while (!mpa_c_eat_p(c, ')')) {
        if (mpa_c_eat_ident(c, "move") && sig.nparams < 64) {
            sig.owned |= 1ull << sig.nparams;
        }
        MirTy param = mpa_parse_ty(c);
        MIR_PUSH(c->p->m, sig.params, sig.nparams, capacity, MirTy, param);
        mpa_c_eat_p(c, ',');
    }
    if (mpa_c_peek_kind(c, MPT_ARROW)) {
        c->pos++;
        sig.ret = mpa_parse_ty(c);
    }
    return sig;
}

static void mpa_define_iface(MpCur *c) {
    MirModule *m = c->p->m;
    uint32_t id = mir_iface_by_name(m, mpa_tsym(c, mpa_c_ident(c)));
    mpa_c_expect_p(c, '{');
    MirMethodSig *methods = NULL;
    uint32_t used = 0, capacity = 0;
    while (!mpa_c_eat_p(c, '}')) {
        MirMethodSig sig = mpa_parse_method_sig(c);
        MIR_PUSH(m, methods, used, capacity, MirMethodSig, sig);
        mpa_c_eat_p(c, ',');
    }
    m->ifaces[id].methods = methods;
    m->ifaces[id].nmethods = used;
    m->ifaces[id].std = mpa_parse_std(c);
}

/* Pass B: the bodies of type, alternative and interface declarations. */
static void mpa_define_declarations(MpParser *p, const MpUnit *unit) {
    for (uint32_t i = 0; i < unit->item_count; i++) {
        MpCur c = mpa_item_cursor(p, &unit->items[i]);
        MpTok keyword = mpa_c_ident(&c);
        if (mpa_tok_is(&keyword, "type")) {
            mpa_define_type(&c);
        } else if (mpa_tok_is(&keyword, "alt")) {
            mpa_define_alt(&c);
        } else if (mpa_tok_is(&keyword, "iface")) {
            mpa_define_iface(&c);
        }
    }
}

static void mpa_item_file(MpCur *c) {
    MirModule *m = c->p->m;
    MpTok index_text = mpa_c_num(c);
    int64_t index = 0;
    if (!mpa_parse_i64(index_text.s, index_text.n, &index) || index < 0) {
        mpa_perr(c->p, c->line, "bad file index");
    }
    MpTok path = mpa_c_string(c);
    if ((uint64_t)index != m->nfiles) {
        mpa_perr(c->p, c->line, "files must be numbered consecutively from 0");
    }
    MsStr copy = {ms_arena_strndup(&m->arena, path.s, path.n), path.n};
    MIR_PUSH(m, m->files, m->nfiles, m->cfiles, MsStr, copy);
}

/* The index of a `blob` or `consts` item, which must be the next one. */
static void mpa_item_numbered(MpCur *c, const char *what, uint32_t expected) {
    MpTok index_text = mpa_c_num(c);
    int64_t index = 0;
    if (!mpa_parse_i64(index_text.s, index_text.n, &index) || index < 0) {
        mpa_perr(c->p, c->line, "bad %s index", what);
    }
    if ((uint64_t)index != expected) {
        mpa_perr(c->p, c->line, "%s entries must be numbered consecutively from 0", what);
    }
}

static void mpa_item_blob(MpCur *c) {
    MirModule *m = c->p->m;
    mpa_item_numbered(c, "blob", m->nblobs);
    MpTok hex = mpa_c_string(c);
    const char *failure = "blob payload must be an even number of hex digits";
    if (hex.n % 2 != 0) {
        mpa_perr(c->p, c->line, "%s", failure);
    }
    char *bytes = ms_alloc(&m->arena, hex.n / 2 + 1, 1);
    for (uint32_t k = 0; k < hex.n; k += 2) {
        int high = ms_text_digit_value(hex.s[k]);
        int low = ms_text_digit_value(hex.s[k + 1]);
        if (high < 0 || low < 0) {
            mpa_perr(c->p, c->line, "%s", failure);
        }
        bytes[k / 2] = (char)(high * 16 + low);
    }
    MsStr blob = {bytes, hex.n / 2};
    MIR_PUSH(m, m->blobs, m->nblobs, m->cblobs, MsStr, blob);
}

static void mpa_item_consts(MpCur *c) {
    MirModule *m = c->p->m;
    mpa_item_numbered(c, "consts", m->nlist_consts);
    mpa_c_expect_p(c, '[');
    MirConsts list = {0};
    uint32_t capacity = 0;
    while (!mpa_c_eat_p(c, ']')) {
        MpTok text = mpa_c_num(c);
        int64_t value = 0;
        if (!mpa_parse_i64(text.s, text.n, &value)) {
            mpa_perr(c->p, c->line, "bad consts element");
        }
        MIR_PUSH(m, list.v, list.n, capacity, int64_t, value);
        mpa_c_eat_p(c, ',');
    }
    MIR_PUSH(m, m->list_consts, m->nlist_consts, m->clist_consts, MirConsts, list);
}

static void mpa_extern_attribute(MpCur *c, MirExtern *e) {
    MpTok attribute = mpa_c_ident(c);
    if (mpa_tok_is(&attribute, "noreturn")) {
        e->noreturn = true;
    } else if (mpa_tok_is(&attribute, "pure")) {
        e->pure = true;
    } else if (mpa_tok_is(&attribute, "fresh")) {
        e->fresh = true;
    } else if (mpa_tok_is(&attribute, "leaf")) {
        e->leaf = true;
    } else if (mpa_tok_is(&attribute, "reads")) {
        e->reads = true;
    } else if (mpa_tok_is(&attribute, "retains")) {
        e->retains = true;
    } else {
        int role = mir_role_from_name(attribute.s, attribute.n);
        if (role == MR_NONE) {
            mpa_perr(c->p, c->line, "unknown extern attribute %.*s", (int)attribute.n, attribute.s);
        }
        e->role = (uint8_t)role;
    }
}

static MirParam mpa_parse_param(MpCur *c) {
    bool owned = mpa_c_eat_ident(c, "move");
    MirTy type = mpa_parse_ty(c);
    return (MirParam){type, owned ? MM_MOVE : MM_BORROW};
}

static void mpa_item_extern(MpCur *c) {
    MirExtern e = {.name = mpa_tsym(c, mpa_c_at(c)), .ret = MIR_VOID};
    uint32_t capacity = 0;
    mpa_c_expect_p(c, '(');
    while (!mpa_c_eat_p(c, ')')) {
        MirParam param = mpa_parse_param(c);
        MIR_PUSH(c->p->m, e.params, e.nparams, capacity, MirParam, param);
        mpa_c_eat_p(c, ',');
    }
    if (mpa_c_peek_kind(c, MPT_ARROW)) {
        c->pos++;
        e.ret = mpa_parse_ty(c);
    }
    while (!mpa_c_done(c)) {
        mpa_extern_attribute(c, &e);
    }
    mir_add_extern(c->p->m, &e);
}

static void mpa_item_module(MpCur *c) {
    const MpTok *name = mpa_c_peek(c);
    if (name == NULL || (name->k != MPT_STR && name->k != MPT_IDENT)) {
        mpa_perr(c->p, c->line, "expected module name");
    }
    c->pos++;
    c->p->m->name = mir_name(c->p->m, name->s, name->n);
}

/* Pass C: module, files, constants, externs, globals and the entry name. */
static void mpa_declare_items(MpParser *p, MpUnit *unit) {
    for (uint32_t i = 0; i < unit->item_count; i++) {
        MpCur c = mpa_item_cursor(p, &unit->items[i]);
        MpTok keyword = mpa_c_ident(&c);
        if (mpa_tok_is(&keyword, "module")) {
            mpa_item_module(&c);
        } else if (mpa_tok_is(&keyword, "file")) {
            mpa_item_file(&c);
        } else if (mpa_tok_is(&keyword, "blob")) {
            mpa_item_blob(&c);
        } else if (mpa_tok_is(&keyword, "consts")) {
            mpa_item_consts(&c);
        } else if (mpa_tok_is(&keyword, "extern")) {
            mpa_item_extern(&c);
        } else if (mpa_tok_is(&keyword, "global")) {
            MsSym name = mpa_tsym(&c, mpa_c_at(&c));
            mpa_c_expect_p(&c, ':');
            mir_add_global(p->m, name, mpa_parse_ty(&c));
        } else if (mpa_tok_is(&keyword, "entry")) {
            unit->entry_name = mpa_c_at(&c);
            unit->entry_line = unit->items[i].no;
            unit->has_entry = true;
        } else if (mpa_tok_is(&keyword, "close")) {
            unit->close_name = mpa_c_at(&c);
            unit->close_line = unit->items[i].no;
            unit->has_close = true;
        } else if (!mpa_tok_is(&keyword, "vtable") && !mpa_tok_is(&keyword, "desc_glue") &&
                   !mpa_tok_is(&keyword, "type") &&
                   !mpa_tok_is(&keyword, "alt") && !mpa_tok_is(&keyword, "iface")) {
            mpa_perr(p, c.line, "unknown item '%.*s'", (int)keyword.n, keyword.s);
        }
    }
}

/* One attribute of a function header, after `fn @name(...) -> type`. */
static void mpa_function_attribute(MpCur *c, MirModule *m, MirFunc *f, MpFnRefs *refs) {
    MpTok attribute = mpa_c_ident(c);
    if (mpa_tok_is(&attribute, "export")) {
        f->linkage = ML_EXPORT;
    } else if (mpa_tok_is(&attribute, "explicit_cancel")) {
        f->explicit_cancel = true;
    } else if (mpa_tok_is(&attribute, "noalias")) {
        uint32_t capacity = 0;
        mpa_c_expect_p(c, '(');
        while (!mpa_c_eat_p(c, ')')) {
            uint32_t index = mpa_imm_u32(c, "parameter index");
            MIR_PUSH(m, f->noalias, f->nnoalias, capacity, uint32_t, index);
            mpa_c_eat_p(c, ',');
        }
    } else if (mpa_tok_is(&attribute, "slot_result")) {
        mpa_c_expect_p(c, '(');
        refs->has_slot = true;
        refs->slot = mpa_c_at(c);
        mpa_c_expect_p(c, ')');
    } else if (mpa_tok_is(&attribute, "close_exit")) {
        mpa_c_expect_p(c, '(');
        refs->has_exit = true;
        refs->exit[0] = mpa_c_at(c);
        mpa_c_expect_p(c, ',');
        refs->exit[1] = mpa_c_at(c);
        mpa_c_expect_p(c, ')');
    } else if (mpa_tok_is(&attribute, "ret_borrowed")) {
        f->ret_borrowed = true;
    } else if (mpa_tok_is(&attribute, "ret_view")) {
        f->ret_view = true;
    } else if (mpa_tok_is(&attribute, "scoped")) {
        f->scoped = true;
    } else if (mpa_tok_is(&attribute, "keeps_scoped")) {
        f->keeps_scoped = true;
    } else if (mpa_tok_is(&attribute, "unwind_only")) {
        f->unwind_only = true;
    } else if (mpa_tok_is(&attribute, "raw_scratch")) {
        f->raw_scratch = true;
    } else if (mpa_tok_is(&attribute, "slot_close")) {
        mpa_c_expect_p(c, '(');
        f->has_slot_close = true;
        f->slot_close = mpa_parse_ty(c);
        mpa_c_expect_p(c, ')');
    } else if (mpa_tok_is(&attribute, "capture_closers")) {
        mpa_c_expect_p(c, '(');
        while (!mpa_c_eat_p(c, ')')) {
            const MpTok index = mpa_c_num(c);
            const MpTok func = mpa_c_at(c);
            MIR_PUSH(m, refs->closers, refs->nclosers, refs->cclosers, MpTok, index);
            MIR_PUSH(m, refs->closers, refs->nclosers, refs->cclosers, MpTok, func);
            mpa_c_eat_p(c, ',');
        }
    } else if (mpa_tok_is(&attribute, "method")) {
        f->kind = MFK_METHOD;
    } else if (mpa_tok_is(&attribute, "sort_cmp")) {
        f->sort = MSORT_GENERIC;
    } else if (mpa_tok_is(&attribute, "sort_cmp_for")) {
        f->sort = MSORT_SPECIALIZED;
    } else if (mpa_tok_is(&attribute, "inline")) {
        mpa_c_expect_p(c, '(');
        MpTok hint = mpa_c_ident(c);
        if (!mpa_tok_is(&hint, "always") && !mpa_tok_is(&hint, "never")) {
            mpa_perr(c->p, c->line, "unknown inline hint %.*s", (int)hint.n, hint.s);
        }
        f->inline_hint = mpa_tok_is(&hint, "always") ? MINL_ALWAYS : MINL_NEVER;
        mpa_c_expect_p(c, ')');
    } else if (mpa_tok_is(&attribute, "closure")) {
        uint32_t capacity = 0;
        mpa_c_expect_p(c, '(');
        while (!mpa_c_eat_p(c, ')')) {
            MirTy type = mpa_parse_ty(c);
            MIR_PUSH(m, f->captures, f->ncaptures, capacity, MirTy, type);
            mpa_c_eat_p(c, ',');
        }
        f->kind = MFK_CLOSURE;
    } else {
        mpa_perr(c->p, c->line, "unknown function attribute %.*s", (int)attribute.n, attribute.s);
    }
}

/* The attributes and position between the result type and the opening brace. */
static void mpa_function_attributes(MpCur *c, MirFunc *f, MpFnRefs *refs) {
    for (;;) {
        if (mpa_c_eat_p(c, '{')) {
            return;
        }
        if (mpa_c_peek_kind(c, MPT_LOC)) {
            f->loc = mpa_c_peek(c)->loc;
            c->pos++;
        } else if (mpa_c_peek_kind(c, MPT_IDENT)) {
            mpa_function_attribute(c, c->p->m, f, refs);
        } else if (mpa_c_peek(c) == NULL) {
            mpa_perr(c->p, c->line, "expected '{'");
        } else {
            mpa_perr(c->p, c->line, "unexpected token in function header");
        }
    }
}

/* Declares one function from its header; its parameter names go to `unit` for the body pass. */
static void mpa_declare_function(MpParser *p, MpUnit *unit, uint32_t index) {
    MirModule *m = p->m;
    const MpFnSrc *src = &unit->fns[index];
    uint32_t token_count = 0;
    MpTok *tokens = mpa_tokenize(p, src->header.s, src->header.n, src->header.no, &token_count);
    MpCur c = {p, tokens, token_count, 0, src->header.no};
    mpa_c_ident(&c); /* fn */
    MsSym name = mpa_tsym(&c, mpa_c_at(&c));
    mpa_c_expect_p(&c, '(');
    MirParam *params = NULL;
    MpTok *names = NULL;
    uint32_t param_count = 0, param_capacity = 0, name_count = 0, name_capacity = 0;
    while (!mpa_c_eat_p(&c, ')')) {
        MpTok value_name = mpa_c_val(&c);
        MIR_PUSH(m, names, name_count, name_capacity, MpTok, value_name);
        mpa_c_expect_p(&c, ':');
        MirParam param = mpa_parse_param(&c);
        MIR_PUSH(m, params, param_count, param_capacity, MirParam, param);
        mpa_c_eat_p(&c, ',');
    }
    MirTy ret = MIR_VOID;
    if (mpa_c_peek_kind(&c, MPT_ARROW)) {
        c.pos++;
        ret = mpa_parse_ty(&c);
    }
    MirFunc f;
    mir_func_init(m, &f, name, params, param_count, ret);
    mpa_function_attributes(&c, &f, &unit->refs[index]);
    if (mir_func_by_name(m, name) != MIR_NONE) {
        MsStr text = ms_name(&m->names, name);
        mpa_perr(p, c.line, "function @%.*s defined twice", (int)text.len, text.ptr);
    }
    unit->refs[index].id = mir_add_func(m, &f);
    unit->param_names[index] = names;
    unit->param_counts[index] = name_count;
}

static void mpa_define_vtable(MpCur *c, uint32_t line) {
    MirModule *m = c->p->m;
    MirVtable vtable = {.name = mpa_tsym(c, mpa_c_at(c))};
    mpa_c_expect_p(c, ':');
    MpTok iface_name = mpa_c_ident(c);
    vtable.iface = mir_iface_by_name(m, mpa_tsym(c, iface_name));
    if (vtable.iface == MIR_NONE) {
        mpa_perr(c->p, line, "unknown interface %.*s", (int)iface_name.n, iface_name.s);
    }
    if (!mpa_c_eat_ident(c, "for")) {
        mpa_perr(c->p, c->line, "expected 'for'");
    }
    vtable.data_ty = mpa_parse_ty(c);
    mpa_c_expect_p(c, '{');
    uint32_t capacity = 0;
    while (!mpa_c_eat_p(c, '}')) {
        MpTok method_name = mpa_c_at(c);
        uint32_t method = mir_func_by_name(m, mpa_tsym(c, method_name));
        if (method == MIR_NONE) {
            mpa_perr(c->p, line, "unknown function @%.*s", (int)method_name.n, method_name.s);
        }
        MIR_PUSH(m, vtable.methods, vtable.nmethods, capacity, uint32_t, method);
        mpa_c_eat_p(c, ',');
    }
    mir_add_vtable(m, &vtable);
}

/* The function a header attribute names. */
static uint32_t mpa_named_function(MpParser *p, uint32_t line, MpTok name) {
    uint32_t id = mir_func_by_name(p->m, mir_name(p->m, name.s, name.n));
    if (id == MIR_NONE) {
        mpa_perr(p, line, "unknown function @%.*s", (int)name.n, name.s);
    }
    return id;
}

/* Vtables, descriptor glue and the entry point name functions, so they come after the headers. */
static void mpa_define_vtables_and_entry(MpParser *p, const MpUnit *unit) {
    for (uint32_t i = 0; i < unit->item_count; i++) {
        MpCur c = mpa_item_cursor(p, &unit->items[i]);
        MpTok keyword = mpa_c_ident(&c);
        if (mpa_tok_is(&keyword, "vtable")) {
            mpa_define_vtable(&c, unit->items[i].no);
        } else if (mpa_tok_is(&keyword, "desc_glue")) {
            const MirTy ty = mpa_parse_ty(&c);
            const uint32_t eq = mpa_named_function(p, unit->items[i].no, mpa_c_at(&c));
            const uint32_t hash = mpa_named_function(p, unit->items[i].no, mpa_c_at(&c));
            mir_add_desc_glue(p->m, ty, eq, hash);
        }
    }
    if (unit->has_close) {
        const uint32_t close = mir_func_by_name(p->m, mir_name(p->m, unit->close_name.s, unit->close_name.n));
        if (close == MIR_NONE) {
            mpa_perr(p, unit->close_line, "unknown close function @%.*s", (int)unit->close_name.n,
                     unit->close_name.s);
        }
        p->m->close = close;
    }
    if (!unit->has_entry) {
        return;
    }
    MsSym name = mir_name(p->m, unit->entry_name.s, unit->entry_name.n);
    uint32_t entry = mir_func_by_name(p->m, name);
    if (entry == MIR_NONE) {
        mpa_perr(p, unit->entry_line, "unknown entry function @%.*s", (int)unit->entry_name.n,
                 unit->entry_name.s);
    }
    p->m->entry = entry;
}

/* `slot_result` and `close_exit` name functions defined anywhere in the module. */
static void mpa_resolve_function_refs(MpParser *p, const MpUnit *unit) {
    for (uint32_t i = 0; i < unit->fn_count; i++) {
        const MpFnRefs *refs = &unit->refs[i];
        uint32_t line = unit->fns[i].header.no;
        MirFunc *f = &p->m->funcs[refs->id];
        if (refs->has_slot) {
            f->has_slot_result = true;
            f->slot_result = mpa_named_function(p, line, refs->slot);
        }
        if (refs->has_exit) {
            f->has_close_exit = true;
            f->close_exit[0] = mpa_named_function(p, line, refs->exit[0]);
            f->close_exit[1] = mpa_named_function(p, line, refs->exit[1]);
        }
        uint32_t closer_capacity = 0;
        for (uint32_t k = 0; k + 1 < refs->nclosers; k += 2) {
            MirCaptureCloser closer = {0};
            if (!mpa_parse_u32(refs->closers[k].s, refs->closers[k].n, &closer.capture)) {
                mpa_perr(p, line, "expected a capture index");
            }
            closer.func = mpa_named_function(p, line, refs->closers[k + 1]);
            MIR_PUSH(p->m, f->capture_closers, f->ncapture_closers, closer_capacity,
                     MirCaptureCloser, closer);
        }
    }
}

static void mpa_parse_all(MpParser *p, const char *src, size_t len) {
    MpUnit unit = {0};
    mpa_split_lines(p, src, len, &unit);
    mpa_declare_names(p, &unit);
    mpa_define_declarations(p, &unit);
    mpa_declare_items(p, &unit);
    unit.param_names = MS_NEW_N(&p->m->arena, MpTok *, unit.fn_count + 1);
    unit.param_counts = MS_NEW_N(&p->m->arena, uint32_t, unit.fn_count + 1);
    unit.refs = MS_NEW_N(&p->m->arena, MpFnRefs, unit.fn_count + 1);
    memset(unit.refs, 0, sizeof(MpFnRefs) * (unit.fn_count + 1));
    for (uint32_t i = 0; i < unit.fn_count; i++) {
        mpa_declare_function(p, &unit, i);
    }
    mpa_resolve_function_refs(p, &unit);
    mpa_define_vtables_and_entry(p, &unit);
    for (uint32_t i = 0; i < unit.fn_count; i++) {
        mpa_parse_body(p, i, &unit.fns[i], unit.param_names[i], unit.param_counts[i]);
    }
}

bool mir_parse(MirModule *m, const char *src, size_t len, uint32_t *line, MsStr *message) {
    MpParser p;
    memset(&p, 0, sizeof p);
    p.m = m;
    ms_names_init(&p.vnames);
    ms_names_init(&p.bnames);
    bool ok = true;
    if (setjmp(p.jb) == 0) {
        mpa_parse_all(&p, src, len);
    } else {
        ok = false;
        *line = p.err_line;
        *message = p.err_msg;
        free(p.terminated);
    }
    ms_names_free(&p.vnames);
    ms_names_free(&p.bnames);
    free(p.val_of);
    free(p.val_gen);
    free(p.blk_of);
    free(p.blk_gen);
    free(p.defined);
    return ok;
}
