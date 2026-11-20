/* The strict parser. A port of crates/ms-syntax/src/parser.rs: the same tree, node ids, positions
 * and messages. A failure unwinds with longjmp to the nearest catch: the entry point, or one of
 * the three places that try something and fall back (a bracket read as type arguments, an inline
 * `if` read as an expression, and the operand of a rejected `try`). */
#include <stdio.h>
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>

#include "ms/lex.h"
#include "ms/parse.h"

#define IMPL_REMOVED                                                                               \
    "'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var "     \
    "Type.name(...)' when it changes self); a type satisfies an interface by having methods that " \
    "match it, so nothing declares it"
#define TRY_REMOVED                                                                                \
    "'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead " \
    "of x | try step"
#define IS_HINT                                                                                    \
    "; there is no 'is' operator: write '==' to compare values, or 'match value:' to test which "  \
    "alternative a value is"
#define HIDDEN_ITEM "for item"
#define INDEX_SET "[]="
/* Binding power of the operand of a prefix `not` or `try`. */
#define PREFIX_OPERAND 3
/* Precedence of `..`: above comparisons, below `+` and `-`. */
#define RANGE_LEVEL 5

typedef struct Catch {
    jmp_buf jb;
    struct Catch *prev;
    size_t scratch, bytes;
    size_t depth;
    bool inline_statement, inline_return, block_lambda;
} Catch;

typedef struct Parser {
    MsArena *arena;
    MsNames *names;
    const char *src;
    size_t src_len;
    const MsToken *tokens;
    size_t ntokens;
    size_t at;
    const MsBounds *bounds;
    size_t source_origin;
    bool inline_statement, inline_return, block_lambda;
    size_t depth;
    MsStmt **queued;
    uint32_t nqueued;
    uint32_t next_id;
    uint32_t speculative;
    bool enter_failed; /* the last unwind came from a failed enter(), which leaves depth raised */
    uint64_t *type_brackets;
    MsBuf *scratch, *bytes; /* shared with nested parsers */
    Catch *catch_;
    MsDiag *diag;
} Parser;

typedef struct {
    MsToken first, last;
} TokPair;

#define LIT(text) ((MsStr){(text), (uint32_t)(sizeof(text) - 1)})

static void *zalloc(MsArena *a, size_t n, size_t align) {
    void *p = ms_alloc(a, n, align);
    memset(p, 0, n);
    return p;
}
#define NEW(p, T) ((T *)zalloc((p)->arena, sizeof(T), _Alignof(T)))

/* ---- failure ---- */

static void throw_(Parser *p) __attribute__((noreturn));
static void throw_(Parser *p) {
    longjmp(p->catch_->jb, 1);
}

static MsDiag *parse_diag(Parser *p, MsPos pos, MsStr message) {
    memset(p->diag, 0, sizeof *p->diag);
    p->diag->pos = pos;
    p->diag->message = message;
    return p->diag;
}

static void catch_begin(Parser *p, Catch *c) {
    c->prev = p->catch_;
    c->scratch = p->scratch->len;
    c->bytes = p->bytes->len;
    c->depth = p->depth;
    c->inline_statement = p->inline_statement;
    c->inline_return = p->inline_return;
    c->block_lambda = p->block_lambda;
    p->catch_ = c;
}

/* Leaves a catch after a normal return. */
static void catch_end(Parser *p, Catch *c) {
    p->catch_ = c->prev;
}

/* Leaves a catch after an unwind, restoring what the unwound frames would have restored. */
static void catch_restore(Parser *p, Catch *c) {
    p->catch_ = c->prev;
    p->scratch->len = c->scratch;
    p->bytes->len = c->bytes;
    p->inline_statement = c->inline_statement;
    p->inline_return = c->inline_return;
    p->block_lambda = c->block_lambda;
    p->depth = c->depth + (p->enter_failed ? 1 : 0);
    p->enter_failed = false;
}

static MsStr fmt(Parser *p, const char *f, ...) __attribute__((format(printf, 2, 3)));
static MsStr fmt(Parser *p, const char *f, ...) {
    va_list ap;
    va_start(ap, f);
    MsStr r = ms_arena_vfmt(p->arena, f, ap);
    va_end(ap);
    return r;
}
#define STR(s) ((int)(s).len), ((s).ptr)

static MsToken peek(const Parser *p) {
    return p->tokens[p->at];
}
static MsTok kind(const Parser *p) {
    return (MsTok)p->tokens[p->at].kind;
}
/* Token n ahead of the current one, clamped to the final Eof. */
static MsToken ahead(const Parser *p, size_t n) {
    size_t i = p->at + n;
    return p->tokens[i < p->ntokens ? i : p->ntokens - 1];
}
static MsToken previous(const Parser *p) {
    return p->tokens[p->at - 1];
}
static MsStr text(const Parser *p, MsToken t) {
    MsStr s = {p->src + t.lo, t.hi - t.lo};
    return s;
}
static bool text_is(const Parser *p, MsToken t, const char *w) {
    MsStr s = text(p, t);
    return s.len == strlen(w) && memcmp(s.ptr, w, s.len) == 0;
}
static bool str_is(MsStr s, const char *w) {
    return s.len == strlen(w) && memcmp(s.ptr, w, s.len) == 0;
}
static MsSym sym(Parser *p, MsToken t) {
    MsStr s = text(p, t);
    return ms_intern(p->names, s.ptr, s.len);
}
static MsSym intern(Parser *p, const char *s) {
    return ms_intern_cstr(p->names, s);
}
static bool take(Parser *p, MsTok k) {
    if (kind(p) == k) {
        p->at++;
        return true;
    }
    return false;
}
static MsToken next(Parser *p) {
    MsToken t = peek(p);
    p->at++;
    return t;
}
static uint32_t new_id(Parser *p) {
    return p->next_id++;
}

/* ---- scratch lists ---- */

static size_t mark(Parser *p) {
    return p->scratch->len;
}
static void push(Parser *p, const void *item, size_t size) {
    ms_buf_put(p->scratch, item, size);
}
static void push_ptr(Parser *p, const void *ptr) {
    push(p, &ptr, sizeof ptr);
}
/* Copies the items pushed since `m` into the arena and drops them from the scratch stack. */
static void *finish(Parser *p, size_t m, uint32_t *len, size_t size, size_t align) {
    size_t bytes = p->scratch->len - m;
    *len = (uint32_t)(bytes / size);
    void *out = ms_alloc(p->arena, bytes ? bytes : 1, align);
    if (bytes != 0) {
        memcpy(out, p->scratch->data + m, bytes);
    }
    p->scratch->len = m;
    return out;
}
#define FINISH_PTRS(p, m, list)                                                                    \
    do {                                                                                           \
        (list).ptr = finish((p), (m), &(list).len, sizeof(void *), _Alignof(void *));              \
    } while (0)

/* ---- describing tokens ---- */

static MsStr describe(Parser *p, MsToken t) {
    MsStr s = text(p, t);
    switch (t.kind) {
    case MS_T_Newline: return LIT("end of line");
    case MS_T_Indent: return LIT("an unexpected indented block");
    case MS_T_Dedent: return LIT("the end of the block");
    case MS_T_Eof: return LIT("end of file");
    case MS_T_Name: return fmt(p, "name '%.*s'", STR(s));
    case MS_T_Number: return fmt(p, "number %.*s", STR(s));
    case MS_T_String: return fmt(p, "text %.*s", STR(s));
    default: return fmt(p, "'%s'", ms_tok_str((MsTok)t.kind));
    }
}

static MsStr describe_kind(Parser *p, MsTok k) {
    switch (k) {
    case MS_T_Newline: return LIT("end of line");
    case MS_T_Indent: return LIT("an indented block");
    case MS_T_Dedent: return LIT("the end of the block");
    case MS_T_Eof: return LIT("end of file");
    case MS_T_Name: return LIT("a name");
    case MS_T_Number: return LIT("a number");
    case MS_T_String: return LIT("text in double quotes");
    default: return fmt(p, "'%s'", ms_tok_str(k));
    }
}

/* The expected-token hint; `kind` is the expected kind's spelling. */
static MsStr need_hint(Parser *p, const char *kd, MsToken found) {
    MsStr found_text = text(p, found);
    MsTok fk = (MsTok)found.kind;
#define IS(s) (strcmp(kd, (s)) == 0)
    if (IS(":")) {
        if (fk == MS_T_Name && str_is(found_text, "is")) {
            return LIT(IS_HINT);
        }
        return LIT("; block headers (fn, if, else, for, while, match, type, enum, impl, test) end with ':' before their indented body");
    }
    if (IS(")")) return LIT("; close the parenthesis, separating items with commas");
    if (IS("]")) {
        if (fk == MS_T_For) {
            return LIT("; there are no comprehensions: build the list with map and filter, e.g. items.filter(fn x: x > 0).map(fn x: x * 2)");
        }
        return LIT("; close the bracket, separating items with commas");
    }
    if (IS("}")) return LIT("; close the brace, separating items with commas");
    if (IS("(")) {
        if (fk == MS_T_Lt) {
            return LIT("; type parameters use square brackets, e.g. fn identity[T](value: T) T:");
        }
        return LIT("; a call or parameter list starts with '('");
    }
    if (IS("from")) {
        if (fk == MS_T_Comma) {
            return LIT("; to import several names, write import a, b from \"path.ms\", or import (a from \"a.ms\", b from \"b.ms\") for several modules");
        }
        return LIT("; imports read: import name from \"path.ms\"");
    }
    if (IS("in")) return LIT("; loops read: for item in items:");
    if (IS("=") && fk == MS_T_Newline) {
        return LIT("; every let/var binding needs an initial value, e.g. var count: Int = 0");
    }
    if (IS(":=") && fk == MS_T_Newline) {
        return LIT("; a binding needs a value: write name := value, or name: Type := value; closure parameters with a type go in parentheses, as in fn(n: Int): n + 1");
    }
    if (IS("NAME")) {
        if (fk == MS_T_SelfKw) {
            return LIT("; 'self' is reserved: a method's receiver is implicit, so leave it out of the parameter list and write self.field in the body");
        }
        if (fk == MS_T_LParen) {
            return LIT("; give it a name, e.g. fn add(a: Int, b: Int) Int:");
        }
        if (str_is(found_text, "_")) {
            return LIT("; '_' is a reserved word and cannot be used as a name: loops, parameters and bindings need a real name such as item, unused or ignored");
        }
        const char *fs = ms_tok_str(fk);
        if (str_is(found_text, fs) && found_text.len > 0 &&
            ((found_text.ptr[0] >= 'a' && found_text.ptr[0] <= 'z') || (found_text.ptr[0] >= 'A' && found_text.ptr[0] <= 'Z'))) {
            return fmt(p, "; '%.*s' is a reserved word and cannot be used as a name", STR(found_text));
        }
        return LIT("");
    }
    if (IS("NEWLINE")) return LIT("; end the statement with a line break");
    if (IS("INDENT")) return LIT("; indent the block body by four spaces under its header");
#undef IS
    return LIT("");
}

/* ---- failures ---- */

static void fail(Parser *p, MsToken t, MsStr message) __attribute__((noreturn));
static void fail(Parser *p, MsToken t, MsStr message) {
    MsDiag *d = parse_diag(p, t.pos, message);
    if (t.end.line > 0) {
        d->has_end = true;
        d->end = t.end;
    }
    throw_(p);
}
#undef FAIL
#undef FAILF
#define FAIL(p, t, lit) fail((p), (t), LIT(lit))
#define FAILF(p, t, ...) fail((p), (t), fmt((p), __VA_ARGS__))

/* Fails on `first` with a replacement of the range first.pos..last.end. */
static void fail_fix_range(Parser *p, MsToken first, MsToken last, MsStr message, MsStr replacement)
    __attribute__((noreturn));
static void fail_fix_range(Parser *p, MsToken first, MsToken last, MsStr message, MsStr replacement) {
    MsDiag *d = parse_diag(p, first.pos, message);
    if (last.end.line > 0) {
        d->has_end = true;
        d->end = last.end;
        d->has_fix = true;
        d->fix_pos = first.pos;
        d->fix_end = last.end;
        d->replacement = replacement;
    }
    throw_(p);
}
static void fail_fix(Parser *p, MsToken t, MsStr message, MsStr replacement) __attribute__((noreturn));
static void fail_fix(Parser *p, MsToken t, MsStr message, MsStr replacement) {
    fail_fix_range(p, t, t, message, replacement);
}

static bool joins_word(uint8_t b) {
    return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b == '_';
}

/* A symbolic operator can touch either operand; its word replacement needs separation wherever it
 * would otherwise join an identifier or number. */
static void fail_word_operator(Parser *p, MsToken first, MsToken last, MsStr message, const char *word)
    __attribute__((noreturn));
static void fail_word_operator(Parser *p, MsToken first, MsToken last, MsStr message, const char *word) {
    MsBuf b = {0};
    if (first.lo > 0 && joins_word((uint8_t)p->src[first.lo - 1])) {
        ms_buf_putc(&b, ' ');
    }
    ms_buf_puts(&b, word);
    if (last.hi < p->src_len && joins_word((uint8_t)p->src[last.hi])) {
        ms_buf_putc(&b, ' ');
    }
    MsStr r = {ms_arena_strndup(p->arena, b.data, b.len), (uint32_t)b.len};
    ms_buf_free(&b);
    fail_fix_range(p, first, last, message, r);
}

static void and_and(Parser *p, MsToken first) __attribute__((noreturn));
static void and_and(Parser *p, MsToken first) {
    MsToken n = ahead(p, 1);
    MsToken last = (n.kind == MS_T_Amp && n.pos.offset == first.end.offset) ? n : first;
    fail_word_operator(p, first, last, LIT("'&&' is not an operator; write 'and' for logical and"), "and");
}

static MsToken need(Parser *p, MsTok k) {
    MsToken t = peek(p);
    if (t.kind == k) {
        p->at++;
        return t;
    }
    if (p->speculative > 0) {
        throw_(p);
    }
    if (k == MS_T_Colon && t.kind == MS_T_LBrace) {
        MsDiag *d = parse_diag(p, t.pos, LIT("expected ':', found '{'; blocks are not braced: end the header with ':', indent the body four spaces on the following lines, and remove the closing '}'"));
        /* The colon attaches to the header, so the edit also takes the spaces before the brace. */
        MsPos start = t.pos;
        if (p->at > 0) {
            MsPos e = p->tokens[p->at - 1].end;
            if (e.line == t.pos.line) {
                start = e;
            }
        }
        d->has_end = true;
        d->end = t.end;
        d->has_fix = true;
        d->fix_pos = start;
        d->fix_end = t.end;
        d->replacement = LIT(":");
        throw_(p);
    }
    MsStr hint = need_hint(p, ms_tok_str(k), t);
    MsStr dk = describe_kind(p, k);
    MsStr dt = describe(p, t);
    fail(p, t, fmt(p, "expected %.*s, found %.*s%.*s", STR(dk), STR(dt), STR(hint)));
}

/* Consumes the contextual word `from` that ends an import's names. */
static void need_from(Parser *p) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Name && text_is(p, t, "from")) {
        p->at++;
        return;
    }
    MsStr dt = describe(p, t);
    MsStr hint = need_hint(p, "from", t);
    fail(p, t, fmt(p, "expected 'from', found %.*s%.*s", STR(dt), STR(hint)));
}

/* A legacy `case` prefix, including the spaces before a following name on the same line. */
static bool legacy_case_prefix(const Parser *p, MsToken *out) {
    MsToken prefix = peek(p);
    MsToken nx = ahead(p, 1);
    if (prefix.kind != MS_T_Name || !text_is(p, prefix, "case") || nx.kind != MS_T_Name ||
        prefix.pos.line != nx.pos.line) {
        return false;
    }
    prefix.end = nx.pos;
    prefix.hi = nx.lo;
    *out = prefix;
    return true;
}

static void newlines(Parser *p) {
    while (take(p, MS_T_Newline)) {
    }
}

static void link(Parser *p, size_t *links) {
    (*links)++;
    if (*links > MS_MAX_CHAIN) {
        FAILF(p, peek(p), "expression chain exceeds %d operators or accesses; split it into named parts", MS_MAX_CHAIN);
    }
}

/* Counts one level of nesting; the caller decrements depth when it is done. */
static void enter(Parser *p) {
    p->depth++;
    if (p->depth > MS_MAX_NESTING) {
        p->enter_failed = true;
        if (p->speculative > 0) {
            throw_(p);
        }
        FAILF(p, peek(p), "nesting exceeds %d levels; split the expression, type, or block into named parts", MS_MAX_NESTING);
    }
}

static void end(Parser *p) {
    if (p->inline_statement) {
        switch (kind(p)) {
        case MS_T_Newline: case MS_T_Comma: case MS_T_RParen: case MS_T_RBracket: case MS_T_RBrace:
            return;
        default:
            break;
        }
        MsToken t = peek(p);
        MsStr dt = describe(p, t);
        const char *is = (t.kind == MS_T_Name && text_is(p, t, "is")) ? IS_HINT : "";
        FAILF(p, t, "expected end of inline statement, found %.*s; an inline body holds one simple statement; for more statements or an `else`, put the body on indented lines and start `else:` on its own line at the `if`'s indentation%s",
              STR(dt), is);
    }
    if (take(p, MS_T_Newline)) {
        newlines(p);
        return;
    }
    if (p->at > 0 && previous(p).kind == MS_T_Dedent) {
        return;
    }
    MsToken t = peek(p);
    if (p->block_lambda && t.kind == MS_T_Comma) {
        FAIL(p, t, "a comma cannot end a statement in an indented function body; to separate enclosing arguments, put the comma on its own line dedented to the fn header, or group the function in parentheses");
    }
    if (t.kind == MS_T_Amp) {
        and_and(p, t);
    }
    if (t.kind == MS_T_Arrow || (t.kind == MS_T_Assign && ahead(p, 1).kind == MS_T_Gt)) {
        FAIL(p, t, "there is no arrow function; anonymous functions are written fn x: x + 1");
    }
    bool prev_new = p->at > 0 && text_is(p, previous(p), "new");
    MsStr prev_word = p->at > 0 ? text(p, previous(p)) : LIT("");
    const char *hint;
    if (str_is(prev_word, "def") && t.kind == MS_T_Name) {
        hint = "; there is no 'def': declare a function with 'fn name(a: Int) Int:'";
    } else if (str_is(prev_word, "lambda")) {
        hint = "; there is no 'lambda': write an anonymous function as 'fn x: x + 1'";
    } else if (str_is(prev_word, "elif")) {
        hint = "; there is no 'elif': write 'else if <condition>:' for a further branch";
    } else if (t.kind == MS_T_Name && text_is(p, t, "is")) {
        hint = IS_HINT;
    } else if (t.kind == MS_T_Name && prev_new) {
        hint = "; there is no 'new': construct a value by calling the type, Name(field: value)";
    } else if (t.kind == MS_T_If) {
        hint = "; there is no inline conditional expression 'a if c else b': write 'if c: a else: b', or use an if statement";
    } else if (t.kind == MS_T_Question) {
        hint = "; '?' after a Result call propagates its error, and is not '?\?' or 'c ? a : b': unwrap an Optional with 'if x := v:' or give it a default with 'v.get(default)', chain with 'a?.b', and write a conditional as 'if c: a else: b'";
    } else if (t.kind == MS_T_Comma) {
        hint = "; commas separate items only inside (), [] or {}: put each field, case, or statement on its own line";
    } else if (t.kind == MS_T_LBrace) {
        hint = "; '{' does not open a block: end the header with ':' and indent the body (an interface method is just its signature)";
    } else {
        hint = "; put one statement per line, and join operands with an operator or a comma inside brackets";
    }
    MsStr dt = describe(p, t);
    FAILF(p, t, "expected end of statement, found %.*s%s", STR(dt), hint);
}

