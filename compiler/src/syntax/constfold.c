/* Constant arithmetic over literals; see ms/constfold.h. A port of
 * crates/ms-check/src/constfaults.rs and crates/ms-syntax/src/number.rs. */
#include <string.h>
#include "ms_rt/chars.h"

#include "ms/constfold.h"
#include "ms/text.h"

#define MAX_MEMO_RANGES 8

/* ---- number literals ---- */

/* The value of a digit of any radix up to 16, or -1. */
__extension__ typedef unsigned __int128 MsUint128;

/* Parses `digits` (no separators) as an unsigned number of the radix; false when it is empty, has
 * a stray character or does not fit 128 bits. */
static bool parse_u128(const char *digits, size_t n, unsigned radix, MsUint128 *out) {
    if (n == 0) {
        return false;
    }
    MsUint128 value = 0;
    for (size_t i = 0; i < n; i++) {
        int digit = ms_text_digit_value(digits[i]);
        if (digit < 0 || (unsigned)digit >= radix) {
            return false;
        }
        if (__builtin_mul_overflow(value, (MsUint128)radix, &value) ||
            __builtin_add_overflow(value, (MsUint128)digit, &value)) {
            return false;
        }
    }
    *out = value;
    return true;
}

/* `value` in decimal, NUL-terminated, at the end of `buf`; returns where it starts. */
static char *u128_to_text(char *end, MsUint128 value) {
    char *at = end;
    *--at = 0;
    do {
        *--at = (char)('0' + (int)(value % 10));
        value /= 10;
    } while (value != 0);
    return at;
}

static bool has_separator(MsStr text) {
    return memchr(text.ptr, '_', text.len) != NULL;
}

/* `text` without `_`, in the arena. */
static MsStr without_separators(MsArena *arena, MsStr text) {
    char *plain = MS_NEW_N(arena, char, (size_t)text.len + 1);
    size_t n = 0;
    for (uint32_t i = 0; i < text.len; i++) {
        if (text.ptr[i] != '_') {
            plain[n++] = text.ptr[i];
        }
    }
    plain[n] = 0;
    return (MsStr){plain, (uint32_t)n};
}

MsStr ms_number_canonical(MsArena *arena, MsStr text) {
    unsigned radix = 10;
    if (text.len >= 2 && text.ptr[0] == '0') {
        if (text.ptr[1] == 'x') {
            radix = 16;
        } else if (text.ptr[1] == 'b') {
            radix = 2;
        }
    }
    if (radix == 10) {
        return has_separator(text) ? without_separators(arena, text) : text;
    }
    MsStr plain = without_separators(arena, text);
    MsUint128 value = 0;
    if (plain.len < 2 || !parse_u128(plain.ptr + 2, plain.len - 2, radix, &value)) {
        return text;
    }
    char buf[48];
    char *start = u128_to_text(buf + sizeof buf, value);
    return (MsStr){ms_arena_strndup(arena, start, strlen(start)), (uint32_t)strlen(start)};
}

bool ms_number_is_decimal(MsStr canonical) {
    return canonical.len > 0 && canonical.ptr[canonical.len - 1] == 'd';
}

bool ms_number_is_fractional(MsStr canonical) {
    if (ms_number_is_decimal(canonical)) {
        return false;
    }
    for (uint32_t i = 0; i < canonical.len; i++) {
        char c = canonical.ptr[i];
        if (c == '.' || c == 'e' || c == 'E') {
            return true;
        }
    }
    return false;
}

/* Rust's `str::parse::<i128>`: an optional sign, then digits only. */
static bool parse_i128(MsStr text, MsInt128 *out) {
    size_t at = 0;
    bool negative = false;
    if (text.len > 0 && (text.ptr[0] == '+' || text.ptr[0] == '-')) {
        negative = text.ptr[0] == '-';
        at = 1;
    }
    MsUint128 magnitude = 0;
    if (!parse_u128(text.ptr + at, text.len - at, 10, &magnitude)) {
        return false;
    }
    const MsUint128 most = ((MsUint128)1 << 127) - 1;
    if (negative) {
        if (magnitude > most + 1) {
            return false;
        }
        *out = (MsInt128)(0 - magnitude);
        return true;
    }
    if (magnitude > most) {
        return false;
    }
    *out = (MsInt128)magnitude;
    return true;
}

/* ---- memo ---- */

/* The folds of every node within one range: 0 unknown, 1 not constant, 2 constant. */
typedef struct FoldMemo {
    MsInt128 lo, hi;
    uint8_t *state;
    MsInt128 *value;
} FoldMemo;

struct MsLiteralFacts {
    MsArena *arena;
    const MsNames *names;
    uint32_t node_count;
    FoldMemo memos[MAX_MEMO_RANGES];
    size_t nmemos;
    uint8_t *kinds; /* by node: 0 unknown, else 1 + MsLiteralKind */
};

