/* The strict parser. A port of crates/ms-syntax/src/parser.rs: the same tree, node ids, positions
 * and messages. A failure unwinds with longjmp to the nearest catch: the entry point, or one of
 * the three places that try something and fall back (a bracket read as type arguments, an inline
 * `if` read as an expression, and the operand of a rejected `try`). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/chars.h"

#include "ms/text.h"
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
#define INDEX_SET MS_INDEX_SET
/* Binding power of the operand of a prefix `not` or `try`. */
#define PREFIX_OPERAND 3
/* Precedence of `..`: above comparisons, below `+` and `-`. */
#define RANGE_LEVEL 5

/* What a speculative parse restores when it fails: the shared scratch stacks and the parser flags
 * that the abandoned frames had changed. Node ids and queued statements are deliberately not
 * restored, so a backtrack consumes ids exactly as the Rust parser does. */
typedef struct Checkpoint {
    size_t scratch, bytes;
    size_t depth;
    bool inline_statement, inline_return, block_lambda;
} Checkpoint;

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

static MsDiag *parse_diag(Parser *p, MsPos pos, MsStr message) {
    memset(p->diag, 0, sizeof *p->diag);
    p->diag->pos = pos;
    p->diag->message = message;
    return p->diag;
}

static Checkpoint checkpoint_take(const Parser *p) {
    Checkpoint c = {
        .scratch = p->scratch->len,
        .bytes = p->bytes->len,
        .depth = p->depth,
        .inline_statement = p->inline_statement,
        .inline_return = p->inline_return,
        .block_lambda = p->block_lambda,
    };
    return c;
}

/* Restores what the abandoned frames of a failed parse would have restored. A failed enter()
 * leaves its own increment of depth in place. */