/* ---- tables ---- */

static bool type_token(MsTok k) {
    switch (k) {
    case MS_T_Name: case MS_T_Dot: case MS_T_LBracket: case MS_T_RBracket: case MS_T_Comma:
    case MS_T_Question: case MS_T_Bang: case MS_T_Fn: case MS_T_Var: case MS_T_LParen:
    case MS_T_RParen:
        return true;
    default:
        return false;
    }
}

/* One bit per token: set on a `[` whose bracketed tokens could all be type arguments. */
static uint64_t *compute_type_brackets(MsArena *a, const MsToken *tokens, size_t n) {
    size_t words = (n + 63) / 64;
    uint64_t *bits = zalloc(a, (words ? words : 1) * sizeof(uint64_t), _Alignof(uint64_t));
    MsBuf open = {0}; /* entries: (index, ok) */
    typedef struct {
        size_t at;
        bool ok;
    } Open;
    for (size_t at = 0; at < n; at++) {
        MsTok k = (MsTok)tokens[at].kind;
        if (k == MS_T_LBracket) {
            Open o = {at, true};
            ms_buf_put(&open, &o, sizeof o);
        } else if (k == MS_T_RBracket) {
            if (open.len != 0) {
                Open o = ((Open *)open.data)[open.len / sizeof(Open) - 1];
                open.len -= sizeof(Open);
                if (o.ok) {
                    bits[o.at / 64] |= (uint64_t)1 << (o.at % 64);
                }
                if (open.len != 0) {
                    ((Open *)open.data)[open.len / sizeof(Open) - 1].ok &= o.ok;
                }
            }
        } else if (!type_token(k)) {
            if (open.len != 0) {
                ((Open *)open.data)[open.len / sizeof(Open) - 1].ok = false;
            }
        }
    }
    ms_buf_free(&open);
    return bits;
}

static bool type_bracket(const Parser *p, size_t at) {
    return (p->type_brackets[at / 64] >> (at % 64)) & 1;
}

static bool binary_op(MsTok k, MsBinaryOp *op) {
    switch (k) {
    case MS_T_Or: *op = MS_B_OR; return true;
    case MS_T_And: *op = MS_B_AND; return true;
    case MS_T_EqEq: *op = MS_B_EQ; return true;
    case MS_T_NotEq: *op = MS_B_NE; return true;
    case MS_T_Lt: *op = MS_B_LT; return true;
    case MS_T_Gt: *op = MS_B_GT; return true;
    case MS_T_Le: *op = MS_B_LE; return true;
    case MS_T_Ge: *op = MS_B_GE; return true;
    case MS_T_Plus: *op = MS_B_ADD; return true;
    case MS_T_Minus: *op = MS_B_SUB; return true;
    case MS_T_Star: *op = MS_B_MUL; return true;
    case MS_T_Slash: *op = MS_B_DIV; return true;
    case MS_T_Percent: *op = MS_B_REM; return true;
    default: return false;
    }
}

static bool arith_op(MsTok k, MsBinaryOp *op) {
    switch (k) {
    case MS_T_Plus: case MS_T_Minus: case MS_T_Star: case MS_T_Slash: case MS_T_Percent:
        return binary_op(k, op);
    default:
        return false;
    }
}

static bool starts_type(MsTok k) {
    return k == MS_T_Name || k == MS_T_Fn || k == MS_T_LParen;
}

const char *ms_unary_str(MsUnaryOp op) {
    switch (op) {
    case MS_U_NOT: return "not";
    case MS_U_NEG: return "-";
    case MS_U_PLUS: return "+";
    default: return "try";
    }
}

const char *ms_binary_str(MsBinaryOp op) {
    static const char *const s[] = {"or", "and", "==", "!=", "<", ">", "<=", ">=", "+", "-", "*", "/", "%"};
    return s[op];
}

int ms_binary_precedence(MsBinaryOp op) {
    switch (op) {
    case MS_B_OR: return 1;
    case MS_B_AND: return 2;
    case MS_B_EQ: case MS_B_NE: case MS_B_LT: case MS_B_GT: case MS_B_LE: case MS_B_GE: return 4;
    case MS_B_ADD: case MS_B_SUB: return 6;
    default: return 7;
    }
}

/* Declaration words from other languages: the message and the Manuscript spelling to replace the
 * word with, when there is one. */
static bool foreign_declaration(Parser *p, MsToken t, MsStr *message, const char **replacement) {
    if (t.kind == MS_T_Var) {
        *message = LIT("module level holds only constants (NAME := value); keep mutable state in a 'var' inside a fn, or in a field of a type");
        *replacement = NULL;
        return true;
    }
    if (t.kind != MS_T_Name) {
        return false;
    }
    MsStr w = text(p, t);
    const char *advice;
    const char *rep = NULL;
#define IN(s) str_is(w, s)
    if (IN("function") || IN("def") || IN("func") || IN("fun") || IN("sub")) {
        rep = "fn";
        advice = "declare a function as 'fn name(a: Int) Int:' with the result type after the parameters";
    } else if (IN("class") || IN("struct") || IN("record") || IN("data")) {
        rep = "type";
        advice = "declare a type with 'type Name:' and 'field: Type' lines, then add methods as 'fn Name.method(...)' after it";
    } else if (IN("union") || IN("variant") || IN("sealed")) {
        rep = "enum";
        advice = "declare an enum with 'enum Name:' and one 'Variant' or 'Variant(field: Type)' line each";
    } else if (IN("trait") || IN("protocol") || IN("abstract")) {
        rep = "interface";
        advice = "declare a contract with 'interface Name:' and method signatures, then give a type methods that match it, 'fn Type.operation(...)'";
    } else if (IN("const") || IN("val") || IN("final") || IN("let")) {
        advice = "write 'NAME := value' (or 'NAME: Type := value') for a module constant";
    } else if (IN("pub") || IN("public")) {
        rep = "export";
        advice = "write 'export' before the declaration to make it visible to other modules";
    } else if (IN("use") || IN("require") || IN("include") || IN("using") || IN("from")) {
        rep = "import";
        advice = "imports read: import name from \"path.ms\"";
    } else if (IN("static") || IN("private") || IN("internal") || IN("async") || IN("extern") ||
               IN("package") || IN("namespace") || IN("module")) {
        advice = "there is no such modifier; top level holds only import, let, fn, type, enum, interface, impl, and test, optionally prefixed by export";
    } else {
        return false;
    }
#undef IN
    *message = fmt(p, "'%.*s' is not a Manuscript declaration keyword; %s", STR(w), advice);
    *replacement = rep;
    return true;
}

/* ---- forward declarations ---- */

static MsExpr *expression(Parser *p, int min);
static MsTypeRef *typ(Parser *p);
static MsTypeRefs type_args(Parser *p);
static MsStmt *statement(Parser *p, bool allow_value);
static MsStmts statement_suite(Parser *p, bool expression, bool fn_body);
static MsPattern *pattern(Parser *p);
static MsExpr *postfix(Parser *p, MsExpr *e);
static MsExpr *primary(Parser *p);
static MsExpr *clone_chain(Parser *p, const MsExpr *e);

/* ---- node construction ---- */

/* An expression ending at the previous token. */
static MsExpr *mk(Parser *p, MsPos pos, MsExprKind k) {
    MsExpr *e = NEW(p, MsExpr);
    e->id = new_id(p);
    e->pos = pos;
    e->end = p->at > 0 ? previous(p).end : pos;
    e->kind = (uint8_t)k;
    return e;
}

static MsExpr *mk_name(Parser *p, MsPos pos, MsSym name) {
    MsExpr *e = mk(p, pos, MS_E_NAME);
    e->u.sym = name;
    return e;
}

static MsExpr *mk_member(Parser *p, MsPos pos, MsExpr *left, MsSym name) {
    MsExpr *e = mk(p, pos, MS_E_MEMBER);
    e->u.member.left = left;
    e->u.member.name = name;
    return e;
}

static MsExpr *mk_call(Parser *p, MsPos pos, MsExpr *callee, MsArg *args, uint32_t nargs) {
    MsExpr *e = mk(p, pos, MS_E_CALL);
    e->u.call.callee = callee;
    e->u.call.args.ptr = args;
    e->u.call.args.len = nargs;
    return e;
}

static MsTypeRef *mk_named_type(Parser *p, MsPos pos, MsSym name, MsTypeRefs args) {
    MsTypeRef *t = NEW(p, MsTypeRef);
    t->id = new_id(p);
    t->pos = pos;
    t->kind = MS_TYPE_NAMED;
    t->name = name;
    t->args = args;
    return t;
}

static MsParam *mk_param(Parser *p, MsPos pos, MsSym name, MsTypeRef *ty, MsExpr *def, bool is_mutable, bool moving) {
    MsParam *m = NEW(p, MsParam);
    m->id = new_id(p);
    m->pos = pos;
    m->name = name;
    m->ty = ty;
    m->def = def;
    m->is_mutable = is_mutable;
    m->moving = moving;
    return m;
}

/* ---- types ---- */

static MsTypeRef *named_type(Parser *p) {
    MsToken name = need(p, MS_T_Name);
    MsSym full = sym(p, name);
    if (kind(p) == MS_T_Dot) {
        size_t bm = p->bytes->len;
        MsStr first = ms_name(p->names, full);
        ms_buf_put(p->bytes, first.ptr, first.len);
        while (take(p, MS_T_Dot)) {
            ms_buf_putc(p->bytes, '.');
            MsToken part = need(p, MS_T_Name);
            MsStr t = text(p, part);
            ms_buf_put(p->bytes, t.ptr, t.len);
        }
        full = ms_intern(p->names, p->bytes->data + bm, p->bytes->len - bm);
        p->bytes->len = bm;
    }
    MsTypeRefs args = {NULL, 0};
    MsStr full_s = ms_name(p->names, full);
    if (kind(p) == MS_T_LBracket && p->speculative == 0 && str_is(full_s, "Callable")) {
        FAILF(p, peek(p), "there is no %.*s[...] type; a function type is written fn(Int) Int: parameter types in parentheses, then the result type", STR(full_s));
    }
    if (kind(p) == MS_T_LBracket && p->speculative == 0 && str_is(full_s, "Optional")) {
        FAIL(p, peek(p), "there is no Optional[T] spelling; write T? instead, e.g. Int? or (fn(Int) Int)?");
    }
    if (take(p, MS_T_LBracket)) {
        if (p->speculative > 0 && !type_bracket(p, p->at - 1)) {
            throw_(p);
        }
        args = type_args(p);
    }
    MsToken lt = peek(p);
    if (lt.kind == MS_T_Lt && p->speculative == 0 && lt.pos.offset == previous(p).end.offset && args.len == 0) {
        FAILF(p, lt, "type arguments use square brackets, not angle brackets; write %.*s[T] instead of %.*s<T>", STR(full_s), STR(full_s));
    }
    return mk_named_type(p, name.pos, full, args);
}

static MsTypeRefs type_args(Parser *p) {
    size_t m = mark(p);
    for (;;) {
        push_ptr(p, typ(p));
        if (!take(p, MS_T_Comma)) {
            break;
        }
        if (kind(p) == MS_T_RBracket) {
            break;
        }
    }
    need(p, MS_T_RBracket);
    MsTypeRefs r;
    FINISH_PTRS(p, m, r);
    return r;
}

/* The type that follows a parameter list, rejecting the removed `->` and a missing type. */
static MsTypeRef *result_type(Parser *p) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Arrow) {
        fail_fix(p, t, LIT("result types follow the parameter list without an arrow; remove '->', e.g. fn f() Void:"), LIT(""));
    }
    if (t.kind == MS_T_LBrace) {
        FAIL(p, t, "blocks are not braced and every fn declares its result type: write the result type, then ':' and an indented body, e.g. fn f() Void: (Void when it returns nothing), and remove the closing '}'");
    }
    if (t.kind == MS_T_Colon || t.kind == MS_T_Newline) {
        if (p->speculative > 0) {
            throw_(p);
        }
        FAIL(p, t, "every fn declares its result type after the parameter list, e.g. fn f() Void:");
    }
    return typ(p);
}

/* Wraps `t` once per trailing suffix: `T?` is Optional[T], `T!` is Result[T, Error], and `T!E`
 * (E directly after the bang) is Result[T, E]. */
static MsTypeRef *type_suffix(Parser *p, MsTypeRef *t) {
    for (;;) {
        MsPos pos = t->pos;
        const char *name;
        MsTypeRef *argv[2];
        uint32_t nargs;
        if (take(p, MS_T_Question)) {
            name = "Optional";
            argv[0] = t;
            nargs = 1;
        } else if (take(p, MS_T_Bang)) {
            MsToken bang = previous(p);
            MsToken nx = peek(p);
            MsTypeRef *error;
            if (nx.kind == MS_T_Name && nx.lo == bang.hi) {
                error = named_type(p);
            } else {
                MsTypeRefs none = {NULL, 0};
                error = mk_named_type(p, pos, intern(p, "Error"), none);
            }
            name = "Result";
            argv[0] = t;
            argv[1] = error;
            nargs = 2;
        } else {
            return t;
        }
        MsTypeRefs args;
        args.ptr = MS_NEW_N(p->arena, MsTypeRef *, nargs);
        args.len = nargs;
        memcpy(args.ptr, argv, nargs * sizeof(MsTypeRef *));
        t = mk_named_type(p, pos, intern(p, name), args);
    }
}

/* Takes a contextual `move` marker: the word `move` followed by a token of one of the `next`
 * kinds, so a name `move` still reads as a name. */
static bool take_move(Parser *p, const MsTok *nexts, size_t n) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Name && text_is(p, t, "move")) {
        MsTok k = (MsTok)ahead(p, 1).kind;
        for (size_t i = 0; i < n; i++) {
            if (nexts[i] == k) {
                p->at++;
                return true;
            }
        }
    }
    return false;
}
#define TAKE_MOVE(p, ...) take_move((p), (const MsTok[]){__VA_ARGS__}, sizeof((const MsTok[]){__VA_ARGS__}) / sizeof(MsTok))

static MsTypeRef *typ_inner(Parser *p) {
    MsToken first = peek(p);
    if (first.kind == MS_T_Fn) {
        p->at++;
        need(p, MS_T_LParen);
        MsParams params = {NULL, 0};
        if (!take(p, MS_T_RParen)) {
            size_t m = mark(p);
            uint32_t count = 0;
            for (;;) {
                /* `fn(var List[Int]) Void`: a parameter the function changes in place. */
                bool moving = TAKE_MOVE(p, MS_T_Var, MS_T_Name, MS_T_Fn);
                bool is_mutable = take(p, MS_T_Var);
                if (moving && is_mutable) {
                    FAIL(p, previous(p), "a parameter is either `move` (the callee takes it) or `var` (the callee changes it in place), not both");
                }
                MsTypeRef *ty = typ(p);
                char nm[32];
                snprintf(nm, sizeof nm, "_%u", count);
                push_ptr(p, mk_param(p, ty->pos, intern(p, nm), ty, NULL, is_mutable, moving));
                count++;
                if (!take(p, MS_T_Comma)) {
                    break;
                }
                if (kind(p) == MS_T_RParen) {
                    break;
                }
            }
            need(p, MS_T_RParen);
            FINISH_PTRS(p, m, params);
        }
        MsTypeRef *result = typ(p);
        MsTypeRef *t = NEW(p, MsTypeRef);
        t->id = new_id(p);
        t->pos = first.pos;
        t->kind = MS_TYPE_FN;
        t->params = params;
        t->result = result;
        return t;
    }
    MsTypeRef *t;
    if (take(p, MS_T_LParen)) {
        t = typ(p);
        if (kind(p) == MS_T_Comma && p->speculative == 0) {
            FAIL(p, peek(p), "Manuscript has no tuples; declare a type with 'type Pair:' and named fields to return several values, or use a List when the items share one type");
        }
        need(p, MS_T_RParen);
    } else {
        t = named_type(p);
    }
    return type_suffix(p, t);
}

static MsTypeRef *typ(Parser *p) {
    enter(p);
    MsTypeRef *r = typ_inner(p);
    p->depth--;
    return r;
}

/* The default of a `T?` parameter or field written without one: `none`. */
static MsExpr *implicit_none(Parser *p, const MsTypeRef *t) {
    if (t->kind != MS_TYPE_NAMED) {
        return NULL;
    }
    if (str_is(ms_name(p->names, t->name), "Optional") && t->args.len == 1) {
        return mk_name(p, t->pos, intern(p, "none"));
    }
    return NULL;
}

static MsTypeParams type_params(Parser *p) {
    MsTypeParams result = {NULL, 0};
    if (!take(p, MS_T_LBracket)) {
        return result;
    }
    size_t m = mark(p);
    for (;;) {
        MsToken name = need(p, MS_T_Name);
        MsTypeRefs bounds = {NULL, 0};
        MsTypeRef *def = NULL;
        if (take(p, MS_T_Colon)) {
            size_t bm = mark(p);
            push_ptr(p, named_type(p));
            while (take(p, MS_T_Amp)) {
                push_ptr(p, named_type(p));
            }
            FINISH_PTRS(p, bm, bounds);
            if (kind(p) == MS_T_Plus || kind(p) == MS_T_And) {
                fail_fix(p, peek(p), LIT("combine bounds with '&', as in T: Comparable & Clonable"), LIT("&"));
            }
        }
        if (take(p, MS_T_Assign)) {
            def = typ(p);
        }
        MsTypeParam *tp = NEW(p, MsTypeParam);
        tp->id = new_id(p);
        tp->pos = name.pos;
        tp->name = sym(p, name);
        tp->bounds = bounds;
        tp->def = def;
        push_ptr(p, tp);
        if (!take(p, MS_T_Comma)) {
            break;
        }
        if (kind(p) == MS_T_RBracket) {
            break;
        }
    }
    need(p, MS_T_RBracket);
    FINISH_PTRS(p, m, result);
    return result;
}