MsLiteralFacts *ms_literal_facts_new(MsArena *arena, const MsNames *names, uint32_t node_count) {
    MsLiteralFacts *facts = MS_NEW_N(arena, MsLiteralFacts, 1);
    memset(facts, 0, sizeof *facts);
    facts->arena = arena;
    facts->names = names;
    facts->node_count = node_count;
    facts->kinds = MS_NEW_N(arena, uint8_t, (size_t)node_count + 1);
    memset(facts->kinds, 0, (size_t)node_count + 1);
    return facts;
}

/* The memo of [lo, hi], made on first use; NULL once MAX_MEMO_RANGES ranges are in use. */
static FoldMemo *memo_for(MsLiteralFacts *facts, MsInt128 lo, MsInt128 hi) {
    for (size_t i = 0; i < facts->nmemos; i++) {
        if (facts->memos[i].lo == lo && facts->memos[i].hi == hi) {
            return &facts->memos[i];
        }
    }
    if (facts->nmemos == MAX_MEMO_RANGES) {
        return NULL;
    }
    FoldMemo *memo = &facts->memos[facts->nmemos++];
    size_t count = (size_t)facts->node_count + 1;
    memo->lo = lo;
    memo->hi = hi;
    memo->state = MS_NEW_N(facts->arena, uint8_t, count);
    memo->value = MS_NEW_N(facts->arena, MsInt128, count);
    memset(memo->state, 0, count);
    return memo;
}

/* ---- folding ---- */

/* `a op b` for the five arithmetic operators; false on overflow of 128 bits, on a zero divisor and
 * for any other operator. */
static bool apply(MsBinaryOp op, MsInt128 a, MsInt128 b, MsInt128 *out) {
    const MsInt128 least = (MsInt128)((MsUint128)1 << 127);
    switch (op) {
    case MS_B_ADD:
        return !__builtin_add_overflow(a, b, out);
    case MS_B_SUB:
        return !__builtin_sub_overflow(a, b, out);
    case MS_B_MUL:
        return !__builtin_mul_overflow(a, b, out);
    case MS_B_DIV:
    case MS_B_REM:
        if (b == 0 || (a == least && b == -1)) {
            return false;
        }
        *out = op == MS_B_DIV ? a / b : a % b;
        return true;
    case MS_B_OR:
    case MS_B_AND:
    case MS_B_EQ:
    case MS_B_NE:
    case MS_B_LT:
    case MS_B_GT:
    case MS_B_LE:
    case MS_B_GE:
        return false;
    }
    return false;
}

static bool fits(MsInt128 v, MsInt128 lo, MsInt128 hi) {
    return v >= lo && v <= hi;
}

static bool fold_number(MsLiteralFacts *facts, const MsExpr *e, MsInt128 *out) {
    MsStr text = ms_number_canonical(facts->arena, ms_name(facts->names, e->u.sym));
    return parse_i128(text, out);
}

static bool fold_unary(MsLiteralFacts *facts, const MsExpr *e, MsInt128 lo, MsInt128 hi, MsInt128 *out) {
    MsInt128 v = 0;
    if (!ms_fold(facts, e->u.bin.left, lo, hi, &v)) {
        return false;
    }
    if (e->op == MS_U_PLUS) {
        *out = v;
        return true;
    }
    MsInt128 negated = 0;
    if (e->op != MS_U_NEG || __builtin_sub_overflow((MsInt128)0, v, &negated) || !fits(negated, lo, hi)) {
        return false;
    }
    *out = negated;
    return true;
}

static bool fold_binary(MsLiteralFacts *facts, const MsExpr *e, MsInt128 lo, MsInt128 hi, MsInt128 *out) {
    MsInt128 a = 0;
    MsInt128 b = 0;
    bool known_a = ms_fold(facts, e->u.bin.left, lo, hi, &a);
    bool known_b = ms_fold(facts, e->u.bin.right, lo, hi, &b);
    MsInt128 result = 0;
    if (!known_a || !known_b || !apply((MsBinaryOp)e->op, a, b, &result) || !fits(result, lo, hi)) {
        return false;
    }
    *out = result;
    return true;
}

static bool fold_node(MsLiteralFacts *facts, const MsExpr *e, MsInt128 lo, MsInt128 hi, MsInt128 *out) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER:
        return fold_number(facts, e, out);
    case MS_E_UNARY:
        return fold_unary(facts, e, lo, hi, out);
    case MS_E_BINARY:
        return fold_binary(facts, e, lo, hi, out);
    case MS_E_BOOL:
    case MS_E_VOID:
    case MS_E_TEXT:
    case MS_E_NAME:
    case MS_E_MEMBER:
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_LAMBDA:
    case MS_E_CALL:
    case MS_E_MATCH:
        return false;
    }
    return false;
}

bool ms_fold(MsLiteralFacts *facts, const MsExpr *e, MsInt128 lo, MsInt128 hi, MsInt128 *out) {
    FoldMemo *memo = e->id <= facts->node_count ? memo_for(facts, lo, hi) : NULL;
    if (memo == NULL) {
        return fold_node(facts, e, lo, hi, out);
    }
    if (memo->state[e->id] == 0) {
        MsInt128 value = 0;
        bool known = fold_node(facts, e, lo, hi, &value);
        memo->state[e->id] = known ? 2 : 1;
        memo->value[e->id] = value;
    }
    *out = memo->value[e->id];
    return memo->state[e->id] == 2;
}

