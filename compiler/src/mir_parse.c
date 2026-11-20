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

#include "ms/mir.h"

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
        if (!isxdigit((unsigned char)s[i])) {
            return false;
        }
        int d = isdigit((unsigned char)s[i]) ? s[i] - '0' : (tolower((unsigned char)s[i]) - 'a' + 10);
        if (v >> 60) {
            return false;
        }
        v = v << 4 | (uint64_t)d;
    }
    *out = v;
    return true;
}

/* ---- tokenizer ---- */

static bool mpa_ident_char(unsigned char c) { return isalnum(c) || c == '_' || c == '.' || c == '$'; }
static bool mpa_ws_char(unsigned char c) { return c == ' ' || (c >= '\t' && c <= '\r'); }

static int mpa_hexval(char c) {
    return isdigit((unsigned char)c) ? c - '0' : isxdigit((unsigned char)c) ? tolower(c) - 'a' + 10 : -1;
}

static MpTok *mpa_tokenize(MpParser *p, const char *s, size_t n, uint32_t no, uint32_t *count) {
    MpTok *out = NULL;
    uint32_t nt = 0, ct = 0;
    size_t i = 0;
#define EMIT(T) MIR_PUSH(p->m, out, nt, ct, MpTok, (T))
    while (i < n) {
        unsigned char c = (unsigned char)s[i];
        if (mpa_ws_char(c)) {
            i++;
        } else if (c == ';') {
            break;
        } else if (c == '"') {
            i++;
            MsBuf b = {0};
            for (;;) {
                if (i >= n) {
                    ms_buf_free(&b);
                    mpa_perr(p, no, "unterminated string");
                }
                unsigned char d = (unsigned char)s[i++];
                if (d == '"') {
                    break;
                }
                if (d != '\\') {
                    ms_buf_putc(&b, (char)d);
                    continue;
                }
                if (i >= n) {
                    ms_buf_free(&b);
                    mpa_perr(p, no, "bad escape");
                }
                char e = s[i++];
                switch (e) {
                case 'n': ms_buf_putc(&b, '\n'); break;
                case 't': ms_buf_putc(&b, '\t'); break;
                case 'r': ms_buf_putc(&b, '\r'); break;
                case '"': ms_buf_putc(&b, '"'); break;
                case '\\': ms_buf_putc(&b, '\\'); break;
                case 'x': {
                    /* Rust reads two chars and parses them as hex, which also takes "+h". */
                    int v = -1;
                    if (i + 2 <= n) {
                        if (mpa_hexval(s[i]) >= 0 && mpa_hexval(s[i + 1]) >= 0) {
                            v = mpa_hexval(s[i]) * 16 + mpa_hexval(s[i + 1]);
                        } else if (s[i] == '+' && mpa_hexval(s[i + 1]) >= 0) {
                            v = mpa_hexval(s[i + 1]);
                        }
                    }
                    if (v < 0) {
                        ms_buf_free(&b);
                        mpa_perr(p, no, "bad \\x escape");
                    }
                    i += 2;
                    ms_utf8_put(&b, (uint32_t)v);
                    break;
                }
                default:
                    ms_buf_free(&b);
                    mpa_perr(p, no, "unknown escape");
                }
            }
            MpTok t = {.k = MPT_STR, .s = ms_arena_strndup(&p->m->arena, b.data ? b.data : "", b.len),
                     .n = (uint32_t)b.len};
            ms_buf_free(&b);
            EMIT(t);
        } else if (c == '%' || c == '@') {
            size_t start = ++i;
            while (i < n && mpa_ident_char((unsigned char)s[i])) {
                i++;
            }
            if (i == start) {
                mpa_perr(p, no, "empty name");
            }
            MpTok t = {.k = c == '%' ? MPT_VAL : MPT_AT, .s = s + start, .n = (uint32_t)(i - start)};
            EMIT(t);
        } else if (c == '!') {
            i++;
            size_t start = i;
            while (i < n && (isdigit((unsigned char)s[i]) || s[i] == ':')) {
                i++;
            }
            const char *part[3];
            size_t plen[3];
            int np = 0;
            size_t ps = start;
            for (size_t k = start; k <= i; k++) {
                if (k == i || s[k] == ':') {
                    if (np < 3) {
                        part[np] = s + ps;
                        plen[np] = k - ps;
                    }
                    np++;
                    ps = k + 1;
                }
            }
            if (np != 3) {
                mpa_perr(p, no, "location must be !file:line:col");
            }
            MpTok t = {.k = MPT_LOC};
            if (!mpa_parse_u32(part[0], plen[0], &t.loc.file) || !mpa_parse_u32(part[1], plen[1], &t.loc.line) ||
                !mpa_parse_u32(part[2], plen[2], &t.loc.col)) {
                mpa_perr(p, no, "bad location");
            }
            EMIT(t);
        } else if (c == '-' && i + 1 < n && s[i + 1] == '>') {
            MpTok t = {.k = MPT_ARROW};
            EMIT(t);
            i += 2;
        } else if (isdigit(c) || (c == '-' && i + 1 < n && isdigit((unsigned char)s[i + 1]))) {
            size_t start = i++;
            if (c == '0' && i < n && s[i] == 'x') {
                i++;
                while (i < n && isxdigit((unsigned char)s[i])) {
                    i++;
                }
            } else {
                while (i < n) {
                    char d = s[i];
                    bool exp_sign = (d == '+' || d == '-') && (s[i - 1] == 'e' || s[i - 1] == 'E');
                    if (isdigit((unsigned char)d) || d == '.' || d == 'e' || d == 'E' || exp_sign) {
                        i++;
                    } else {
                        break;
                    }
                }
            }
            MpTok t = {.k = MPT_NUM, .s = s + start, .n = (uint32_t)(i - start)};
            EMIT(t);
        } else if (isalpha(c) || c == '_') {
            size_t start = i;
            while (i < n && mpa_ident_char((unsigned char)s[i])) {
                i++;
            }
            MpTok t = {.k = MPT_IDENT, .s = s + start, .n = (uint32_t)(i - start)};
            EMIT(t);
        } else if (c != 0 && strchr("(){}<>[],:=", c) != NULL) {
            MpTok t = {.k = MPT_P, .ch = (char)c};
            EMIT(t);
            i++;
        } else {
            mpa_perr(p, no, "unexpected character");
        }
    }
#undef EMIT
    *count = nt;
    return out;
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

static MirTy mpa_parse_ty(MpCur *c) {
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
    *of = realloc(*of, sizeof(uint32_t) * ncap);
    *gen = realloc(*gen, sizeof(uint32_t) * ncap);
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
        p->defined = realloc(p->defined, ncap);
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

static MpTok mpa_c_name(MpCur *c) { return mpa_c_ident(c); }

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

static MirImm mpa_parse_imm(MpCur *c, MirOp op, int cc, const char *mn, size_t mnlen) {
    MirModule *m = c->p->m;
    MirImm im = {.tag = MI_NONE};
    switch (mir_op_info[op].imm) {
    case MIR_K_NONE:
        if (op == MOP_Clone && mpa_c_peek_kind(c, MPT_NUM)) {
            im.tag = MI_INT;
            im.i = mpa_imm_int(c);
        }
        break;
    case MIR_K_CC:
        if (cc < 0) {
            mpa_perr(c->p, c->line, "%.*s needs a condition such as %.*s.eq", (int)mnlen, mn, (int)mnlen, mn);
        }
        im.tag = MI_CC;
        im.a = (uint32_t)cc;
        break;
    case MIR_K_INT:
        im.tag = MI_INT;
        im.i = mpa_imm_int(c);
        break;
    case MIR_K_FLOAT: {
        MpTok s = mpa_c_num(c);
        im.tag = MI_FLOAT;
        if (s.n >= 2 && s.s[0] == '0' && s.s[1] == 'x') {
            uint64_t bits;
            if (!mpa_parse_hex_u64(s.s + 2, s.n - 2, &bits)) {
                mpa_perr(c->p, c->line, "bad float bits %.*s", (int)s.n, s.s);
            }
            im.i = (int64_t)bits;
        } else {
            char buf[128];
            char *end;
            if (s.n >= sizeof buf) {
                mpa_perr(c->p, c->line, "bad float %.*s", (int)s.n, s.s);
            }
            memcpy(buf, s.s, s.n);
            buf[s.n] = 0;
            errno = 0;
            double v = strtod(buf, &end);
            if (*end != 0) {
                mpa_perr(c->p, c->line, "bad float %.*s", (int)s.n, s.s);
            }
            uint64_t bits;
            memcpy(&bits, &v, sizeof bits);
            im.i = (int64_t)bits;
        }
        break;
    }
    case MIR_K_BOOL: {
        MpTok b = mpa_c_ident(c);
        im.tag = MI_BOOL;
        if (mpa_tok_is(&b, "true")) {
            im.a = 1;
        } else if (!mpa_tok_is(&b, "false")) {
            mpa_perr(c->p, c->line, "expected true or false, found %.*s", (int)b.n, b.s);
        }
        break;
    }
    case MIR_K_STR: {
        MpTok s = mpa_c_string(c);
        im.tag = MI_STR;
        im.a = mir_add_string(m, s.s, s.n);
        break;
    }
    case MIR_K_FUNC: {
        MpTok n = mpa_c_at(c);
        im.tag = MI_FUNC;
        im.a = mir_func_by_name(m, mpa_tsym(c, n));
        if (im.a == MIR_NONE) mpa_perr(c->p, c->line, "unknown function @%.*s", (int)n.n, n.s);
        break;
    }
    case MIR_K_EXT: {
        MpTok n = mpa_c_at(c);
        im.tag = MI_EXT;
        im.a = mir_extern_by_name(m, mpa_tsym(c, n));
        if (im.a == MIR_NONE) mpa_perr(c->p, c->line, "unknown extern @%.*s", (int)n.n, n.s);
        break;
    }
    case MIR_K_VTABLE: {
        MpTok n = mpa_c_at(c);
        im.tag = MI_VTABLE;
        im.a = mir_vtable_by_name(m, mpa_tsym(c, n));
        if (im.a == MIR_NONE) mpa_perr(c->p, c->line, "unknown vtable @%.*s", (int)n.n, n.s);
        break;
    }
    case MIR_K_GLOBAL: {
        MpTok n = mpa_c_at(c);
        im.tag = MI_GLOBAL;
        im.a = mir_global_by_name(m, mpa_tsym(c, n));
        if (im.a == MIR_NONE) mpa_perr(c->p, c->line, "unknown global @%.*s", (int)n.n, n.s);
        break;
    }
    case MIR_K_TY:
        im.tag = MI_TY;
        im.a = mpa_parse_ty(c);
        break;
    case MIR_K_SCOPE:
        im.tag = MI_SCOPE;
        im.a = mpa_imm_u32(c, "scope number");
        im.b = mpa_imm_u32(c, "scope number");
        break;
    case MIR_K_IDX:
        im.tag = MI_IDX;
        im.a = mpa_imm_u32(c, "index");
        break;
    case MIR_K_TYPE: {
        MpTok n = mpa_c_name(c);
        im.tag = MI_TYPE;
        im.a = mir_type_by_name(m, mpa_tsym(c, n));
        if (im.a == MIR_NONE) mpa_perr(c->p, c->line, "unknown type %.*s", (int)n.n, n.s);
        break;
    }
    case MIR_K_FIELD: {
        MpTok n = mpa_c_name(c);
        const char *part[2];
        size_t len[2];
        const char *dot = memchr(n.s, '.', n.n);
        if (dot == NULL) mpa_perr(c->p, c->line, "expected Type.field");
        part[0] = n.s; len[0] = (size_t)(dot - n.s);
        part[1] = dot + 1; len[1] = n.n - len[0] - 1;
        uint32_t t = mir_type_by_name(m, mpa_psym(c, part[0], len[0]));
        if (t == MIR_NONE) mpa_perr(c->p, c->line, "unknown type %.*s", (int)len[0], part[0]);
        uint32_t fi = mpa_find_field(m, m->type_defs[t].fields, m->type_defs[t].nfields, part[1], len[1]);
        if (fi == MIR_NONE) mpa_perr(c->p, c->line, "unknown field %.*s", (int)n.n, n.s);
        im.tag = MI_FIELD; im.a = t; im.b = fi;
        break;
    }
    case MIR_K_CASE: {
        MpTok n = mpa_c_name(c);
        const char *dot = memchr(n.s, '.', n.n);
        if (dot == NULL) mpa_perr(c->p, c->line, "expected Alt.Case");
        size_t l0 = (size_t)(dot - n.s);
        uint32_t a = mir_alt_by_name(m, mpa_psym(c, n.s, l0));
        if (a == MIR_NONE) mpa_perr(c->p, c->line, "unknown alternative %.*s", (int)l0, n.s);
        uint32_t ci = mpa_find_case(m, &m->alts[a], dot + 1, n.n - l0 - 1);
        if (ci == MIR_NONE) mpa_perr(c->p, c->line, "unknown case %.*s", (int)n.n, n.s);
        im.tag = MI_CASE; im.a = a; im.b = ci;
        break;
    }
    case MIR_K_ALTFIELD:
    case MIR_K_ALTMASK: {
        bool mask = mir_op_info[op].imm == MIR_K_ALTMASK;
        MpTok n = mpa_c_name(c);
        const char *part[64];
        size_t len[64];
        int np = mpa_split_dots(n, part, len, 64);
        if (mask ? np < 2 : np != 3) {
            mpa_perr(c->p, c->line, mask ? "expected Alt.Case.field..." : "expected Alt.Case.field");
        }
        uint32_t a = mir_alt_by_name(m, mpa_psym(c, part[0], len[0]));
        if (a == MIR_NONE) mpa_perr(c->p, c->line, "unknown alternative %.*s", (int)len[0], part[0]);
        uint32_t ci = mpa_find_case(m, &m->alts[a], part[1], len[1]);
        if (ci == MIR_NONE) mpa_perr(c->p, c->line, "unknown case %.*s", (int)n.n, n.s);
        const MirCaseDef *cd = &m->alts[a].cases[ci];
        uint32_t bits = 0;
        for (int k = 2; k < np && k < 64; k++) {
            uint32_t fi = mpa_find_field(m, cd->fields, cd->nfields, part[k], len[k]);
            if (fi == MIR_NONE) mpa_perr(c->p, c->line, "unknown field %.*s", (int)n.n, n.s);
            bits |= 1u << fi;
            im.c = bits;
        }
        im.tag = mask ? MI_ALTMASK : MI_ALTFIELD;
        im.a = a; im.b = ci;
        if (!mask) {
            im.c = mpa_find_field(m, cd->fields, cd->nfields, part[2], len[2]);
        } else {
            im.c = bits;
        }
        break;
    }
    case MIR_K_TYPEMASK: {
        MpTok n = mpa_c_name(c);
        const char *part[64];
        size_t len[64];
        int np = mpa_split_dots(n, part, len, 64);
        uint32_t t = mir_type_by_name(m, mpa_psym(c, part[0], len[0]));
        if (t == MIR_NONE) mpa_perr(c->p, c->line, "unknown type %.*s", (int)len[0], part[0]);
        uint32_t bits = 0;
        for (int k = 1; k < np && k < 64; k++) {
            uint32_t fi = mpa_find_field(m, m->type_defs[t].fields, m->type_defs[t].nfields, part[k], len[k]);
            if (fi == MIR_NONE) mpa_perr(c->p, c->line, "unknown field %.*s", (int)n.n, n.s);
            bits |= 1u << fi;
        }
        im.tag = MI_TYPEMASK; im.a = t; im.b = bits;
        break;
    }
    case MIR_K_METHOD: {
        MpTok n = mpa_c_name(c);
        const char *dot = memchr(n.s, '.', n.n);
        if (dot == NULL) mpa_perr(c->p, c->line, "expected Interface.method");
        size_t l0 = (size_t)(dot - n.s), l1 = n.n - l0 - 1;
        uint32_t i = mir_iface_by_name(m, mpa_psym(c, n.s, l0));
        if (i == MIR_NONE) mpa_perr(c->p, c->line, "unknown interface %.*s", (int)l0, n.s);
        const MirIfaceDef *d = &m->ifaces[i];
        uint32_t mi = MIR_NONE;
        for (uint32_t k = 0; k < d->nmethods; k++) {
            MsStr nm = ms_name(&m->names, d->methods[k].name);
            if (nm.len == l1 && memcmp(nm.ptr, dot + 1, l1) == 0) {
                mi = k;
                break;
            }
        }
        if (mi == MIR_NONE) mpa_perr(c->p, c->line, "unknown method %.*s", (int)n.n, n.s);
        im.tag = MI_METHOD; im.a = i; im.b = mi;
        break;
    }
    }
    return im;
}

static void mpa_parse_line(MpCur *c, MirFunc *f, MirBlock b) {
    MpParser *p = c->p;
    MirModule *m = p->m;
    bool has_res = false;
    MpTok res_name = {0};
    MirTy res_ty = 0;
    if (mpa_c_peek_kind(c, MPT_VAL)) {
        res_name = mpa_c_val(c);
        mpa_c_expect_p(c, ':');
        res_ty = mpa_parse_ty(c);
        mpa_c_expect_p(c, '=');
        has_res = true;
    }
    MpTok mn = mpa_c_ident(c);
    MirTerm term = {.kind = 255, .value = MIR_NONE};
    if (mpa_tok_is(&mn, "br")) {
        term.kind = MT_BR;
        term.a = mpa_parse_target(c, f);
    } else if (mpa_tok_is(&mn, "br_if")) {
        term.kind = MT_CONDBR;
        MpTok cn = mpa_c_val(c);
        term.value = mpa_value_of(p, f, cn);
        mpa_c_expect_p(c, ',');
        term.a = mpa_parse_target(c, f);
        mpa_c_expect_p(c, ',');
        term.b = mpa_parse_target(c, f);
    } else if (mpa_tok_is(&mn, "switch")) {
        term.kind = MT_SWITCH;
        MpTok vn = mpa_c_val(c);
        term.value = mpa_value_of(p, f, vn);
        mpa_c_expect_p(c, '[');
        MirCase *cases = NULL;
        uint32_t n = 0, cap = 0;
        while (!mpa_c_eat_p(c, ']')) {
            MpTok k = mpa_c_num(c);
            int64_t kv;
            if (!mpa_parse_i64(k.s, k.n, &kv)) mpa_perr(p, c->line, "bad switch constant");
            mpa_c_expect_p(c, ':');
            MirCase cs = {kv, mpa_parse_target(c, f)};
            MIR_PUSH(m, cases, n, cap, MirCase, cs);
            mpa_c_eat_p(c, ',');
        }
        if (!mpa_c_eat_ident(c, "default")) mpa_perr(p, c->line, "expected 'default'");
        term.b = mpa_parse_target(c, f);
        term.cases = cases;
        term.ncases = n;
    } else if (mpa_tok_is(&mn, "ret")) {
        term.kind = MT_RET;
        if (mpa_c_peek_kind(c, MPT_VAL)) {
            MpTok vn = mpa_c_val(c);
            term.value = mpa_value_of(p, f, vn);
        }
    } else if (mpa_tok_is(&mn, "unreachable")) {
        term.kind = MT_UNREACHABLE;
    } else if (mpa_tok_is(&mn, "fault")) {
        term.kind = MT_FAULT;
        const MpTok *t = mpa_c_peek(c);
        if (t == NULL) mpa_perr(p, c->line, "expected fault kind");
        c->pos++;
        if (t->k == MPT_STR) {
            term.fault = MF_MESSAGE;
            term.fault_str = mir_add_string(m, t->s, t->n);
        } else if (t->k == MPT_IDENT) {
            static const char *const names[] = {"int_overflow", "div_by_zero", "index_out_of_range",
                                                "none_unwrap", "cancelled", "call_depth",
                                                "unreachable_code"};
            int k = -1;
            for (int i = 0; i < 7; i++) {
                if (mpa_tok_is(t, names[i])) k = i;
            }
            if (k < 0) mpa_perr(p, c->line, "unknown fault kind %.*s", (int)t->n, t->s);
            term.fault = (uint8_t)k;
        } else {
            mpa_perr(p, c->line, "expected fault kind");
        }
    }
    if (term.kind != 255) {
        if (has_res) mpa_perr(p, c->line, "terminators have no result");
        MirLoc loc = MIR_LOC_NONE;
        if (mpa_c_peek_kind(c, MPT_LOC)) {
            loc = mpa_c_peek(c)->loc;
            c->pos++;
        }
        if (!mpa_c_done(c)) mpa_perr(p, c->line, "unexpected tokens after terminator");
        f->blocks[b].term = term;
        f->blocks[b].term_loc = loc;
        p->terminated[b] = 1;
        return;
    }
    /* Instructions. */
    int op = mir_op_from_name(mn.s, mn.n);
    int cc = -1;
    if (op < 0) {
        const char *dot = NULL;
        for (uint32_t i = mn.n; i > 0; i--) {
            if (mn.s[i - 1] == '.') {
                dot = mn.s + i - 1;
                break;
            }
        }
        if (dot == NULL) mpa_perr(p, c->line, "unknown instruction '%.*s'", (int)mn.n, mn.s);
        int head = mir_op_from_name(mn.s, (size_t)(dot - mn.s));
        size_t tl = mn.n - (size_t)(dot - mn.s) - 1;
        for (int i = 0; i < 6; i++) {
            if (strlen(mir_cc_name[i]) == tl && memcmp(mir_cc_name[i], dot + 1, tl) == 0) cc = i;
        }
        if (!(head == MOP_ICmp || head == MOP_UICmp || head == MOP_FCmp) || cc < 0) {
            mpa_perr(p, c->line, "unknown instruction '%.*s'", (int)mn.n, mn.s);
        }
        op = head;
    }
    const MirOpInfo *info = &mir_op_info[op];
    if ((bool)info->has_result != has_res) {
        if (info->has_result) {
            mpa_perr(p, c->line, "%.*s needs a result: %%v: type = %.*s ...", (int)mn.n, mn.s, (int)mn.n, mn.s);
        }
        mpa_perr(p, c->line, "%.*s has no result", (int)mn.n, mn.s);
    }
    MirImm imm = mpa_parse_imm(c, (MirOp)op, cc, mn.s, mn.n);
    MirValue *args = NULL;
    uint32_t nargs = 0, cargs = 0;
    bool parens = mir_op_is_call((MirOp)op);
    if (parens) mpa_c_expect_p(c, '(');
    while (mpa_c_peek_kind(c, MPT_VAL)) {
        MpTok vn = mpa_c_val(c);
        MirValue x = mpa_value_of(p, f, vn);
        MIR_PUSH(m, args, nargs, cargs, MirValue, x);
        if (!mpa_c_eat_p(c, ',')) break;
    }
    if (parens) mpa_c_expect_p(c, ')');
    MirLoc loc = MIR_LOC_NONE;
    if (mpa_c_peek_kind(c, MPT_LOC)) {
        loc = mpa_c_peek(c)->loc;
        c->pos++;
    }
    if (!mpa_c_done(c)) mpa_perr(p, c->line, "unexpected token after instruction");
    MirInst in = {.op = (uint8_t)op, .imm = imm, .res = MIR_NONE, .loc = loc, .args = args, .nargs = nargs};
    if (has_res) {
        in.res = mpa_define(c, f, res_name, res_ty);
    }
    MirBlockData *bd = &f->blocks[b];
    MIR_PUSH(m, bd->insts, bd->ninsts, bd->cinsts, MirInst, in);
}

static bool mpa_is_label(const MpTok *t, uint32_t n) {
    return n > 0 && t[0].k == MPT_IDENT && t[n - 1].k == MPT_P && t[n - 1].ch == ':' && !mpa_tok_is(&t[0], "switch");
}

typedef struct MpBodyLine {
    uint32_t no;
    MpTok *t;
    uint32_t nt;
} MpBodyLine;

static void mpa_parse_body(MpParser *p, uint32_t id, const MpFnSrc *src, const MpTok *pnames, uint32_t npn) {
    MirModule *m = p->m;
    MirFunc *f = &m->funcs[id];
    p->gen++;
    uint32_t line0 = src->nbody ? src->body[0].no : 0;
    if (p->cdefined < f->nvalues * 2 + 8) {
        p->cdefined = f->nvalues * 2 + 8;
        p->defined = realloc(p->defined, p->cdefined);
    }
    memset(p->defined, 0, p->cdefined);
    for (uint32_t i = 0; i < npn; i++) {
        MsSym s = ms_intern(&p->vnames, pnames[i].s, pnames[i].n);
        if (mpa_vname_lookup(p, s) != MIR_NONE) {
            mpa_perr(p, line0, "parameter %%%.*s defined twice", (int)pnames[i].n, pnames[i].s);
        }
        mpa_grow_names(&p->val_of, &p->val_gen, &p->nval_cap, s);
        MirValue v = f->blocks[0].params[i].value;
        p->val_of[s] = v;
        p->val_gen[s] = p->gen;
        p->defined[v] = 1;
    }
    MpBodyLine *lines = NULL;
    uint32_t nl = 0, cl = 0;
    for (uint32_t i = 0; i < src->nbody; i++) {
        uint32_t nt;
        MpTok *t = mpa_tokenize(p, src->body[i].s, src->body[i].n, src->body[i].no, &nt);
        if (nt > 0) {
            MpBodyLine bl = {src->body[i].no, t, nt};
            MIR_PUSH(m, lines, nl, cl, MpBodyLine, bl);
        }
    }
    bool first = true;
    for (uint32_t i = 0; i < nl; i++) {
        if (mpa_is_label(lines[i].t, lines[i].nt)) {
            MpTok name = lines[i].t[0];
            MsSym s = ms_intern(&p->bnames, name.s, name.n);
            if (first) {
                mpa_grow_names(&p->blk_of, &p->blk_gen, &p->nblk_cap, s);
                p->blk_of[s] = 0;
                p->blk_gen[s] = p->gen;
                first = false;
            } else {
                if (s < p->nblk_cap && p->blk_gen[s] == p->gen) {
                    mpa_perr(p, lines[i].no, "block %.*s defined twice", (int)name.n, name.s);
                }
                mpa_grow_names(&p->blk_of, &p->blk_gen, &p->nblk_cap, s);
                p->blk_of[s] = mir_new_block(m, f);
                p->blk_gen[s] = p->gen;
            }
        } else if (first) {
            mpa_perr(p, lines[i].no, "function body must start with a block label");
        }
    }
    p->terminated = calloc(f->nblocks + 1, 1);
    MirBlock cur = MIR_NONE;
    for (uint32_t i = 0; i < nl; i++) {
        MpCur c = {p, lines[i].t, lines[i].nt, 0, lines[i].no};
        if (mpa_is_label(c.t, c.n)) {
            MpTok name = mpa_c_ident(&c);
            MsSym s = ms_intern(&p->bnames, name.s, name.n);
            MirBlock b = p->blk_of[s];
            if (b != 0 && mpa_c_eat_p(&c, '(')) {
                while (!mpa_c_eat_p(&c, ')')) {
                    MpTok vn = mpa_c_val(&c);
                    mpa_c_expect_p(&c, ':');
                    bool own = mpa_c_eat_ident(&c, "move");
                    MirTy ty = mpa_parse_ty(&c);
                    MirValue v = mpa_define(&c, f, vn, ty);
                    MirBlockData *bd = &f->blocks[b];
                    MirBlockParam bp = {v, own ? MM_MOVE : MM_BORROW};
                    MIR_PUSH(m, bd->params, bd->nparams, bd->cparams, MirBlockParam, bp);
                    mpa_c_eat_p(&c, ',');
                }
            } else if (b == 0 && mpa_c_eat_p(&c, '(')) {
                mpa_perr(p, c.line, "the entry block takes the function parameters");
            }
            cur = b;
            continue;
        }
        if (p->terminated[cur]) mpa_perr(p, c.line, "instruction after the block terminator");
        mpa_parse_line(&c, f, cur);
    }
    for (uint32_t i = 0; i < f->nblocks; i++) {
        if (!p->terminated[i]) {
            MsStr fn = ms_name(&m->names, f->name);
            mpa_perr(p, line0, "block b%u of @%.*s has no terminator", i, (int)fn.len, fn.ptr);
        }
    }
    for (uint32_t s = 0; s < p->nval_cap; s++) {
        if (p->val_gen[s] == p->gen) {
            uint32_t v = p->val_of[s];
            if (v >= p->cdefined || !p->defined[v]) {
                MsStr vn = ms_name(&p->vnames, s), fn = ms_name(&m->names, f->name);
                mpa_perr(p, line0, "%%%.*s is used but never defined in @%.*s", (int)vn.len, vn.ptr,
                     (int)fn.len, fn.ptr);
            }
        }
    }
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

static MirParam mpa_parse_param(MpCur *c) {
    bool own = mpa_c_eat_ident(c, "move");
    MirTy ty = mpa_parse_ty(c);
    return (MirParam){ty, own ? MM_MOVE : MM_BORROW};
}

static void mpa_parse_all(MpParser *p, const char *src, size_t len) {
    MirModule *m = p->m;
    MpItem *items = NULL;
    uint32_t nitems = 0, citems = 0;
    MpFnSrc *fns = NULL;
    uint32_t nfns = 0, cfns = 0;
    /* Group lines into items. */
    size_t pos = 0;
    uint32_t no = 0;
    while (pos < len) {
        size_t s0 = pos;
        const char *nl = memchr(src + pos, '\n', len - pos);
        size_t end = nl ? (size_t)(nl - src) : len;
        pos = nl ? end + 1 : len;
        size_t le = end;
        if (le > s0 && src[le - 1] == '\r') le--;
        no++;
        MpLine line = mpa_trim_line(src + s0, le - s0);
        line.no = no;
        if (line.n == 0 || line.s[0] == ';') continue;
        if (mpa_line_starts(line, "fn ")) {
            MpFnSrc fs = {.header = line};
            bool closed = false;
            while (pos < len) {
                size_t b0 = pos;
                const char *bnl = memchr(src + pos, '\n', len - pos);
                size_t bend = bnl ? (size_t)(bnl - src) : len;
                pos = bnl ? bend + 1 : len;
                size_t ble = bend;
                if (ble > b0 && src[ble - 1] == '\r') ble--;
                no++;
                MpLine tl = mpa_trim_line(src + b0, ble - b0);
                if (tl.n == 1 && tl.s[0] == '}') {
                    closed = true;
                    break;
                }
                MpLine bl = {no, src + b0, (uint32_t)(ble - b0)};
                MIR_PUSH(m, fs.body, fs.nbody, fs.cbody, MpLine, bl);
            }
            if (!closed) mpa_perr(p, line.no, "function body is not closed with '}'");
            MIR_PUSH(m, fns, nfns, cfns, MpFnSrc, fs);
        } else {
            MpItem it = {.no = line.no, .s = line.s, .n = line.n};
            MIR_PUSH(m, items, nitems, citems, MpItem, it);
        }
    }
    for (uint32_t i = 0; i < nitems; i++) {
        items[i].t = mpa_tokenize(p, items[i].s, items[i].n, items[i].no, &items[i].nt);
    }
    /* Pass A: names of types, alternatives and interfaces. */
    for (uint32_t i = 0; i < nitems; i++) {
        MpCur c = {p, items[i].t, items[i].nt, 0, items[i].no};
        MpTok kw = mpa_c_ident(&c);
        if (mpa_tok_is(&kw, "type")) {
            mir_add_type(m, mpa_tsym(&c, mpa_c_ident(&c)));
        } else if (mpa_tok_is(&kw, "alt")) {
            mir_add_alt(m, mpa_tsym(&c, mpa_c_ident(&c)));
        } else if (mpa_tok_is(&kw, "iface")) {
            mir_add_iface(m, mpa_tsym(&c, mpa_c_ident(&c)));
        }
    }
    /* Pass B: bodies of type declarations. */
    for (uint32_t i = 0; i < nitems; i++) {
        MpCur c = {p, items[i].t, items[i].nt, 0, items[i].no};
        MpTok kw = mpa_c_ident(&c);
        if (mpa_tok_is(&kw, "type")) {
            uint32_t id = mir_type_by_name(m, mpa_tsym(&c, mpa_c_ident(&c)));
            mpa_c_expect_p(&c, '{');
            MirField *fields = NULL;
            uint32_t n = 0, cap = 0;
            while (!mpa_c_eat_p(&c, '}')) {
                MpTok fname = mpa_c_ident(&c);
                mpa_c_expect_p(&c, ':');
                MirField fd = {mpa_tsym(&c, fname), mpa_parse_ty(&c)};
                MIR_PUSH(m, fields, n, cap, MirField, fd);
                mpa_c_eat_p(&c, ',');
            }
            m->type_defs[id].fields = fields;
            m->type_defs[id].nfields = n;
        } else if (mpa_tok_is(&kw, "alt")) {
            uint32_t id = mir_alt_by_name(m, mpa_tsym(&c, mpa_c_ident(&c)));
            mpa_c_expect_p(&c, '{');
            MirCaseDef *cases = NULL;
            uint32_t n = 0, cap = 0;
            while (!mpa_c_eat_p(&c, '}')) {
                MirCaseDef cd = {.name = mpa_tsym(&c, mpa_c_ident(&c))};
                uint32_t nf = 0, cf = 0;
                if (mpa_c_eat_p(&c, '(')) {
                    while (!mpa_c_eat_p(&c, ')')) {
                        MpTok fname = mpa_c_ident(&c);
                        mpa_c_expect_p(&c, ':');
                        MirField fd = {mpa_tsym(&c, fname), mpa_parse_ty(&c)};
                        MIR_PUSH(m, cd.fields, nf, cf, MirField, fd);
                        mpa_c_eat_p(&c, ',');
                    }
                }
                cd.nfields = nf;
                MIR_PUSH(m, cases, n, cap, MirCaseDef, cd);
                mpa_c_eat_p(&c, ',');
            }
            m->alts[id].cases = cases;
            m->alts[id].ncases = n;
            m->alts[id].std = mpa_parse_std(&c);
        } else if (mpa_tok_is(&kw, "iface")) {
            uint32_t id = mir_iface_by_name(m, mpa_tsym(&c, mpa_c_ident(&c)));
            mpa_c_expect_p(&c, '{');
            MirMethodSig *ms = NULL;
            uint32_t n = 0, cap = 0;
            while (!mpa_c_eat_p(&c, '}')) {
                MirMethodSig s = {.name = mpa_tsym(&c, mpa_c_ident(&c)), .ret = MIR_VOID};
                uint32_t np = 0, cp = 0;
                mpa_c_expect_p(&c, '(');
                while (!mpa_c_eat_p(&c, ')')) {
                    if (mpa_c_eat_ident(&c, "move") && np < 64) s.owned |= 1ull << np;
                    MirTy t = mpa_parse_ty(&c);
                    MIR_PUSH(m, s.params, np, cp, MirTy, t);
                    mpa_c_eat_p(&c, ',');
                }
                s.nparams = np;
                if (mpa_c_peek_kind(&c, MPT_ARROW)) {
                    c.pos++;
                    s.ret = mpa_parse_ty(&c);
                }
                MIR_PUSH(m, ms, n, cap, MirMethodSig, s);
                mpa_c_eat_p(&c, ',');
            }
            m->ifaces[id].close = MIR_NONE;
            MsSym close = mir_name(m, "close", 5);
            for (uint32_t k = 0; k < n; k++) {
                if (ms[k].name == close) {
                    m->ifaces[id].close = k;
                    break;
                }
            }
            m->ifaces[id].methods = ms;
            m->ifaces[id].nmethods = n;
            m->ifaces[id].std = mpa_parse_std(&c);
        }
    }
    /* Pass C: module, files, externs, globals, entry. */
    uint32_t entry_line = 0;
    MpTok entry_tok = {0};
    bool has_entry = false;
    for (uint32_t i = 0; i < nitems; i++) {
        MpCur c = {p, items[i].t, items[i].nt, 0, items[i].no};
        MpTok kw = mpa_c_ident(&c);
        if (mpa_tok_is(&kw, "module")) {
            const MpTok *t = mpa_c_peek(&c);
            if (t == NULL || (t->k != MPT_STR && t->k != MPT_IDENT)) mpa_perr(p, c.line, "expected module name");
            c.pos++;
            m->name = mir_name(m, t->s, t->n);
        } else if (mpa_tok_is(&kw, "file")) {
            MpTok idx = mpa_c_num(&c);
            int64_t v;
            if (idx.s[0] == '-' || !mpa_parse_i64(idx.s, idx.n, &v)) mpa_perr(p, c.line, "bad file index");
            MpTok path = mpa_c_string(&c);
            if ((uint64_t)v != m->nfiles) mpa_perr(p, c.line, "files must be numbered consecutively from 0");
            MsStr s = {ms_arena_strndup(&m->arena, path.s, path.n), path.n};
            MIR_PUSH(m, m->files, m->nfiles, m->cfiles, MsStr, s);
        } else if (mpa_tok_is(&kw, "blob") || mpa_tok_is(&kw, "consts")) {
            bool blob = mpa_tok_is(&kw, "blob");
            MpTok idx = mpa_c_num(&c);
            int64_t v;
            if (idx.s[0] == '-' || !mpa_parse_i64(idx.s, idx.n, &v)) mpa_perr(p, c.line, "bad %s index", blob ? "blob" : "consts");
            uint32_t have = blob ? m->nblobs : m->nlist_consts;
            if ((uint64_t)v != have) {
                mpa_perr(p, c.line, "%s entries must be numbered consecutively from 0", blob ? "blob" : "consts");
            }
            if (blob) {
                MpTok hex = mpa_c_string(&c);
                if (hex.n % 2 != 0) mpa_perr(p, c.line, "blob payload must be an even number of hex digits");
                char *bytes = ms_alloc(&m->arena, hex.n / 2 + 1, 1);
                for (uint32_t k = 0; k < hex.n; k += 2) {
                    int h = mpa_hexval(hex.s[k]), l = mpa_hexval(hex.s[k + 1]);
                    if (h < 0 || l < 0) mpa_perr(p, c.line, "blob payload must be an even number of hex digits");
                    bytes[k / 2] = (char)(h * 16 + l);
                }
                MsStr b = {bytes, hex.n / 2};
                MIR_PUSH(m, m->blobs, m->nblobs, m->cblobs, MsStr, b);
            } else {
                mpa_c_expect_p(&c, '[');
                int64_t *vals = NULL;
                uint32_t n = 0, cap = 0;
                while (!mpa_c_eat_p(&c, ']')) {
                    MpTok e = mpa_c_num(&c);
                    int64_t x;
                    if (!mpa_parse_i64(e.s, e.n, &x)) mpa_perr(p, c.line, "bad consts element");
                    MIR_PUSH(m, vals, n, cap, int64_t, x);
                    mpa_c_eat_p(&c, ',');
                }
                MirConsts k = {vals, n};
                MIR_PUSH(m, m->list_consts, m->nlist_consts, m->clist_consts, MirConsts, k);
            }
        } else if (mpa_tok_is(&kw, "extern")) {
            MirExtern e = {.name = mpa_tsym(&c, mpa_c_at(&c)), .ret = MIR_VOID};
            uint32_t np = 0, cp = 0;
            mpa_c_expect_p(&c, '(');
            while (!mpa_c_eat_p(&c, ')')) {
                MirParam pr = mpa_parse_param(&c);
                MIR_PUSH(m, e.params, np, cp, MirParam, pr);
                mpa_c_eat_p(&c, ',');
            }
            e.nparams = np;
            if (mpa_c_peek_kind(&c, MPT_ARROW)) {
                c.pos++;
                e.ret = mpa_parse_ty(&c);
            }
            while (!mpa_c_done(&c)) {
                MpTok a = mpa_c_ident(&c);
                if (mpa_tok_is(&a, "noreturn")) e.noreturn = true;
                else if (mpa_tok_is(&a, "pure")) e.pure = true;
                else if (mpa_tok_is(&a, "fresh")) e.fresh = true;
                else if (mpa_tok_is(&a, "leaf")) e.leaf = true;
                else if (mpa_tok_is(&a, "reads")) e.reads = true;
                else if (mpa_tok_is(&a, "retains")) e.retains = true;
                else {
                    int r = mir_role_from_name(a.s, a.n);
                    if (r == MR_NONE) mpa_perr(p, c.line, "unknown extern attribute %.*s", (int)a.n, a.s);
                    e.role = (uint8_t)r;
                }
            }
            mir_add_extern(m, &e);
        } else if (mpa_tok_is(&kw, "global")) {
            MsSym name = mpa_tsym(&c, mpa_c_at(&c));
            mpa_c_expect_p(&c, ':');
            mir_add_global(m, name, mpa_parse_ty(&c));
        } else if (mpa_tok_is(&kw, "entry")) {
            entry_tok = mpa_c_at(&c);
            entry_line = items[i].no;
            has_entry = true;
        } else if (mpa_tok_is(&kw, "vtable") || mpa_tok_is(&kw, "type") || mpa_tok_is(&kw, "alt") || mpa_tok_is(&kw, "iface")) {
        } else {
            mpa_perr(p, c.line, "unknown item '%.*s'", (int)kw.n, kw.s);
        }
    }
    /* Function headers. */
    MpTok **pnames = MS_NEW_N(&m->arena, MpTok *, nfns + 1);
    uint32_t *npn = MS_NEW_N(&m->arena, uint32_t, nfns + 1);
    for (uint32_t i = 0; i < nfns; i++) {
        uint32_t nt;
        MpTok *toks = mpa_tokenize(p, fns[i].header.s, fns[i].header.n, fns[i].header.no, &nt);
        MpCur c = {p, toks, nt, 0, fns[i].header.no};
        mpa_c_ident(&c); /* fn */
        MsSym name = mpa_tsym(&c, mpa_c_at(&c));
        mpa_c_expect_p(&c, '(');
        MirParam *params = NULL;
        MpTok *names = NULL;
        uint32_t np = 0, cp = 0, nn = 0, cn = 0;
        while (!mpa_c_eat_p(&c, ')')) {
            MpTok vn = mpa_c_val(&c);
            MIR_PUSH(m, names, nn, cn, MpTok, vn);
            mpa_c_expect_p(&c, ':');
            MirParam pr = mpa_parse_param(&c);
            MIR_PUSH(m, params, np, cp, MirParam, pr);
            mpa_c_eat_p(&c, ',');
        }
        MirTy ret = MIR_VOID;
        if (mpa_c_peek_kind(&c, MPT_ARROW)) {
            c.pos++;
            ret = mpa_parse_ty(&c);
        }
        MirFunc f;
        mir_func_init(m, &f, name, params, np, ret);
        for (;;) {
            if (mpa_c_peek_p(&c, '{')) {
                c.pos++;
                break;
            }
            if (mpa_c_peek_kind(&c, MPT_LOC)) {
                f.loc = mpa_c_peek(&c)->loc;
                c.pos++;
            }
            if (mpa_c_peek(&c) == NULL) mpa_perr(p, c.line, "expected '{'");
            if (mpa_c_peek_kind(&c, MPT_IDENT)) {
                MpTok a = mpa_c_ident(&c);
                if (mpa_tok_is(&a, "export")) f.linkage = ML_EXPORT;
                else if (mpa_tok_is(&a, "method")) f.kind = MFK_METHOD;
                else if (mpa_tok_is(&a, "sort_cmp")) f.sort = MSORT_GENERIC;
                else if (mpa_tok_is(&a, "sort_cmp_for")) f.sort = MSORT_SPECIALIZED;
                else if (mpa_tok_is(&a, "inline")) {
                    mpa_c_expect_p(&c, '(');
                    MpTok h = mpa_c_ident(&c);
                    if (mpa_tok_is(&h, "always")) f.inline_hint = MINL_ALWAYS;
                    else if (mpa_tok_is(&h, "never")) f.inline_hint = MINL_NEVER;
                    else mpa_perr(p, c.line, "unknown inline hint %.*s", (int)h.n, h.s);
                    mpa_c_expect_p(&c, ')');
                } else if (mpa_tok_is(&a, "closure")) {
                    mpa_c_expect_p(&c, '(');
                    uint32_t nc = 0, cc = 0;
                    while (!mpa_c_eat_p(&c, ')')) {
                        MirTy t = mpa_parse_ty(&c);
                        MIR_PUSH(m, f.captures, nc, cc, MirTy, t);
                        mpa_c_eat_p(&c, ',');
                    }
                    f.ncaptures = nc;
                    f.kind = MFK_CLOSURE;
                } else {
                    mpa_perr(p, c.line, "unknown function attribute %.*s", (int)a.n, a.s);
                }
            } else if (!mpa_c_peek_kind(&c, MPT_LOC) && !mpa_c_peek_p(&c, '{')) {
                mpa_perr(p, c.line, "unexpected token in function header");
            }
        }
        if (mir_func_by_name(m, name) != MIR_NONE) {
            MsStr fn = ms_name(&m->names, name);
            mpa_perr(p, c.line, "function @%.*s defined twice", (int)fn.len, fn.ptr);
        }
        mir_add_func(m, &f);
        pnames[i] = names;
        npn[i] = nn;
    }
    /* Vtables and entry need function ids. */
    for (uint32_t i = 0; i < nitems; i++) {
        MpCur c = {p, items[i].t, items[i].nt, 0, items[i].no};
        MpTok kw = mpa_c_ident(&c);
        if (!mpa_tok_is(&kw, "vtable")) continue;
        MirVtable v = {0};
        v.name = mpa_tsym(&c, mpa_c_at(&c));
        mpa_c_expect_p(&c, ':');
        MpTok in = mpa_c_ident(&c);
        uint32_t iface = mir_iface_by_name(m, mpa_tsym(&c, in));
        if (iface == MIR_NONE) mpa_perr(p, items[i].no, "unknown interface %.*s", (int)in.n, in.s);
        v.iface = iface;
        if (!mpa_c_eat_ident(&c, "for")) mpa_perr(p, c.line, "expected 'for'");
        v.data_ty = mpa_parse_ty(&c);
        mpa_c_expect_p(&c, '{');
        uint32_t n = 0, cap = 0;
        while (!mpa_c_eat_p(&c, '}')) {
            MpTok fn = mpa_c_at(&c);
            uint32_t f = mir_func_by_name(m, mpa_tsym(&c, fn));
            if (f == MIR_NONE) mpa_perr(p, items[i].no, "unknown function @%.*s", (int)fn.n, fn.s);
            MIR_PUSH(m, v.methods, n, cap, uint32_t, f);
            mpa_c_eat_p(&c, ',');
        }
        v.nmethods = n;
        mir_add_vtable(m, &v);
    }
    if (has_entry) {
        uint32_t f = mir_func_by_name(m, mpa_tsym(&(MpCur){p, NULL, 0, 0, 0}, entry_tok));
        if (f == MIR_NONE) mpa_perr(p, entry_line, "unknown entry function @%.*s", (int)entry_tok.n, entry_tok.s);
        m->entry = f;
    }
    /* Bodies. */
    for (uint32_t i = 0; i < nfns; i++) {
        mpa_parse_body(p, i, &fns[i], pnames[i], npn[i]);
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