/* The colon after a parameter or field name; a missing one is usually a type written directly
 * after the name. */
static void need_name_colon(Parser *p, MsToken name) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Name && p->speculative == 0) {
        MsToken at = name;
        at.pos = name.end;
        at.end = name.end;
        MsStr n = text(p, name);
        fail_fix(p, at, fmt(p, "expected ':' between '%.*s' and its type; parameters and fields are written name: Type", STR(n)), LIT(":"));
    }
    if ((t.kind == MS_T_Comma || t.kind == MS_T_RParen) && p->speculative == 0) {
        MsStr n = text(p, name);
        FAILF(p, name, "parameter '%.*s' has no type; every parameter is written name: Type, e.g. %.*s: Int", STR(n), STR(n));
    }
    need(p, MS_T_Colon);
}

static MsParams parameters(Parser *p, bool defaults, bool inferred) {
    need(p, MS_T_LParen);
    MsParams params = {NULL, 0};
    if (take(p, MS_T_RParen)) {
        return params;
    }
    size_t m = mark(p);
    for (;;) {
        bool moving = TAKE_MOVE(p, MS_T_Var, MS_T_Name);
        bool is_mutable = take(p, MS_T_Var);
        if (moving && is_mutable) {
            FAIL(p, previous(p), "a parameter is either `move` (the callee takes it) or `var` (the callee changes it in place), not both");
        }
        MsToken name = need(p, MS_T_Name);
        MsTypeRef *ty = NULL;
        MsExpr *def = NULL;
        if (take(p, MS_T_Colon)) {
            if (kind(p) == MS_T_Var) {
                MsToken t = peek(p);
                MsStr n = text(p, name);
                MsStr rep = fmt(p, "var %.*s:", STR(n));
                fail_fix_range(p, name, t, fmt(p, "'var' goes before the parameter name, not its type; write var %.*s: Type", STR(n)), rep);
            }
            ty = typ(p);
        } else if (!inferred || kind(p) == MS_T_Name) {
            need_name_colon(p, name);
        }
        if (take(p, MS_T_Assign)) {
            if (!defaults) {
                FAIL(p, previous(p), "function types and case payloads cannot have defaults; put the default on a named function parameter or a type field instead");
            }
            def = expression(p, 0);
        } else if (defaults && ty != NULL) {
            def = implicit_none(p, ty);
        }
        push_ptr(p, mk_param(p, name.pos, sym(p, name), ty, def, is_mutable, moving));
        if (!take(p, MS_T_Comma)) {
            break;
        }
        if (kind(p) == MS_T_RParen) {
            break;
        }
    }
    need(p, MS_T_RParen);
    FINISH_PTRS(p, m, params);
    return params;
}

/* ---- declarations ---- */

static MsStmts suite(Parser *p) {
    return statement_suite(p, false, false);
}

static MsMethod *method_signature(Parser *p, MsToken name, bool generics, bool body, bool mutating, MsPos var_at) {
    MsTypeParams tps = {NULL, 0};
    if (generics) {
        tps = type_params(p);
    }
    MsParams params = parameters(p, true, false);
    MsTypeRef *result = result_type(p);
    MsStmts stmts = {NULL, 0};
    if (body) {
        stmts = statement_suite(p, false, true);
    }
    MsMethod *m = NEW(p, MsMethod);
    m->id = new_id(p);
    m->pos = name.pos;
    m->var_at = var_at;
    m->func.name = sym(p, name);
    m->func.type_params = tps;
    m->func.params = params;
    m->func.result = result;
    m->func.body = stmts;
    m->mutating = mutating;
    return m;
}

/* The suite after `test "name":` or `bench "name":` (the keyword is consumed). */
static void single_line(Parser *p, MsToken token, const char *what) {
    MsStr full = text(p, token);
    if ((full.len >= 3 && memcmp(full.ptr, "\"\"\"", 3) == 0) || (full.len >= 4 && memcmp(full.ptr, "r\"\"\"", 4) == 0)) {
        FAILF(p, token, "%s are one-line text; write them with a single pair of quotes", what);
    }
}

typedef struct TextParts {
    MsTextPart *ptr;
    uint32_t len;
} TextParts;
static TextParts text_parts_of(Parser *p, MsToken token);

/* The plain text of a one-line name or path, or NULL when it interpolates. */
static bool plain_text(TextParts parts, MsStr *out) {
    if (parts.len == 1 && parts.ptr[0].expr == NULL) {
        *out = parts.ptr[0].lit;
        return true;
    }
    return false;
}

static bool parse_positive_i64(MsStr s, int64_t *out) {
    if (s.len == 0) {
        return false;
    }
    uint64_t v = 0;
    for (uint32_t i = 0; i < s.len; i++) {
        if (s.ptr[i] < '0' || s.ptr[i] > '9') {
            return false;
        }
        if (v > (UINT64_MAX - (uint64_t)(s.ptr[i] - '0')) / 10) {
            return false;
        }
        v = v * 10 + (uint64_t)(s.ptr[i] - '0');
    }
    if (v == 0 || v > (uint64_t)INT64_MAX) {
        return false;
    }
    *out = (int64_t)v;
    return true;
}

static MsDecl *new_decl(Parser *p, MsPos pos, MsDeclKind k) {
    MsDecl *d = NEW(p, MsDecl);
    d->id = new_id(p);
    d->pos = pos;
    d->kind = (uint8_t)k;
    return d;
}

static void test_block(Parser *p, bool bench, MsDecl *d) {
    MsToken name = need(p, MS_T_String);
    single_line(p, name, bench ? "bench names" : "test names");
    TextParts parts = text_parts_of(p, name);
    MsStr text_;
    if (!plain_text(parts, &text_)) {
        if (bench) {
            FAIL(p, name, "bench names cannot interpolate; use plain text, e.g. bench \"sums a list\":");
        }
        FAIL(p, name, "test names cannot interpolate; use plain text, e.g. test \"adds numbers\":");
    }
    int64_t per = 1;
    if (bench && kind(p) == MS_T_Name && text_is(p, peek(p), "per")) {
        p->at++;
        MsToken count = need(p, MS_T_Number);
        if (!parse_positive_i64(text(p, count), &per)) {
            FAIL(p, count, "'per' takes a positive whole number of operations, e.g. bench \"sums a list\" per 1000:");
        }
    }
    MsStmts body = suite(p);
    d->kind = MS_D_TEST;
    d->u.test.name = text_;
    d->u.test.body = body;
    d->u.test.bench = bench;
    d->u.test.per = per;
}

/* `const NAME = v` on one line: the range from the word through `=` and its replacement. */
static bool constant_fix(Parser *p, MsToken word, MsToken *first, MsToken *last, MsStr *replacement) {
    MsToken name = ahead(p, 1);
    if (name.kind != MS_T_Name || name.pos.line != word.pos.line) {
        return false;
    }
    for (size_t n = 2;; n++) {
        MsToken t = ahead(p, n);
        if (t.pos.line != word.pos.line || t.kind == MS_T_Newline || t.kind == MS_T_Eof) {
            return false;
        }
        if (t.kind == MS_T_Assign) {
            /* head = src[name.lo..t.lo].trim_end() */
            size_t hi = t.lo;
            while (hi > name.lo && (p->src[hi - 1] == ' ' || p->src[hi - 1] == '\t' || p->src[hi - 1] == '\n' || p->src[hi - 1] == '\r')) {
                hi--;
            }
            *replacement = fmt(p, "%.*s :=", (int)(hi - name.lo), p->src + name.lo);
            *first = word;
            *last = t;
            return true;
        }
    }
}

/* Whether the `fn` at the cursor starts a receiver method (`fn [var] Type[T].name`). */
static bool receiver_method_ahead(const Parser *p) {
    size_t at = 1;
    if (ahead(p, at).kind == MS_T_Name && text_is(p, ahead(p, at), "move") &&
        (ahead(p, at + 1).kind == MS_T_Name || ahead(p, at + 1).kind == MS_T_Var)) {
        at++;
    }
    if (ahead(p, at).kind == MS_T_Var) {
        at++;
    }
    if (ahead(p, at).kind != MS_T_Name) {
        return false;
    }
    at++;
    if (ahead(p, at).kind == MS_T_LBracket) {
        size_t depth = 0;
        for (;;) {
            MsTok k = (MsTok)ahead(p, at).kind;
            if (k == MS_T_LBracket) {
                depth++;
            } else if (k == MS_T_RBracket) {
                depth--;
                if (depth == 0) {
                    at++;
                    break;
                }
            } else if (k == MS_T_Newline || k == MS_T_Eof) {
                return false;
            }
            at++;
        }
    }
    return ahead(p, at).kind == MS_T_Dot;
}

static MsExpr *constant_value(Parser *p, MsPos *init_pos) {
    *init_pos = peek(p).pos;
    return expression(p, 0);
}

/* Consumes the `:=` of an immutable binding. A leftover `=` after a type annotation gets a fix-it. */
static void need_immutable_bind(Parser *p) {
    if (kind(p) == MS_T_Assign) {
        fail_fix(p, peek(p), LIT("an immutable binding uses ':=' after its type: write 'x: Type := value'; '=' binds only after 'var'"), LIT(":="));
    }
    need(p, MS_T_ColonAssign);
}

static void type_param_names(Parser *p, MsBuf *out, MsTypeParams tps) {
    if (tps.len == 0) {
        return;
    }
    ms_buf_putc(out, '[');
    for (uint32_t i = 0; i < tps.len; i++) {
        if (i > 0) {
            ms_buf_puts(out, ", ");
        }
        MsStr n = ms_name(p->names, tps.ptr[i]->name);
        ms_buf_put(out, n.ptr, n.len);
    }
    ms_buf_putc(out, ']');
}

static MsDecl *type_declaration(Parser *p, MsToken token) {
    p->at++;
    MsToken name_tok = need(p, MS_T_Name);
    MsSym name = sym(p, name_tok);
    MsTypeParams tps = type_params(p);
    if (token.kind == MS_T_Type && take(p, MS_T_Assign)) {
        size_t m = mark(p);
        push_ptr(p, typ(p));
        while (take(p, MS_T_Pipe)) {
            push_ptr(p, typ(p));
        }
        MsTypeRefs targets;
        FINISH_PTRS(p, m, targets);
        end(p);
        MsDecl *d = new_decl(p, token.pos, MS_D_ALIAS);
        d->u.alias.name = name;
        d->u.alias.type_params = tps;
        d->u.alias.targets = targets;
        return d;
    }
    need(p, MS_T_Colon);
    if (token.kind == MS_T_Interface && take(p, MS_T_Ellipsis)) {
        /* `interface Name: ...` declares a property with no operations, like `Data`. */
        end(p);
        MsDecl *d = new_decl(p, token.pos, MS_D_INTERFACE);
        d->u.iface.name = name;
        d->u.iface.type_params = tps;
        return d;
    }
    if (token.kind == MS_T_Type && take(p, MS_T_Ellipsis)) {
        end(p);
        MsDecl *d = new_decl(p, token.pos, MS_D_TYPE);
        d->u.type.name = name;
        d->u.type.type_params = tps;
        return d;
    }
    if (token.kind == MS_T_Enum && kind(p) == MS_T_Ellipsis) {
        FAIL(p, peek(p), "an enum must declare at least one variant; replace '...' with 'Name' or 'Name(field: Type)'");
    }
    need(p, MS_T_Newline);
    if (token.kind == MS_T_Enum && kind(p) != MS_T_Indent) {
        FAIL(p, peek(p), "an enum must declare at least one variant; indent 'Name' or 'Name(field: Type)' under the header");
    }
    need(p, MS_T_Indent);
    /* Only one of fields, cases and methods is ever collected for a given declaration kind. */
    size_t m = mark(p);
    while (kind(p) != MS_T_Dedent) {
        newlines(p);
        if (kind(p) == MS_T_Dedent) {
            break;
        }
        MsToken prefix;
        if (token.kind == MS_T_Type &&
            (legacy_case_prefix(p, &prefix) ||
             (kind(p) == MS_T_Name &&
              (ahead(p, 1).kind == MS_T_LParen || ahead(p, 1).kind == MS_T_Newline ||
               ahead(p, 1).kind == MS_T_Dedent || ahead(p, 1).kind == MS_T_Eof)))) {
            FAIL(p, token, "a type declared with 'type' cannot contain enum variants; replace 'type' with 'enum' and remove any legacy 'case' prefixes");
        }
        if (token.kind == MS_T_Enum) {
            if (legacy_case_prefix(p, &prefix)) {
                FAIL(p, prefix, "enum variants do not use 'case'; remove the prefix and write 'Name' or 'Name(field: Type)'");
            }
            if (kind(p) != MS_T_Name) {
                FAIL(p, peek(p), "an enum contains only variants; write 'Name' or 'Name(field: Type)', use 'type' for type fields, and put methods in an 'impl' block");
            }
        }
        bool move_fn = kind(p) == MS_T_Name && text_is(p, peek(p), "move") && ahead(p, 1).kind == MS_T_Fn;
        if (token.kind == MS_T_Interface && !move_fn && kind(p) != MS_T_Fn && kind(p) != MS_T_Var) {
            FAIL(p, peek(p), "an interface contains only operation signatures; write 'fn name(...) Type' and put method bodies in an 'impl' block");
        }
        if (token.kind == MS_T_Enum) {
            MsToken cname = need(p, MS_T_Name);
            MsParams payload = {NULL, 0};
            if (kind(p) == MS_T_LParen) {
                payload = parameters(p, false, false);
                for (uint32_t i = 0; i < payload.len; i++) {
                    if (payload.ptr[i]->is_mutable) {
                        FAIL(p, previous(p), "case payload fields cannot be 'var'; mutability belongs to the binding that holds the value");
                    }
                }
                if (payload.len == 0) {
                    MsStr n = text(p, cname);
                    FAILF(p, cname, "payloadless variants omit parentheses; write '%.*s' instead of '%.*s()'", STR(n), STR(n));
                }
            }
            if (kind(p) == MS_T_Colon) {
                FAIL(p, peek(p), "enum variants have no field or method bodies; write 'Name' or 'Name(field: Type)', use 'type' for type fields, and put methods in an 'impl' block");
            }
            if (kind(p) == MS_T_Assign) {
                FAIL(p, peek(p), "enum variants cannot have defaults; write 'Name' or 'Name(field: Type)' and supply payload values when constructing a variant");
            }
            MsCase *c = NEW(p, MsCase);
            c->id = new_id(p);
            c->pos = cname.pos;
            c->name = sym(p, cname);
            c->fields = payload;
            push_ptr(p, c);
            end(p);
        } else if (kind(p) == MS_T_Fn || move_fn || (kind(p) == MS_T_Var && ahead(p, 1).kind == MS_T_Fn)) {
            bool consuming = TAKE_MOVE(p, MS_T_Fn);
            bool mutating = take(p, MS_T_Var);
            MsPos fn_pos = need(p, MS_T_Fn).pos;
            if (token.kind == MS_T_Type) {
                MsBuf names = {0};
                type_param_names(p, &names, tps);
                MsStr nt = ms_name(p->names, name);
                MsStr msg = fmt(p, "a type declares only fields; write its methods after it as 'fn %.*s%.*s.name(...)'", STR(nt), (int)names.len, names.data ? names.data : "");
                ms_buf_free(&names);
                fail(p, previous(p), msg);
            }
            MsToken mname = need(p, MS_T_Name);
            MsMethod *me = method_signature(p, mname, true, false, mutating, fn_pos);
            me->consuming = consuming;
            end(p);
            push_ptr(p, me);
        } else {
            MsToken fname = need(p, MS_T_Name);
            need_name_colon(p, fname);
            MsTypeRef *ty = typ(p);
            MsExpr *def;
            if (take(p, MS_T_Assign)) {
                def = expression(p, 0);
            } else {
                def = implicit_none(p, ty);
            }
            push_ptr(p, mk_param(p, fname.pos, sym(p, fname), ty, def, false, false));
            end(p);
        }
    }
    need(p, MS_T_Dedent);
    uint32_t count;
    void **items = finish(p, m, &count, sizeof(void *), _Alignof(void *));
    if (token.kind == MS_T_Interface && count == 0) {
        FAIL(p, token, "declaration body cannot be empty; an interface needs at least one 'fn name(...) Type' operation");
    }
    if (token.kind == MS_T_Enum && count == 0) {
        FAIL(p, token, "an enum must declare at least one variant; add 'Name' or 'Name(field: Type)'");
    }
    MsDecl *d;
    if (token.kind == MS_T_Interface) {
        d = new_decl(p, token.pos, MS_D_INTERFACE);
        d->u.iface.name = name;
        d->u.iface.type_params = tps;
        d->u.iface.methods.ptr = (MsMethod **)items;
        d->u.iface.methods.len = count;
    } else if (token.kind == MS_T_Enum) {
        d = new_decl(p, token.pos, MS_D_ENUM);
        d->u.enumeration.name = name;
        d->u.enumeration.type_params = tps;
        d->u.enumeration.cases.ptr = (MsCase **)items;
        d->u.enumeration.cases.len = count;
    } else {
        d = new_decl(p, token.pos, MS_D_TYPE);
        d->u.type.name = name;
        d->u.type.type_params = tps;
        d->u.type.fields.ptr = (MsParam **)items;
        d->u.type.fields.len = count;
    }
    return d;
}

