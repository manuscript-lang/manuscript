/* `match` expressions and patterns in function bodies (the Rust checker's match_expression and
 * match_literals). Handled: a scrutinee of `Int`, `String` or `Bool`, literal arms with at most a
 * final `_`, arms that are one value each (or none, for a `Void` match), and the `if c: a else: b`
 * form the parser writes as a match over `Bool`. Every diagnostic case (duplicate or unreachable
 * arm, a missing `_`, mismatched arm types) and every other construct leaves the function to the
 * Rust checker. */
#include <string.h>

#include "check/check_body.h"
#include "ms/constfold.h"

/* What the arms matched so far. */
typedef struct MatchSeen {
    MsBuf keys; /* MsStr: the spelling of each literal, to find a repeat */
    bool wildcard;
    bool has_true, has_false;
} MatchSeen;

/* `kind` followed by `text`, in the arena. */
static MsStr match_key(MsArena *arena, const char *kind, MsStr text) {
    return ms_arena_fmt(arena, "%s%.*s", kind, (int)text.len, text.len == 0 ? "" : text.ptr);
}

/* The identity of a literal arm: kind byte, then its text. Same spelling means the same value. */
static MsStr match_literal_key(MsBody *b, const MsExpr *path, bool *is_bool) {
    MsArena *arena = &b->c->arena;
    *is_bool = false;
    switch ((MsExprKind)path->kind) {
    case MS_E_NUMBER: return match_key(arena, "n", ms_number_canonical(arena, ms_name(b->c->names, path->u.sym)));
    case MS_E_BOOL:
        *is_bool = true;
        return match_key(arena, path->u.flag ? "bt" : "bf", (MsStr){0});
    case MS_E_TEXT:
        if (path->u.text.len != 1 || path->u.text.ptr[0].expr != NULL) {
            break;
        }
        return match_key(arena, "s", path->u.text.ptr[0].lit);
    case MS_E_UNARY: {
        const MsExpr *operand = path->u.bin.left;
        if (path->op != MS_U_NEG || operand->kind != MS_E_NUMBER) {
            break;
        }
        // Zero has no sign: `-0` repeats `0`.
        const MsStr value = ms_number_canonical(arena, ms_name(b->c->names, operand->u.sym));
        bool zero = true;
        for (size_t i = 0; i < value.len; i++) {
            zero = zero && value.ptr[i] == '0';
        }
        return match_key(arena, zero ? "n" : "n-", value);
    }
    default: break;
    }
    return (MsStr){0};
}

static bool match_seen_before(const MatchSeen *seen, MsStr key) {
    const MsStr *keys = ms_buf_items(&seen->keys);
    for (size_t i = 0; i < MS_VEC_LEN(seen->keys, MsStr); i++) {
        if (keys[i].len == key.len && memcmp(keys[i].ptr, key.ptr, key.len) == 0) {
            return true;
        }
    }
    return false;
}

static bool match_is_wildcard(const MsBody *b, const MsExpr *path) {
    if (path->kind != MS_E_NAME) {
        return false;
    }
    const MsStr name = ms_name(b->c->names, path->u.sym);
    return name.len == 1 && name.ptr[0] == '_';
}

/* Checks one arm's pattern against the scrutinee type; false when it is not one handled without a
 * diagnostic. */
static bool match_literal_arm(MsBody *b, const MsArm *arm, bool last, MsTy scrutinee, MatchSeen *seen) {
    if (arm->bindings.len != 0) {
        return false;
    }
    if (match_is_wildcard(b, arm->path)) {
        const bool both_bools = scrutinee == b->bool_ty && seen->has_true && seen->has_false;
        const bool ok = !seen->wildcard && last && !both_bools;
        seen->wildcard = true;
        return ok;
    }
    bool is_bool = false;
    const MsStr key = match_literal_key(b, arm->path, &is_bool);
    if (key.len == 0 || seen->wildcard || match_seen_before(seen, key)) {
        return false;
    }
    if (ms_body_expr(b, arm->path, scrutinee) == MS_TY_NONE) {
        return false;
    }
    if (is_bool) {
        seen->has_true = seen->has_true || arm->path->u.flag;
        seen->has_false = seen->has_false || !arm->path->u.flag;
    }
    MS_VEC_PUSH(seen->keys, MsStr, key);
    return true;
}

/* One arm's body: a statement arm runs its block (`falls` says it can reach the end), a value arm
 * is checked against the result so far, which its value then fixes. The arm's bindings close
 * with it. */
static bool match_arm_body(MsBody *b, const MsArm *arm, bool valued, MsTy *result, bool *falls) {
    const uint32_t first = b->facts->bindings.count;
    if ((arm->value != NULL) != valued) {
        return false;
    }
    if (!valued) {
        *falls = ms_body_block(b, &arm->body) || *falls;
        ms_body_close_from(b, first);
        return b->supported;
    }
    const MsTy ty = ms_body_block_value(b, &arm->body, arm->value, *result);
    ms_body_close_from(b, first);
    if (ty == MS_TY_NONE || ty == b->void_ty) {
        return false;
    }
    *result = ty;
    return true;
}

MsTy ms_body_match(MsBody *b, const MsExpr *e, MsTy expected) {
    const MsExpr *scrutinee = e->u.match.scrutinee;
    const MsTy ty = ms_body_expr(b, scrutinee, MS_TY_NONE);
    if (ty == b->invalid_ty) {
        // The scrutinee is already reported: the arms are not checked, and the match neither falls
        // through nor has a value beyond the one the context expects.
        b->match_falls = false;
        return expected != MS_TY_NONE ? expected : b->never_ty;
    }
    if (ty != MS_TY_NONE && ms_ty_kind(&b->c->tys, ty) == MS_K_ALTERNATIVE) {
        if (ms_body_is_foreign_opaque(b, ty)) {
            return ms_body_unsupported(b);
        }
        return ms_body_match_alternative(b, e, expected, ty);
    }
    if (ty != b->int_ty && ty != b->string_ty && ty != b->bool_ty) {
        return ms_body_unsupported(b);
    }
    const uint32_t count = e->u.match.arms.len;
    if (count == 0 || (e->u.match.arms.ptr[0]->from_if && ty != b->bool_ty)) {
        return ms_body_unsupported(b);
    }
    const bool valued = e->u.match.arms.ptr[0]->value != NULL;
    if (!valued && expected != MS_TY_NONE && expected != b->void_ty) {
        return ms_body_unsupported(b);
    }
    MatchSeen seen = {0};
    MsTy result = valued ? expected : b->void_ty;
    bool ok = true, falls = false;
    for (uint32_t i = 0; i < count && ok && b->supported; i++) {
        const MsArm *arm = e->u.match.arms.ptr[i];
        ok = match_literal_arm(b, arm, i == count - 1, ty, &seen) && match_arm_body(b, arm, valued, &result, &falls);
    }
    const bool covered = seen.wildcard || (ty == b->bool_ty && seen.has_true && seen.has_false);
    ms_buf_free(&seen.keys);
    if (!ok || !covered || !b->supported) {
        return ms_body_unsupported(b);
    }
    // A statement match falls through when some arm does; a value match always has a value.
    b->match_falls = valued || falls;
    return b->match_falls ? result : b->never_ty;
}