static void checkpoint_restore(Parser *p, const Checkpoint *c) {
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
        if (fk == MS_T_Name && ms_text_is(found_text, "is")) {
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
        if (ms_text_is(found_text, "_")) {
            return LIT("; '_' is a reserved word and cannot be used as a name: loops, parameters and bindings need a real name such as item, unused or ignored");
        }
        const char *fs = ms_tok_str(fk);
        if (ms_text_is(found_text, fs) && found_text.len > 0 &&
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

static void fail(Parser *p, MsToken t, MsStr message) {
    MsDiag *d = parse_diag(p, t.pos, message);
    if (t.end.line > 0) {
        d->has_end = true;
        d->end = t.end;
    }
}

/* Fails on `first` with a replacement of the range first.pos..last.end. */
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
}

static void fail_fix(Parser *p, MsToken t, MsStr message, MsStr replacement) {
    fail_fix_range(p, t, t, message, replacement);
}

/* A symbolic operator can touch either operand; its word replacement needs separation wherever it
 * would otherwise join an identifier or number. */
static void fail_word_operator(Parser *p, MsToken first, MsToken last, MsStr message, const char *word) {
    MsBuf b = {0};
    if (first.lo > 0 && ms_ascii_is_ident((uint8_t)p->src[first.lo - 1])) {
        ms_buf_putc(&b, ' ');
    }
    ms_buf_puts(&b, word);
    if (last.hi < p->src_len && ms_ascii_is_ident((uint8_t)p->src[last.hi])) {
        ms_buf_putc(&b, ' ');
    }
    MsStr r = {ms_arena_strndup(p->arena, b.data, b.len), (uint32_t)b.len};
    ms_buf_free(&b);
    fail_fix_range(p, first, last, message, r);
}

static void and_and(Parser *p, MsToken first) {
    MsToken n = ahead(p, 1);
    MsToken last = (n.kind == MS_T_Amp && n.pos.offset == first.end.offset) ? n : first;
    fail_word_operator(p, first, last, LIT("'&&' is not an operator; write 'and' for logical and"), "and");
}

MS_NODISCARD static bool need_token(Parser *p, MsTok k, MsToken *out) {
    MsToken t = peek(p);
    if (t.kind == k) {
        p->at++;
        *out = t;
        return true;
    }
    if (p->speculative > 0) {
        return false;
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
        return false;
    }
    MsStr hint = need_hint(p, ms_tok_str(k), t);
    MsStr dk = describe_kind(p, k);
    MsStr dt = describe(p, t);
    fail(p, t, fmt(p, "expected %.*s, found %.*s%.*s", STR(dk), STR(dt), STR(hint)));
    return false;
}

MS_NODISCARD static bool need(Parser *p, MsTok k) {
    MsToken ignored = {0};
    return need_token(p, k, &ignored);
}

/* Consumes the contextual word `from` that ends an import's names. */
MS_NODISCARD static bool need_from(Parser *p) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Name && text_is(p, t, "from")) {
        p->at++;
        return true;
    }
    MsStr dt = describe(p, t);
    MsStr hint = need_hint(p, "from", t);
    fail(p, t, fmt(p, "expected 'from', found %.*s%.*s", STR(dt), STR(hint)));
    return false;
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

MS_NODISCARD static bool parse_link(Parser *p, size_t *links) {
    (*links)++;
    if (*links > MS_MAX_CHAIN) {
        fail(p, peek(p), fmt(p, "expression chain exceeds %d operators or accesses; split it into named parts", MS_MAX_CHAIN));
        return false;
    }
    return true;
}

/* Counts one level of nesting; the caller decrements depth when it is done. */
MS_NODISCARD static bool enter(Parser *p) {
    p->depth++;
    if (p->depth > MS_MAX_NESTING) {
        p->enter_failed = true;
        if (p->speculative > 0) {
            return false;
        }
        fail(p, peek(p), fmt(p, "nesting exceeds %d levels; split the expression, type, or block into named parts", MS_MAX_NESTING));
        return false;
    }
    return true;
}

MS_NODISCARD static bool end(Parser *p) {
    if (p->inline_statement) {
        switch (kind(p)) {
        case MS_T_Newline: case MS_T_Comma: case MS_T_RParen: case MS_T_RBracket: case MS_T_RBrace:
            return true;
        default:
            break;
        }
        MsToken t = peek(p);
        MsStr dt = describe(p, t);
        const char *is = (t.kind == MS_T_Name && text_is(p, t, "is")) ? IS_HINT : "";
        fail(p, t, fmt(p, "expected end of inline statement, found %.*s; an inline body holds one simple statement; for more statements or an `else`, put the body on indented lines and start `else:` on its own line at the `if`'s indentation%s",
              STR(dt), is));
        return false;
    }
    if (take(p, MS_T_Newline)) {
        newlines(p);
        return true;
    }
    if (p->at > 0 && previous(p).kind == MS_T_Dedent) {
        return true;
    }
    MsToken t = peek(p);
    if (p->block_lambda && t.kind == MS_T_Comma) {
        fail(p, t, LIT("a comma cannot end a statement in an indented function body; to separate enclosing arguments, put the comma on its own line dedented to the fn header, or group the function in parentheses"));
        return false;
    }
    if (t.kind == MS_T_Amp) {
        and_and(p, t);
        return false;
    }
    if (t.kind == MS_T_Arrow || (t.kind == MS_T_Assign && ahead(p, 1).kind == MS_T_Gt)) {
        fail(p, t, LIT("there is no arrow function; anonymous functions are written fn x: x + 1"));
        return false;
    }
    bool prev_new = p->at > 0 && text_is(p, previous(p), "new");
    MsStr prev_word = p->at > 0 ? text(p, previous(p)) : LIT("");
    const char *hint;
    if (ms_text_is(prev_word, "def") && t.kind == MS_T_Name) {
        hint = "; there is no 'def': declare a function with 'fn name(a: Int) Int:'";
    } else if (ms_text_is(prev_word, "lambda")) {
        hint = "; there is no 'lambda': write an anonymous function as 'fn x: x + 1'";
    } else if (ms_text_is(prev_word, "elif")) {
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
    fail(p, t, fmt(p, "expected end of statement, found %.*s%s", STR(dt), hint));
    return false;
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
            MS_VEC_PUSH(open, Open, o);
        } else if (k == MS_T_RBracket) {
            if (open.len != 0) {
                Open o = MS_VEC_LAST(open, Open);
                MS_VEC_POP(open, Open);
                if (o.ok) {
                    bits[o.at / 64] |= (uint64_t)1 << (o.at % 64);
                }
                if (open.len != 0) {
                    MS_VEC_LAST(open, Open).ok &= o.ok;
                }
            }
        } else if (!type_token(k)) {
            if (open.len != 0) {
                MS_VEC_LAST(open, Open).ok = false;
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
#define IN(s) ms_text_is(w, s)
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

MS_NODISCARD static bool expression(Parser *p, int min, MsExpr **out);
MS_NODISCARD static bool typ(Parser *p, MsTypeRef **out);
MS_NODISCARD static bool type_args(Parser *p, MsTypeRefs *out);
MS_NODISCARD static bool statement(Parser *p, bool allow_value, MsStmt **out);
MS_NODISCARD static bool statement_suite(Parser *p, bool expression, bool fn_body, MsStmts *out);
MS_NODISCARD static bool pattern(Parser *p, MsPattern **out);
MS_NODISCARD static bool postfix(Parser *p, MsExpr *e, MsExpr **out);
MS_NODISCARD static bool primary(Parser *p, MsExpr **out);
MS_NODISCARD static bool named_type(Parser *p, MsTypeRef **out);
MS_NODISCARD static bool binding(Parser *p, bool is_mutable, const MsPos *group, MsPos pos, MsStmt **out);

/* Parses one element and pushes it on the open scratch list. */
MS_NODISCARD static bool push_typ(Parser *p) {
    MsTypeRef *element = NULL;
    if (!typ(p, &element)) return false;
    push_ptr(p, element);
    return true;
}

MS_NODISCARD static bool push_named_type(Parser *p) {
    MsTypeRef *element = NULL;
    if (!named_type(p, &element)) return false;
    push_ptr(p, element);
    return true;
}

MS_NODISCARD static bool push_pattern(Parser *p) {
    MsPattern *element = NULL;
    if (!pattern(p, &element)) return false;
    push_ptr(p, element);
    return true;
}

MS_NODISCARD static bool push_expression(Parser *p, int min) {
    MsExpr *element = NULL;
    if (!expression(p, min, &element)) return false;
    push_ptr(p, element);
    return true;
}

MS_NODISCARD static bool push_binding(Parser *p, bool is_mutable, const MsPos *group, MsPos pos) {
    MsStmt *element = NULL;
    if (!binding(p, is_mutable, group, pos, &element)) return false;
    push_ptr(p, element);
    return true;
}
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

MS_NODISCARD static bool named_type(Parser *p, MsTypeRef **out) {
    MsToken name = {0};
    if (!need_token(p, MS_T_Name, &name)) return false;
    MsSym full = sym(p, name);
    if (kind(p) == MS_T_Dot) {
        size_t bm = p->bytes->len;
        MsStr first = ms_name(p->names, full);
        ms_buf_put(p->bytes, first.ptr, first.len);
        while (take(p, MS_T_Dot)) {
            ms_buf_putc(p->bytes, '.');
            MsToken part = {0};
            if (!need_token(p, MS_T_Name, &part)) return false;
            MsStr t = text(p, part);
            ms_buf_put(p->bytes, t.ptr, t.len);
        }
        full = ms_intern(p->names, p->bytes->data + bm, p->bytes->len - bm);
        p->bytes->len = bm;
    }
    MsTypeRefs args = {NULL, 0};
    MsStr full_s = ms_name(p->names, full);
    if (kind(p) == MS_T_LBracket && p->speculative == 0 && ms_text_is(full_s, "Callable")) {
        fail(p, peek(p), fmt(p, "there is no %.*s[...] type; a function type is written fn(Int) Int: parameter types in parentheses, then the result type", STR(full_s)));
        return false;
    }
    if (kind(p) == MS_T_LBracket && p->speculative == 0 && ms_text_is(full_s, "Optional")) {
        fail(p, peek(p), LIT("there is no Optional[T] spelling; write T? instead, e.g. Int? or (fn(Int) Int)?"));
        return false;
    }
    if (take(p, MS_T_LBracket)) {
        if (p->speculative > 0 && !type_bracket(p, p->at - 1)) {
            return false;
        }
        if (!type_args(p, &args)) return false;
    }
    MsToken lt = peek(p);
    if (lt.kind == MS_T_Lt && p->speculative == 0 && lt.pos.offset == previous(p).end.offset && args.len == 0) {
        fail(p, lt, fmt(p, "type arguments use square brackets, not angle brackets; write %.*s[T] instead of %.*s<T>", STR(full_s), STR(full_s)));
        return false;
    }
    *out = mk_named_type(p, name.pos, full, args);
    return true;
}

MS_NODISCARD static bool type_args(Parser *p, MsTypeRefs *out) {
    size_t m = mark(p);
    for (;;) {
        if (!push_typ(p)) return false;
        if (!take(p, MS_T_Comma)) {
            break;
        }
        if (kind(p) == MS_T_RBracket) {
            break;
        }
    }
    if (!need(p, MS_T_RBracket)) return false;
    MsTypeRefs r;
    FINISH_PTRS(p, m, r);
    *out = r;
    return true;
}

/* The type that follows a parameter list, rejecting the removed `->` and a missing type. */
MS_NODISCARD static bool result_type(Parser *p, MsTypeRef **out) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Arrow) {
        fail_fix(p, t, LIT("result types follow the parameter list without an arrow; remove '->', e.g. fn f() Void:"), LIT(""));
        return false;
    }
    if (t.kind == MS_T_LBrace) {
        fail(p, t, LIT("blocks are not braced and every fn declares its result type: write the result type, then ':' and an indented body, e.g. fn f() Void: (Void when it returns nothing), and remove the closing '}'"));
        return false;
    }
    if (t.kind == MS_T_Colon || t.kind == MS_T_Newline) {
        if (p->speculative > 0) {
            return false;
        }
        fail(p, t, LIT("every fn declares its result type after the parameter list, e.g. fn f() Void:"));
        return false;
    }
    return typ(p, out);
}

/* Wraps `t` once per trailing suffix: `T?` is Optional[T], `T!` is Result[T, Error], and `T!E`
 * (E directly after the bang) is Result[T, E]. */
MS_NODISCARD static bool type_suffix(Parser *p, MsTypeRef *t, MsTypeRef **out) {
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
                if (!named_type(p, &error)) return false;
            } else {
                MsTypeRefs none = {NULL, 0};
                error = mk_named_type(p, pos, intern(p, "Error"), none);
            }
            name = "Result";
            argv[0] = t;
            argv[1] = error;
            nargs = 2;
        } else {
            *out = t;
            return true;
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

MS_NODISCARD static bool typ_inner(Parser *p, MsTypeRef **out) {
    MsToken first = peek(p);
    if (first.kind == MS_T_Fn) {
        p->at++;
        if (!need(p, MS_T_LParen)) return false;
        MsParams params = {NULL, 0};
        if (!take(p, MS_T_RParen)) {
            size_t m = mark(p);
            uint32_t count = 0;
            for (;;) {
                /* `fn(var List[Int]) Void`: a parameter the function changes in place. */
                bool moving = TAKE_MOVE(p, MS_T_Var, MS_T_Name, MS_T_Fn);
                bool is_mutable = take(p, MS_T_Var);
                if (moving && is_mutable) {
                    fail(p, previous(p), LIT("a parameter is either `move` (the callee takes it) or `var` (the callee changes it in place), not both"));
                    return false;
                }
                MsTypeRef *ty = NULL;
                if (!typ(p, &ty)) return false;
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
            if (!need(p, MS_T_RParen)) return false;
            FINISH_PTRS(p, m, params);
        }
        MsTypeRef *result = NULL;
        if (!typ(p, &result)) return false;
        MsTypeRef *t = NEW(p, MsTypeRef);
        t->id = new_id(p);
        t->pos = first.pos;
        t->kind = MS_TYPE_FN;
        t->params = params;
        t->result = result;
        *out = t;
        return true;
    }
    MsTypeRef *t;
    if (take(p, MS_T_LParen)) {
        if (!typ(p, &t)) return false;
        if (kind(p) == MS_T_Comma && p->speculative == 0) {
            fail(p, peek(p), LIT("Manuscript has no tuples; declare a type with 'type Pair:' and named fields to return several values, or use a List when the items share one type"));
            return false;
        }
        if (!need(p, MS_T_RParen)) return false;
    } else {
        if (!named_type(p, &t)) return false;
    }
    return type_suffix(p, t, out);
}

MS_NODISCARD static bool typ(Parser *p, MsTypeRef **out) {
    if (!enter(p)) return false;
    MsTypeRef *r = NULL;
    if (!typ_inner(p, &r)) return false;
    p->depth--;
    *out = r;
    return true;
}

/* The default of a `T?` parameter or field written without one: `none`. */
static MsExpr *implicit_none(Parser *p, const MsTypeRef *t) {
    if (t->kind != MS_TYPE_NAMED) {
        return NULL;
    }
    if (ms_text_is(ms_name(p->names, t->name), "Optional") && t->args.len == 1) {
        return mk_name(p, t->pos, intern(p, "none"));
    }
    return NULL;
}

MS_NODISCARD static bool type_params(Parser *p, MsTypeParams *out) {
    MsTypeParams result = {NULL, 0};
    if (!take(p, MS_T_LBracket)) {
        *out = result;
        return true;
    }
    size_t m = mark(p);
    for (;;) {
        MsToken name = {0};
        if (!need_token(p, MS_T_Name, &name)) return false;
        MsTypeRefs bounds = {NULL, 0};
        MsTypeRef *def = NULL;
        if (take(p, MS_T_Colon)) {
            size_t bm = mark(p);
            if (!push_named_type(p)) return false;
            while (take(p, MS_T_Amp)) {
                if (!push_named_type(p)) return false;
            }
            FINISH_PTRS(p, bm, bounds);
            if (kind(p) == MS_T_Plus || kind(p) == MS_T_And) {
                fail_fix(p, peek(p), LIT("combine bounds with '&', as in T: Comparable & Clonable"), LIT("&"));
                return false;
            }
        }
        if (take(p, MS_T_Assign)) {
            if (!typ(p, &def)) return false;
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
    if (!need(p, MS_T_RBracket)) return false;
    FINISH_PTRS(p, m, result);
    *out = result;
    return true;
}

/* The colon after a parameter or field name; a missing one is usually a type written directly
 * after the name. */
MS_NODISCARD static bool need_name_colon(Parser *p, MsToken name) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Name && p->speculative == 0) {
        MsToken at = name;
        at.pos = name.end;
        at.end = name.end;
        MsStr n = text(p, name);
        fail_fix(p, at, fmt(p, "expected ':' between '%.*s' and its type; parameters and fields are written name: Type", STR(n)), LIT(":"));
        return false;
    }
    if ((t.kind == MS_T_Comma || t.kind == MS_T_RParen) && p->speculative == 0) {
        MsStr n = text(p, name);
        fail(p, name, fmt(p, "parameter '%.*s' has no type; every parameter is written name: Type, e.g. %.*s: Int", STR(n), STR(n)));
        return false;
    }
    if (!need(p, MS_T_Colon)) return false;
    return true;
}

MS_NODISCARD static bool parameters(Parser *p, bool defaults, bool inferred, MsParams *out) {
    if (!need(p, MS_T_LParen)) return false;
    MsParams params = {NULL, 0};
    if (take(p, MS_T_RParen)) {
        *out = params;
        return true;
    }
    size_t m = mark(p);
    for (;;) {
        bool moving = TAKE_MOVE(p, MS_T_Var, MS_T_Name);
        bool is_mutable = take(p, MS_T_Var);
        if (moving && is_mutable) {
            fail(p, previous(p), LIT("a parameter is either `move` (the callee takes it) or `var` (the callee changes it in place), not both"));
            return false;
        }
        MsToken name = {0};
        if (!need_token(p, MS_T_Name, &name)) return false;
        MsTypeRef *ty = NULL;
        MsExpr *def = NULL;
        if (take(p, MS_T_Colon)) {
            if (kind(p) == MS_T_Var) {
                MsToken t = peek(p);
                MsStr n = text(p, name);
                MsStr rep = fmt(p, "var %.*s:", STR(n));
                fail_fix_range(p, name, t, fmt(p, "'var' goes before the parameter name, not its type; write var %.*s: Type", STR(n)), rep);
                return false;
            }
            if (!typ(p, &ty)) return false;
        } else if (!inferred || kind(p) == MS_T_Name) {
            if (!need_name_colon(p, name)) return false;
        }
        if (take(p, MS_T_Assign)) {
            if (!defaults) {
                fail(p, previous(p), LIT("function types and case payloads cannot have defaults; put the default on a named function parameter or a type field instead"));
                return false;
            }
            if (!expression(p, 0, &def)) return false;
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
    if (!need(p, MS_T_RParen)) return false;
    FINISH_PTRS(p, m, params);
    *out = params;
    return true;
}

/* ---- declarations ---- */

MS_NODISCARD static bool suite(Parser *p, MsStmts *out) {
    return statement_suite(p, false, false, out);
}

MS_NODISCARD static bool method_signature(Parser *p, MsToken name, bool generics, bool body, bool mutating, MsPos var_at, MsMethod **out) {
    MsTypeParams tps = {NULL, 0};
    if (generics) {
        if (!type_params(p, &tps)) return false;
    }
    MsParams params = {0};
    if (!parameters(p, true, false, &params)) return false;
    MsTypeRef *result = NULL;
    if (!result_type(p, &result)) return false;
    MsStmts stmts = {NULL, 0};
    if (body) {
        if (!statement_suite(p, false, true, &stmts)) return false;
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
    *out = m;
    return true;
}

/* The suite after `test "name":` or `bench "name":` (the keyword is consumed). */
MS_NODISCARD static bool single_line(Parser *p, MsToken token, const char *what) {
    MsStr full = text(p, token);
    if ((full.len >= 3 && memcmp(full.ptr, "\"\"\"", 3) == 0) || (full.len >= 4 && memcmp(full.ptr, "r\"\"\"", 4) == 0)) {
        fail(p, token, fmt(p, "%s are one-line text; write them with a single pair of quotes", what));
        return false;
    }
    return true;
}

typedef struct TextParts {
    MsTextPart *ptr;
    uint32_t len;
} TextParts;
MS_NODISCARD static bool text_parts_of(Parser *p, MsToken token, TextParts *out);

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

MS_NODISCARD static bool test_block(Parser *p, bool bench, MsDecl *d) {
    MsToken name = {0};
    if (!need_token(p, MS_T_String, &name)) return false;
    if (!single_line(p, name, bench ? "bench names" : "test names")) return false;
    TextParts parts = {0};
    if (!text_parts_of(p, name, &parts)) return false;
    MsStr plain;
    if (!plain_text(parts, &plain)) {
        if (bench) {
            fail(p, name, LIT("bench names cannot interpolate; use plain text, e.g. bench \"sums a list\":"));
            return false;
        }
        fail(p, name, LIT("test names cannot interpolate; use plain text, e.g. test \"adds numbers\":"));
        return false;
    }
    int64_t per = 1;
    if (bench && kind(p) == MS_T_Name && text_is(p, peek(p), "per")) {
        p->at++;
        MsToken count = {0};
        if (!need_token(p, MS_T_Number, &count)) return false;
        if (!parse_positive_i64(text(p, count), &per)) {
            fail(p, count, LIT("'per' takes a positive whole number of operations, e.g. bench \"sums a list\" per 1000:"));
            return false;
        }
    }
    MsStmts body = {0};
    if (!suite(p, &body)) return false;
    d->kind = MS_D_TEST;
    d->u.test.name = plain;
    d->u.test.body = body;
    d->u.test.bench = bench;
    d->u.test.per = per;
    return true;
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

MS_NODISCARD static bool constant_value(Parser *p, MsPos *init_pos, MsExpr **out) {
    *init_pos = peek(p).pos;
    return expression(p, 0, out);
}

/* Consumes the `:=` of an immutable binding. A leftover `=` after a type annotation gets a fix-it. */
MS_NODISCARD static bool need_immutable_bind(Parser *p) {
    if (kind(p) == MS_T_Assign) {
        fail_fix(p, peek(p), LIT("an immutable binding uses ':=' after its type: write 'x: Type := value'; '=' binds only after 'var'"), LIT(":="));
        return false;
    }
    if (!need(p, MS_T_ColonAssign)) return false;
    return true;
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

/* `type Name = A | B`: an alias for one or several types. */
MS_NODISCARD static bool alias_declaration(Parser *p, MsToken token, MsSym name, MsTypeParams tps, MsDecl **out) {
    size_t m = mark(p);
    if (!push_typ(p)) return false;
    while (take(p, MS_T_Pipe)) {
        if (!push_typ(p)) return false;
    }
    MsTypeRefs targets;
    FINISH_PTRS(p, m, targets);
    if (!end(p)) return false;
    MsDecl *d = new_decl(p, token.pos, MS_D_ALIAS);
    d->u.alias.name = name;
    d->u.alias.type_params = tps;
    d->u.alias.targets = targets;
    *out = d;
    return true;
}

/* `interface Name: ...` or `type Name: ...`: a declaration with no members. */
MS_NODISCARD static bool empty_declaration(Parser *p, MsToken token, MsSym name, MsTypeParams tps, MsDecl **out) {
    if (!end(p)) return false;
    MsDecl *d = new_decl(p, token.pos, token.kind == MS_T_Interface ? MS_D_INTERFACE : MS_D_TYPE);
    if (token.kind == MS_T_Interface) {
        d->u.iface.name = name;
        d->u.iface.type_params = tps;
    } else {
        d->u.type.name = name;
        d->u.type.type_params = tps;
    }
    *out = d;
    return true;
}

/* `move fn` in an interface or type body. */
static bool at_move_fn(const Parser *p) {
    return kind(p) == MS_T_Name && text_is(p, peek(p), "move") && ahead(p, 1).kind == MS_T_Fn;
}

static bool at_enum_variant_start(const Parser *p) {
    MsTok next_kind = (MsTok)ahead(p, 1).kind;
    return kind(p) == MS_T_Name && (next_kind == MS_T_LParen || next_kind == MS_T_Newline ||
                                    next_kind == MS_T_Dedent || next_kind == MS_T_Eof);
}

/* Rejects a member that does not belong in the body of this kind of declaration. */
static bool report_misplaced_member(Parser *p, MsToken token) {
    MsToken prefix;
    if (token.kind == MS_T_Type && (legacy_case_prefix(p, &prefix) || at_enum_variant_start(p))) {
        fail(p, token, LIT("a type declared with 'type' cannot contain enum variants; replace 'type' with 'enum' and remove any legacy 'case' prefixes"));
        return true;
    }
    if (token.kind == MS_T_Enum && legacy_case_prefix(p, &prefix)) {
        fail(p, prefix, LIT("enum variants do not use 'case'; remove the prefix and write 'Name' or 'Name(field: Type)'"));
        return true;
    }
    if (token.kind == MS_T_Enum && kind(p) != MS_T_Name) {
        fail(p, peek(p), LIT("an enum contains only variants; write 'Name' or 'Name(field: Type)', use 'type' for type fields, and put methods in an 'impl' block"));
        return true;
    }
    if (token.kind == MS_T_Interface && !at_move_fn(p) && kind(p) != MS_T_Fn && kind(p) != MS_T_Var) {
        fail(p, peek(p), LIT("an interface contains only operation signatures; write 'fn name(...) Type' and put method bodies in an 'impl' block"));
        return true;
    }
    return false;
}

/* The payload fields of an enum variant, `(field: Type, ...)`. */
MS_NODISCARD static bool variant_payload(Parser *p, MsToken variant, MsParams *payload) {
    if (!parameters(p, false, false, payload)) return false;
    for (uint32_t i = 0; i < payload->len; i++) {
        if (payload->ptr[i]->is_mutable) {
            fail(p, previous(p), LIT("case payload fields cannot be 'var'; mutability belongs to the binding that holds the value"));
            return false;
        }
    }
    if (payload->len == 0) {
        MsStr n = text(p, variant);
        fail(p, variant, fmt(p, "payloadless variants omit parentheses; write '%.*s' instead of '%.*s()'", STR(n), STR(n)));
        return false;
    }
    return true;
}

/* One enum variant, pushed on the scratch stack. */
MS_NODISCARD static bool enum_variant(Parser *p) {
    MsToken cname = {0};
    if (!need_token(p, MS_T_Name, &cname)) return false;
    MsParams payload = {NULL, 0};
    if (kind(p) == MS_T_LParen && !variant_payload(p, cname, &payload)) return false;
    if (kind(p) == MS_T_Colon) {
        fail(p, peek(p), LIT("enum variants have no field or method bodies; write 'Name' or 'Name(field: Type)', use 'type' for type fields, and put methods in an 'impl' block"));
        return false;
    }
    if (kind(p) == MS_T_Assign) {
        fail(p, peek(p), LIT("enum variants cannot have defaults; write 'Name' or 'Name(field: Type)' and supply payload values when constructing a variant"));
        return false;
    }
    MsCase *c = NEW(p, MsCase);
    c->id = new_id(p);
    c->pos = cname.pos;
    c->name = sym(p, cname);
    c->fields = payload;
    push_ptr(p, c);
    return end(p);
}

/* An interface operation `fn name(...) Type`; a `type` body may not hold one. */
MS_NODISCARD static bool member_signature(Parser *p, MsToken token, MsSym name, MsTypeParams tps) {
    bool consuming = TAKE_MOVE(p, MS_T_Fn);
    bool mutating = take(p, MS_T_Var);
    MsToken fn_token = {0};
    if (!need_token(p, MS_T_Fn, &fn_token)) return false;
    if (token.kind == MS_T_Type) {
        MsBuf names = {0};
        type_param_names(p, &names, tps);
        MsStr nt = ms_name(p->names, name);
        MsStr msg = fmt(p, "a type declares only fields; write its methods after it as 'fn %.*s%.*s.name(...)'", STR(nt), (int)names.len, names.data ? names.data : "");
        ms_buf_free(&names);
        fail(p, previous(p), msg);
        return false;
    }
    MsToken mname = {0};
    if (!need_token(p, MS_T_Name, &mname)) return false;
    MsMethod *me = NULL;
    if (!method_signature(p, mname, true, false, mutating, fn_token.pos, &me)) return false;
    me->consuming = consuming;
    if (!end(p)) return false;
    push_ptr(p, me);
    return true;
}

/* One `name: Type [= default]` field of a type, pushed on the scratch stack. */
MS_NODISCARD static bool type_field(Parser *p) {
    MsToken fname = {0};
    if (!need_token(p, MS_T_Name, &fname)) return false;
    if (!need_name_colon(p, fname)) return false;
    MsTypeRef *ty = NULL;
    if (!typ(p, &ty)) return false;
    MsExpr *def = NULL;
    if (take(p, MS_T_Assign)) {
        if (!expression(p, 0, &def)) return false;
    } else {
        def = implicit_none(p, ty);
    }
    push_ptr(p, mk_param(p, fname.pos, sym(p, fname), ty, def, false, false));
    return end(p);
}

/* One member of the indented body, pushed on the scratch stack. */
MS_NODISCARD static bool declaration_member(Parser *p, MsToken token, MsSym name, MsTypeParams tps) {
    if (report_misplaced_member(p, token)) {
        return false;
    }
    if (token.kind == MS_T_Enum) {
        return enum_variant(p);
    }
    bool starts_signature = kind(p) == MS_T_Fn || at_move_fn(p) || (kind(p) == MS_T_Var && ahead(p, 1).kind == MS_T_Fn);
    return starts_signature ? member_signature(p, token, name, tps) : type_field(p);
}

/* The declaration of `token`'s kind built from the collected members. */
MS_NODISCARD static bool finish_declaration(Parser *p, MsToken token, MsSym name, MsTypeParams tps, void **items,
                                            uint32_t count, MsDecl **out) {
    if (token.kind == MS_T_Interface && count == 0) {
        fail(p, token, LIT("declaration body cannot be empty; an interface needs at least one 'fn name(...) Type' operation"));
        return false;
    }
    if (token.kind == MS_T_Enum && count == 0) {
        fail(p, token, LIT("an enum must declare at least one variant; add 'Name' or 'Name(field: Type)'"));
        return false;
    }
    MsDecl *d = NULL;
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
    *out = d;
    return true;
}

/* The header of a declaration with members, through its indent; false after reporting a problem. */
MS_NODISCARD static bool declaration_body_start(Parser *p, MsToken token) {
    if (token.kind == MS_T_Enum && kind(p) == MS_T_Ellipsis) {
        fail(p, peek(p), LIT("an enum must declare at least one variant; replace '...' with 'Name' or 'Name(field: Type)'"));
        return false;
    }
    if (!need(p, MS_T_Newline)) return false;
    if (token.kind == MS_T_Enum && kind(p) != MS_T_Indent) {
        fail(p, peek(p), LIT("an enum must declare at least one variant; indent 'Name' or 'Name(field: Type)' under the header"));
        return false;
    }
    return need(p, MS_T_Indent);
}

MS_NODISCARD static bool type_declaration(Parser *p, MsToken token, MsDecl **out) {
    p->at++;
    MsToken name_tok = {0};
    if (!need_token(p, MS_T_Name, &name_tok)) return false;
    MsSym name = sym(p, name_tok);
    MsTypeParams tps = {0};
    if (!type_params(p, &tps)) return false;
    if (token.kind == MS_T_Type && take(p, MS_T_Assign)) {
        return alias_declaration(p, token, name, tps, out);
    }
    if (!need(p, MS_T_Colon)) return false;
    bool no_members = (token.kind == MS_T_Interface || token.kind == MS_T_Type) && take(p, MS_T_Ellipsis);
    if (no_members) {
        return empty_declaration(p, token, name, tps, out);
    }
    if (!declaration_body_start(p, token)) return false;
    /* Only one of fields, cases and methods is ever collected for a given declaration kind. */
    size_t m = mark(p);
    while (kind(p) != MS_T_Dedent) {
        newlines(p);
        if (kind(p) == MS_T_Dedent) {
            break;
        }
        if (!declaration_member(p, token, name, tps)) return false;
    }
    if (!need(p, MS_T_Dedent)) return false;
    uint32_t count = 0;
    void **items = finish(p, m, &count, sizeof(void *), _Alignof(void *));
    return finish_declaration(p, token, name, tps, items, count, out);
}

/* The type parameters that stand for the receiver's own arguments in `fn Type[T: Bound].m()`. */
MS_NODISCARD static bool receiver_arguments(Parser *p, MsTypeParams *bounds, MsTypeRefs *args) {
    bool bounded = kind(p) == MS_T_LBracket && ahead(p, 1).kind == MS_T_Name && ahead(p, 2).kind == MS_T_Colon;
    if (!bounded) {
        return !take(p, MS_T_LBracket) || type_args(p, args);
    }
    if (!type_params(p, bounds)) return false;
    args->ptr = MS_NEW_N(p->arena, MsTypeRef *, bounds->len ? bounds->len : 1);
    args->len = bounds->len;
    for (uint32_t i = 0; i < bounds->len; i++) {
        MsTypeRefs none = {NULL, 0};
        args->ptr[i] = mk_named_type(p, bounds->ptr[i]->pos, bounds->ptr[i]->name, none);
    }
    return true;
}

/* `fn [var] Type[T].name(...)`: one method of `Type`. */
MS_NODISCARD static bool method_declaration(Parser *p, MsToken token, MsDecl **out) {
    p->at++;
    bool consuming = TAKE_MOVE(p, MS_T_Var, MS_T_Name);
    bool mutating = take(p, MS_T_Var);
    if (consuming && mutating) {
        fail(p, previous(p), LIT("a method either takes its receiver with `move` or changes it with `var`, not both"));
        return false;
    }
    MsToken receiver_name = {0};
    if (!need_token(p, MS_T_Name, &receiver_name)) return false;
    MsTypeParams bounds = {NULL, 0};
    MsTypeRefs args = {NULL, 0};
    if (!receiver_arguments(p, &bounds, &args)) return false;
    MsTypeRef *receiver = mk_named_type(p, receiver_name.pos, sym(p, receiver_name), args);
    if (!need(p, MS_T_Dot)) return false;
    MsToken name = {0};
    if (!need_token(p, MS_T_Name, &name)) return false;
    MsMethod *method = NULL;
    if (!method_signature(p, name, true, true, mutating, receiver_name.pos, &method)) return false;
    method->consuming = consuming;
    method->receiver_args = args;
    /* The Rust parser allocates the declaration's id after the method's. */
    MsDecl *d = new_decl(p, token.pos, MS_D_IMPL);
    d->u.impl.receiver = receiver;
    d->u.impl.bounds = bounds;
    d->u.impl.methods.ptr = MS_NEW_N(p->arena, MsMethod *, 1);
    d->u.impl.methods.ptr[0] = method;
    d->u.impl.methods.len = 1;
    *out = d;
    return true;
}

MS_NODISCARD static bool fn_declaration(Parser *p, MsToken token, MsDecl **out) {
    p->at++;
    if (kind(p) == MS_T_Var && ahead(p, 1).kind == MS_T_Name) {
        fail(p, peek(p), LIT("'fn var' marks a method that changes its receiver, as in 'fn var Counter.add(n: Int) Void:'; a free function takes 'var' on the parameter instead: 'fn add(var counter: Counter, n: Int) Void:'"));
        return false;
    }
    MsToken name = {0};
    if (!need_token(p, MS_T_Name, &name)) return false;
    MsTypeParams tps = {0};
    if (!type_params(p, &tps)) return false;
    MsParams params = {0};
    if (!parameters(p, true, false, &params)) return false;
    MsTypeRef *result = NULL;
    if (!result_type(p, &result)) return false;
    MsStmts body = {0};
    if (!statement_suite(p, false, true, &body)) return false;
    MsDecl *d = new_decl(p, token.pos, MS_D_FN);
    d->u.fn.name = sym(p, name);
    d->u.fn.type_params = tps;
    d->u.fn.params = params;
    d->u.fn.result = result;
    d->u.fn.body = body;
    *out = d;
    return true;
}

/* `extern type Name[T]` is a runtime-backed type; a ':' body gives it the fields a constructor takes,
 * as a `type` does (`extern type List[T]:` with its `reserve` field). */
MS_NODISCARD static bool extern_type_declaration(Parser *p, MsToken token, MsDecl **out) {
    const size_t keyword = p->at + 1;
    p->at += 2;
    MsToken name_tok = {0};
    if (!need_token(p, MS_T_Name, &name_tok)) return false;
    MsSym name = sym(p, name_tok);
    MsTypeParams tps = {0};
    if (!type_params(p, &tps)) return false;
    if (kind(p) == MS_T_Colon) {
        p->at = keyword;
        if (!type_declaration(p, peek(p), out)) return false;
        (*out)->pos = token.pos; /* the declaration starts at `extern`, where its comment sits above */
        (*out)->u.type.external = true;
        return true;
    }
    if (!end(p)) return false;
    MsDecl *d = new_decl(p, token.pos, MS_D_TYPE);
    d->u.type.name = name;
    d->u.type.type_params = tps;
    d->u.type.external = true;
    *out = d;
    return true;
}

MS_NODISCARD static bool extern_fn_declaration(Parser *p, MsToken token, MsDecl **out) {
    p->at++;
    if (!need(p, MS_T_Fn)) return false;
    MsToken name = {0};
    if (!need_token(p, MS_T_Name, &name)) return false;
    MsTypeParams tps = {0};
    if (!type_params(p, &tps)) return false;
    MsParams params = {0};
    if (!parameters(p, true, false, &params)) return false;
    MsTypeRef *result = NULL;
    if (!result_type(p, &result)) return false;
    if (kind(p) == MS_T_Colon) {
        fail(p, peek(p), LIT("an extern fn has no body; remove the ':'"));
        return false;
    }
    if (!end(p)) return false;
    MsDecl *d = new_decl(p, token.pos, MS_D_FN);
    d->u.fn.name = sym(p, name);
    d->u.fn.type_params = tps;
    d->u.fn.params = params;
    d->u.fn.result = result;
    d->u.fn.external = true;
    *out = d;
    return true;
}

/* `NAME := value` or `NAME: Type := value` at module level. */
MS_NODISCARD static bool constant_declaration(Parser *p, MsToken token, MsDecl **out) {
    MsToken name = {0};
    if (!need_token(p, MS_T_Name, &name)) return false;
    MsTypeRef *ty = NULL;
    if (take(p, MS_T_Colon)) {
        if (!typ(p, &ty)) return false;
    }
    if (!need_immutable_bind(p)) return false;
    MsPos init_pos = {0};
    MsExpr *value = NULL;
    if (!constant_value(p, &init_pos, &value)) return false;
    if (!end(p)) return false;
    MsDecl *d = new_decl(p, token.pos, MS_D_CONST);
    d->u.konst.name = sym(p, name);
    d->u.konst.ty = ty;
    d->u.konst.value = value;
    d->u.konst.init_pos = init_pos;
    *out = d;
    return true;
}

MS_NODISCARD static bool test_declaration(Parser *p, MsToken token, bool bench, MsDecl **out) {
    p->at++;
    MsDecl block = {0};
    if (!test_block(p, bench, &block)) return false;
    MsDecl *d = new_decl(p, token.pos, MS_D_TEST);
    d->u = block.u;
    *out = d;
    return true;
}

/* `opaque type` and `opaque enum`: the declaration after the modifier, marked opaque. */
MS_NODISCARD static bool opaque_declaration(Parser *p, MsToken token, MsDecl **out) {
    p->at++;
    MsDecl *decl = NULL;
    if (!type_declaration(p, peek(p), &decl)) return false;
    decl->pos = token.pos;
    if (decl->kind == MS_D_TYPE) {
        decl->u.type.opaque = true;
    } else if (decl->kind == MS_D_ENUM) {
        decl->u.enumeration.opaque = true;
    }
    *out = decl;
    return true;
}

/* A declaration keyword from another language, with the rewrite when there is one. */
static void report_foreign_declaration(Parser *p, MsToken token, MsStr message, const char *replacement) {
    MsStr word = text(p, token);
    if (replacement == NULL && (ms_text_is(word, "const") || ms_text_is(word, "val") || ms_text_is(word, "final"))) {
        MsToken first, last;
        MsStr rewrite;
        if (constant_fix(p, token, &first, &last, &rewrite)) {
            fail_fix_range(p, first, last, message, rewrite);
            return;
        }
    }
    if (replacement != NULL) {
        fail_fix(p, token, message, (MsStr){replacement, (uint32_t)strlen(replacement)});
        return;
    }
    fail(p, token, message);
}

static void report_misplaced_opaque(Parser *p, MsToken token) {
    MsStr advice = LIT("'opaque' applies only to a type or enum; write 'opaque type Name:' or 'opaque enum Name:', optionally after 'export'");
    if (ahead(p, 1).kind == MS_T_Export) {
        const char *kw = ahead(p, 2).kind == MS_T_Enum ? "enum" : "type";
        advice = fmt(p, "write 'export opaque %s Name:', with export first", kw);
    }
    fail(p, token, fmt(p, "misplaced 'opaque'; %.*s", STR(advice)));
}

/* Reports why `token` cannot start a module declaration. */
static void report_bad_declaration(Parser *p, MsToken token) {
    MsTok k = (MsTok)token.kind;
    if (k == MS_T_Impl) {
        fail(p, token, LIT(IMPL_REMOVED));
        return;
    }
    if (k == MS_T_Var && ahead(p, 1).kind == MS_T_Fn) {
        /* `var fn T.m()` is the receiver-changing method spelled in the wrong order. */
        fail_fix_range(p, token, ahead(p, 1), LIT("a method that changes its receiver is written fn var Type.name(), with var after fn"), LIT("fn var"));
        return;
    }
    MsStr message;
    const char *replacement;
    if (foreign_declaration(p, token, &message, &replacement)) {
        report_foreign_declaration(p, token, message, replacement);
        return;
    }
    if (k == MS_T_Export) {
        fail_fix(p, token, LIT("'export' appears twice; write it once before the declaration"), LIT(""));
        return;
    }
    if (k == MS_T_Name && text_is(p, token, "opaque")) {
        report_misplaced_opaque(p, token);
        return;
    }
    MsStr found = describe(p, token);
    fail(p, token, fmt(p, "expected a module declaration or import, found %.*s; top level holds only import, constants (NAME := value), fn, type, enum, interface, impl, and test (optionally prefixed by export), so put statements inside a fn", STR(found)));
}

MS_NODISCARD static bool declaration(Parser *p, MsDecl **out) {
    MsToken token = peek(p);
    MsTok k = (MsTok)token.kind;
    MsTok next_kind = (MsTok)ahead(p, 1).kind;
    if (k == MS_T_Fn) {
        return receiver_method_ahead(p) ? method_declaration(p, token, out) : fn_declaration(p, token, out);
    }
    if (k == MS_T_Extern) {
        return next_kind == MS_T_Type ? extern_type_declaration(p, token, out) : extern_fn_declaration(p, token, out);
    }
    if (k == MS_T_Name && (next_kind == MS_T_ColonAssign || next_kind == MS_T_Colon)) {
        return constant_declaration(p, token, out);
    }
    if (k == MS_T_Test) {
        return test_declaration(p, token, false, out);
    }
    if (k == MS_T_Name && text_is(p, token, "bench") && next_kind == MS_T_String) {
        return test_declaration(p, token, true, out);
    }
    if (k == MS_T_Type || k == MS_T_Enum || k == MS_T_Interface) {
        return type_declaration(p, token, out);
    }
    if (k == MS_T_Name && text_is(p, token, "opaque") && (next_kind == MS_T_Type || next_kind == MS_T_Enum)) {
        return opaque_declaration(p, token, out);
    }
    report_bad_declaration(p, token);
    return false;
}

/* ---- patterns ---- */

static MsPattern *new_pattern(Parser *p, MsPos pos, MsPatternKind k) {
    MsPattern *pt = NEW(p, MsPattern);
    pt->id = new_id(p);
    pt->pos = pos;
    pt->kind = (uint8_t)k;
    return pt;
}

MS_NODISCARD static bool pattern_inner(Parser *p, MsPattern **out) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Void) {
        fail(p, t, LIT("void is a reserved value keyword, not a binding name; choose another name such as code_unit, and use void for the Void value"));
        return false;
    }
    if (take(p, MS_T_Name)) {
        MsPattern *pt = new_pattern(p, t.pos, MS_P_NAME);
        pt->u.name = sym(p, t);
        *out = pt;
        return true;
    }
    /* `_` binds a value nothing reads, such as a `Result` ignored on purpose. */
    if (take(p, MS_T_Underscore)) {
        MsPattern *pt = new_pattern(p, t.pos, MS_P_NAME);
        pt->u.name = intern(p, "_");
        *out = pt;
        return true;
    }
    if (take(p, MS_T_LBracket)) {
        MsPatterns elements = {NULL, 0};
        if (!take(p, MS_T_RBracket)) {
            size_t m = mark(p);
            for (;;) {
                if (!push_pattern(p)) return false;
                if (!take(p, MS_T_Comma)) {
                    break;
                }
                if (kind(p) == MS_T_RBracket) {
                    break;
                }
            }
            if (!need(p, MS_T_RBracket)) return false;
            FINISH_PTRS(p, m, elements);
        }
        MsPattern *pt = new_pattern(p, t.pos, MS_P_LIST);
        pt->u.list = elements;
        *out = pt;
        return true;
    }
    if (take(p, MS_T_LBrace)) {
        size_t m = mark(p);
        for (;;) {
            MsToken name = {0};
            if (!need_token(p, MS_T_Name, &name)) return false;
            MsPattern *child;
            if (take(p, MS_T_Colon)) {
                if (!pattern(p, &child)) return false;
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
        if (!need(p, MS_T_RBrace)) return false;
        MsPattern *pt = NULL;
        uint32_t n;
        MsPatternField *fields = finish(p, m, &n, sizeof(MsPatternField), _Alignof(MsPatternField));
        pt = new_pattern(p, t.pos, MS_P_TYPE);
        pt->u.fields.ptr = fields;
        pt->u.fields.len = n;
        *out = pt;
        return true;
    }
    MsStr dt = describe(p, t);
    fail(p, t, fmt(p, "expected a binding name, list pattern, or type pattern, found %.*s; write a name, [a, b], or {x, y}", STR(dt)));
    return false;
}

MS_NODISCARD static bool pattern(Parser *p, MsPattern **out) {
    if (!enter(p)) return false;
    MsPattern *r = NULL;
    if (!pattern_inner(p, &r)) return false;
    p->depth--;
    *out = r;
    return true;
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
MS_NODISCARD static bool binding(Parser *p, bool is_mutable, const MsPos *group, MsPos pos, MsStmt **out) {
    MsPattern *pat = NULL;
    if (!pattern(p, &pat)) return false;
    MsTypeRef *ty = NULL;
    bool named = pat->kind == MS_P_NAME;
    if (is_mutable) {
        if (named && take(p, MS_T_Colon)) {
            if (!typ(p, &ty)) return false;
        }
        if (kind(p) == MS_T_ColonAssign) {
            fail_fix(p, peek(p), LIT("'var' binds with '=': write 'var x = value'; ':=' declares an immutable binding"), LIT("="));
            return false;
        }
        if (!need(p, MS_T_Assign)) return false;
    } else {
        if (named && take(p, MS_T_Colon)) {
            if (!typ(p, &ty)) return false;
        }
        if (!need_immutable_bind(p)) return false;
    }
    MsExpr *value = NULL;
    if (!expression(p, 0, &value)) return false;
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
    *out = finish_stmt(p, &st);
    return true;
}

/* The `( ... )` after a consumed `var`. The lexer ends each line of the group with a newline. */
MS_NODISCARD static bool binding_group(Parser *p, MsToken keyword, MsStmts *out) {
    uint32_t indent = keyword.pos.column;
    long i = (long)p->at - 2;
    while (i >= 0 && p->tokens[i].pos.line == keyword.pos.line && p->tokens[i].kind != MS_T_Newline) {
        indent = p->tokens[i].pos.column;
        i--;
    }
    const char *kw = ms_tok_str((MsTok)keyword.kind);
    if (p->inline_statement) {
        fail(p, peek(p), fmt(p, "a binding group needs its own lines; put '%s (' on a line of its own with one binding per indented line, or write single '%s name = value' bindings", kw, kw));
        return false;
    }
    if (!need(p, MS_T_LParen)) return false;
    if (kind(p) != MS_T_Newline) {
        fail(p, peek(p), fmt(p, "a binding group starts its entries on the next line; write '%s (' then one 'name = value' per indented line, or destructure with '%s [a, b] = value' or '%s {x, y} = value'", kw, kw, kw));
        return false;
    }
    next(p);
    size_t m = mark(p);
    uint32_t count = 0;
    for (;;) {
        newlines(p);
        MsToken t = peek(p);
        if (t.kind == MS_T_RParen) {
            if (t.pos.column != indent) {
                fail(p, t, fmt(p, "the closing ')' of a binding group aligns with its '%s' line, at column %u", kw, indent));
                return false;
            }
            break;
        }
        if (t.kind == MS_T_Eof) {
            if (!need(p, MS_T_RParen)) return false;
        } else if (t.pos.column != indent + 4) {
            fail(p, t, fmt(p, "binding group entries are indented four spaces past the '%s' line, to column %u", kw, indent + 4));
            return false;
        }
        MsPos epos = peek(p).pos;
        if (!push_binding(p, true, &keyword.pos, epos)) return false;
        count++;
        if (kind(p) == MS_T_Comma) {
            fail(p, peek(p), fmt(p, "a binding group holds one 'name = value' per line, not a comma list; to destructure write '%s [a, b] = value' or '%s {x, y} = value'", kw, kw));
            return false;
        }
        /* A block lambda value ends at its dedent, which also ends the line. */
        if (previous(p).kind != MS_T_Dedent) {
            if (!need(p, MS_T_Newline)) return false;
        }
    }
    if (count == 0) {
        fail(p, peek(p), LIT("a binding group cannot be empty; add 'name = value' lines or remove the group"));
        return false;
    }
    if (!need(p, MS_T_RParen)) return false;
    if (!end(p)) return false;
    MsStmts result;
    FINISH_PTRS(p, m, result);
    *out = result;
    return true;
}

/* Parses one statement, plus the rest of its bindings for a group, onto the open scratch list. */
MS_NODISCARD static bool statements(Parser *p, bool allow_value) {
    MsStmt *s = NULL;
    if (!statement(p, allow_value, &s)) return false;
    push_ptr(p, s);
    for (uint32_t i = 0; i < p->nqueued; i++) {
        push_ptr(p, p->queued[i]);
    }
    p->queued = NULL;
    p->nqueued = 0;
    return true;
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

bool ms_plain_index_target(const MsExpr *left, const MsExpr *index) {
    return plain_chain(left) && plain_index(index);
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

bool ms_is_index_store(const MsNames *names, const MsExpr *call) {
    const MsExpr *callee = call->u.call.callee;
    if (callee->kind != MS_E_MEMBER) {
        return false;
    }
    const MsStr name = ms_name(names, callee->u.member.name);
    return name.len == strlen(MS_INDEX_SET) && memcmp(name.ptr, MS_INDEX_SET, name.len) == 0;
}

/* `xs[i] = value` (the receiver `left` and `index` of the target at `pos`) as the call of the member `[]=`. With `reread`, the value reads the same
 * element, so a name or field key is cloned for the store. */
static MsExpr *index_set(Parser *p, MsPos pos, MsExpr *left, MsExpr *index, MsExpr *value, bool reread) {
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

MS_NODISCARD static bool assign_target(Parser *p, MsToken start, MsExpr *e, MsStmt *st) {
    if (e->kind == MS_E_NAME) {
        MsStr n = ms_name(p->names, e->u.sym);
        if (!ms_text_is(n, "self") && !ms_text_is(n, "fixture")) {
            st->u.assign.member_target = false;
            st->u.assign.name = e->u.sym;
            return true;
        }
    } else if (e->kind == MS_E_MEMBER) {
        st->u.assign.member_target = true;
        st->u.assign.target = e;
        return true;
    }
    fail(p, start, LIT("assignment requires a local binding name or type field; the left side of '=' must be a name or a.field; to change a collection element, write xs[index] = value on a List or m[key] = value on a Map"));
    return false;
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
MS_NODISCARD static bool compound(Parser *p, MsToken start, MsExpr *e, MsStmt *st) {
    MsToken op = peek(p);
    MsToken equal = ahead(p, 1);
    bool plain = plain_chain(e);
    MsExpr *copy = plain ? clone_chain(p, e) : NULL;
    MsExpr *l = NULL, *ix = NULL;
    MsBinaryOp bop;
    if (copy != NULL && ms_expr_index(e, &l, &ix)) {
        p->at += 2;
        arith_op((MsTok)op.kind, &bop);
        MsExpr *right = NULL;
        if (!expression(p, 0, &right)) return false;
        MsExpr *value = mk_binary_at(p, op, bop, copy, right);
        st->kind = MS_S_CALL;
        st->u.expr = index_set(p, e->pos, l, ix, value, true);
        return true;
    }
    if (!assign_target(p, start, e, st)) return false;
    if (copy == NULL) {
        MsDiag *d = parse_diag(p, op.pos,
            fmt(p, "compound assignment '%s=' needs a name or a.field target whose receiver is names only; bind the receiver to a name first, or write the assignment out",
                ms_tok_str((MsTok)op.kind)));
        d->has_end = true;
        d->end = equal.end;
        return false;
    }
    p->at += 2;
    arith_op((MsTok)op.kind, &bop);
    MsExpr *right = NULL;
    if (!expression(p, 0, &right)) return false;
    MsExpr *value = mk_binary_at(p, op, bop, copy, right);
    st->kind = MS_S_ASSIGN;
    st->u.assign.has_compound = true;
    st->u.assign.compound = (uint8_t)bop;
    st->u.assign.value = value;
    return true;
}

#define IS(s) ms_text_is(n, s)
/* A name that is a keyword in another language, written as a statement: reports how to say it in
 * Manuscript and returns true. */
static bool report_foreign_keyword(Parser *p, MsToken t, MsStr n) {
    if (IS("assert")) {
        fail(p, t, LIT("there is no 'assert': in a test block write 'expect_equal(actual, expected)?' or 'expect_true(condition)?', imported from \"@std/test/test.ms\""));
        return true;
    }
    if (IS("pass")) {
        fail_fix(p, t, LIT("'pass' is not a keyword; write 'void' for an empty block or match arm"), LIT("void"));
        return true;
    }
    if (IS("const") || IS("val") || IS("final")) {
        fail(p, t, fmt(p, "'%.*s' is not a keyword; write 'name := ...' for a binding that is not reassigned, or 'var name = ...' when it changes", STR(n)));
        return true;
    }
    if (IS("throw") || IS("raise") || IS("catch")) {
        fail(p, t, fmt(p, "'%.*s' is not a keyword; failures are values; return error(...) from a fn returning T!, propagate a Result with 'call()?', or handle it with 'if value := result:' and an else branch", STR(n)));
        return true;
    }
    if (IS("elseif")) {
        fail(p, t, LIT("'elseif' is not a keyword; write 'else if <condition>:' for a further branch"));
        return true;
    }
    if (IS("elif")) {
        fail(p, t, LIT("there is no 'elif': write 'else if <condition>:' for a further branch"));
        return true;
    }
    if (IS("def")) {
        fail(p, t, LIT("there is no 'def': declare a function with 'fn name(a: Int) Int:'"));
        return true;
    }
    if (IS("switch")) {
        fail(p, t, LIT("'switch' is not a keyword; write 'match value:' with one arm per case of your own type, or 'if x == a:' with 'else if' for plain values"));
        return true;
    }
    if (IS("except") || IS("finally")) {
        fail(p, t, fmt(p, "'%.*s' is not a keyword; failures are values; return error(...) from a fn returning T!, propagate a Result with 'call()?', or handle it with 'if value := result:' and an else branch", STR(n)));
        return true;
    }
    if (IS("loop")) {
        fail(p, t, LIT("'loop' is not a keyword; write 'while true:' and leave it with 'break'"));
        return true;
    }
    if (IS("foreach")) {
        fail(p, t, LIT("'foreach' is not a keyword; write 'for item in items:'"));
        return true;
    }
    if (IS("class")) {
        fail(p, t, LIT("'class' is not a keyword inside a fn; declare a type with 'type Name:' at module level"));
        return true;
    }
    if (IS("del")) {
        fail(p, t, LIT("'del' is not a keyword; remove from a collection with its methods, such as xs.remove(i) or m.remove(key)"));
        return true;
    }
    if (IS("global") || IS("nonlocal")) {
        fail(p, t, fmt(p, "'%.*s' is not a keyword; a fn sees module constants directly, and mutable state lives in a 'var' or a field passed explicitly", STR(n)));
        return true;
    }
    if (IS("yield")) {
        fail(p, t, LIT("'yield' is not a keyword; there are no generators, so build a list and return it"));
        return true;
    }
    if (IS("async") || IS("await")) {
        fail(p, t, fmt(p, "'%.*s' is not a keyword; call the function directly, or start concurrent work with promise(fn: ...) from \"@std/concurrency/promise.ms\"", STR(n)));
        return true;
    }
    if (IS("go")) {
        fail(p, t, LIT("'go' is not a keyword; start concurrent work with promise(fn: ...) from \"@std/concurrency/promise.ms\": result := promise(fn: work()), then result.wait()"));
        return true;
    }
    return false;
}
#undef IS

/* An expression that is not a call, written as a statement where only calls may stand alone. */
static void report_standalone_expression(Parser *p, MsToken t, const MsExpr *e) {
    if (e->kind == MS_E_NAME && report_foreign_keyword(p, t, ms_name(p->names, e->u.sym))) {
        return;
    }
    if (kind(p) == MS_T_Comma) {
        fail(p, t, LIT("a statement cannot start with a comma-separated list of names: write one binding per line ('a := f()'), or destructure one value with '[a, b] := value'"));
        return;
    }
    fail(p, t, LIT("only a call, a call followed by '?', or match can be a standalone expression statement; use 'name := ...' to keep the value, 'return' to return it, or call a function"));
}

/* `target = value`; an index target becomes the call that sets the element. */
MS_NODISCARD static bool assignment_statement(Parser *p, MsToken t, MsExpr *e, MsStmt *st) {
    MsExpr *left = NULL, *index = NULL;
    MsExpr *value = NULL;
    if (ms_expr_index(e, &left, &index)) {
        if (!expression(p, 0, &value)) return false;
        st->kind = MS_S_CALL;
        st->u.expr = index_set(p, e->pos, left, index, value, false);
        return true;
    }
    if (!assign_target(p, t, e, st)) return false;
    if (!expression(p, 0, &value)) return false;
    st->kind = MS_S_ASSIGN;
    st->u.assign.value = value;
    return true;
}

MS_NODISCARD static bool expression_statement(Parser *p, MsToken t, bool allow_value, MsStmt *st) {
    MsExpr *e = NULL;
    if (!expression(p, 0, &e)) return false;
    if (compound_assignment(p)) {
        if (!compound(p, t, e, st)) return false;
    } else if (take(p, MS_T_Assign)) {
        if (!assignment_statement(p, t, e, st)) return false;
    } else {
        bool try_call = e->kind == MS_E_UNARY && e->op == MS_U_TRY && e->u.bin.left->kind == MS_E_CALL;
        bool is_call = e->kind == MS_E_CALL || e->kind == MS_E_MATCH || e->kind == MS_E_VOID;
        if (!p->inline_return && !is_call && !try_call && !allow_value) {
            report_standalone_expression(p, t, e);
            return false;
        }
        st->kind = p->inline_return ? MS_S_RETURN : MS_S_CALL;
        st->u.expr = e;
    }
    return end(p);
}

/* The statement parsers below each take the statement's first token and a statement `st` that
 * already holds its position. They set *out to the finished statement, or leave it NULL when the
 * tokens are not their statement, so the caller tries the next one. */

static bool ends_expression(MsTok k) {
    return k == MS_T_Newline || k == MS_T_Indent || k == MS_T_Dedent || k == MS_T_Eof ||
           k == MS_T_Comma || k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace;
}

/* `void call()` runs the call and drops its result on purpose: the `_ := call()` binding. */
MS_NODISCARD static bool void_statement(Parser *p, MsToken t, MsStmt **out) {
    if (ends_expression((MsTok)ahead(p, 1).kind)) {
        return true;
    }
    p->at++;
    MsExpr *value = NULL;
    if (!expression(p, 0, &value)) return false;
    if (!end(p)) return false;
    MsStmt *s = NEW(p, MsStmt);
    s->id = new_id(p);
    uint32_t pattern_id = new_id(p);
    s->pos = t.pos;
    s->kind = MS_S_BIND;
    MsPattern *pt = NEW(p, MsPattern);
    pt->id = pattern_id;
    pt->pos = t.pos;
    pt->kind = MS_P_NAME;
    pt->u.name = intern(p, "_");
    s->u.bind.pattern = pt;
    s->u.bind.value = value;
    *out = s;
    return true;
}

static bool starts_binding_target(MsTok k) {
    return k == MS_T_Name || k == MS_T_Underscore || k == MS_T_LBracket || k == MS_T_LBrace;
}

/* Reports the removed `let`, which is the current token, with the rewrite that replaces it;
 * `first` is where the diagnostic points. */
static void report_removed_let(Parser *p, MsToken first, MsStr message) {
    MsToken name = ahead(p, 1), eq = ahead(p, 2);
    if (name.kind == MS_T_Name && eq.kind == MS_T_Assign) {
        MsStr n = text(p, name);
        fail_fix_range(p, first, eq, message, fmt(p, "%.*s :=", STR(n)));
        return;
    }
    fail(p, first, message);
}

/* Syntax from other languages that was removed: `_ := v` and `let`. Returns true when it
 * reported one. */
static bool report_removed_binding(Parser *p, MsToken t) {
    if (t.kind == MS_T_Underscore && ahead(p, 1).kind == MS_T_ColonAssign) {
        fail_fix_range(p, t, ahead(p, 1), LIT("'_ := value' was removed; write 'void value' to run an expression and drop its result on purpose"), LIT("void"));
        return true;
    }
    if (t.kind == MS_T_Name && text_is(p, t, "let") && starts_binding_target((MsTok)ahead(p, 1).kind)) {
        report_removed_let(p, t, LIT("'let' was removed; bind with 'x := value' (or 'x: Type := value'), destructure with '[a, b] := value', and use 'var x = value' for a mutable binding"));
        return true;
    }
    return false;
}

MS_NODISCARD static bool var_statement(Parser *p, MsToken t, MsPos pos, MsStmt **out) {
    p->at++;
    if (kind(p) == MS_T_LParen) {
        MsStmts entries = {0};
        if (!binding_group(p, t, &entries)) return false;
        p->nqueued = entries.len - 1;
        p->queued = entries.ptr + 1;
        *out = entries.ptr[0];
        return true;
    }
    MsStmt *s = NULL;
    if (!binding(p, true, NULL, pos, &s)) return false;
    if (!end(p)) return false;
    *out = s;
    return true;
}

/* `fn name(...) Result:` inside a body binds a lambda to the name. */
MS_NODISCARD static bool local_fn_statement(Parser *p, MsToken t, MsStmt *st, MsStmt **out) {
    if (!(ahead(p, 1).kind == MS_T_Name && (ahead(p, 2).kind == MS_T_LParen || ahead(p, 2).kind == MS_T_LBracket))) {
        return true;
    }
    p->at++;
    MsToken name = {0};
    if (!need_token(p, MS_T_Name, &name)) return false;
    if (kind(p) == MS_T_LBracket) {
        fail(p, peek(p), LIT("a local fn cannot take type parameters; declare a generic function at module level"));
        return false;
    }
    MsParams params = {0};
    if (!parameters(p, true, false, &params)) return false;
    MsTypeRef *result = NULL;
    if (!result_type(p, &result)) return false;
    MsStmts body = {0};
    if (!statement_suite(p, true, false, &body)) return false;
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
    st->kind = MS_S_BIND;
    st->u.bind.pattern = pt;
    st->u.bind.value = value;
    *out = finish_stmt(p, st);
    return true;
}

MS_NODISCARD static bool return_statement(Parser *p, MsStmt *st, MsStmt **out) {
    p->at++;
    MsExpr *value = NULL;
    MsTok k = kind(p);
    bool closes_inline = p->inline_statement && (k == MS_T_Comma || k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace);
    if (k != MS_T_Newline && !closes_inline) {
        if (!expression(p, 0, &value)) return false;
    }
    if (!end(p)) return false;
    st->kind = MS_S_RETURN;
    st->u.expr = value;
    *out = finish_stmt(p, st);
    return true;
}

/* The binding of `if value := optional:` or `if var value = optional:`; none when absent. */
MS_NODISCARD static bool if_binding(Parser *p, MsToken t, MsPattern **bind, bool *is_mutable) {
    if (kind(p) == MS_T_Name && text_is(p, peek(p), "let") && starts_binding_target((MsTok)ahead(p, 1).kind)) {
        report_removed_let(p, peek(p), LIT("'if let' was removed; write 'if value := optional:' (or 'if var value = optional:' for a mutable binding)"));
        return false;
    }
    bool names_binding = (kind(p) == MS_T_Name || kind(p) == MS_T_Underscore) && ahead(p, 1).kind == MS_T_ColonAssign;
    if (kind(p) != MS_T_Var && !names_binding) {
        return true;
    }
    *is_mutable = kind(p) == MS_T_Var;
    if (*is_mutable) {
        p->at++;
    }
    MsPattern *pat = NULL;
    if (!pattern(p, &pat)) return false;
    if (pat->kind != MS_P_NAME) {
        fail(p, t, LIT("an if binding takes one name; write 'if value := optional:' and destructure the value inside the branch"));
        return false;
    }
    if (kind(p) == MS_T_LParen) {
        fail(p, t, LIT("an if binding unwraps an Optional or Result into one name; it does not match alternative cases. Write 'match value:' with a 'Case(x):' arm, or 'if value := optional:'"));
        return false;
    }
    *bind = pat;
    return need(p, *is_mutable ? MS_T_Assign : MS_T_ColonAssign);
}

MS_NODISCARD static bool if_statement(Parser *p, MsToken t, MsStmt *st, MsStmt **out) {
    p->at++;
    MsPattern *bind = NULL;
    bool is_mutable = false;
    if (!if_binding(p, t, &bind, &is_mutable)) return false;
    MsExpr *cond = NULL;
    if (!expression(p, 0, &cond)) return false;
    MsStmts body = {0};
    if (!suite(p, &body)) return false;
    newlines(p);
    MsStmts else_body = {NULL, 0};
    if (take(p, MS_T_Else)) {
        if (kind(p) == MS_T_If) {
            else_body.ptr = MS_NEW_N(p->arena, MsStmt *, 1);
            if (!statement(p, false, &else_body.ptr[0])) return false;
            else_body.len = 1;
        } else if (!suite(p, &else_body)) {
            return false;
        }
    }
    st->kind = MS_S_IF;
    st->u.branch.binding = bind;
    st->u.branch.is_mutable = is_mutable;
    st->u.branch.cond = cond;
    st->u.branch.body = body;
    st->u.branch.else_body = else_body;
    *out = finish_stmt(p, st);
    return true;
}

MS_NODISCARD static bool while_statement(Parser *p, MsStmt *st, MsStmt **out) {
    p->at++;
    MsExpr *cond = NULL;
    if (!expression(p, 0, &cond)) return false;
    if (kind(p) == MS_T_ColonAssign) {
        fail(p, peek(p), LIT("while takes a condition, not a binding; to loop while a value is present write 'while true:', bind it inside with 'if name := value:', and leave with 'else: break'"));
        return false;
    }
    MsStmts body = {0};
    if (!suite(p, &body)) return false;
    st->kind = MS_S_WHILE;
    st->u.loop.cond = cond;
    st->u.loop.body = body;
    *out = finish_stmt(p, st);
    return true;
}

/* The variable of `for`: a name, or a hidden name when the element is destructured by `*pat`. */
MS_NODISCARD static bool for_variable(Parser *p, MsSym *name, MsPattern **pat) {
    if (kind(p) == MS_T_LBracket || kind(p) == MS_T_LBrace) {
        *name = intern(p, HIDDEN_ITEM);
        return pattern(p, pat);
    }
    MsToken name_token = {0};
    if (!need_token(p, MS_T_Name, &name_token)) return false;
    *name = sym(p, name_token);
    return true;
}

MS_NODISCARD static bool for_statement(Parser *p, MsStmt *st, MsStmt **out) {
    p->at++;
    if (kind(p) == MS_T_LParen) {
        fail(p, peek(p), LIT("for does not take parentheses or a counter clause; write 'for item in items:' to visit a List, or 'for i in 0..n:' to count"));
        return false;
    }
    MsSym name = 0;
    MsPattern *pat = NULL;
    if (!for_variable(p, &name, &pat)) return false;
    if (kind(p) == MS_T_Name && text_is(p, peek(p), "of")) {
        fail(p, peek(p), LIT("for uses 'in', not 'of'; write 'for item in items:'"));
        return false;
    }
    if (kind(p) == MS_T_Comma) {
        fail(p, peek(p), LIT("for binds one name or one pattern; to read positions, loop over the entries, e.g. 'for entry in items.entries():' and use entry.index and entry.value (a Map's entries() give entry.key and entry.value), or destructure each element with 'for [a, b] in pairs:'"));
        return false;
    }
    if (!need(p, MS_T_In)) return false;
    MsExpr *iter = NULL;
    if (!expression(p, 0, &iter)) return false;
    MsStmts body = {0};
    if (!suite(p, &body)) return false;
    if (pat != NULL) {
        MsStmt **with_binding = MS_NEW_N(p->arena, MsStmt *, body.len + 1);
        with_binding[0] = destructure(p, pat, name);
        memcpy(with_binding + 1, body.ptr, body.len * sizeof(MsStmt *));
        body.ptr = with_binding;
        body.len++;
    }
    st->kind = MS_S_FOR;
    st->u.each.name = name;
    st->u.each.iter = iter;
    st->u.each.body = body;
    *out = finish_stmt(p, st);
    return true;
}

/* The statements that start with a keyword; *out stays NULL for any other. */
MS_NODISCARD static bool keyword_statement(Parser *p, MsToken t, MsStmt *st, MsStmt **out) {
    switch (t.kind) {
    case MS_T_Void:
        return void_statement(p, t, out);
    case MS_T_Var:
        return var_statement(p, t, st->pos, out);
    case MS_T_Fn:
        return local_fn_statement(p, t, st, out);
    case MS_T_Return:
        return return_statement(p, st, out);
    case MS_T_Break:
    case MS_T_Continue:
        p->at++;
        if (!end(p)) return false;
        st->kind = t.kind == MS_T_Break ? MS_S_BREAK : MS_S_CONTINUE;
        *out = finish_stmt(p, st);
        return true;
    case MS_T_If:
        return if_statement(p, t, st, out);
    case MS_T_While:
        return while_statement(p, st, out);
    case MS_T_For:
        return for_statement(p, st, out);
    default:
        return true;
    }
}

MS_NODISCARD static bool statement(Parser *p, bool allow_value, MsStmt **out) {
    MsToken t = peek(p);
    MsStmt st = {0};
    st.pos = t.pos;
    *out = NULL;
    if (report_removed_binding(p, t)) {
        return false;
    }
    if (starts_binding_target((MsTok)t.kind) && binding_ahead(p)) {
        MsStmt *s = NULL;
        if (!binding(p, false, NULL, t.pos, &s)) return false;
        if (!end(p)) return false;
        *out = s;
        return true;
    }
    if (!keyword_statement(p, t, &st, out)) return false;
    if (*out != NULL) return true;
    if (!expression_statement(p, t, allow_value, &st)) return false;
    *out = finish_stmt(p, &st);
    return true;
}

/* Parses `: body`. `expression` marks a lambda body (an inline body is its value); `fn_body`
 * marks a function or method body (inline returns, may be empty). */
MS_NODISCARD static bool statement_suite_inner(Parser *p, bool is_expression, bool fn_body, bool outer, bool outer_lambda, MsStmts *out) {
    if (!need(p, MS_T_Colon)) return false;
    MsStmts none = {NULL, 0};
    if (kind(p) == MS_T_Ellipsis && fn_body) {
        p->at++;
        if (!end(p)) return false;
        *out = none;
        return true;
    }
    if (kind(p) != MS_T_Newline) {
        if (kind(p) == MS_T_If && (is_expression || fn_body)) {
            /* `fn x: if c: a else: b`: the body is the conditional expression. */
            size_t start = p->at;
            MsPos at_pos = peek(p).pos;
            Checkpoint checkpoint = checkpoint_take(p);
            MsExpr *value = NULL;
            bool ok = expression(p, 0, &value) && (is_expression || end(p));
            if (!ok) {
                checkpoint_restore(p, &checkpoint);
            }
            if (ok) {
                MsStmt *s = NEW(p, MsStmt);
                s->id = new_id(p);
                s->pos = at_pos;
                s->kind = MS_S_RETURN;
                s->u.expr = value;
                MsStmts result = {MS_NEW_N(p->arena, MsStmt *, 1), 1};
                result.ptr[0] = s;
                *out = result;
                return true;
            }
            /* Not a conditional expression: report it as the statement it was written as. */
            p->at = start;
        }
        if (kind(p) == MS_T_If || kind(p) == MS_T_While || kind(p) == MS_T_For) {
            MsToken t = peek(p);
            fail(p, t, fmt(p, "inline bodies require one simple statement; put '%s' on its own line in an indented block", ms_tok_str((MsTok)t.kind)));
            return false;
        }
        p->inline_statement = true;
        p->inline_return = is_expression || fn_body;
        MsStmts body = {MS_NEW_N(p->arena, MsStmt *, 1), 1};
        if (!statement(p, false, &body.ptr[0])) return false;
        p->inline_statement = outer;
        if (!is_expression) {
            if (!end(p)) return false;
        }
        *out = body;
        return true;
    }
    p->inline_statement = false;
    p->inline_return = false;
    p->block_lambda = outer_lambda || is_expression;
    if (!need(p, MS_T_Newline)) return false;
    if (!need(p, MS_T_Indent)) return false;
    size_t m = mark(p);
    for (;;) {
        newlines(p);
        if (kind(p) == MS_T_Dedent || kind(p) == MS_T_Eof) {
            break;
        }
        if (!statements(p, false)) return false;
    }
    if (!need(p, MS_T_Dedent)) return false;
    MsStmts body;
    FINISH_PTRS(p, m, body);
    if (body.len == 0) {
        fail(p, previous(p), LIT("suite cannot be empty; add at least one statement, or write '...' after the colon for a runtime-bound declaration"));
        return false;
    }
    *out = body;
    return true;
}

MS_NODISCARD static bool statement_suite(Parser *p, bool is_expression, bool fn_body, MsStmts *out) {
    if (!enter(p)) return false;
    bool outer = p->inline_statement, outer_return = p->inline_return, outer_lambda = p->block_lambda;
    MsStmts r = {0};
    if (!statement_suite_inner(p, is_expression, fn_body, outer, outer_lambda, &r)) return false;
    p->inline_statement = outer;
    p->inline_return = outer_return;
    p->block_lambda = outer_lambda;
    p->depth--;
    *out = r;
    return true;
}

/* ---- expressions ---- */

typedef struct Args {
    MsArg *ptr;
    uint32_t len;
} Args;

MS_NODISCARD static bool call_arguments(Parser *p, Args *out);

static MsExpr *mk_unary(Parser *p, MsPos pos, MsUnaryOp op, MsExpr *operand) {
    MsExpr *e = mk(p, pos, MS_E_UNARY);
    e->op = (uint8_t)op;
    e->u.bin.left = operand;
    return e;
}

/* Rejects prefix `try`. When the operand is one call or access chain, the fix rewrites
 * `try f(x)` to `f(x)?`. */
static void fail_try(Parser *p, MsToken t) {
    p->at++;
    MsToken start = peek(p);
    Checkpoint checkpoint = checkpoint_take(p);
    MsExpr *operand = NULL;
    if (!expression(p, PREFIX_OPERAND, &operand)) {
        checkpoint_restore(p, &checkpoint);
        operand = NULL;
    }
    MsDiag *d = parse_diag(p, t.pos, LIT(TRY_REMOVED));
    d->has_end = true;
    d->end = t.end;
    MsToken last = previous(p);
    bool chain = false;
    if (operand != NULL) {
        switch (operand->kind) {
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
}

/* `start..end` as the call `range(start, end)`; `..` names the standard `range`. */
static MsExpr *range_call(Parser *p, MsExpr *start, MsExpr *stop) {
    MsPos pos = start->pos;
    MsExpr *callee = mk_name(p, pos, intern(p, ".."));
    MsArg *args = MS_NEW_N(p->arena, MsArg, 2);
    args[0] = (MsArg){start->pos, false, 0, start};
    args[1] = (MsArg){stop->pos, false, 0, stop};
    return mk_call(p, pos, callee, args, 2);
}

/* Parses one `| step` after `lhs` and desugars it to the ordinary expression the step names. */
MS_NODISCARD static bool parse_pipe(Parser *p, MsExpr *lhs, MsExpr **out) {
    p->at++;
    if (kind(p) == MS_T_Pipe) {
        MsToken t = peek(p);
        MsToken first = previous(p);
        fail_word_operator(p, first, t, LIT("'||' is not an operator; write 'or' for logical or, and '|' only to start a pipe step"), "or");
        return false;
    }
    if (kind(p) == MS_T_Try) {
        fail(p, peek(p), LIT(TRY_REMOVED));
        return false;
    }
    MsExpr *step;
    if (kind(p) == MS_T_Dot) {
        if (!postfix(p, lhs, &step)) return false;
    } else {
        MsToken name = peek(p);
        if (name.kind != MS_T_Name) {
            const char *hint = "";
            if (name.kind == MS_T_Newline) {
                hint = "; to continue a flow on the next line, end this line before '|' and start the next line with '|'";
            }
            MsStr dn = describe(p, name);
            fail(p, name, fmt(p, "a pipe step is a function name, a call without its first argument, or a '.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found %.*s%s", STR(dn), hint));
            return false;
        }
        p->at++;
        MsExpr *callee = mk_name(p, name.pos, sym(p, name));
        size_t links = 0;
        /* A '.' on a later line continues the flow and applies to the step's result. */
        while (kind(p) == MS_T_Dot && peek(p).pos.line == p->tokens[p->at - 1].pos.line) {
            if (!parse_link(p, &links)) return false;
            p->at++;
            MsToken member = {0};
            if (!need_token(p, MS_T_Name, &member)) return false;
            callee = mk_member(p, member.pos, callee, sym(p, member));
        }
        if (kind(p) == MS_T_LBracket) {
            MsStr n = text(p, name);
            fail(p, peek(p), fmt(p, "a pipe step cannot take type arguments; bind the instance to a name first, e.g. step := %.*s[Int], then write x | step", STR(n)));
            return false;
        }
        Args rest = {NULL, 0};
        if (take(p, MS_T_LParen)) {
            if (!call_arguments(p, &rest)) return false;
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
    *out = step;
    return true;
}

/* The first operand: a prefix `not`, `+` or `-` with its operand, or a primary expression. */
MS_NODISCARD static bool leading_operand(Parser *p, int min, MsExpr **out) {
    MsToken t = peek(p);
    if (t.kind == MS_T_Not && min > PREFIX_OPERAND) {
        fail(p, t, LIT("not requires grouping at this operator position; wrap it in parentheses, e.g. a == (not b)"));
        return false;
    }
    if (t.kind == MS_T_Try) {
        fail_try(p, t);
        return false;
    }
    if (t.kind != MS_T_Not && t.kind != MS_T_Plus && t.kind != MS_T_Minus) {
        return primary(p, out);
    }
    p->at++;
    MsUnaryOp op = MS_U_NOT;
    int binding_power = PREFIX_OPERAND;
    if (t.kind != MS_T_Not) {
        op = t.kind == MS_T_Plus ? MS_U_PLUS : MS_U_NEG;
        binding_power = 8;
    }
    MsExpr *operand = NULL;
    if (!expression(p, binding_power, &operand)) return false;
    *out = mk_unary(p, t.pos, op, operand);
    return true;
}

/* `e | step`, then a member access or call chain on the result. */
MS_NODISCARD static bool pipe_operator(Parser *p, MsExpr **e, size_t *links) {
    if (!parse_link(p, links)) return false;
    if (!parse_pipe(p, *e, e)) return false;
    if (kind(p) == MS_T_Dot) {
        if (!postfix(p, *e, e)) return false;
    }
    MsBinaryOp ignored;
    if (binary_op(kind(p), &ignored)) {
        fail(p, peek(p), LIT("a pipe has the lowest precedence; parenthesize it to use its result in an operator, e.g. (x | f) == y"));
        return false;
    }
    return true;
}

/* `e..right`, which is the call range(e, right). */
MS_NODISCARD static bool range_operator(Parser *p, MsExpr **e) {
    p->at++;
    MsExpr *right = NULL;
    if (!expression(p, RANGE_LEVEL + 1, &right)) return false;
    if (kind(p) == MS_T_DotDot) {
        fail(p, peek(p), LIT("a range cannot chain; write one 'start..end', or use range_by for a step from \"@std/collections/collections.ms\""));
        return false;
    }
    *e = range_call(p, *e, right);
    return true;
}

/* Rejects `x++` and `x--` written as statements, which parse as two operators. */
static bool is_increment(const Parser *p, MsToken op, const MsExpr *e) {
    return (op.kind == MS_T_Plus || op.kind == MS_T_Minus) && e->kind == MS_E_NAME &&
           ahead(p, 1).kind == op.kind && ahead(p, 2).kind == MS_T_Newline;
}

MS_NODISCARD static bool expression_inner(Parser *p, int min, MsExpr **out) {
    MsExpr *e = NULL;
    if (!leading_operand(p, min, &e)) return false;
    bool compared = false;
    size_t links = 0;
    for (;;) {
        MsToken op = peek(p);
        if (compound_assignment(p)) {
            break;
        }
        if (op.kind == MS_T_Amp) {
            and_and(p, op);
            return false;
        }
        if (op.kind == MS_T_Pipe || op.kind == MS_T_DotDot) {
            if (min > (op.kind == MS_T_Pipe ? 0 : RANGE_LEVEL)) {
                break;
            }
            bool ok = op.kind == MS_T_Pipe ? pipe_operator(p, &e, &links) : range_operator(p, &e);
            if (!ok) return false;
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
        if (is_increment(p, op, e)) {
            const char *o = ms_tok_str((MsTok)op.kind);
            MsStr n = ms_name(p->names, e->u.sym);
            fail(p, op, fmt(p, "Manuscript has no '%s%s' operator; write '%.*s %s= 1'", o, o, STR(n), o));
            return false;
        }
        if (level == 4 && compared) {
            fail(p, op, LIT("comparison operators cannot chain; combine two comparisons with 'and', e.g. a < b and b < c"));
            return false;
        }
        p->at++;
        if (!parse_link(p, &links)) return false;
        MsExpr *right = NULL;
        if (!expression(p, level + 1, &right)) return false;
        MsExpr *b = mk(p, op.pos, MS_E_BINARY);
        b->op = (uint8_t)bop;
        b->u.bin.left = e;
        b->u.bin.right = right;
        e = b;
        compared = compared || level == 4;
    }
    *out = e;
    return true;
}

MS_NODISCARD static bool expression(Parser *p, int min, MsExpr **out) {
    if (!enter(p)) return false;
    MsExpr *r = NULL;
    if (!expression_inner(p, min, &r)) return false;
    p->depth--;
    *out = r;
    return true;
}

MS_NODISCARD static bool case_path(Parser *p, MsExpr **out) {
    MsToken t = {0};
    if (!need_token(p, MS_T_Name, &t)) return false;
    MsExpr *e = mk_name(p, t.pos, sym(p, t));
    if (take(p, MS_T_LBracket)) {
        MsTypeRefs types = {0};
        if (!type_args(p, &types)) return false;
        MsExpr *a = mk(p, t.pos, MS_E_APPLY);
        a->u.apply.left = e;
        a->u.apply.types = types;
        e = a;
    }
    size_t links = 0;
    while (take(p, MS_T_Dot)) {
        if (!parse_link(p, &links)) return false;
        MsToken name = {0};
        if (!need_token(p, MS_T_Name, &name)) return false;
        e = mk_member(p, name.pos, e, sym(p, name));
    }
    *out = e;
    return true;
}

/* ---- text ---- */

static MsPos text_pos(MsPos pos, MsStr full, size_t index, const MsBounds *bounds) {
    size_t last = (size_t)-1;
    uint32_t newline_count = 0;
    for (size_t i = 0; i < index; i++) {
        if (full.ptr[i] == '\n') {
            last = i;
            newline_count++;
        }
    }
    uint32_t offset = (uint32_t)(pos.offset + index);
    MsPos position;
    if (last == (size_t)-1) {
        position = (MsPos){offset, pos.line, (uint32_t)(pos.column + index)};
    } else {
        position = (MsPos){offset, pos.line + newline_count, (uint32_t)(index - last)};
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

MS_NODISCARD static bool interpolation(Parser *p, MsToken token, size_t at, MsStr source, MsPos position, MsExpr **out);

/* Where text_parts stands in the raw text and in the literal it is building. */
typedef struct TextCursor {
    const uint8_t *raw;
    size_t at;     /* next byte of the raw text */
    size_t stop;   /* end of the content */
    size_t indent; /* indentation removed from each line of multi-line text */
    size_t bytes;  /* start of the literal being built, on the byte stack */
    bool line_start;
} TextCursor;

/* Turns the literal bytes built so far into a part and pushes it. */
static void flush_literal(Parser *p, size_t literal_start) {
    if (p->bytes->len == literal_start) {
        return;
    }
    size_t length = p->bytes->len - literal_start;
    MsTextPart part = {{ms_arena_strndup(p->arena, p->bytes->data + literal_start, length), (uint32_t)length}, NULL};
    push(p, &part, sizeof part);
    p->bytes->len = literal_start;
}

/* Appends the character an escape stands for; the cursor is after the backslash. */
static void append_escape(Parser *p, TextCursor *c) {
    uint8_t escape = c->raw[c->at++];
    switch (escape) {
    case 'n':
        ms_buf_putc(p->bytes, '\n');
        return;
    case 'r':
        ms_buf_putc(p->bytes, '\r');
        return;
    case 't':
        ms_buf_putc(p->bytes, '\t');
        return;
    case 'u':
        break;
    default:
        ms_buf_putc(p->bytes, (char)escape);
        return;
    }
    size_t digits = c->at + 1; /* after the '{' */
    c->at = digits;
    while (c->raw[c->at] != '}') {
        c->at++;
    }
    uint32_t scalar = 0;
    for (size_t k = digits; k < c->at; k++) {
        uint8_t h = c->raw[k];
        uint32_t digit = 0;
        if (ms_hex_digit_value(h, &digit)) { /* the lexer admitted only hex digits */
            scalar = scalar * 16 + digit;
        }
    }
    ms_utf8_put(p->bytes, scalar);
    c->at++;
}

/* Consumes `{expr}` (the cursor is after the brace) and parses it. */
MS_NODISCARD static bool text_interpolation(Parser *p, MsToken token, MsStr raw, size_t quotes, TextCursor *c,
                                            MsPos *position, size_t *positioned) {
    size_t start = c->at;
    size_t brace = p->source_origin + token.lo + quotes + start - 1;
    size_t close = ms_bounds_interp_end(p->bounds, brace);
    c->at = close - (p->source_origin + token.lo + quotes);
    MsStr source = {raw.ptr + start, (uint32_t)(c->at - 1 - start)};
    /* Advance through each prefix once, including physical lines in multiline text. */
    size_t at = quotes + start;
    MsStr full = text(p, token);
    MsStr rest = {full.ptr + *positioned, (uint32_t)(full.len - *positioned)};
    *position = text_pos(*position, rest, at - *positioned, p->bounds);
    *positioned = at;
    MsExpr *value = NULL;
    if (!interpolation(p, token, at, source, *position, &value)) return false;
    MsTextPart part = {{NULL, 0}, value};
    push(p, &part, sizeof part);
    return true;
}

/* Skips the indentation a multi-line text's closing line removes from each content line. */
static void skip_text_indent(TextCursor *c) {
    size_t skipped = 0;
    while (skipped < c->indent && c->at < c->stop && (c->raw[c->at] == ' ' || c->raw[c->at] == '\t')) {
        skipped++;
        c->at++;
    }
}

MS_NODISCARD static bool text_parts(Parser *p, MsToken token, MsStr raw, size_t quotes, bool interpolating, TextParts *out) {
    TextCursor c = {.raw = (const uint8_t *)raw.ptr, .stop = raw.len};
    if (quotes >= 3) {
        MsStr content;
        multiline_body(raw, &content, &c.indent, &c.at);
        c.stop = c.at + content.len;
    }
    size_t parts_start = mark(p); /* parts, on the scratch stack */
    c.bytes = p->bytes->len;
    c.line_start = c.indent > 0;
    size_t positioned = 0;
    MsPos position = token.pos;
    while (c.at < c.stop) {
        if (c.line_start) {
            c.line_start = false;
            skip_text_indent(&c);
            continue;
        }
        uint8_t b = c.raw[c.at++];
        if (b == '\\') {
            append_escape(p, &c);
        } else if (interpolating && b == '{') {
            flush_literal(p, c.bytes);
            if (!text_interpolation(p, token, raw, quotes, &c, &position, &positioned)) return false;
        } else {
            ms_buf_putc(p->bytes, (char)b);
            c.line_start = b == '\n' && c.indent > 0;
        }
    }
    flush_literal(p, c.bytes);
    TextParts result;
    result.ptr = finish(p, parts_start, &result.len, sizeof(MsTextPart), _Alignof(MsTextPart));
    if (result.len == 0) {
        result.ptr = MS_NEW_N(p->arena, MsTextPart, 1);
        result.ptr[0].lit = (MsStr){"", 0};
        result.len = 1;
    }
    *out = result;
    return true;
}

static TextParts one_literal(Parser *p, MsStr s) {
    TextParts out = {MS_NEW_N(p->arena, MsTextPart, 1), 1};
    out.ptr[0].lit = s;
    out.ptr[0].expr = NULL;
    return out;
}

/* Decodes a text token into literal and interpolated parts. Only `f"..."` and `f"""` text
 * interpolates; braces are plain in the other forms. */
MS_NODISCARD static bool text_parts_of(Parser *p, MsToken token, TextParts *out) {
    MsStr full = text(p, token);
    if (ms_text_starts_with(full, "r\"\"\"")) {
        MsStr body = {full.ptr + 4, full.len - 4 - 3};
        MsStr content;
        size_t indent, f;
        multiline_body(body, &content, &indent, &f);
        *out = one_literal(p, dedent(p, content, indent));
        return true;
    }
    if (ms_text_starts_with(full, "f\"\"\"")) {
        MsStr body = {full.ptr + 4, full.len - 4 - 3};
        return text_parts(p, token, body, 4, true, out);
    }
    if (ms_text_starts_with(full, "\"\"\"")) {
        MsStr body = {full.ptr + 3, full.len - 6};
        return text_parts(p, token, body, 3, false, out);
    }
    if (ms_text_starts_with(full, "r\"")) {
        *out = one_literal(p, (MsStr){full.ptr + 2, full.len - 3});
        return true;
    }
    if (ms_text_starts_with(full, "f\"")) {
        MsStr body = {full.ptr + 2, full.len - 3};
        return text_parts(p, token, body, 2, true, out);
    }
    MsStr raw = {full.ptr + 1, full.len - 2};
    if (memchr(raw.ptr, '\\', raw.len) == NULL) {
        *out = one_literal(p, raw);
        return true;
    }
    return text_parts(p, token, raw, 1, false, out);
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
MS_NODISCARD static bool nested_body(Parser *n, bool eof_by_need, MsExpr **out) {
    if (!expression(n, 0, out)) return false;
    newlines(n);
    if (eof_by_need) {
        return need(n, MS_T_Eof);
    }
    if (kind(n) != MS_T_Eof) {
        MsToken at = peek(n);
        MsStr found = describe(n, at);
        fail(n, at, fmt(n, "an interpolation holds one expression, found %.*s after it; close the brace after the expression, or bind the rest to a name first", STR(found)));
        return false;
    }
    return true;
}

MS_NODISCARD static bool nested_expression(Parser *p, Parser *n, MsStr suffix, MsStr source, bool eof_by_need, MsExpr **out) {
    (void)source;
    size_t scratch = n->scratch->len;
    size_t bytes = n->bytes->len;
    MsExpr *value = NULL;
    bool ok = nested_body(n, eof_by_need, &value);
    p->next_id = n->next_id;
    if (ok) {
        *out = value;
        return true;
    }
    p->diag->message = append_suffix(p, p->diag->message, suffix);
    p->scratch->len = scratch;
    p->bytes->len = bytes;
    return false;
}

/* The wrapper path for an expression whose lexical error depends on its physical closing
 * parenthesis. */
MS_NODISCARD static bool interpolation_wrapped(Parser *p, MsToken token, size_t at, MsStr source, MsExpr **out) {
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
        return false;
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
    return nested_expression(p, &n, suffix, source, true, out);
}

/* Lexes and parses the expression inside one `{...}` of `f` text. */
MS_NODISCARD static bool interpolation(Parser *p, MsToken token, size_t at, MsStr source, MsPos position, MsExpr **out) {
    MsStr suffix = fmt(p, " ('{' at column %u starts an interpolation in f\"...\" text; write \\{ and \\} for literal braces, or drop the f)", position.column - 1);
    size_t origin = p->source_origin + token.lo + at;
    MsToken *tokens;
    size_t nt;
    MsDiag ld;
    if (!ms_lex_interpolation(p->arena, source.ptr, source.len, origin, p->bounds, &tokens, &nt, &ld)) {
        return interpolation_wrapped(p, token, at, source, out);
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
    return nested_expression(p, &n, suffix, source, false, out);
}

/* ---- match ---- */

/* `if c: a else: b` (also `else if`) as a match over the Bool `c`. */
MS_NODISCARD static bool if_expression(Parser *p, MsToken t, MsExpr **out) {
    MsExpr *cond = NULL;
    if (!expression(p, 0, &cond)) return false;
    if (!need(p, MS_T_Colon)) return false;
    if (kind(p) == MS_T_Newline) {
        fail(p, peek(p), LIT("an if expression writes its branches on one line, 'if c: a else: b'; to run statements, use an if statement that assigns a 'var' or returns"));
        return false;
    }
    MsExpr *then = NULL;
    if (!expression(p, 0, &then)) return false;
    if (kind(p) != MS_T_Else) {
        fail(p, peek(p), LIT("an if expression needs an else branch; write 'if c: a else: b', or use an if statement when no value is needed"));
        return false;
    }
    MsToken else_token = peek(p);
    p->at++;
    MsExpr *els = NULL;
    if (kind(p) == MS_T_If) {
        MsToken nested = peek(p);
        p->at++;
        if (!if_expression(p, nested, &els)) return false;
    } else {
        if (!need(p, MS_T_Colon)) return false;
        if (!expression(p, 0, &els)) return false;
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
    *out = m;
    return true;
}

/* An arm's final expression supplies its value; a statement-only arm yields Void. */
MS_NODISCARD static bool value_arm_inner(Parser *p, MsArm *a) {
    p->inline_return = false;
    if (!need(p, MS_T_Colon)) return false;
    bool indented = take(p, MS_T_Newline);
    if (indented) {
        if (!need(p, MS_T_Indent)) return false;
    }
    p->inline_statement = !indented;
    size_t m = mark(p);
    for (;;) {
        if (!statements(p, true)) return false;
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
                return false;
            }
        }
    }
    if (indented) {
        if (!need(p, MS_T_Dedent)) return false;
    } else {
        p->inline_statement = false;
        if (!end(p)) return false;
    }
    return true;
}

MS_NODISCARD static bool value_arm(Parser *p, MsArm *a) {
    bool outer = p->inline_statement, outer_return = p->inline_return;
    if (!value_arm_inner(p, a)) return false;
    p->inline_statement = outer;
    p->inline_return = outer_return;
    return true;
}

static bool is_lower_start(MsStr s) {
    return s.len > 0 && ((s.ptr[0] >= 'a' && s.ptr[0] <= 'z') || s.ptr[0] == '_');
}

/* The names in `(a, b)` after a variant path, pushed as arm bindings. The `(` is consumed. */
MS_NODISCARD static bool payload_bindings(Parser *p) {
    for (;;) {
        MsToken tok = peek(p);
        if (!take(p, MS_T_Underscore)) {
            if (!need(p, MS_T_Name)) return false;
        }
        MsArmBinding b = {sym(p, tok), tok.pos};
        push(p, &b, sizeof b);
        if (kind(p) == MS_T_LParen) {
            fail(p, peek(p), LIT("patterns cannot be nested; bind the outer payload, then handle it in a separate match or helper function"));
            return false;
        }
        if (!take(p, MS_T_Comma) || kind(p) == MS_T_RParen) {
            break;
        }
    }
    return need(p, MS_T_RParen);
}

/* A variant path, optionally with payload names. A lone lowercase name binds an Optional payload;
 * the checker tells that from a lowercase variant using the scrutinee's type. */
MS_NODISCARD static bool variant_pattern(Parser *p, MsToken start, MsExpr **path, bool *bare) {
    MsExpr *written = NULL;
    if (!case_path(p, &written)) return false;
    if (written->kind == MS_E_NAME && ms_text_is(ms_name(p->names, written->u.sym), "some") &&
        kind(p) == MS_T_LParen && p->speculative == 0) {
        fail(p, peek(p), LIT("there is no some pattern; write the payload name alone, e.g. 'value:' beside 'none:'"));
        return false;
    }
    if (written->kind == MS_E_NAME && kind(p) != MS_T_LParen) {
        MsStr n = ms_name(p->names, written->u.sym);
        if (!ms_text_is(n, "none") && is_lower_start(n)) {
            MsArmBinding single = {written->u.sym, start.pos};
            push(p, &single, sizeof single);
            *bare = true;
        }
    }
    *path = written;
    if (take(p, MS_T_LParen)) {
        return payload_bindings(p);
    }
    return true;
}

static bool starts_literal_pattern(const Parser *p) {
    MsTok k = kind(p);
    return k == MS_T_Number || k == MS_T_True || k == MS_T_False || k == MS_T_String ||
           (k == MS_T_Minus && ahead(p, 1).kind == MS_T_Number);
}

/* One `pattern: body` arm. */
MS_NODISCARD static bool match_arm(Parser *p, MsArm **out) {
    MsToken start = peek(p);
    size_t bindings_start = mark(p);
    bool bare = false;
    MsExpr *path = NULL;
    if (starts_literal_pattern(p)) {
        if (!expression(p, 0, &path)) return false;
    } else if (take(p, MS_T_Underscore)) {
        path = mk_name(p, start.pos, intern(p, "_"));
    } else if (!variant_pattern(p, start, &path, &bare)) {
        return false;
    }
    MsArm *a = NEW(p, MsArm);
    a->bindings.ptr = finish(p, bindings_start, &a->bindings.len, sizeof(MsArmBinding), _Alignof(MsArmBinding));
    a->id = new_id(p);
    a->pos = start.pos;
    a->path = path;
    a->bare = bare;
    if (!value_arm(p, a)) return false;
    *out = a;
    return true;
}

MS_NODISCARD static bool match_arms(Parser *p, MsToken header, MsExpr *m) {
    if (!need(p, MS_T_Colon)) return false;
    if (!need(p, MS_T_Newline)) return false;
    if (!need(p, MS_T_Indent)) return false;
    size_t arms_start = mark(p);
    uint32_t narms = 0;
    for (;;) {
        newlines(p);
        if (kind(p) == MS_T_Dedent) {
            if (narms == 0) {
                fail(p, header, LIT("match requires at least one arm; add a case pattern or '_' arm under the header"));
                return false;
            }
            break;
        }
        MsToken prefix;
        if (legacy_case_prefix(p, &prefix)) {
            fail_fix(p, prefix, LIT("match arms use bare variant names, e.g. Paid(receipt): or Missing:; remove the legacy 'case' prefix"), LIT(""));
            return false;
        }
        MsArm *arm = NULL;
        if (!match_arm(p, &arm)) return false;
        push_ptr(p, arm);
        narms++;
    }
    if (!need(p, MS_T_Dedent)) return false;
    uint32_t n = 0;
    MsArm **arms = finish(p, arms_start, &n, sizeof(void *), _Alignof(void *));
    m->u.match.arms.ptr = arms;
    m->u.match.arms.len = n;
    return true;
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
MS_NODISCARD static bool bracket(Parser *p, MsExpr *left, MsExpr **out) {
    size_t start = p->at;
    MsTypeRefs types = {NULL, 0};
    bool have_types = false;
    /* A type starts with a name, `fn` or `(`; anything else is a value. */
    if (starts_type(kind(p)) && type_bracket(p, start - 1)) {
        Checkpoint checkpoint = checkpoint_take(p);
        p->speculative++;
        have_types = type_args(p, &types);
        p->speculative--;
        if (!have_types) {
            checkpoint_restore(p, &checkpoint);
            p->at = start;
            types = (MsTypeRefs){NULL, 0};
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
        *out = a;
        return true;
    }
    MsExpr *index = NULL;
    if (!expression(p, 0, &index)) return false;
    if (kind(p) == MS_T_Colon) {
        fail(p, peek(p), LIT("there is no slice syntax; call slice(start: 0, end: 2) on a List or String"));
        return false;
    }
    if (!need(p, MS_T_RBracket)) return false;
    MsPos pos = left->pos;
    MsExpr *ix = mk(p, pos, MS_E_INDEX);
    ix->u.bin.left = left;
    ix->u.bin.right = index;
    *out = ix;
    return true;
}

/* ---- primary, postfix, calls ---- */

MS_NODISCARD static bool postfix(Parser *p, MsExpr *e, MsExpr **out) {
    size_t links = 0;
    for (;;) {
        MsExpr *l, *ix;
        if (take(p, MS_T_Dot)) {
            if (!parse_link(p, &links)) return false;
            if (kind(p) == MS_T_Number) {
                fail(p, peek(p), LIT("a number has at most one decimal point and member access needs a name; write the number once, e.g. 1.2"));
                return false;
            }
            MsToken name = {0};
            if (!need_token(p, MS_T_Name, &name)) return false;
            e = mk_member(p, name.pos, e, sym(p, name));
        } else if (take(p, MS_T_LBracket)) {
            if (!parse_link(p, &links)) return false;
            if (!bracket(p, e, &e)) return false;
        } else if (take(p, MS_T_LParen)) {
            if (!parse_link(p, &links)) return false;
            MsPos pos = e->pos;
            Args args = {0};
            if (!call_arguments(p, &args)) return false;
            e = mk_call(p, pos, e, args.ptr, args.len);
        } else if (kind(p) == MS_T_Question && ms_expr_index(e, &l, &ix) && ahead(p, 1).kind != MS_T_Dot) {
            p->at++;
            MsPos pos = e->pos;
            MsExpr *pr = mk(p, pos, MS_E_PROBE);
            pr->u.bin.left = e;
            e = pr;
        } else if (kind(p) == MS_T_Question) {
            /* `call()?` is `try call()`; one per value keeps a line readable. */
            p->at++;
            if (kind(p) == MS_T_Question) {
                fail(p, peek(p), LIT("'?\?' is not an operator and '?' cannot repeat: unwrap an Optional with 'if x := v:' or give it a default with 'v.get(default)', or bind a Result to a name before the next '?'"));
                return false;
            }
            MsPos pos = e->pos;
            e = mk_unary(p, pos, MS_U_TRY, e);
        } else {
            break;
        }
    }
    *out = e;
    return true;
}

/* Parses the arguments after an opening parenthesis, through `)`. */
MS_NODISCARD static bool call_arguments(Parser *p, Args *out) {
    Args result = {NULL, 0};
    if (take(p, MS_T_RParen)) {
        *out = result;
        return true;
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
                return false;
            }
            fail(p, eq, fmt(p, "argument labels use a colon; write %.*s: value", STR(n)));
            return false;
        }
        if (kind(p) == MS_T_Var) {
            MsToken t = peek(p);
            t.end = ahead(p, 1).pos;
            fail_fix_range(p, t, t, LIT("a call does not write `var`: the callee's parameter declares that it changes the argument; write the argument plainly"), LIT(""));
            return false;
        }
        MsExpr *value = NULL;
        if (!expression(p, 0, &value)) return false;
        if (value->kind == MS_E_NAME && kind(p) == MS_T_Arrow) {
            MsStr n = ms_name(p->names, value->u.sym);
            fail(p, peek(p), fmt(p, "arrow closures are not supported; write 'fn %.*s: %.*s + 1', or 'fn(%.*s: Int) Int: %.*s + 1' with explicit types", STR(n), STR(n), STR(n), STR(n)));
            return false;
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
    if (!need(p, MS_T_RParen)) return false;
    result.ptr = finish(p, m, &result.len, sizeof(MsArg), _Alignof(MsArg));
    *out = result;
    return true;
}

MS_NODISCARD static bool list_literal(Parser *p, MsToken t, MsExpr **out) {
    MsExprs items = {NULL, 0};
    if (!take(p, MS_T_RBracket)) {
        size_t m = mark(p);
        for (;;) {
            if (!push_expression(p, 0)) return false;
            if (!take(p, MS_T_Comma) || kind(p) == MS_T_RBracket) {
                break;
            }
        }
        if (!need(p, MS_T_RBracket)) return false;
        FINISH_PTRS(p, m, items);
    }
    MsExpr *e = mk(p, t.pos, MS_E_LIST);
    e->u.list = items;
    *out = e;
    return true;
}

MS_NODISCARD static bool match_expression(Parser *p, MsToken t, MsExpr **out) {
    MsExpr *scrutinee = NULL;
    if (!expression(p, 0, &scrutinee)) return false;
    MsExpr *arms_holder = NEW(p, MsExpr);
    if (!match_arms(p, t, arms_holder)) return false;
    MsExpr *e = mk(p, t.pos, MS_E_MATCH);
    e->u.match.scrutinee = scrutinee;
    e->u.match.arms = arms_holder->u.match.arms;
    *out = e;
    return true;
}

/* One `key: value` entry of a map literal, pushed on the scratch stack. */
MS_NODISCARD static bool map_entry(Parser *p) {
    MsExpr *key = NULL;
    if (!expression(p, 0, &key)) return false;
    if (kind(p) == MS_T_Comma || kind(p) == MS_T_RBrace) {
        fail(p, peek(p), LIT("a brace literal is a Map and needs 'key: value' entries; there is no set literal, so write Set[T]() and call add(value), or [a, b].to_set() from a List"));
        return false;
    }
    if (!need(p, MS_T_Colon)) return false;
    MsExpr *value = NULL;
    if (!expression(p, 0, &value)) return false;
    MsMapEntry entry = {key, value};
    push(p, &entry, sizeof entry);
    return true;
}

MS_NODISCARD static bool map_literal(Parser *p, MsToken t, MsExpr **out) {
    uint32_t n = 0;
    MsMapEntry *entries = NULL;
    if (!take(p, MS_T_RBrace)) {
        size_t m = mark(p);
        for (;;) {
            if (!map_entry(p)) return false;
            if (!take(p, MS_T_Comma) || kind(p) == MS_T_RBrace) {
                break;
            }
        }
        if (!need(p, MS_T_RBrace)) return false;
        entries = finish(p, m, &n, sizeof(MsMapEntry), _Alignof(MsMapEntry));
    }
    MsExpr *e = mk(p, t.pos, MS_E_MAP);
    e->u.map.ptr = entries;
    e->u.map.len = n;
    *out = e;
    return true;
}

/* The parameters of `fn a, b: ...`, which have no parentheses or types. A bracket or brace pattern
 * binds from a hidden parameter, and `destructured` collects the statements that unpack it. */
MS_NODISCARD static bool bare_lambda_parameters(Parser *p, MsParams *params, MsBuf *destructured) {
    size_t m = mark(p);
    uint32_t count = 0;
    while (kind(p) == MS_T_Name || kind(p) == MS_T_LBracket || kind(p) == MS_T_LBrace ||
           (kind(p) == MS_T_Var && ahead(p, 1).kind == MS_T_Name)) {
        if (kind(p) == MS_T_LBracket || kind(p) == MS_T_LBrace) {
            MsPattern *pat = NULL;
            if (!pattern(p, &pat)) return false;
            char nm[48];
            snprintf(nm, sizeof nm, HIDDEN_ITEM " %u", count);
            MsSym hidden = intern(p, nm);
            push_ptr(p, mk_param(p, pat->pos, hidden, NULL, NULL, false, false));
            count++;
            MS_VEC_PUSH(*destructured, MsStmt *, destructure(p, pat, hidden));
        } else {
            /* `fn var exchange, next: ...`: a parameter the function changes in place;
             * `fn move item: ...` takes ownership of it. */
            bool moving = TAKE_MOVE(p, MS_T_Name);
            bool is_mutable = take(p, MS_T_Var);
            MsToken name = next(p);
            push_ptr(p, mk_param(p, name.pos, sym(p, name), NULL, NULL, is_mutable, moving));
            count++;
        }
        if (!take(p, MS_T_Comma)) {
            break;
        }
    }
    FINISH_PTRS(p, m, *params);
    return true;
}

/* The parameters in parentheses of `fn (a: Int) Int: ...`, and its optional result type. */
MS_NODISCARD static bool lambda_signature(Parser *p, MsParams *params, MsTypeRef **result) {
    if (!parameters(p, true, true, params)) return false;
    if (kind(p) == MS_T_Arrow) {
        fail_fix(p, peek(p), LIT("result types follow the parameter list without an arrow; remove '->', e.g. fn (x: Int) Int: x + 1"), LIT(""));
        return false;
    }
    if (kind(p) != MS_T_Colon) {
        return typ(p, result);
    }
    return true;
}

MS_NODISCARD static bool lambda_expression(Parser *p, MsToken t, MsExpr **out) {
    MsTypeRef *result = NULL;
    MsParams params = {0};
    MsBuf destructured = {0}; /* MsStmt * */
    bool ok = kind(p) == MS_T_LParen ? lambda_signature(p, &params, &result)
                                      : bare_lambda_parameters(p, &params, &destructured);
    MsStmts body = {0};
    ok = ok && statement_suite(p, true, false, &body);
    size_t ndestructured = MS_VEC_LEN(destructured, MsStmt *);
    if (ok && ndestructured != 0) {
        MsStmt **with_unpacking = MS_NEW_N(p->arena, MsStmt *, body.len + ndestructured);
        memcpy(with_unpacking, ms_buf_items(&destructured), ndestructured * sizeof(MsStmt *));
        memcpy(with_unpacking + ndestructured, body.ptr, body.len * sizeof(MsStmt *));
        body.ptr = with_unpacking;
        body.len += (uint32_t)ndestructured;
    }
    ms_buf_free(&destructured);
    if (!ok) {
        return false;
    }
    MsExpr *e = mk(p, t.pos, MS_E_LAMBDA);
    e->u.lambda.params = params;
    e->u.lambda.result = result;
    e->u.lambda.body = body;
    *out = e;
    return true;
}

/* What to say about a token that cannot start an expression; `before` is the token ahead of it. */
static const char *expression_hint(MsToken t, MsTok before) {
    if (t.kind == MS_T_Else) {
        return "'else' continues an 'if' block: put it on its own line at the same indentation as that 'if', directly after the if body";
    }
    if (t.kind == MS_T_Gt && before == MS_T_Lt) {
        return "'<>' is not an operator; write '!=' for inequality";
    }
    if (t.kind == MS_T_Star && before == MS_T_Star) {
        return "there is no '**' power operator; multiply explicitly or call a function from @std/math/math.ms";
    }
    if ((t.kind == MS_T_Comma || t.kind == MS_T_RParen) && before == MS_T_Colon) {
        return "a label before ':' needs a value, e.g. count: 1";
    }
    if (t.kind == MS_T_Comma) {
        return "remove the extra comma or add the missing value before it";
    }
    return "write a value, name, call, or literal here";
}

static void report_expected_expression(Parser *p, MsToken t) {
    MsTok before = p->at > 1 ? (MsTok)p->tokens[p->at - 2].kind : MS_T_Eof;
    MsStr word = text(p, t);
    MsStr dt = describe(p, t);
    /* Words that read as names (`type`, `test`) are the ones written as variables. */
    bool reserved = t.kind == MS_T_Test || t.kind == MS_T_Type || t.kind == MS_T_Fixture;
    if (reserved) {
        fail(p, t, fmt(p, "expected an expression, found %.*s; '%.*s' is a reserved word and cannot be used as a name: pick another name for the variable, field or parameter", STR(dt), STR(word)));
        return;
    }
    fail(p, t, fmt(p, "expected an expression, found %.*s; %s", STR(dt), expression_hint(t, before)));
}

/* `( expression )`. */
MS_NODISCARD static bool grouped_expression(Parser *p, MsToken t, MsExpr **out) {
    if (kind(p) == MS_T_RParen) {
        fail(p, t, LIT("'()' is not a value; the Void value is written 'void'"));
        return false;
    }
    if (!expression(p, 0, out)) return false;
    if (kind(p) == MS_T_Comma) {
        fail(p, peek(p), LIT("Manuscript has no tuples; declare a type with 'type Pair:' and named fields, or use a List when the items share one type"));
        return false;
    }
    return need(p, MS_T_RParen);
}

/* The expressions that are one token or a simple literal; *out stays NULL for any other token. */
MS_NODISCARD static bool simple_primary(Parser *p, MsToken t, MsExpr **out) {
    switch (t.kind) {
    case MS_T_Name: case MS_T_SelfKw: case MS_T_Fixture:
        *out = mk_name(p, t.pos, sym(p, t));
        return true;
    case MS_T_Number:
        *out = mk(p, t.pos, MS_E_NUMBER);
        (*out)->u.sym = sym(p, t);
        return true;
    case MS_T_True: case MS_T_False:
        *out = mk(p, t.pos, MS_E_BOOL);
        (*out)->u.flag = t.kind == MS_T_True;
        return true;
    case MS_T_Void:
        *out = mk(p, t.pos, MS_E_VOID);
        return true;
    case MS_T_String: {
        TextParts parts = {0};
        if (!text_parts_of(p, t, &parts)) return false;
        MsExpr *e = mk(p, t.pos, MS_E_TEXT);
        e->u.text.ptr = parts.ptr;
        e->u.text.len = parts.len;
        *out = e;
        return true;
    }
    default:
        return true;
    }
}

MS_NODISCARD static bool primary_operand(Parser *p, MsToken t, MsExpr **out) {
    switch (t.kind) {
    case MS_T_LParen:
        return grouped_expression(p, t, out);
    case MS_T_LBracket:
        return list_literal(p, t, out);
    case MS_T_Match:
        return match_expression(p, t, out);
    case MS_T_LBrace:
        return map_literal(p, t, out);
    case MS_T_Fn:
        return lambda_expression(p, t, out);
    case MS_T_If:
        return if_expression(p, t, out);
    default:
        report_expected_expression(p, t);
        return false;
    }
}

MS_NODISCARD static bool primary(Parser *p, MsExpr **out) {
    MsToken t = peek(p);
    p->at++;
    MsExpr *e = NULL;
    if (!simple_primary(p, t, &e)) return false;
    if (e == NULL && !primary_operand(p, t, &e)) return false;
    return postfix(p, e, out);
}

/* ---- module ---- */

MS_NODISCARD static bool import_path(Parser *p, MsStr *out) {
    MsToken token = {0};
    if (!need_token(p, MS_T_String, &token)) return false;
    if (!single_line(p, token, "import paths")) return false;
    TextParts parts = {0};
    if (!text_parts_of(p, token, &parts)) return false;
    MsStr result;
    if (!plain_text(parts, &result)) {
        fail(p, token, LIT("import paths cannot interpolate; write the path as plain text without {…}"));
        return false;
    }
    *out = result;
    return true;
}

MS_NODISCARD static bool import_names(Parser *p, bool wrapped, uint32_t *count, MsToken **out) {
    size_t m = mark(p);
    for (;;) {
        MsToken n = {0};
        if (!need_token(p, MS_T_Name, &n)) return false;
        push(p, &n, sizeof n);
        if (kind(p) == MS_T_Name && text_is(p, peek(p), "as")) {
            fail(p, peek(p), LIT("imports cannot be renamed with 'as'; import the name as the module declares it"));
            return false;
        }
        if (!take(p, MS_T_Comma) || (wrapped && kind(p) == MS_T_RParen)) {
            break;
        }
    }
    *out = finish(p, m, count, sizeof(MsToken), _Alignof(MsToken));
    return true;
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
MS_NODISCARD static bool import_statement(Parser *p, MsBuf *imports) {
    MsPos pos = previous(p).pos;
    if (kind(p) == MS_T_Star) {
        fail(p, peek(p), LIT("namespace and wildcard imports are unsupported; import individual exports with 'import Name, OtherName from \"./module.ms\"'"));
        return false;
    }
    if (kind(p) == MS_T_LBrace) {
        fail(p, peek(p), LIT("imports take no braces; write 'import a, b from \"path.ms\"', or 'import (a, b) from \"path.ms\"' to wrap across lines"));
        return false;
    }
    bool wrapped = take(p, MS_T_LParen);
    for (;;) {
        uint32_t n;
        MsToken *names = NULL;
        if (!import_names(p, wrapped, &n, &names)) return false;
        if (wrapped && kind(p) == MS_T_RParen) {
            if (!need(p, MS_T_RParen)) return false;
            if (!need_from(p)) return false;
            MsStr path = {0};
            if (!import_path(p, &path)) return false;
            push_imports(p, imports, pos, names, n, path);
            break;
        }
        if (!need_from(p)) return false;
        MsStr path = {0};
        if (!import_path(p, &path)) return false;
        push_imports(p, imports, pos, names, n, path);
        if (!wrapped) {
            break;
        }
        if (!take(p, MS_T_Comma) || kind(p) == MS_T_RParen) {
            if (!need(p, MS_T_RParen)) return false;
            break;
        }
    }
    if (!end(p)) return false;
    return true;
}

MS_NODISCARD static bool parse_module(Parser *p, MsBuf *imports, MsBuf *decls) {
    while (kind(p) != MS_T_Eof) {
        newlines(p);
        if (kind(p) == MS_T_Eof) {
            break;
        }
        if (take(p, MS_T_Import)) {
            if (!import_statement(p, imports)) return false;
            continue;
        }
        if (kind(p) == MS_T_Name && text_is(p, peek(p), "from") && ahead(p, 1).kind == MS_T_String) {
            fail(p, peek(p), LIT("imports read: import name, other from \"path.ms\""));
            return false;
        }
        MsToken export_tok = peek(p);
        bool exported = take(p, MS_T_Export);
        MsDecl *d = NULL;
        if (!declaration(p, &d)) return false;
        if (exported && (d->kind == MS_D_IMPL || d->kind == MS_D_TEST)) {
            fail(p, export_tok, LIT("only types, interfaces, and named functions can be exported; remove 'export' before this method, impl, test, or bench (a method is exported with its type)"));
            return false;
        }
        d->is_exported = exported;
        MS_VEC_PUSH(*decls, MsDecl *, d);
    }
    return true;
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
    bool ok = parse_module(&p, &imports, &decls);
    if (ok) {
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
    }
    ms_buf_free(&scratch);
    ms_buf_free(&bytes);
    ms_buf_free(&imports);
    ms_buf_free(&decls);
    return ok;
}