static MsDecl *declaration(Parser *p) {
    MsToken token = peek(p);
    MsDecl *d = NULL;
    MsTok k = (MsTok)token.kind;
    if (k == MS_T_Fn && receiver_method_ahead(p)) {
        /* `fn [var] Type[T].name(...)`: one method of `Type`. */
        p->at++;
        bool consuming = TAKE_MOVE(p, MS_T_Var, MS_T_Name);
        bool mutating = take(p, MS_T_Var);
        if (consuming && mutating) {
            FAIL(p, previous(p), "a method either takes its receiver with `move` or changes it with `var`, not both");
        }
        MsToken receiver_name = need(p, MS_T_Name);
        bool bounded = kind(p) == MS_T_LBracket && ahead(p, 1).kind == MS_T_Name && ahead(p, 2).kind == MS_T_Colon;
        MsTypeParams bounds = {NULL, 0};
        MsTypeRefs args = {NULL, 0};
        if (bounded) {
            bounds = type_params(p);
            args.ptr = MS_NEW_N(p->arena, MsTypeRef *, bounds.len ? bounds.len : 1);
            args.len = bounds.len;
            for (uint32_t i = 0; i < bounds.len; i++) {
                MsTypeRefs none = {NULL, 0};
                args.ptr[i] = mk_named_type(p, bounds.ptr[i]->pos, bounds.ptr[i]->name, none);
            }
        } else if (take(p, MS_T_LBracket)) {
            args = type_args(p);
        }
        MsTypeRefs receiver_args = args;
        MsTypeRef *receiver = mk_named_type(p, receiver_name.pos, sym(p, receiver_name), args);
        need(p, MS_T_Dot);
        MsToken name = need(p, MS_T_Name);
        MsMethod *method = method_signature(p, name, true, true, mutating, receiver_name.pos);
        method->consuming = consuming;
        method->receiver_args = receiver_args;
        d = new_decl(p, token.pos, MS_D_IMPL);
        d->u.impl.receiver = receiver;
        d->u.impl.bounds = bounds;
        d->u.impl.methods.ptr = MS_NEW_N(p->arena, MsMethod *, 1);
        d->u.impl.methods.ptr[0] = method;
        d->u.impl.methods.len = 1;
        /* The Rust parser allocates the declaration's id after the method's. */
        return d;
    }
    if (k == MS_T_Fn) {
        p->at++;
        if (kind(p) == MS_T_Var && ahead(p, 1).kind == MS_T_Name) {
            FAIL(p, peek(p), "'fn var' marks a method that changes its receiver, as in 'fn var Counter.add(n: Int) Void:'; a free function takes 'var' on the parameter instead: 'fn add(var counter: Counter, n: Int) Void:'");
        }
        MsToken name = need(p, MS_T_Name);
        MsTypeParams tps = type_params(p);
        MsParams params = parameters(p, true, false);
        MsTypeRef *result = result_type(p);
        MsStmts body = statement_suite(p, false, true);
        d = new_decl(p, token.pos, MS_D_FN);
        d->u.fn.name = sym(p, name);
        d->u.fn.type_params = tps;
        d->u.fn.params = params;
        d->u.fn.result = result;
        d->u.fn.body = body;
        return d;
    }
    if (k == MS_T_Extern && ahead(p, 1).kind == MS_T_Type) {
        p->at += 2;
        MsToken name_tok = need(p, MS_T_Name);
        MsSym name = sym(p, name_tok);
        MsTypeParams tps = type_params(p);
        if (kind(p) == MS_T_Colon) {
            FAIL(p, peek(p), "an extern type has no body; remove the ':'");
        }
        end(p);
        d = new_decl(p, token.pos, MS_D_TYPE);
        d->u.type.name = name;
        d->u.type.type_params = tps;
        d->u.type.external = true;
        return d;
    }
    if (k == MS_T_Extern) {
        p->at++;
        need(p, MS_T_Fn);
        MsToken name = need(p, MS_T_Name);
        MsTypeParams tps = type_params(p);
        MsParams params = parameters(p, true, false);
        MsTypeRef *result = result_type(p);
        if (kind(p) == MS_T_Colon) {
            FAIL(p, peek(p), "an extern fn has no body; remove the ':'");
        }
        end(p);
        d = new_decl(p, token.pos, MS_D_FN);
        d->u.fn.name = sym(p, name);
        d->u.fn.type_params = tps;
        d->u.fn.params = params;
        d->u.fn.result = result;
        d->u.fn.external = true;
        return d;
    }
    if (k == MS_T_Name && (ahead(p, 1).kind == MS_T_ColonAssign || ahead(p, 1).kind == MS_T_Colon)) {
        MsToken name = need(p, MS_T_Name);
        MsTypeRef *ty = NULL;
        if (take(p, MS_T_Colon)) {
            ty = typ(p);
        }
        need_immutable_bind(p);
        MsPos init_pos;
        MsExpr *value = constant_value(p, &init_pos);
        end(p);
        d = new_decl(p, token.pos, MS_D_CONST);
        d->u.konst.name = sym(p, name);
        d->u.konst.ty = ty;
        d->u.konst.value = value;
        d->u.konst.init_pos = init_pos;
        return d;
    }
    if (k == MS_T_Test) {
        p->at++;
        MsDecl tmp = {0};
        test_block(p, false, &tmp);
        d = new_decl(p, token.pos, MS_D_TEST);
        d->u = tmp.u;
        return d;
    }
    if (k == MS_T_Name && text_is(p, token, "bench") && ahead(p, 1).kind == MS_T_String) {
        p->at++;
        MsDecl tmp = {0};
        test_block(p, true, &tmp);
        d = new_decl(p, token.pos, MS_D_TEST);
        d->u = tmp.u;
        return d;
    }
    if (k == MS_T_Impl) {
        FAIL(p, token, IMPL_REMOVED);
    }
    if (k == MS_T_Type || k == MS_T_Enum || k == MS_T_Interface) {
        return type_declaration(p, token);
    }
    if (k == MS_T_Name && text_is(p, token, "opaque") && (ahead(p, 1).kind == MS_T_Type || ahead(p, 1).kind == MS_T_Enum)) {
        p->at++;
        MsToken nx = peek(p);
        MsDecl *decl = type_declaration(p, nx);
        decl->pos = token.pos;
        if (decl->kind == MS_D_TYPE) {
            decl->u.type.opaque = true;
        } else if (decl->kind == MS_D_ENUM) {
            decl->u.enumeration.opaque = true;
        }
        return decl;
    }
    if (k == MS_T_Var && ahead(p, 1).kind == MS_T_Fn) {
        /* `var fn T.m()` is the receiver-changing method spelled in the wrong order. */
        fail_fix_range(p, token, ahead(p, 1), LIT("a method that changes its receiver is written fn var Type.name(), with var after fn"), LIT("fn var"));
    }
    MsStr fmsg;
    const char *freplacement;
    if (foreign_declaration(p, token, &fmsg, &freplacement)) {
        MsStr tw = text(p, token);
        if (freplacement == NULL && (str_is(tw, "const") || str_is(tw, "val") || str_is(tw, "final"))) {
            MsToken first, last;
            MsStr rep;
            if (constant_fix(p, token, &first, &last, &rep)) {
                fail_fix_range(p, first, last, fmsg, rep);
            }
        }
        if (freplacement != NULL) {
            fail_fix(p, token, fmsg, (MsStr){freplacement, (uint32_t)strlen(freplacement)});
        }
        fail(p, token, fmsg);
    }
    if (k == MS_T_Export) {
        fail_fix(p, token, LIT("'export' appears twice; write it once before the declaration"), LIT(""));
    }
    if (k == MS_T_Name && text_is(p, token, "opaque")) {
        const char *advice;
        MsStr adv;
        if (ahead(p, 1).kind == MS_T_Export) {
            const char *kw = ahead(p, 2).kind == MS_T_Enum ? "enum" : "type";
            adv = fmt(p, "write 'export opaque %s Name:', with export first", kw);
        } else {
            adv = LIT("'opaque' applies only to a type or enum; write 'opaque type Name:' or 'opaque enum Name:', optionally after 'export'");
        }
        (void)advice;
        FAILF(p, token, "misplaced 'opaque'; %.*s", STR(adv));
    }
    MsStr dt = describe(p, token);
    FAILF(p, token, "expected a module declaration or import, found %.*s; top level holds only import, constants (NAME := value), fn, type, enum, interface, impl, and test (optionally prefixed by export), so put statements inside a fn", STR(dt));
}

/* ---- patterns ---- */

static MsPattern *new_pattern(Parser *p, MsPos pos, MsPatternKind k) {
    MsPattern *pt = NEW(p, MsPattern);
    pt->id = new_id(p);
    pt->pos = pos;
    pt->kind = (uint8_t)k;
    return pt;
}

static MsPattern *pattern_inner(Parser *p) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Void) {
        FAIL(p, t, "void is a reserved value keyword, not a binding name; choose another name such as code_unit, and use void for the Void value");
    }
    if (take(p, MS_T_Name)) {
        MsPattern *pt = new_pattern(p, t.pos, MS_P_NAME);
        pt->u.name = sym(p, t);
        return pt;
    }
    /* `_` binds a value nothing reads, such as a `Result` ignored on purpose. */
    if (take(p, MS_T_Underscore)) {
        MsPattern *pt = new_pattern(p, t.pos, MS_P_NAME);
        pt->u.name = intern(p, "_");
        return pt;
    }
    if (take(p, MS_T_LBracket)) {
        MsPatterns elements = {NULL, 0};
        if (!take(p, MS_T_RBracket)) {
            size_t m = mark(p);
            for (;;) {
                push_ptr(p, pattern(p));
                if (!take(p, MS_T_Comma)) {
                    break;
                }
                if (kind(p) == MS_T_RBracket) {
                    break;
                }
            }
            need(p, MS_T_RBracket);
            FINISH_PTRS(p, m, elements);
        }
        MsPattern *pt = new_pattern(p, t.pos, MS_P_LIST);
        pt->u.list = elements;
        return pt;
    }
    if (take(p, MS_T_LBrace)) {
        size_t m = mark(p);
        for (;;) {
            MsToken name = need(p, MS_T_Name);
            MsPattern *child;
            if (take(p, MS_T_Colon)) {
                child = pattern(p);
            } else {
                child = new_pattern(p, name.pos, MS_P_NAME);
                child->u.name = sym(p, name);
            }
            MsPatternField f = {name.pos, sym(p, name), child};
            push(p, &f, sizeof f);
            if (!take(p, MS_T_Comma)) {
                break;
            }
            if (kind(p) == MS_T_RBrace) {
                break;
            }
        }
        need(p, MS_T_RBrace);
        MsPattern *pt = NULL;
        uint32_t n;
        MsPatternField *fields = finish(p, m, &n, sizeof(MsPatternField), _Alignof(MsPatternField));
        pt = new_pattern(p, t.pos, MS_P_TYPE);
        pt->u.fields.ptr = fields;
        pt->u.fields.len = n;
        return pt;
    }
    MsStr dt = describe(p, t);
    FAILF(p, t, "expected a binding name, list pattern, or type pattern, found %.*s; write a name, [a, b], or {x, y}", STR(dt));
}

static MsPattern *pattern(Parser *p) {
    enter(p);
    MsPattern *r = pattern_inner(p);
    p->depth--;
    return r;
}

/* ---- statements ---- */

static MsStmt *finish_stmt(Parser *p, const MsStmt *st) {
    MsStmt *s = NEW(p, MsStmt);
    *s = *st;
    s->id = new_id(p);
    return s;
}

/* `pattern := hidden`: the first statement of a `for` body or lambda whose parameter is a pattern. */
static MsStmt *destructure(Parser *p, MsPattern *pat, MsSym hidden) {
    MsPos pos = pat->pos;
    MsExpr *value = mk_name(p, pos, hidden);
    MsStmt *s = NEW(p, MsStmt);
    s->id = new_id(p);
    s->pos = pos;
    s->kind = MS_S_BIND;
    s->u.bind.pattern = pat;
    s->u.bind.value = value;
    return s;
}

static bool binding_ahead(const Parser *p) {
    switch (kind(p)) {
    case MS_T_Name:
    case MS_T_Underscore:
        return ahead(p, 1).kind == MS_T_ColonAssign || ahead(p, 1).kind == MS_T_Colon;
    case MS_T_LBracket:
    case MS_T_LBrace: {
        size_t depth = 0;
        for (size_t i = p->at; i < p->ntokens; i++) {
            switch (p->tokens[i].kind) {
            case MS_T_LParen: case MS_T_LBracket: case MS_T_LBrace:
                depth++;
                break;
            case MS_T_RParen: case MS_T_RBracket: case MS_T_RBrace:
                depth--;
                if (depth == 0) {
                    return i + 1 < p->ntokens && p->tokens[i + 1].kind == MS_T_ColonAssign;
                }
                break;
            case MS_T_Newline: case MS_T_Eof:
                return false;
            default:
                break;
            }
        }
        return false;
    }
    default:
        return false;
    }
}

/* A binding: `var pattern [: Type] = value` after `var`, or an immutable `name := value`,
 * `name: Type := value`, or `pattern := value`. */
static MsStmt *binding(Parser *p, bool is_mutable, const MsPos *group, MsPos pos) {
    MsPattern *pat = pattern(p);
    MsTypeRef *ty = NULL;
    bool named = pat->kind == MS_P_NAME;
    if (is_mutable) {
        if (named && take(p, MS_T_Colon)) {
            ty = typ(p);
        }
        if (kind(p) == MS_T_ColonAssign) {
            fail_fix(p, peek(p), LIT("'var' binds with '=': write 'var x = value'; ':=' declares an immutable binding"), LIT("="));
        }
        need(p, MS_T_Assign);
    } else {
        if (named && take(p, MS_T_Colon)) {
            ty = typ(p);
        }
        need_immutable_bind(p);
    }
    MsExpr *value = expression(p, 0);
    MsStmt st = {0};
    st.pos = pos;
    st.kind = MS_S_BIND;
    st.u.bind.is_mutable = is_mutable;
    st.u.bind.pattern = pat;
    st.u.bind.ty = ty;
    st.u.bind.value = value;
    if (group != NULL) {
        st.u.bind.has_group = true;
        st.u.bind.group = *group;
    }
    return finish_stmt(p, &st);
}

/* The `( ... )` after a consumed `var`. The lexer ends each line of the group with a newline. */
static MsStmts binding_group(Parser *p, MsToken keyword) {
    uint32_t indent = keyword.pos.column;
    long i = (long)p->at - 2;
    while (i >= 0 && p->tokens[i].pos.line == keyword.pos.line && p->tokens[i].kind != MS_T_Newline) {
        indent = p->tokens[i].pos.column;
        i--;
    }
    const char *kw = ms_tok_str((MsTok)keyword.kind);
    if (p->inline_statement) {
        FAILF(p, peek(p), "a binding group needs its own lines; put '%s (' on a line of its own with one binding per indented line, or write single '%s name = value' bindings", kw, kw);
    }
    need(p, MS_T_LParen);
    if (kind(p) != MS_T_Newline) {
        FAILF(p, peek(p), "a binding group starts its entries on the next line; write '%s (' then one 'name = value' per indented line, or destructure with '%s [a, b] = value' or '%s {x, y} = value'", kw, kw, kw);
    }
    next(p);
    size_t m = mark(p);
    uint32_t count = 0;
    for (;;) {
        newlines(p);
        MsToken t = peek(p);
        if (t.kind == MS_T_RParen) {
            if (t.pos.column != indent) {
                FAILF(p, t, "the closing ')' of a binding group aligns with its '%s' line, at column %u", kw, indent);
            }
            break;
        } else if (t.kind == MS_T_Eof) {
            need(p, MS_T_RParen);
        } else if (t.pos.column != indent + 4) {
            FAILF(p, t, "binding group entries are indented four spaces past the '%s' line, to column %u", kw, indent + 4);
        }
        MsPos epos = peek(p).pos;
        push_ptr(p, binding(p, true, &keyword.pos, epos));
        count++;
        if (kind(p) == MS_T_Comma) {
            FAILF(p, peek(p), "a binding group holds one 'name = value' per line, not a comma list; to destructure write '%s [a, b] = value' or '%s {x, y} = value'", kw, kw);
        }
        /* A block lambda value ends at its dedent, which also ends the line. */
        if (previous(p).kind != MS_T_Dedent) {
            need(p, MS_T_Newline);
        }
    }
    if (count == 0) {
        FAIL(p, peek(p), "a binding group cannot be empty; add 'name = value' lines or remove the group");
    }
    need(p, MS_T_RParen);
    end(p);
    MsStmts out;
    FINISH_PTRS(p, m, out);
    return out;
}

/* Parses one statement, plus the rest of its bindings for a group, onto the open scratch list. */
static void statements(Parser *p, bool allow_value) {
    MsStmt *s = statement(p, allow_value);
    push_ptr(p, s);
    for (uint32_t i = 0; i < p->nqueued; i++) {
        push_ptr(p, p->queued[i]);
    }
    p->queued = NULL;
    p->nqueued = 0;
}

static bool plain_index(const MsExpr *e) {
    switch (e->kind) {
    case MS_E_NAME:
    case MS_E_NUMBER:
        return true;
    case MS_E_MEMBER:
        return plain_index(e->u.member.left);
    case MS_E_TEXT:
        for (uint32_t i = 0; i < e->u.text.len; i++) {
            if (e->u.text.ptr[i].expr != NULL) {
                return false;
            }
        }
        return true;
    default:
        return false;
    }
}

static bool plain_chain(const MsExpr *e) {
    for (;;) {
        if (e->kind == MS_E_MEMBER) {
            e = e->u.member.left;
        } else if (e->kind == MS_E_INDEX && plain_index(e->u.bin.right)) {
            e = e->u.bin.left;
        } else if (e->kind == MS_E_APPLY && e->u.apply.value != NULL && e->u.apply.types.len == 1 &&
                   plain_index(e->u.apply.value)) {
            e = e->u.apply.left;
        } else {
            return e->kind == MS_E_NAME;
        }
    }
}

/* The receiver and index of `left[index]`, however the bracket was parsed. */
static bool index_parts(const MsExpr *e, MsExpr **left, MsExpr **index) {
    if (e->kind == MS_E_INDEX) {
        *left = e->u.bin.left;
        *index = e->u.bin.right;
        return true;
    }
    if (e->kind == MS_E_APPLY && e->u.apply.value != NULL && e->u.apply.types.len == 1) {
        *left = e->u.apply.left;
        *index = e->u.apply.value;
        return true;
    }
    return false;
}

static MsTypeRef *copy_type(Parser *p, const MsTypeRef *t);

static MsTypeRefs copy_types(Parser *p, MsTypeRefs types) {
    MsTypeRefs out = {NULL, types.len};
    out.ptr = MS_NEW_N(p->arena, MsTypeRef *, types.len ? types.len : 1);
    for (uint32_t i = 0; i < types.len; i++) {
        out.ptr[i] = copy_type(p, types.ptr[i]);
    }
    return out;
}

