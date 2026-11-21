/* Strings built from pieces: `a + b + c` and `f"{x} and {y}"`. The pieces of a sum or an
 * interpolation are evaluated left to right and joined by one runtime call, at most LT_MAX_JOIN
 * to a call (a longer text joins the first group, then that result with the next pieces). Pieces
 * that are all strings join with `msrt_string_concatN`. Every other piece becomes a string through
 * its type's text form, one table (`lt_forms`) read by type; a form the join writes itself (an
 * integer, in decimal) joins with `msrt_string_fmtN` and a mask of which pieces it is. */
#include <stdio.h>
#include <string.h>

#include "ms/lower_internal.h"

enum { LT_MAX_JOIN = 6 };

/* How a value of one type becomes text: the runtime function that writes it, or `fused` when the
 * join itself writes it (the piece stays the raw value). A type without a row has no text form
 * here and leaves the function to the Rust lowering. */
typedef struct LtForm {
    MirTy ty;
    const char *symbol;
    MirRole role;
    bool fused;
} LtForm;

static const LtForm lt_forms[] = {
    {MIR_INT, "msrt_int_to_string", MR_INT_TO_STRING, true},
    {MIR_FLOAT, "msrt_float_to_string", MR_NONE, false},
    {MIR_BOOL, "msrt_bool_to_string", MR_NONE, false},
};

static const LtForm *lt_form_of(MirTy ty) {
    for (size_t i = 0; i < sizeof lt_forms / sizeof lt_forms[0]; i++) {
        if (lt_forms[i].ty == ty) {
            return &lt_forms[i];
        }
    }
    return NULL;
}

/* One operand of a join: a string, or a value the join writes itself (`is_int`: an integer). */
typedef struct LtPiece {
    MirValue v;
    bool is_int;
    bool owned; /* a temporary string: dropped once the join has read it */
} LtPiece;

typedef struct LtPieces {
    LtPiece *items;
    uint32_t len;
} LtPieces;

/* How many pieces `e` gives: the operands of a chain of `+`, the parts of an interpolation. */
static uint32_t lt_count(const MsExpr *e) {
    if (e->kind == MS_E_BINARY && e->op == MS_B_ADD) {
        return lt_count(e->u.bin.left) + lt_count(e->u.bin.right);
    }
    return e->kind == MS_E_TEXT && e->u.text.len > 1 ? e->u.text.len : 1;
}

static void lt_push(LtPieces *pieces, LtPiece piece) {
    pieces->items[pieces->len++] = piece;
}

static bool lt_literal(Lb *lb, MsStr lit, LtPieces *pieces) {
    const MirImm imm = {.tag = MI_STR, .a = mir_add_string(lb->m, lit.ptr, lit.len)};
    lt_push(pieces, (LtPiece){mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, imm, MIR_STR), false, false});
    return true;
}

/* The runtime function `name` over `params`, declared once per name and operand types. */
static uint32_t lt_runtime_extern(Lb *lb, const MirExtern *want) {
    for (uint32_t i = 0; i < lb->m->nexterns; i++) {
        const MirExtern *known = &lb->m->externs[i];
        if (known->name == want->name && known->nparams == want->nparams &&
            (want->nparams == 0 || memcmp(known->params, want->params, (size_t)want->nparams * sizeof *want->params) == 0)) {
            return i;
        }
    }
    return mir_add_extern(lb->m, want);
}

/* The piece `value` of a text: a string as it is, a value with a text form as that form's result
 * (or itself when the join writes it). Any other type marks the function unsupported. */
static LtPiece lt_piece(Lb *lb, LbVal value) {
    const MirTy ty = mir_b_ty(&lb->b, value.v);
    if (ty == MIR_STR) {
        return (LtPiece){value.v, false, value.owned};
    }
    const LtForm *form = lt_form_of(ty);
    if (form == NULL) {
        (void)lb_unsupported(lb);
        return (LtPiece){MIR_NONE, false, false};
    }
    if (form->fused) {
        return (LtPiece){value.v, true, value.owned};
    }
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, 1);
    params[0] = (MirParam){ty, MM_BORROW};
    const MirExtern ext = {.name = mir_name(lb->m, form->symbol, strlen(form->symbol)),
                           .params = params, .nparams = 1, .ret = MIR_STR, .fresh = true, .leaf = true, .role = form->role};
    const MirValue text = mir_b_call_rt(&lb->b, lt_runtime_extern(lb, &ext), &value.v, 1);
    if (value.owned) {
        lb_drop(lb, value.v);
    }
    return (LtPiece){text, false, true};
}