/* ---- literal kind ---- */

static MsLiteralKind kind_of_number(MsLiteralFacts *facts, const MsExpr *e) {
    MsStr text = ms_number_canonical(facts->arena, ms_name(facts->names, e->u.sym));
    if (ms_number_is_decimal(text)) {
        return MS_LITERAL_NONE;
    }
    return ms_number_is_fractional(text) ? MS_LITERAL_FRACTIONAL : MS_LITERAL_INTEGER;
}

static bool is_arithmetic(MsBinaryOp op) {
    return op == MS_B_ADD || op == MS_B_SUB || op == MS_B_MUL || op == MS_B_DIV || op == MS_B_REM;
}

static MsLiteralKind kind_of_binary(MsLiteralFacts *facts, const MsExpr *e) {
    if (!is_arithmetic((MsBinaryOp)e->op)) {
        return MS_LITERAL_NONE;
    }
    MsLiteralKind left = ms_literal_tree_kind(facts, e->u.bin.left);
    MsLiteralKind right = ms_literal_tree_kind(facts, e->u.bin.right);
    return left == right ? left : MS_LITERAL_NONE;
}

static MsLiteralKind kind_of(MsLiteralFacts *facts, const MsExpr *e) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER:
        return kind_of_number(facts, e);
    case MS_E_UNARY:
        return e->op == MS_U_NEG || e->op == MS_U_PLUS ? ms_literal_tree_kind(facts, e->u.bin.left)
                                                        : MS_LITERAL_NONE;
    case MS_E_BINARY:
        return kind_of_binary(facts, e);
    case MS_E_BOOL:
    case MS_E_VOID:
    case MS_E_TEXT:
    case MS_E_NAME:
    case MS_E_MEMBER:
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_LAMBDA:
    case MS_E_CALL:
    case MS_E_MATCH:
        return MS_LITERAL_NONE;
    }
    return MS_LITERAL_NONE;
}

MsLiteralKind ms_literal_tree_kind(MsLiteralFacts *facts, const MsExpr *e) {
    if (e->id > facts->node_count) {
        return kind_of(facts, e);
    }
    if (facts->kinds[e->id] == 0) {
        facts->kinds[e->id] = (uint8_t)(1 + kind_of(facts, e));
    }
    return (MsLiteralKind)(facts->kinds[e->id] - 1);
}

/* ---- certain faults ---- */

static MsStr empty_message(void) {
    return (MsStr){"", 0};
}

/* `value` in decimal, in the arena. */
static MsStr int128_text(MsArena *arena, MsInt128 value) {
    char buf[48];
    MsUint128 magnitude = value < 0 ? 0 - (MsUint128)value : (MsUint128)value;
    char *start = u128_to_text(buf + sizeof buf, magnitude);
    if (value < 0) {
        *--start = '-';
    }
    return (MsStr){ms_arena_strndup(arena, start, strlen(start)), (uint32_t)strlen(start)};
}

MsStr ms_constant_arithmetic_fault(MsArena *arena, MsLiteralFacts *facts, MsBinaryOp op, const MsExpr *left,
                                   const MsExpr *right, const char *type_name, MsInt128 lo, MsInt128 hi) {
    MsInt128 divisor = 0;
    if ((op == MS_B_DIV || op == MS_B_REM) && ms_fold(facts, right, lo, hi, &divisor) && divisor == 0) {
        return ms_arena_fmt(arena, "division by zero always faults; guard the divisor or use a nonzero constant");
    }
    MsInt128 a = 0;
    MsInt128 b = 0;
    MsInt128 result = 0;
    bool known = ms_fold(facts, left, lo, hi, &a) && ms_fold(facts, right, lo, hi, &b);
    if (!known || !apply(op, a, b, &result) || fits(result, lo, hi)) {
        return empty_message();
    }
    MsStr shown_a = int128_text(arena, a);
    MsStr shown_b = int128_text(arena, b);
    return ms_arena_fmt(arena,
                        "%.*s %s %.*s overflows %s and always faults; use a smaller value or a wider type such "
                        "as BigInt",
                        (int)shown_a.len, shown_a.ptr, ms_binary_str(op), (int)shown_b.len, shown_b.ptr, type_name);
}

MsStr ms_constant_index_fault(MsArena *arena, MsLiteralFacts *facts, const MsExpr *left, const MsExpr *index,
                              MsInt128 lo, MsInt128 hi) {
    MsInt128 at = 0;
    if (left->kind != MS_E_LIST || !ms_fold(facts, index, lo, hi, &at)) {
        return empty_message();
    }
    MsInt128 len = (MsInt128)left->u.list.len;
    if (at < len && at >= -len) {
        return empty_message();
    }
    MsStr shown = int128_text(arena, at);
    return ms_arena_fmt(arena, "index %.*s is outside this list literal of %u element(s) and always faults",
                        (int)shown.len, shown.ptr, left->u.list.len);
}