static MsTypeRef *copy_type(Parser *p, const MsTypeRef *t) {
    MsTypeRef *c = NEW(p, MsTypeRef);
    c->id = new_id(p);
    c->pos = t->pos;
    c->kind = t->kind;
    if (t->kind == MS_TYPE_NAMED) {
        c->name = t->name;
        c->args = copy_types(p, t->args);
    } else {
        c->params.len = t->params.len;
        c->params.ptr = MS_NEW_N(p->arena, MsParam *, t->params.len ? t->params.len : 1);
        for (uint32_t i = 0; i < t->params.len; i++) {
            const MsParam *q = t->params.ptr[i];
            MsParam *m = NEW(p, MsParam);
            m->id = new_id(p);
            m->pos = q->pos;
            m->name = q->name;
            m->ty = q->ty != NULL ? copy_type(p, q->ty) : NULL;
            m->def = q->def; /* the Rust clone keeps the same ids too */
            m->is_mutable = q->is_mutable;
            m->moving = q->moving;
            c->params.ptr[i] = m;
        }
        c->result = copy_type(p, t->result);
    }
    return c;
}

static MsExpr *clone_chain(Parser *p, const MsExpr *e) {
    MsExpr *c = NEW(p, MsExpr);
    c->id = new_id(p);
    c->pos = e->pos;
    c->end = e->end;
    c->kind = e->kind;
    c->op = e->op;
    c->u = e->u;
    switch (e->kind) {
    case MS_E_MEMBER:
        c->u.member.left = clone_chain(p, e->u.member.left);
        break;
    case MS_E_INDEX:
        c->u.bin.left = clone_chain(p, e->u.bin.left);
        c->u.bin.right = clone_chain(p, e->u.bin.right);
        break;
    case MS_E_APPLY:
        c->u.apply.left = clone_chain(p, e->u.apply.left);
        c->u.apply.types = copy_types(p, e->u.apply.types);
        c->u.apply.value = e->u.apply.value != NULL ? clone_chain(p, e->u.apply.value) : NULL;
        break;
    default:
        break;
    }
    return c;
}

/* `xs[i] = value` as the call of the member `[]=`. With `reread`, the value reads the same
 * element, so a name or field key is cloned for the store. */
static MsExpr *index_set(Parser *p, MsExpr *target, MsExpr *value, bool reread) {
    MsExpr *left, *index;
    index_parts(target, &left, &index);
    MsPos pos = target->pos;
    if (reread && (index->kind == MS_E_NAME || index->kind == MS_E_MEMBER)) {
        MsExpr *receiver = clone_chain(p, index);
        MsSym name = intern(p, "clone");
        MsExpr *callee = mk_member(p, index->pos, receiver, name);
        MsExpr *c = NEW(p, MsExpr);
        c->id = new_id(p);
        c->pos = index->pos;
        c->end = index->end;
        c->kind = MS_E_CALL;
        c->u.call.callee = callee;
        index = c;
    }
    MsExpr *member = mk_member(p, pos, left, intern(p, INDEX_SET));
    MsArg *args = MS_NEW_N(p->arena, MsArg, 2);
    args[0] = (MsArg){index->pos, false, 0, index};
    args[1] = (MsArg){value->pos, false, 0, value};
    return mk_call(p, pos, member, args, 2);
}

static void assign_target(Parser *p, MsToken start, MsExpr *e, MsStmt *st) {
    if (e->kind == MS_E_NAME) {
        MsStr n = ms_name(p->names, e->u.sym);
        if (!str_is(n, "self") && !str_is(n, "fixture")) {
            st->u.assign.member_target = false;
            st->u.assign.name = e->u.sym;
            return;
        }
    } else if (e->kind == MS_E_MEMBER) {
        st->u.assign.member_target = true;
        st->u.assign.target = e;
        return;
    }
    FAIL(p, start, "assignment requires a local binding name or type field; the left side of '=' must be a name or a.field; to change a collection element, write xs[index] = value on a List or m[key] = value on a Map");
}

static bool compound_assignment(const Parser *p) {
    MsBinaryOp op;
    if (arith_op(kind(p), &op) && p->at + 1 < p->ntokens) {
        MsToken nx = p->tokens[p->at + 1];
        return nx.kind == MS_T_Assign && peek(p).end.offset == nx.pos.offset;
    }
    return false;
}

static MsExpr *mk_binary_at(Parser *p, MsToken op, MsBinaryOp bop, MsExpr *left, MsExpr *right) {
    MsExpr *e = NEW(p, MsExpr);
    e->id = new_id(p);
    e->pos = op.pos;
    e->end = right->end;
    e->kind = MS_E_BINARY;
    e->op = (uint8_t)bop;
    e->u.bin.left = left;
    e->u.bin.right = right;
    return e;
}

/* `target op= value` as the assignment `target = target op value`. */
static void compound(Parser *p, MsToken start, MsExpr *e, MsStmt *st) {
    MsToken op = peek(p);
    MsToken equal = ahead(p, 1);
    bool plain = plain_chain(e);
    MsExpr *copy = plain ? clone_chain(p, e) : NULL;
    MsExpr *l, *ix;
    MsBinaryOp bop;
    if (copy != NULL && index_parts(e, &l, &ix)) {
        p->at += 2;
        arith_op((MsTok)op.kind, &bop);
        MsExpr *right = expression(p, 0);
        MsExpr *value = mk_binary_at(p, op, bop, copy, right);
        st->kind = MS_S_CALL;
        st->u.expr = index_set(p, e, value, true);
        return;
    }
    assign_target(p, start, e, st);
    if (copy == NULL) {
        MsDiag *d = parse_diag(p, op.pos,
            fmt(p, "compound assignment '%s=' needs a name or a.field target whose receiver is names only; bind the receiver to a name first, or write the assignment out",
                ms_tok_str((MsTok)op.kind)));
        d->has_end = true;
        d->end = equal.end;
        throw_(p);
    }
    p->at += 2;
    arith_op((MsTok)op.kind, &bop);
    MsExpr *right = expression(p, 0);
    MsExpr *value = mk_binary_at(p, op, bop, copy, right);
    st->kind = MS_S_ASSIGN;
    st->u.assign.has_compound = true;
    st->u.assign.compound = (uint8_t)bop;
    st->u.assign.value = value;
}

static void expression_statement(Parser *p, MsToken t, bool allow_value, MsStmt *st) {
    MsExpr *e = expression(p, 0);
    MsExpr *l, *ix;
    if (compound_assignment(p)) {
        compound(p, t, e, st);
    } else if (take(p, MS_T_Assign)) {
        if (index_parts(e, &l, &ix)) {
            MsExpr *value = expression(p, 0);
            st->kind = MS_S_CALL;
            st->u.expr = index_set(p, e, value, false);
            end(p);
            return;
        }
        assign_target(p, t, e, st);
        MsExpr *value = expression(p, 0);
        st->kind = MS_S_ASSIGN;
        st->u.assign.value = value;
    } else {
        bool try_call = e->kind == MS_E_UNARY && e->op == MS_U_TRY && e->u.bin.left->kind == MS_E_CALL;
        bool is_call = e->kind == MS_E_CALL || e->kind == MS_E_MATCH || e->kind == MS_E_VOID;
        if (!p->inline_return && !is_call && !try_call && !allow_value) {
            if (e->kind == MS_E_NAME) {
                MsStr n = ms_name(p->names, e->u.sym);
#define IS(s) str_is(n, s)
                if (IS("assert")) FAIL(p, t, "there is no 'assert': in a test block write 'expect_equal(actual, expected)?' or 'expect_true(condition)?', imported from \"@std/test/test.ms\"");
                if (IS("pass")) fail_fix(p, t, LIT("'pass' is not a keyword; write 'void' for an empty block or match arm"), LIT("void"));
                if (IS("const") || IS("val") || IS("final")) FAILF(p, t, "'%.*s' is not a keyword; write 'name := ...' for a binding that is not reassigned, or 'var name = ...' when it changes", STR(n));
                if (IS("throw") || IS("raise") || IS("catch")) FAILF(p, t, "'%.*s' is not a keyword; failures are values; return error(...) from a fn returning T!, propagate a Result with 'call()?', or handle it with 'if value := result:' and an else branch", STR(n));
                if (IS("elseif")) FAIL(p, t, "'elseif' is not a keyword; write 'else if <condition>:' for a further branch");
                if (IS("elif")) FAIL(p, t, "there is no 'elif': write 'else if <condition>:' for a further branch");
                if (IS("def")) FAIL(p, t, "there is no 'def': declare a function with 'fn name(a: Int) Int:'");
                if (IS("switch")) FAIL(p, t, "'switch' is not a keyword; write 'match value:' with one arm per case of your own type, or 'if x == a:' with 'else if' for plain values");
                if (IS("except") || IS("finally")) FAILF(p, t, "'%.*s' is not a keyword; failures are values; return error(...) from a fn returning T!, propagate a Result with 'call()?', or handle it with 'if value := result:' and an else branch", STR(n));
                if (IS("loop")) FAIL(p, t, "'loop' is not a keyword; write 'while true:' and leave it with 'break'");
                if (IS("foreach")) FAIL(p, t, "'foreach' is not a keyword; write 'for item in items:'");
                if (IS("class")) FAIL(p, t, "'class' is not a keyword inside a fn; declare a type with 'type Name:' at module level");
                if (IS("del")) FAIL(p, t, "'del' is not a keyword; remove from a collection with its methods, such as xs.remove(i) or m.remove(key)");
                if (IS("global") || IS("nonlocal")) FAILF(p, t, "'%.*s' is not a keyword; a fn sees module constants directly, and mutable state lives in a 'var' or a field passed explicitly", STR(n));
                if (IS("yield")) FAIL(p, t, "'yield' is not a keyword; there are no generators, so build a list and return it");
                if (IS("async") || IS("await")) FAILF(p, t, "'%.*s' is not a keyword; call the function directly, or start concurrent work with promise(fn: ...) from \"@std/concurrency/promise.ms\"", STR(n));
                if (IS("go")) FAIL(p, t, "'go' is not a keyword; start concurrent work with promise(fn: ...) from \"@std/concurrency/promise.ms\": result := promise(fn: work()), then result.wait()");
#undef IS
            }
            if (kind(p) == MS_T_Comma) {
                FAIL(p, t, "a statement cannot start with a comma-separated list of names: write one binding per line ('a := f()'), or destructure one value with '[a, b] := value'");
            }
            FAIL(p, t, "only a call, a call followed by '?', or match can be a standalone expression statement; use 'name := ...' to keep the value, 'return' to return it, or call a function");
        }
        if (p->inline_return) {
            st->kind = MS_S_RETURN;
        } else {
            st->kind = MS_S_CALL;
        }
        st->u.expr = e;
    }
    end(p);
}

static MsStmt *statement(Parser *p, bool allow_value) {
    MsToken t = peek(p);
    MsPos pos = t.pos;
    MsStmt st = {0};
    st.pos = pos;
    switch (t.kind) {
    case MS_T_Void: {
        MsTok k1 = (MsTok)ahead(p, 1).kind;
        if (k1 == MS_T_Newline || k1 == MS_T_Indent || k1 == MS_T_Dedent || k1 == MS_T_Eof ||
            k1 == MS_T_Comma || k1 == MS_T_RParen || k1 == MS_T_RBracket || k1 == MS_T_RBrace) {
            break;
        }
        /* `void call()` runs the call and drops its result on purpose: the `_ := call()` binding. */
        p->at++;
        MsExpr *value = expression(p, 0);
        end(p);
        MsStmt *s = NEW(p, MsStmt);
        s->id = new_id(p);
        uint32_t pattern_id = new_id(p);
        s->pos = pos;
        s->kind = MS_S_BIND;
        MsPattern *pt = NEW(p, MsPattern);
        pt->id = pattern_id;
        pt->pos = pos;
        pt->kind = MS_P_NAME;
        pt->u.name = intern(p, "_");
        s->u.bind.pattern = pt;
        s->u.bind.value = value;
        return s;
    }
    default:
        break;
    }
    if (t.kind == MS_T_Underscore && ahead(p, 1).kind == MS_T_ColonAssign) {
        fail_fix_range(p, t, ahead(p, 1), LIT("'_ := value' was removed; write 'void value' to run an expression and drop its result on purpose"), LIT("void"));
    }
    if ((t.kind == MS_T_Name || t.kind == MS_T_Underscore || t.kind == MS_T_LBracket || t.kind == MS_T_LBrace) && binding_ahead(p)) {
        MsStmt *s = binding(p, false, NULL, pos);
        end(p);
        return s;
    }
    if (t.kind == MS_T_Name && text_is(p, t, "let")) {
        MsTok k1 = (MsTok)ahead(p, 1).kind;
        if (k1 == MS_T_Name || k1 == MS_T_Underscore || k1 == MS_T_LBracket || k1 == MS_T_LBrace) {
            MsStr message = LIT("'let' was removed; bind with 'x := value' (or 'x: Type := value'), destructure with '[a, b] := value', and use 'var x = value' for a mutable binding");
            /* `let x = v` becomes `x := v`; other shapes name the rewrite and get no edit. */
            MsToken name = ahead(p, 1), eq = ahead(p, 2);
            if (name.kind == MS_T_Name && eq.kind == MS_T_Assign) {
                MsStr n = text(p, name);
                fail_fix_range(p, t, eq, message, fmt(p, "%.*s :=", STR(n)));
            }
            fail(p, t, message);
        }
    }
    switch (t.kind) {
    case MS_T_Var: {
        p->at++;
        if (kind(p) == MS_T_LParen) {
            MsStmts entries = binding_group(p, t);
            MsStmt *first = entries.ptr[0];
            p->nqueued = entries.len - 1;
            p->queued = entries.ptr + 1;
            return first;
        }
        MsStmt *s = binding(p, true, NULL, pos);
        end(p);
        return s;
    }
    case MS_T_Fn: {
        if (!(ahead(p, 1).kind == MS_T_Name && (ahead(p, 2).kind == MS_T_LParen || ahead(p, 2).kind == MS_T_LBracket))) {
            break;
        }
        p->at++;
        MsToken name = need(p, MS_T_Name);
        if (kind(p) == MS_T_LBracket) {
            FAIL(p, peek(p), "a local fn cannot take type parameters; declare a generic function at module level");
        }
        MsParams params = parameters(p, true, false);
        MsTypeRef *result = result_type(p);
        MsStmts body = statement_suite(p, true, false);
        uint32_t pid = new_id(p);
        MsExpr *value = mk(p, t.pos, MS_E_LAMBDA);
        value->u.lambda.params = params;
        value->u.lambda.result = result;
        value->u.lambda.body = body;
        MsPattern *pt = NEW(p, MsPattern);
        pt->id = pid;
        pt->pos = name.pos;
        pt->kind = MS_P_NAME;
        pt->u.name = sym(p, name);
        st.kind = MS_S_BIND;
        st.u.bind.pattern = pt;
        st.u.bind.value = value;
        return finish_stmt(p, &st);
    }
    case MS_T_Return: {
        p->at++;
        MsExpr *value = NULL;
        MsTok k = kind(p);
        if (k != MS_T_Newline && !(p->inline_statement && (k == MS_T_Comma || k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace))) {
            value = expression(p, 0);
        }
        end(p);
        st.kind = MS_S_RETURN;
        st.u.expr = value;
        return finish_stmt(p, &st);
    }
    case MS_T_Break:
    case MS_T_Continue:
        p->at++;
        end(p);
        st.kind = t.kind == MS_T_Break ? MS_S_BREAK : MS_S_CONTINUE;
        return finish_stmt(p, &st);
    case MS_T_If: {
        p->at++;
        MsPattern *bind = NULL;
        bool is_mutable = false;
        MsTok k1 = (MsTok)ahead(p, 1).kind;
        if (kind(p) == MS_T_Name && text_is(p, peek(p), "let") &&
            (k1 == MS_T_Name || k1 == MS_T_Underscore || k1 == MS_T_LBracket || k1 == MS_T_LBrace)) {
            MsToken l = peek(p);
            MsStr message = LIT("'if let' was removed; write 'if value := optional:' (or 'if var value = optional:' for a mutable binding)");
            MsToken name = ahead(p, 1), eq = ahead(p, 2);
            if (name.kind == MS_T_Name && eq.kind == MS_T_Assign) {
                MsStr n = text(p, name);
                fail_fix_range(p, l, eq, message, fmt(p, "%.*s :=", STR(n)));
            }
            fail(p, l, message);
        }
        if (kind(p) == MS_T_Var || ((kind(p) == MS_T_Name || kind(p) == MS_T_Underscore) && ahead(p, 1).kind == MS_T_ColonAssign)) {
            is_mutable = kind(p) == MS_T_Var;
            if (is_mutable) {
                p->at++;
            }
            MsPattern *pat = pattern(p);
            if (pat->kind != MS_P_NAME) {
                FAIL(p, t, "an if binding takes one name; write 'if value := optional:' and destructure the value inside the branch");
            }
            if (kind(p) == MS_T_LParen) {
                FAIL(p, t, "an if binding unwraps an Optional or Result into one name; it does not match alternative cases. Write 'match value:' with a 'Case(x):' arm, or 'if value := optional:'");
            }
            bind = pat;
            need(p, is_mutable ? MS_T_Assign : MS_T_ColonAssign);
        }
        MsExpr *cond = expression(p, 0);
        MsStmts body = suite(p);
        newlines(p);
        MsStmts else_body = {NULL, 0};
        if (take(p, MS_T_Else)) {
            if (kind(p) == MS_T_If) {
                else_body.ptr = MS_NEW_N(p->arena, MsStmt *, 1);
                else_body.ptr[0] = statement(p, false);
                else_body.len = 1;
            } else {
                else_body = suite(p);
            }
        }
        st.kind = MS_S_IF;
        st.u.branch.binding = bind;
        st.u.branch.is_mutable = is_mutable;
        st.u.branch.cond = cond;
        st.u.branch.body = body;
        st.u.branch.else_body = else_body;
        return finish_stmt(p, &st);
    }
    case MS_T_While: {
        p->at++;
        MsExpr *cond = expression(p, 0);
        if (kind(p) == MS_T_ColonAssign) {
            FAIL(p, peek(p), "while takes a condition, not a binding; to loop while a value is present write 'while true:', bind it inside with 'if name := value:', and leave with 'else: break'");
        }
        MsStmts body = suite(p);
        st.kind = MS_S_WHILE;
        st.u.loop.cond = cond;
        st.u.loop.body = body;
        return finish_stmt(p, &st);
    }
    case MS_T_For: {
        p->at++;
        if (kind(p) == MS_T_LParen) {
            FAIL(p, peek(p), "for does not take parentheses or a counter clause; write 'for item in items:' to visit a List, or 'for i in 0..n:' to count");
        }
        MsSym name;
        MsPattern *pat = NULL;
        if (kind(p) == MS_T_LBracket || kind(p) == MS_T_LBrace) {
            name = intern(p, HIDDEN_ITEM);
            pat = pattern(p);
        } else {
            name = sym(p, need(p, MS_T_Name));
        }
        if (kind(p) == MS_T_Name && text_is(p, peek(p), "of")) {
            FAIL(p, peek(p), "for uses 'in', not 'of'; write 'for item in items:'");
        }
        if (kind(p) == MS_T_Comma) {
            FAIL(p, peek(p), "for binds one name or one pattern; to read positions, loop over the entries, e.g. 'for entry in items.entries():' and use entry.index and entry.value (a Map's entries() give entry.key and entry.value), or destructure each element with 'for [a, b] in pairs:'");
        }
        need(p, MS_T_In);
        MsExpr *iter = expression(p, 0);
        MsStmts body = suite(p);
        if (pat != NULL) {
            MsStmt **nb = MS_NEW_N(p->arena, MsStmt *, body.len + 1);
            nb[0] = destructure(p, pat, name);
            memcpy(nb + 1, body.ptr, body.len * sizeof(MsStmt *));
            body.ptr = nb;
            body.len++;
        }
        st.kind = MS_S_FOR;
        st.u.each.name = name;
        st.u.each.iter = iter;
        st.u.each.body = body;
        return finish_stmt(p, &st);
    }
    default:
        break;
    }
    expression_statement(p, t, allow_value, &st);
    return finish_stmt(p, &st);
}