/* The pieces of `e`, evaluated left to right. */
static void lt_collect(Lb *lb, const MsExpr *e, LtPieces *pieces) {
    if (e->kind == MS_E_BINARY && e->op == MS_B_ADD) {
        lt_collect(lb, e->u.bin.left, pieces);
        lt_collect(lb, e->u.bin.right, pieces);
        return;
    }
    if (e->kind == MS_E_TEXT && e->u.text.len > 1) {
        for (uint32_t i = 0; i < e->u.text.len && lb->ok; i++) {
            const MsTextPart *part = &e->u.text.ptr[i];
            if (part->expr == NULL) {
                (void)lt_literal(lb, part->lit, pieces);
                continue;
            }
            const LbVal value = lb_expr(lb, part->expr);
            if (!lb->ok) {
                return;
            }
            const LtPiece piece = lt_piece(lb, value);
            if (!lb->ok) {
                return;
            }
            lt_push(pieces, piece);
        }
        return;
    }
    const LbVal value = lb_expr(lb, e);
    if (lb->ok) {
        lt_push(pieces, (LtPiece){value.v, false, value.owned});
    }
}

/* The runtime function joining `count` pieces: `msrt_string_concat` for two strings,
 * `msrt_string_concatN` for more, `msrt_string_fmtN` (a mask first) when a piece is an integer. */
static uint32_t lt_join_extern(Lb *lb, const LtPiece *group, uint32_t count, bool with_ints) {
    char text[40];
    const char *base = with_ints ? "msrt_string_fmt" : "msrt_string_concat";
    const bool plain_pair = !with_ints && count == 2; // the two-string join has no count in its name
    const int length = plain_pair ? snprintf(text, sizeof text, "%s", base) : snprintf(text, sizeof text, "%s%u", base, count);
    const MsSym name = mir_name(lb->m, text, (size_t)length);
    const uint32_t nparams = count + (with_ints ? 1 : 0);
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, nparams);
    uint32_t next = 0;
    if (with_ints) {
        params[next++] = (MirParam){MIR_INT, MM_BORROW};
    }
    for (uint32_t i = 0; i < count; i++) {
        params[next++] = (MirParam){group[i].is_int ? MIR_INT : MIR_STR, MM_BORROW};
    }
    const MirExtern ext = {
        .name = name, .params = params, .nparams = nparams, .ret = MIR_STR, .fresh = true, .leaf = true,
        .role = !with_ints && count == 2 ? MR_STRING_CONCAT : MR_STRING_JOIN};
    return lt_runtime_extern(lb, &ext);
}

/* One runtime call over up to LT_MAX_JOIN pieces; the temporaries among them are dropped after. */
static MirValue lt_join_group(Lb *lb, const LtPiece *group, uint32_t count) {
    bool with_ints = false;
    int64_t mask = 0;
    MirValue *args = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)count + 1);
    uint32_t next = 0;
    for (uint32_t i = 0; i < count; i++) {
        if (group[i].is_int) {
            with_ints = true;
            mask |= (int64_t)1 << i;
        }
    }
    if (with_ints) {
        args[next++] = mir_b_iconst(&lb->b, mask);
    }
    for (uint32_t i = 0; i < count; i++) {
        args[next++] = group[i].v;
    }
    const MirValue joined = mir_b_call_rt(&lb->b, lt_join_extern(lb, group, count, with_ints), args, next);
    for (uint32_t i = 0; i < count; i++) {
        if (group[i].owned) {
            lb_drop(lb, group[i].v);
        }
    }
    return joined;
}

static LbVal lt_join(Lb *lb, LtPieces *pieces) {
    const LtPiece *rest = pieces->items;
    uint32_t left = pieces->len;
    uint32_t take = left < LT_MAX_JOIN ? left : LT_MAX_JOIN;
    MirValue joined = lt_join_group(lb, rest, take);
    rest += take;
    left -= take;
    while (left > 0) {
        take = left < LT_MAX_JOIN - 1 ? left : LT_MAX_JOIN - 1;
        LtPiece *group = MS_NEW_N(&lb->b.scratch, LtPiece, (size_t)take + 1);
        group[0] = (LtPiece){joined, false, true}; // the previous join is a temporary
        memcpy(group + 1, rest, (size_t)take * sizeof *group);
        joined = lt_join_group(lb, group, take + 1);
        rest += take;
        left -= take;
    }
    return (LbVal){joined, true};
}

/* An interpolated text, or a chain of `+` over strings. */
LbVal lt_text(Lb *lb, const MsExpr *e) {
    LtPieces pieces = {MS_NEW_N(&lb->b.scratch, LtPiece, (size_t)lt_count(e) + 1), 0};
    lt_collect(lb, e, &pieces);
    if (!lb->ok || pieces.len < 2) {
        return lb_unsupported(lb); // one piece is a plain literal or name, lowered elsewhere
    }
    return lt_join(lb, &pieces);
}