/* Parses `: body`. `expression` marks a lambda body (an inline body is its value); `fn_body`
 * marks a function or method body (inline returns, may be empty). */
static MsStmts statement_suite_inner(Parser *p, bool expression_, bool fn_body, bool outer, bool outer_lambda) {
    need(p, MS_T_Colon);
    MsStmts none = {NULL, 0};
    if (kind(p) == MS_T_Ellipsis && fn_body) {
        p->at++;
        end(p);
        return none;
    }
    if (kind(p) != MS_T_Newline) {
        if (kind(p) == MS_T_If && (expression_ || fn_body)) {
            /* `fn x: if c: a else: b`: the body is the conditional expression. */
            size_t start = p->at;
            MsPos at_pos = peek(p).pos;
            Catch c;
            catch_begin(p, &c);
            struct {
                MsExpr *volatile value;
                volatile bool ok;
            } r = {NULL, false};
            if (setjmp(c.jb) == 0) {
                r.value = expression(p, 0);
                if (!expression_) {
                    end(p);
                }
                r.ok = true;
                catch_end(p, &c);
            } else {
                catch_restore(p, &c);
            }
            if (r.ok) {
                MsStmt *s = NEW(p, MsStmt);
                s->id = new_id(p);
                s->pos = at_pos;
                s->kind = MS_S_RETURN;
                s->u.expr = r.value;
                MsStmts out = {MS_NEW_N(p->arena, MsStmt *, 1), 1};
                out.ptr[0] = s;
                return out;
            }
            /* Not a conditional expression: report it as the statement it was written as. */
            p->at = start;
        }
        if (kind(p) == MS_T_If || kind(p) == MS_T_While || kind(p) == MS_T_For) {
            MsToken t = peek(p);
            FAILF(p, t, "inline bodies require one simple statement; put '%s' on its own line in an indented block", ms_tok_str((MsTok)t.kind));
        }
        p->inline_statement = true;
        p->inline_return = expression_ || fn_body;
        MsStmts body = {MS_NEW_N(p->arena, MsStmt *, 1), 1};
        body.ptr[0] = statement(p, false);
        p->inline_statement = outer;
        if (!expression_) {
            end(p);
        }
        return body;
    }
    p->inline_statement = false;
    p->inline_return = false;
    p->block_lambda = outer_lambda || expression_;
    need(p, MS_T_Newline);
    need(p, MS_T_Indent);
    size_t m = mark(p);
    for (;;) {
        newlines(p);
        if (kind(p) == MS_T_Dedent || kind(p) == MS_T_Eof) {
            break;
        }
        statements(p, false);
    }
    need(p, MS_T_Dedent);
    MsStmts body;
    FINISH_PTRS(p, m, body);
    if (body.len == 0) {
        FAIL(p, previous(p), "suite cannot be empty; add at least one statement, or write '...' after the colon for a runtime-bound declaration");
    }
    return body;
}

static MsStmts statement_suite(Parser *p, bool expression_, bool fn_body) {
    enter(p);
    bool outer = p->inline_statement, outer_return = p->inline_return, outer_lambda = p->block_lambda;
    MsStmts r = statement_suite_inner(p, expression_, fn_body, outer, outer_lambda);
    p->inline_statement = outer;
    p->inline_return = outer_return;
    p->block_lambda = outer_lambda;
    p->depth--;
    return r;
}

/* ---- expressions ---- */

typedef struct Args {
    MsArg *ptr;
    uint32_t len;
} Args;

static Args call_arguments(Parser *p);

static MsExpr *mk_unary(Parser *p, MsPos pos, MsUnaryOp op, MsExpr *operand) {
    MsExpr *e = mk(p, pos, MS_E_UNARY);
    e->op = (uint8_t)op;
    e->u.bin.left = operand;
    return e;
}

/* Rejects prefix `try`. When the operand is one call or access chain, the fix rewrites
 * `try f(x)` to `f(x)?`. */
static void fail_try(Parser *p, MsToken t) __attribute__((noreturn));
static void fail_try(Parser *p, MsToken t) {
    p->at++;
    MsToken start = peek(p);
    Catch c;
    catch_begin(p, &c);
    struct {
        MsExpr *volatile operand;
    } r = {NULL};
    if (setjmp(c.jb) == 0) {
        r.operand = expression(p, PREFIX_OPERAND);
        catch_end(p, &c);
    } else {
        catch_restore(p, &c);
    }
    MsDiag *d = parse_diag(p, t.pos, LIT(TRY_REMOVED));
    d->has_end = true;
    d->end = t.end;
    MsToken last = previous(p);
    bool chain = false;
    if (r.operand != NULL) {
        switch (r.operand->kind) {
        case MS_E_NAME: case MS_E_MEMBER: case MS_E_CALL: case MS_E_INDEX: case MS_E_APPLY:
            chain = true;
            break;
        default:
            break;
        }
    }
    if (chain && last.end.line > 0 && start.lo < last.hi) {
        MsStr replacement = fmt(p, "%.*s?", (int)(last.hi - start.lo), p->src + start.lo);
        d->has_end = true;
        d->end = last.end;
        d->has_fix = true;
        d->fix_pos = t.pos;
        d->fix_end = last.end;
        d->replacement = replacement;
    }
    throw_(p);
}

/* `start..end` as the call `range(start, end)`; `..` names the standard `range`. */
static MsExpr *range_call(Parser *p, MsExpr *start, MsExpr *end_) {
    MsPos pos = start->pos;
    MsExpr *callee = mk_name(p, pos, intern(p, ".."));
    MsArg *args = MS_NEW_N(p->arena, MsArg, 2);
    args[0] = (MsArg){start->pos, false, 0, start};
    args[1] = (MsArg){end_->pos, false, 0, end_};
    return mk_call(p, pos, callee, args, 2);
}

/* Parses one `| step` after `lhs` and desugars it to the ordinary expression the step names. */
static MsExpr *pipe(Parser *p, MsExpr *lhs) {
    p->at++;
    if (kind(p) == MS_T_Pipe) {
        MsToken t = peek(p);
        MsToken first = previous(p);
        fail_word_operator(p, first, t, LIT("'||' is not an operator; write 'or' for logical or, and '|' only to start a pipe step"), "or");
    }
    if (kind(p) == MS_T_Try) {
        FAIL(p, peek(p), TRY_REMOVED);
    }
    MsExpr *step;
    if (kind(p) == MS_T_Dot) {
        step = postfix(p, lhs);
    } else {
        MsToken name = peek(p);
        if (name.kind != MS_T_Name) {
            const char *hint = "";
            if (name.kind == MS_T_Newline) {
                hint = "; to continue a flow on the next line, end this line before '|' and start the next line with '|'";
            }
            MsStr dn = describe(p, name);
            FAILF(p, name, "a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found %.*s%s", STR(dn), hint);
        }
        p->at++;
        MsExpr *callee = mk_name(p, name.pos, sym(p, name));
        size_t links = 0;
        /* A '.' on a later line continues the flow and applies to the step's result. */
        while (kind(p) == MS_T_Dot && peek(p).pos.line == p->tokens[p->at - 1].pos.line) {
            link(p, &links);
            p->at++;
            MsToken member = need(p, MS_T_Name);
            callee = mk_member(p, member.pos, callee, sym(p, member));
        }
        if (kind(p) == MS_T_LBracket) {
            MsStr n = text(p, name);
            FAILF(p, peek(p), "a pipe step cannot take type arguments; bind the instance to a name first, e.g. step := %.*s[Int], then write x | step", STR(n));
        }
        Args rest = {NULL, 0};
        if (take(p, MS_T_LParen)) {
            rest = call_arguments(p);
        }
        MsArg *args = MS_NEW_N(p->arena, MsArg, rest.len + 1);
        args[0] = (MsArg){lhs->pos, false, 0, lhs};
        if (rest.len != 0) {
            memcpy(args + 1, rest.ptr, rest.len * sizeof(MsArg));
        }
        step = mk_call(p, name.pos, callee, args, rest.len + 1);
    }
    if (kind(p) == MS_T_Question) {
        MsToken question = peek(p);
        p->at++;
        step = mk_unary(p, question.pos, MS_U_TRY, step);
    }
    return step;
}

static MsExpr *expression_inner(Parser *p, int min) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Not && min > 3) {
        FAIL(p, t, "not requires grouping at this operator position; wrap it in parentheses, e.g. a == (not b)");
    }
    MsExpr *e;
    if (take(p, MS_T_Not)) {
        MsExpr *operand = expression(p, PREFIX_OPERAND);
        e = mk_unary(p, t.pos, MS_U_NOT, operand);
    } else if (t.kind == MS_T_Try) {
        fail_try(p, t);
    } else if (t.kind == MS_T_Plus || t.kind == MS_T_Minus) {
        p->at++;
        MsUnaryOp op = t.kind == MS_T_Plus ? MS_U_PLUS : MS_U_NEG;
        MsExpr *operand = expression(p, 8);
        e = mk_unary(p, t.pos, op, operand);
    } else {
        e = primary(p);
    }
    bool compared = false;
    size_t links = 0;
    for (;;) {
        MsToken op = peek(p);
        if (compound_assignment(p)) {
            break;
        }
        if (op.kind == MS_T_Amp) {
            and_and(p, op);
        }
        if (op.kind == MS_T_Pipe) {
            if (min > 0) {
                break;
            }
            link(p, &links);
            e = pipe(p, e);
            if (kind(p) == MS_T_Dot) {
                e = postfix(p, e);
            }
            MsBinaryOp tmp;
            if (binary_op(kind(p), &tmp)) {
                FAIL(p, peek(p), "a pipe has the lowest precedence; parenthesize it to use its result in an operator, e.g. (x | f) == y");
            }
            continue;
        }
        if (op.kind == MS_T_DotDot) {
            if (min > RANGE_LEVEL) {
                break;
            }
            p->at++;
            MsExpr *right = expression(p, RANGE_LEVEL + 1);
            if (kind(p) == MS_T_DotDot) {
                FAIL(p, peek(p), "a range cannot chain; write one 'start..end', or use range_by for a step from \"@std/collections/collections.ms\"");
            }
            e = range_call(p, e, right);
            continue;
        }
        MsBinaryOp bop;
        if (!binary_op((MsTok)op.kind, &bop)) {
            break;
        }
        int level = ms_binary_precedence(bop);
        if (level < min) {
            break;
        }
        if ((op.kind == MS_T_Plus || op.kind == MS_T_Minus) && e->kind == MS_E_NAME &&
            ahead(p, 1).kind == op.kind && ahead(p, 2).kind == MS_T_Newline) {
            const char *o = ms_tok_str((MsTok)op.kind);
            MsStr n = ms_name(p->names, e->u.sym);
            FAILF(p, op, "Manuscript has no '%s%s' operator; write '%.*s %s= 1'", o, o, STR(n), o);
        }
        if (level == 4 && compared) {
            FAIL(p, op, "comparison operators cannot chain; combine two comparisons with 'and', e.g. a < b and b < c");
        }
        p->at++;
        link(p, &links);
        MsExpr *right = expression(p, level + 1);
        MsExpr *b = mk(p, op.pos, MS_E_BINARY);
        b->op = (uint8_t)bop;
        b->u.bin.left = e;
        b->u.bin.right = right;
        e = b;
        if (level == 4) {
            compared = true;
        }
    }
    return e;
}

static MsExpr *expression(Parser *p, int min) {
    enter(p);
    MsExpr *r = expression_inner(p, min);
    p->depth--;
    return r;
}

static MsExpr *case_path(Parser *p) {
    MsToken t = need(p, MS_T_Name);
    MsExpr *e = mk_name(p, t.pos, sym(p, t));
    if (take(p, MS_T_LBracket)) {
        MsTypeRefs types = type_args(p);
        MsExpr *a = mk(p, t.pos, MS_E_APPLY);
        a->u.apply.left = e;
        a->u.apply.types = types;
        e = a;
    }
    size_t links = 0;
    while (take(p, MS_T_Dot)) {
        link(p, &links);
        MsToken name = need(p, MS_T_Name);
        e = mk_member(p, name.pos, e, sym(p, name));
    }
    return e;
}

/* ---- text ---- */

static MsPos text_pos(MsPos pos, MsStr full, size_t index, const MsBounds *bounds) {
    size_t last = (size_t)-1;
    uint32_t newlines_ = 0;
    for (size_t i = 0; i < index; i++) {
        if (full.ptr[i] == '\n') {
            last = i;
            newlines_++;
        }
    }
    uint32_t offset = (uint32_t)(pos.offset + index);
    MsPos position;
    if (last == (size_t)-1) {
        position = (MsPos){offset, pos.line, (uint32_t)(pos.column + index)};
    } else {
        position = (MsPos){offset, pos.line + newlines_, (uint32_t)(index - last)};
    }
    return ms_bounds_restore_offset(bounds, pos, position);
}

/* Splits the text between multi-line delimiters into its content (without the line break after the
 * opening quotes and the closing line), the closing line's indentation width, and the content's
 * start within `body`. */
static void multiline_body(MsStr body, MsStr *content, size_t *indent, size_t *first) {
    size_t last = 0;
    for (size_t i = body.len; i > 0; i--) {
        if (body.ptr[i - 1] == '\n') {
            last = i - 1;
            break;
        }
    }
    *indent = body.len - last - 1;
    size_t f = last < 1 ? last : 1;
    content->ptr = body.ptr + f;
    content->len = (uint32_t)(last - f);
    *first = f;
}

/* Removes up to `indent` leading blanks from every line of `content`. */
static MsStr dedent(Parser *p, MsStr content, size_t indent) {
    size_t bm = p->bytes->len;
    size_t i = 0;
    bool line_begin = true;
    while (i < content.len) {
        if (line_begin) {
            size_t blanks = 0;
            while (blanks < indent && i < content.len && (content.ptr[i] == ' ' || content.ptr[i] == '\t')) {
                blanks++;
                i++;
            }
            line_begin = false;
            continue;
        }
        char c = content.ptr[i++];
        ms_buf_putc(p->bytes, c);
        if (c == '\n') {
            line_begin = true;
        }
    }
    MsStr out = {ms_arena_strndup(p->arena, p->bytes->data + bm, p->bytes->len - bm), (uint32_t)(p->bytes->len - bm)};
    p->bytes->len = bm;
    return out;
}

static MsExpr *interpolation(Parser *p, MsToken token, size_t at, MsStr source, MsPos position);

static void flush_literal(Parser *p, size_t bm) {
    /* Pending literal bytes sit above `bm` in p->bytes; parts are pushed by the caller. */
    (void)p;
    (void)bm;
}

static TextParts text_parts(Parser *p, MsToken token, MsStr raw, size_t quotes, bool interpolating) {
    const uint8_t *rb = (const uint8_t *)raw.ptr;
    size_t first, end_, indent;
    if (quotes >= 3) {
        MsStr content;
        multiline_body(raw, &content, &indent, &first);
        end_ = first + content.len;
    } else {
        first = 0;
        end_ = raw.len;
        indent = 0;
    }
    size_t pm = mark(p);       /* parts, on the scratch stack */
    size_t bm = p->bytes->len; /* the literal being built, on the byte stack */
    size_t i = first;
    bool line_start = indent > 0;
    size_t positioned = 0;
    MsPos position = token.pos;
#define FLUSH()                                                                                    \
    do {                                                                                           \
        if (p->bytes->len != bm) {                                                                 \
            MsTextPart part = {{ms_arena_strndup(p->arena, p->bytes->data + bm, p->bytes->len - bm), \
                                (uint32_t)(p->bytes->len - bm)}, NULL};                            \
            push(p, &part, sizeof part);                                                           \
            p->bytes->len = bm;                                                                    \
        }                                                                                          \
    } while (0)
    while (i < end_) {
        if (line_start) {
            line_start = false;
            size_t skipped = 0;
            while (skipped < indent && i < end_ && (rb[i] == ' ' || rb[i] == '\t')) {
                skipped++;
                i++;
            }
            continue;
        }
        uint8_t c = rb[i++];
        if (c == '\\') {
            c = rb[i++];
            switch (c) {
            case 'n': ms_buf_putc(p->bytes, '\n'); break;
            case 'r': ms_buf_putc(p->bytes, '\r'); break;
            case 't': ms_buf_putc(p->bytes, '\t'); break;
            case 'u': {
                size_t start = i + 1;
                i = start;
                while (rb[i] != '}') {
                    i++;
                }
                uint32_t n = 0;
                for (size_t k = start; k < i; k++) {
                    uint8_t h = rb[k];
                    n = n * 16 + (uint32_t)(h <= '9' ? h - '0' : (h | 0x20) - 'a' + 10);
                }
                ms_utf8_put(p->bytes, n);
                i++;
                break;
            }
            default:
                ms_buf_putc(p->bytes, (char)c);
            }
            continue;
        }
        if (!(interpolating && c == '{')) {
            ms_buf_putc(p->bytes, (char)c);
            line_start = c == '\n' && indent > 0;
            continue;
        }
        FLUSH();
        size_t start = i;
        size_t brace = p->source_origin + token.lo + quotes + start - 1;
        size_t stop = ms_bounds_interp_end(p->bounds, brace);
        i = stop - (p->source_origin + token.lo + quotes);
        MsStr source = {raw.ptr + start, (uint32_t)(i - 1 - start)};
        /* Advance through each prefix once, including physical lines in multiline text. */
        size_t at = quotes + start;
        MsStr full = text(p, token);
        MsStr rest = {full.ptr + positioned, (uint32_t)(full.len - positioned)};
        position = text_pos(position, rest, at - positioned, p->bounds);
        positioned = at;
        MsExpr *value = interpolation(p, token, at, source, position);
        MsTextPart part = {{NULL, 0}, value};
        push(p, &part, sizeof part);
    }
    FLUSH();
#undef FLUSH
    TextParts out;
    out.ptr = finish(p, pm, &out.len, sizeof(MsTextPart), _Alignof(MsTextPart));
    if (out.len == 0) {
        out.ptr = MS_NEW_N(p->arena, MsTextPart, 1);
        out.ptr[0].lit = (MsStr){"", 0};
        out.len = 1;
    }
    (void)flush_literal;
    return out;
}

static TextParts one_literal(Parser *p, MsStr s) {
    TextParts out = {MS_NEW_N(p->arena, MsTextPart, 1), 1};
    out.ptr[0].lit = s;
    out.ptr[0].expr = NULL;
    return out;
}

static bool has_prefix(MsStr s, const char *pre) {
    size_t n = strlen(pre);
    return s.len >= n && memcmp(s.ptr, pre, n) == 0;
}

/* Decodes a text token into literal and interpolated parts. Only `f"..."` and `f"""` text
 * interpolates; braces are plain in the other forms. */
static TextParts text_parts_of(Parser *p, MsToken token) {
    MsStr full = text(p, token);
    if (has_prefix(full, "r\"\"\"")) {
        MsStr body = {full.ptr + 4, full.len - 4 - 3};
        MsStr content;
        size_t indent, f;
        multiline_body(body, &content, &indent, &f);
        return one_literal(p, dedent(p, content, indent));
    }
    if (has_prefix(full, "f\"\"\"")) {
        MsStr body = {full.ptr + 4, full.len - 4 - 3};
        return text_parts(p, token, body, 4, true);
    }
    if (has_prefix(full, "\"\"\"")) {
        MsStr body = {full.ptr + 3, full.len - 6};
        return text_parts(p, token, body, 3, false);
    }
    if (has_prefix(full, "r\"")) {
        return one_literal(p, (MsStr){full.ptr + 2, full.len - 3});
    }
    if (has_prefix(full, "f\"")) {
        MsStr body = {full.ptr + 2, full.len - 3};
        return text_parts(p, token, body, 2, true);
    }
    MsStr raw = {full.ptr + 1, full.len - 2};
    if (memchr(raw.ptr, '\\', raw.len) == NULL) {
        return one_literal(p, raw);
    }
    return text_parts(p, token, raw, 1, false);
}

static MsStr append_suffix(Parser *p, MsStr message, MsStr suffix) {
    char *d = ms_alloc(p->arena, (size_t)message.len + suffix.len + 1, 1);
    memcpy(d, message.ptr, message.len);
    memcpy(d + message.len, suffix.ptr, suffix.len);
    d[message.len + suffix.len] = 0;
    return (MsStr){d, message.len + suffix.len};
}

static void parser_init_nested(Parser *n, const Parser *p, MsStr src, const MsToken *tokens, size_t ntokens, size_t origin) {
    memset(n, 0, sizeof *n);
    n->arena = p->arena;
    n->names = p->names;
    n->src = src.ptr;
    n->src_len = src.len;
    n->tokens = tokens;
    n->ntokens = ntokens;
    n->bounds = p->bounds;
    n->source_origin = origin;
    n->depth = p->depth;
    n->next_id = p->next_id;
    n->scratch = p->scratch;
    n->bytes = p->bytes;
    n->diag = p->diag;
    n->type_brackets = compute_type_brackets(p->arena, tokens, ntokens);
}

/* Parses the one expression of an interpolation with a nested parser; on failure appends `suffix`
 * to the message and rethrows into `p`. `eof_by_need` makes the final check `need(Eof)`. */
static MsExpr *nested_expression(Parser *p, Parser *n, MsStr suffix, MsStr source, bool eof_by_need) {
    Catch c;
    n->catch_ = NULL;
    catch_begin(n, &c);
    struct {
        MsExpr *volatile value;
    } r = {NULL};
    if (setjmp(c.jb) == 0) {
        r.value = expression(n, 0);
        newlines(n);
        if (eof_by_need) {
            need(n, MS_T_Eof);
        } else if (kind(n) != MS_T_Eof) {
            MsToken at = peek(n);
            MsStr found = describe(n, at);
            (void)source;
            FAILF(n, at, "an interpolation holds one expression, found %.*s after it; close the brace after the expression, or bind the rest to a name first", STR(found));
        }
        catch_end(n, &c);
        p->next_id = n->next_id;
        return r.value;
    }
    p->next_id = n->next_id;
    p->diag->message = append_suffix(p, p->diag->message, suffix);
    p->scratch->len = c.scratch;
    p->bytes->len = c.bytes;
    throw_(p);
}

/* The wrapper path for an expression whose lexical error depends on its physical closing
 * parenthesis. */
static MsExpr *interpolation_wrapped(Parser *p, MsToken token, size_t at, MsStr source) {
    MsStr full = text(p, token);
    MsPos open_pos = text_pos(token.pos, full, at - 1, p->bounds);
    MsStr suffix = fmt(p, " ('{' at column %u starts an interpolation in f\"...\" text; write \\{ and \\} for literal braces, or drop the f)", open_pos.column);
    char *w = ms_alloc(p->arena, (size_t)source.len + 3, 1);
    w[0] = '(';
    memcpy(w + 1, source.ptr, source.len);
    w[source.len + 1] = ')';
    w[source.len + 2] = 0;
    MsStr wrapped = {w, source.len + 2};
#define SHIFT(pt) text_pos(token.pos, full, at - 1 + ((pt).offset < (uint32_t)source.len + 1 ? (pt).offset : (uint32_t)source.len + 1), p->bounds)
    MsLexed lexed;
    MsDiag ld;
    if (!ms_lex(p->arena, wrapped.ptr, wrapped.len, &lexed, &ld)) {
        ld.pos = SHIFT(ld.pos);
        if (ld.has_end) {
            ld.end = SHIFT(ld.end);
        }
        if (ld.has_fix) {
            ld.fix_pos = SHIFT(ld.fix_pos);
            ld.fix_end = SHIFT(ld.fix_end);
        }
        ld.message = append_suffix(p, ld.message, suffix);
        *p->diag = ld;
        throw_(p);
    }
    size_t closing = lexed.ntokens - 3;
    MsToken *toks = lexed.tokens;
    memmove(toks + closing, toks + closing + 1, (lexed.ntokens - closing - 1) * sizeof(MsToken));
    size_t nt = lexed.ntokens - 1;
    memmove(toks, toks + 1, (nt - 1) * sizeof(MsToken));
    nt--;
    for (size_t k = 0; k < nt; k++) {
        toks[k].pos = SHIFT(toks[k].pos);
        toks[k].end = SHIFT(toks[k].end);
    }
#undef SHIFT
    size_t origin = p->source_origin + token.lo + at - 1;
    Parser n;
    parser_init_nested(&n, p, (MsStr){lexed.source, (uint32_t)lexed.source_len}, toks, nt, origin);
    return nested_expression(p, &n, suffix, source, true);
}

/* Lexes and parses the expression inside one `{...}` of `f` text. */
static MsExpr *interpolation(Parser *p, MsToken token, size_t at, MsStr source, MsPos position) {
    MsStr suffix = fmt(p, " ('{' at column %u starts an interpolation in f\"...\" text; write \\{ and \\} for literal braces, or drop the f)", position.column - 1);
    size_t origin = p->source_origin + token.lo + at;
    MsToken *tokens;
    size_t nt;
    MsDiag ld;
    if (!ms_lex_interpolation(p->arena, source.ptr, source.len, origin, p->bounds, &tokens, &nt, &ld)) {
        return interpolation_wrapped(p, token, at, source);
    }
    /* The lexer rejects physical newlines inside an interpolation, so each token maps from its
     * relative byte offset. */
    for (size_t k = 0; k < nt; k++) {
        MsPos *ps[2] = {&tokens[k].pos, &tokens[k].end};
        for (int j = 0; j < 2; j++) {
            uint32_t off = ps[j]->offset < source.len ? ps[j]->offset : source.len;
            *ps[j] = (MsPos){position.offset + off, position.line, position.column + off};
        }
    }
    Parser n;
    parser_init_nested(&n, p, source, tokens, nt, origin);
    return nested_expression(p, &n, suffix, source, false);
}

/* ---- match ---- */

/* `if c: a else: b` (also `else if`) as a match over the Bool `c`. */
static MsExpr *if_expression(Parser *p, MsToken t) {
    MsExpr *cond = expression(p, 0);
    need(p, MS_T_Colon);
    if (kind(p) == MS_T_Newline) {
        FAIL(p, peek(p), "an if expression writes its branches on one line, 'if c: a else: b'; to run statements, use an if statement that assigns a 'var' or returns");
    }
    MsExpr *then = expression(p, 0);
    if (kind(p) != MS_T_Else) {
        FAIL(p, peek(p), "an if expression needs an else branch; write 'if c: a else: b', or use an if statement when no value is needed");
    }
    MsToken else_token = peek(p);
    p->at++;
    MsExpr *els;
    if (kind(p) == MS_T_If) {
        MsToken nested = peek(p);
        p->at++;
        els = if_expression(p, nested);
    } else {
        need(p, MS_T_Colon);
        els = expression(p, 0);
    }
    MsArm **arms = MS_NEW_N(p->arena, MsArm *, 2);
    for (int k = 0; k < 2; k++) {
        MsPos pos = k == 0 ? t.pos : else_token.pos;
        MsExpr *path = mk(p, pos, MS_E_BOOL);
        path->u.flag = k == 0;
        MsArm *a = NEW(p, MsArm);
        a->id = new_id(p);
        a->pos = pos;
        a->path = path;
        a->value = k == 0 ? then : els;
        a->from_if = true;
        arms[k] = a;
    }
    MsExpr *m = mk(p, t.pos, MS_E_MATCH);
    m->u.match.scrutinee = cond;
    m->u.match.arms.ptr = arms;
    m->u.match.arms.len = 2;
    return m;
}

/* An arm's final expression supplies its value; a statement-only arm yields Void. */
static void value_arm_inner(Parser *p, MsArm *a) {
    p->inline_return = false;
    need(p, MS_T_Colon);
    bool indented = take(p, MS_T_Newline);
    if (indented) {
        need(p, MS_T_Indent);
    }
    p->inline_statement = !indented;
    size_t m = mark(p);
    for (;;) {
        statements(p, true);
        if (!indented) {
            break;
        }
        newlines(p);
        if (kind(p) == MS_T_Dedent || kind(p) == MS_T_Eof) {
            break;
        }
    }
    FINISH_PTRS(p, m, a->body);
    if (a->body.len != 0 && a->body.ptr[a->body.len - 1]->kind == MS_S_CALL) {
        a->value = a->body.ptr[a->body.len - 1]->u.expr;
        a->body.len--;
    }
    for (uint32_t k = 0; k < a->body.len; k++) {
        MsStmt *s = a->body.ptr[k];
        if (s->kind == MS_S_CALL) {
            MsExpr *e = s->u.expr;
            bool is_try = e->kind == MS_E_UNARY && e->op == MS_U_TRY;
            if (e->kind != MS_E_CALL && e->kind != MS_E_MATCH && !is_try) {
                parse_diag(p, s->pos, LIT("an arm value must be its final expression"));
                throw_(p);
            }
        }
    }
    if (indented) {
        need(p, MS_T_Dedent);
    } else {
        p->inline_statement = false;
        end(p);
    }
}

static void value_arm(Parser *p, MsArm *a) {
    bool outer = p->inline_statement, outer_return = p->inline_return;
    value_arm_inner(p, a);
    p->inline_statement = outer;
    p->inline_return = outer_return;
}

static bool is_lower_start(MsStr s) {
    return s.len > 0 && ((s.ptr[0] >= 'a' && s.ptr[0] <= 'z') || s.ptr[0] == '_');
}

static void match_arms(Parser *p, MsToken header, MsExpr *m) {
    need(p, MS_T_Colon);
    need(p, MS_T_Newline);
    need(p, MS_T_Indent);
    size_t am = mark(p);
    uint32_t narms = 0;
    for (;;) {
        newlines(p);
        if (kind(p) == MS_T_Dedent) {
            if (narms == 0) {
                FAIL(p, header, "match requires at least one arm; add a case pattern or '_' arm under the header");
            }
            break;
        }
        MsToken prefix;
        if (legacy_case_prefix(p, &prefix)) {
            fail_fix(p, prefix, LIT("match arms use bare variant names, e.g. Paid(receipt): or Missing:; remove the legacy 'case' prefix"), LIT(""));
        }
        MsToken start = peek(p);
        MsTok k = (MsTok)start.kind;
        bool literal = k == MS_T_Number || k == MS_T_True || k == MS_T_False || k == MS_T_String ||
                       (k == MS_T_Minus && ahead(p, 1).kind == MS_T_Number);
        size_t bm = mark(p);
        bool bare = false;
        MsExpr *path;
        MsArmBinding single;
        bool has_single = false;
        if (literal) {
            path = expression(p, 0);
        } else if (take(p, MS_T_Underscore)) {
            path = mk_name(p, start.pos, intern(p, "_"));
        } else {
            MsExpr *written = case_path(p);
            if (written->kind == MS_E_NAME && str_is(ms_name(p->names, written->u.sym), "some") &&
                kind(p) == MS_T_LParen && p->speculative == 0) {
                FAIL(p, peek(p), "there is no some pattern; write the payload name alone, e.g. 'value:' beside 'none:'");
            }
            if (written->kind == MS_E_NAME && kind(p) != MS_T_LParen) {
                MsStr n = ms_name(p->names, written->u.sym);
                if (!str_is(n, "none") && is_lower_start(n)) {
                    /* The checker distinguishes an Optional payload binding from a lowercase
                     * variant using the scrutinee's type. */
                    single = (MsArmBinding){written->u.sym, start.pos};
                    has_single = true;
                    bare = true;
                }
            }
            path = written;
            if (has_single) {
                push(p, &single, sizeof single);
            }
            if (take(p, MS_T_LParen)) {
                for (;;) {
                    MsToken tok = peek(p);
                    if (!take(p, MS_T_Underscore)) {
                        need(p, MS_T_Name);
                    }
                    MsArmBinding b = {sym(p, tok), tok.pos};
                    push(p, &b, sizeof b);
                    if (kind(p) == MS_T_LParen) {
                        FAIL(p, peek(p), "patterns cannot be nested; bind the outer payload, then handle it in a separate match or helper function");
                    }
                    if (!take(p, MS_T_Comma)) {
                        break;
                    }
                    if (kind(p) == MS_T_RParen) {
                        break;
                    }
                }
                need(p, MS_T_RParen);
            }
        }
        MsArm *a = NEW(p, MsArm);
        a->bindings.ptr = finish(p, bm, &a->bindings.len, sizeof(MsArmBinding), _Alignof(MsArmBinding));
        a->id = new_id(p);
        a->pos = start.pos;
        a->path = path;
        a->bare = bare;
        value_arm(p, a);
        push_ptr(p, a);
        narms++;
    }
    need(p, MS_T_Dedent);
    uint32_t n;
    MsArm **arms = finish(p, am, &n, sizeof(void *), _Alignof(void *));
    m->u.match.arms.ptr = arms;
    m->u.match.arms.len = n;
}

/* ---- brackets ---- */

/* Reinterprets a type as the value expression that spells it. */
static MsExpr *type_value(Parser *p, const MsTypeRef *t) {
    if (t->kind != MS_TYPE_NAMED) {
        return NULL;
    }
    MsStr full = ms_name(p->names, t->name);
    size_t i = 0;
    while (i < full.len && full.ptr[i] != '.') {
        i++;
    }
    MsExpr *e = mk_name(p, t->pos, ms_intern(p->names, full.ptr, i));
    /* token = tokens.partition_point(|k| k.pos.offset < t.pos.offset) */
    size_t lo = 0, hi = p->ntokens;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (p->tokens[mid].pos.offset < t->pos.offset) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    size_t token = lo;
    size_t index = 0;
    while (i < full.len) {
        i++; /* the dot */
        size_t j = i;
        while (j < full.len && full.ptr[j] != '.') {
            j++;
        }
        MsPos pos = p->tokens[token + 2 * (index + 1)].pos;
        e = mk_member(p, pos, e, ms_intern(p->names, full.ptr + i, j - i));
        i = j;
        index++;
    }
    if (t->args.len != 0) {
        MsTypeRefs types = copy_types(p, t->args);
        MsExpr *value = t->args.len == 1 ? type_value(p, t->args.ptr[0]) : NULL;
        MsExpr *a = mk(p, t->pos, MS_E_APPLY);
        a->u.apply.left = e;
        a->u.apply.types = types;
        a->u.apply.value = value;
        e = a;
    }
    return e;
}

/* Brackets may contain types or a value. A single name or application keeps both interpretations
 * until name resolution identifies the receiver. */
static MsExpr *bracket(Parser *p, MsExpr *left) {
    size_t start = p->at;
    MsTypeRefs types = {NULL, 0};
    bool have_types = false;
    /* A type starts with a name, `fn` or `(`; anything else is a value. */
    if (starts_type(kind(p)) && type_bracket(p, start - 1)) {
        Catch c;
        catch_begin(p, &c);
        p->speculative++;
        struct {
            volatile bool ok;
            MsTypeRefs types;
        } r = {false, {NULL, 0}};
        if (setjmp(c.jb) == 0) {
            r.types = type_args(p);
            r.ok = true;
            catch_end(p, &c);
            p->speculative--;
        } else {
            p->speculative--;
            catch_restore(p, &c);
            p->at = start;
        }
        if (r.ok) {
            types = r.types;
            have_types = true;
        }
    }
    if (have_types) {
        MsPos pos = left->pos;
        MsExpr *value = NULL;
        if (types.len == 1) {
            value = type_value(p, types.ptr[0]);
        }
        if (value != NULL) {
            types = copy_types(p, types);
        }
        MsExpr *a = mk(p, pos, MS_E_APPLY);
        a->u.apply.left = left;
        a->u.apply.types = types;
        a->u.apply.value = value;
        return a;
    }
    MsExpr *index = expression(p, 0);
    if (kind(p) == MS_T_Colon) {
        FAIL(p, peek(p), "there is no slice syntax; call slice(start: 0, end: 2) on a List or String");
    }
    need(p, MS_T_RBracket);
    MsPos pos = left->pos;
    MsExpr *ix = mk(p, pos, MS_E_INDEX);
    ix->u.bin.left = left;
    ix->u.bin.right = index;
    return ix;
}

/* ---- primary, postfix, calls ---- */

static MsExpr *postfix(Parser *p, MsExpr *e) {
    size_t links = 0;
    for (;;) {
        MsExpr *l, *ix;
        if (take(p, MS_T_Dot)) {
            link(p, &links);
            if (kind(p) == MS_T_Number) {
                FAIL(p, peek(p), "a number has at most one decimal point and member access needs a name; write the number once, e.g. 1.2");
            }
            MsToken name = need(p, MS_T_Name);
            e = mk_member(p, name.pos, e, sym(p, name));
        } else if (take(p, MS_T_LBracket)) {
            link(p, &links);
            e = bracket(p, e);
        } else if (take(p, MS_T_LParen)) {
            link(p, &links);
            MsPos pos = e->pos;
            Args args = call_arguments(p);
            e = mk_call(p, pos, e, args.ptr, args.len);
        } else if (kind(p) == MS_T_Question && index_parts(e, &l, &ix) && ahead(p, 1).kind != MS_T_Dot) {
            p->at++;
            MsPos pos = e->pos;
            MsExpr *pr = mk(p, pos, MS_E_PROBE);
            pr->u.bin.left = e;
            e = pr;
        } else if (kind(p) == MS_T_Question) {
            /* `call()?` is `try call()`; one per value keeps a line readable. */
            p->at++;
            if (kind(p) == MS_T_Question) {
                FAIL(p, peek(p), "'?\?' is not an operator and '?' cannot repeat: unwrap an Optional with 'if x := v:' or give it a default with 'v.get(default)', or bind a Result to a name before the next '?'");
            }
            MsPos pos = e->pos;
            e = mk_unary(p, pos, MS_U_TRY, e);
        } else {
            break;
        }
    }
    return e;
}

/* Parses the arguments after an opening parenthesis, through `)`. */
static Args call_arguments(Parser *p) {
    Args out = {NULL, 0};
    if (take(p, MS_T_RParen)) {
        return out;
    }
    size_t m = mark(p);
    for (;;) {
        MsPos pos = peek(p).pos;
        bool has_name = false;
        MsSym name = 0;
        if (kind(p) == MS_T_Name && ahead(p, 1).kind == MS_T_Colon) {
            name = sym(p, peek(p));
            has_name = true;
            p->at += 2;
        }
        if (kind(p) == MS_T_Name && ahead(p, 1).kind == MS_T_Assign) {
            MsToken eq = ahead(p, 1);
            MsStr n = text(p, peek(p));
            MsToken gt = ahead(p, 2);
            if (gt.kind == MS_T_Gt && gt.pos.offset == eq.end.offset) {
                /* `x => x * 2`: a closure written with an arrow. */
                MsToken nm = peek(p);
                MsStr message = fmt(p, "there is no '=>' closure; write fn %.*s: body, with the parameter after fn and a colon before the body", STR(n));
                fail_fix_range(p, nm, gt, message, fmt(p, "fn %.*s:", STR(n)));
            }
            FAILF(p, eq, "argument labels use a colon; write %.*s: value", STR(n));
        }
        if (kind(p) == MS_T_Var) {
            MsToken t = peek(p);
            t.end = ahead(p, 1).pos;
            fail_fix_range(p, t, t, LIT("a call does not write `var`: the callee's parameter declares that it changes the argument; write the argument plainly"), LIT(""));
        }
        MsExpr *value = expression(p, 0);
        if (value->kind == MS_E_NAME && kind(p) == MS_T_Arrow) {
            MsStr n = ms_name(p->names, value->u.sym);
            FAILF(p, peek(p), "arrow closures are not supported; write 'fn %.*s: %.*s + 1', or 'fn(%.*s: Int) Int: %.*s + 1' with explicit types", STR(n), STR(n), STR(n), STR(n));
        }
        MsArg a = {pos, has_name, name, value};
        push(p, &a, sizeof a);
        if (!take(p, MS_T_Comma)) {
            break;
        }
        if (kind(p) == MS_T_RParen) {
            break;
        }
    }
    need(p, MS_T_RParen);
    out.ptr = finish(p, m, &out.len, sizeof(MsArg), _Alignof(MsArg));
    return out;
}

static MsExpr *primary(Parser *p) {
    MsToken t = peek(p);
    p->at++;
    MsExpr *e;
    switch (t.kind) {
    case MS_T_Name: case MS_T_SelfKw: case MS_T_Fixture:
        e = mk_name(p, t.pos, sym(p, t));
        break;
    case MS_T_Number:
        e = mk(p, t.pos, MS_E_NUMBER);
        e->u.sym = sym(p, t);
        break;
    case MS_T_True: case MS_T_False:
        e = mk(p, t.pos, MS_E_BOOL);
        e->u.flag = t.kind == MS_T_True;
        break;
    case MS_T_String: {
        TextParts parts = text_parts_of(p, t);
        e = mk(p, t.pos, MS_E_TEXT);
        e->u.text.ptr = parts.ptr;
        e->u.text.len = parts.len;
        break;
    }
    case MS_T_Void:
        e = mk(p, t.pos, MS_E_VOID);
        break;
    case MS_T_LParen:
        if (kind(p) == MS_T_RParen) {
            FAIL(p, t, "'()' is not a value; the Void value is written 'void'");
        }
        e = expression(p, 0);
        if (kind(p) == MS_T_Comma) {
            FAIL(p, peek(p), "Manuscript has no tuples; declare a type with 'type Pair:' and named fields, or use a List when the items share one type");
        }
        need(p, MS_T_RParen);
        break;
    case MS_T_LBracket: {
        MsExprs items = {NULL, 0};
        if (!take(p, MS_T_RBracket)) {
            size_t m = mark(p);
            for (;;) {
                push_ptr(p, expression(p, 0));
                if (!take(p, MS_T_Comma)) {
                    break;
                }
                if (kind(p) == MS_T_RBracket) {
                    break;
                }
            }
            need(p, MS_T_RBracket);
            FINISH_PTRS(p, m, items);
        }
        e = mk(p, t.pos, MS_E_LIST);
        e->u.list = items;
        break;
    }
    case MS_T_Match: {
        MsExpr *scrutinee = expression(p, 0);
        MsExpr *tmp = NEW(p, MsExpr);
        match_arms(p, t, tmp);
        e = mk(p, t.pos, MS_E_MATCH);
        e->u.match.scrutinee = scrutinee;
        e->u.match.arms = tmp->u.match.arms;
        break;
    }
    case MS_T_LBrace: {
        uint32_t n = 0;
        MsMapEntry *entries = NULL;
        if (!take(p, MS_T_RBrace)) {
            size_t m = mark(p);
            for (;;) {
                MsExpr *key = expression(p, 0);
                if (kind(p) == MS_T_Comma || kind(p) == MS_T_RBrace) {
                    FAIL(p, peek(p), "a brace literal is a Map and needs 'key: value' entries; there is no set literal, so write Set[T]() and call add(value), or [a, b].to_set() from a List");
                }
                need(p, MS_T_Colon);
                MsExpr *value = expression(p, 0);
                MsMapEntry en = {key, value};
                push(p, &en, sizeof en);
                if (!take(p, MS_T_Comma) || kind(p) == MS_T_RBrace) {
                    break;
                }
            }
            need(p, MS_T_RBrace);
            entries = finish(p, m, &n, sizeof(MsMapEntry), _Alignof(MsMapEntry));
        }
        e = mk(p, t.pos, MS_E_MAP);
        e->u.map.ptr = entries;
        e->u.map.len = n;
        break;
    }
    case MS_T_Fn: {
        MsTypeRef *result = NULL;
        MsParams params;
        MsStmt **destructured = NULL;
        uint32_t ndestructured = 0, cap = 0;
        if (kind(p) == MS_T_LParen) {
            params = parameters(p, true, true);
            if (kind(p) == MS_T_Arrow) {
                fail_fix(p, peek(p), LIT("result types follow the parameter list without an arrow; remove '->', e.g. fn (x: Int) Int: x + 1"), LIT(""));
            }
            if (kind(p) != MS_T_Colon) {
                result = typ(p);
            }
        } else {
            size_t m = mark(p);
            uint32_t count = 0;
            while (kind(p) == MS_T_Name || kind(p) == MS_T_LBracket || kind(p) == MS_T_LBrace ||
                   (kind(p) == MS_T_Var && ahead(p, 1).kind == MS_T_Name)) {
                if (kind(p) == MS_T_LBracket || kind(p) == MS_T_LBrace) {
                    /* `fn [a, b]: ...` binds the pattern from a hidden parameter. */
                    MsPattern *pat = pattern(p);
                    char nm[48];
                    snprintf(nm, sizeof nm, HIDDEN_ITEM " %u", count);
                    MsSym hidden = intern(p, nm);
                    push_ptr(p, mk_param(p, pat->pos, hidden, NULL, NULL, false, false));
                    count++;
                    MsStmt *d = destructure(p, pat, hidden);
                    if (ndestructured == cap) {
                        uint32_t ncap = cap ? cap * 2 : 4;
                        MsStmt **nd = MS_NEW_N(p->arena, MsStmt *, ncap);
                        if (ndestructured != 0) {
                            memcpy(nd, destructured, ndestructured * sizeof(MsStmt *));
                        }
                        destructured = nd;
                        cap = ncap;
                    }
                    destructured[ndestructured++] = d;
                    if (!take(p, MS_T_Comma)) {
                        break;
                    }
                    continue;
                }
                /* `fn var exchange, next: ...`: a parameter the function changes in place;
                 * `fn move item: ...` takes ownership of it. */
                bool moving = TAKE_MOVE(p, MS_T_Name);
                bool is_mutable = take(p, MS_T_Var);
                MsToken name = next(p);
                push_ptr(p, mk_param(p, name.pos, sym(p, name), NULL, NULL, is_mutable, moving));
                count++;
                if (!take(p, MS_T_Comma)) {
                    break;
                }
            }
            FINISH_PTRS(p, m, params);
        }
        MsStmts body = statement_suite(p, true, false);
        if (ndestructured != 0) {
            MsStmt **nb = MS_NEW_N(p->arena, MsStmt *, body.len + ndestructured);
            memcpy(nb, destructured, ndestructured * sizeof(MsStmt *));
            memcpy(nb + ndestructured, body.ptr, body.len * sizeof(MsStmt *));
            body.ptr = nb;
            body.len += ndestructured;
        }
        e = mk(p, t.pos, MS_E_LAMBDA);
        e->u.lambda.params = params;
        e->u.lambda.result = result;
        e->u.lambda.body = body;
        break;
    }
    case MS_T_If:
        e = if_expression(p, t);
        break;
    default: {
        MsTok before = p->at > 1 ? (MsTok)p->tokens[p->at - 2].kind : MS_T_Eof;
        const char *hint;
        if (t.kind == MS_T_Else) {
            hint = "'else' continues an 'if' block: put it on its own line at the same indentation as that 'if', directly after the if body";
        } else if (t.kind == MS_T_Gt && before == MS_T_Lt) {
            hint = "'<>' is not an operator; write '!=' for inequality";
        } else if (t.kind == MS_T_Star && before == MS_T_Star) {
            hint = "there is no '**' power operator; multiply explicitly or call a function from @std/math/math.ms";
        } else if ((t.kind == MS_T_Comma || t.kind == MS_T_RParen) && before == MS_T_Colon) {
            hint = "a label before ':' needs a value, e.g. count: 1";
        } else if (t.kind == MS_T_Comma) {
            hint = "remove the extra comma or add the missing value before it";
        } else {
            hint = "write a value, name, call, or literal here";
        }
        MsStr word = text(p, t);
        /* Words that read as names (`type`, `test`) are the ones written as variables. */
        bool reserved = t.kind == MS_T_Test || t.kind == MS_T_Type || t.kind == MS_T_Fixture;
        MsStr dt = describe(p, t);
        if (reserved) {
            FAILF(p, t, "expected an expression, found %.*s; '%.*s' is a reserved word and cannot be used as a name: pick another name for the variable, field or parameter", STR(dt), STR(word));
        }
        FAILF(p, t, "expected an expression, found %.*s; %s", STR(dt), hint);
    }
    }
    return postfix(p, e);
}

/* ---- module ---- */

static MsStr import_path(Parser *p) {
    MsToken token = need(p, MS_T_String);
    single_line(p, token, "import paths");
    TextParts parts = text_parts_of(p, token);
    MsStr out;
    if (!plain_text(parts, &out)) {
        FAIL(p, token, "import paths cannot interpolate; write the path as plain text without {…}");
    }
    return out;
}

static MsToken *import_names(Parser *p, bool wrapped, uint32_t *count) {
    size_t m = mark(p);
    for (;;) {
        MsToken n = need(p, MS_T_Name);
        push(p, &n, sizeof n);
        if (kind(p) == MS_T_Name && text_is(p, peek(p), "as")) {
            FAIL(p, peek(p), "imports cannot be renamed with 'as'; import the name as the module declares it");
        }
        if (!take(p, MS_T_Comma) || (wrapped && kind(p) == MS_T_RParen)) {
            break;
        }
    }
    return finish(p, m, count, sizeof(MsToken), _Alignof(MsToken));
}

static void push_imports(Parser *p, MsBuf *imports, MsPos pos, const MsToken *names, uint32_t n, MsStr path) {
    MsPos clause = names[0].pos;
    for (uint32_t i = 0; i < n; i++) {
        MsImport im;
        im.id = new_id(p);
        im.pos = pos;
        im.clause = clause;
        im.name_pos = names[i].pos;
        im.name = sym(p, names[i]);
        im.path = path;
        ms_buf_put(imports, &im, sizeof im);
    }
}

/* The rest of an import after `import`: `a, b from "path"`, `(a, b) from "path"`, or a group of
 * clauses `(a, b from "path", c from "other")`. */
static void import_statement(Parser *p, MsBuf *imports) {
    MsPos pos = previous(p).pos;
    if (kind(p) == MS_T_Star) {
        FAIL(p, peek(p), "namespace and wildcard imports are unsupported; import individual exports with 'import Name, OtherName from \"./module.ms\"'");
    }
    if (kind(p) == MS_T_LBrace) {
        FAIL(p, peek(p), "imports take no braces; write 'import a, b from \"path.ms\"', or 'import (a, b) from \"path.ms\"' to wrap across lines");
    }
    bool wrapped = take(p, MS_T_LParen);
    for (;;) {
        uint32_t n;
        MsToken *names = import_names(p, wrapped, &n);
        if (wrapped && kind(p) == MS_T_RParen) {
            need(p, MS_T_RParen);
            need_from(p);
            MsStr path = import_path(p);
            push_imports(p, imports, pos, names, n, path);
            break;
        }
        need_from(p);
        MsStr path = import_path(p);
        push_imports(p, imports, pos, names, n, path);
        if (!wrapped) {
            break;
        }
        if (!take(p, MS_T_Comma) || kind(p) == MS_T_RParen) {
            need(p, MS_T_RParen);
            break;
        }
    }
    end(p);
}

static void module_(Parser *p, MsBuf *imports, MsBuf *decls) {
    while (kind(p) != MS_T_Eof) {
        newlines(p);
        if (kind(p) == MS_T_Eof) {
            break;
        }
        if (take(p, MS_T_Import)) {
            import_statement(p, imports);
            continue;
        }
        if (kind(p) == MS_T_Name && text_is(p, peek(p), "from") && ahead(p, 1).kind == MS_T_String) {
            FAIL(p, peek(p), "imports read: import name, other from \"path.ms\"");
        }
        MsToken export_tok = peek(p);
        bool exported = take(p, MS_T_Export);
        MsDecl *d = declaration(p);
        if (exported && (d->kind == MS_D_IMPL || d->kind == MS_D_TEST)) {
            FAIL(p, export_tok, "only types, interfaces, and named functions can be exported; remove 'export' before this method, impl, test, or bench (a method is exported with its type)");
        }
        d->is_exported = exported;
        ms_buf_put(decls, &d, sizeof d);
    }
}

bool ms_parse(MsArena *arena, MsNames *names, const char *src, size_t len, MsModule *out, MsDiag *diag) {
    return ms_parse_chunk(arena, names, src, len, 0, 0, 0, out, diag);
}

bool ms_parse_chunk(MsArena *arena, MsNames *names, const char *src, size_t len, uint32_t base_offset,
                    uint32_t base_line, uint32_t first_id, MsModule *out, MsDiag *diag) {
    memset(out, 0, sizeof *out);
    MsLexed lexed;
    if (!ms_lex_at(arena, src, len, base_offset, base_line, &lexed, diag)) {
        return false;
    }
    MsBuf scratch = {0}, bytes = {0}, imports = {0}, decls = {0};
    Parser p;
    memset(&p, 0, sizeof p);
    p.arena = arena;
    p.names = names;
    p.src = lexed.source;
    p.src_len = lexed.source_len;
    p.tokens = lexed.tokens;
    p.ntokens = lexed.ntokens;
    p.bounds = &lexed.bounds;
    p.type_brackets = compute_type_brackets(arena, lexed.tokens, lexed.ntokens);
    p.scratch = &scratch;
    p.bytes = &bytes;
    p.diag = diag;
    p.next_id = first_id;
    Catch c;
    c.prev = NULL;
    p.catch_ = &c;
    bool ok = false;
    if (setjmp(c.jb) == 0) {
        module_(&p, &imports, &decls);
        out->nimports = (uint32_t)(imports.len / sizeof(MsImport));
        out->imports = ms_alloc(arena, imports.len ? imports.len : 1, _Alignof(MsImport));
        if (imports.len != 0) {
            memcpy(out->imports, imports.data, imports.len);
        }
        out->ndecls = (uint32_t)(decls.len / sizeof(MsDecl *));
        out->decls = ms_alloc(arena, decls.len ? decls.len : 1, _Alignof(MsDecl *));
        if (decls.len != 0) {
            memcpy(out->decls, decls.data, decls.len);
        }
        out->node_count = p.next_id;
        ok = true;
    }
    ms_buf_free(&scratch);
    ms_buf_free(&bytes);
    ms_buf_free(&imports);
    ms_buf_free(&decls);
    return ok;
}
