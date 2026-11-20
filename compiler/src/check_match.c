/* `match` expressions in function bodies (the Rust checker's match_expression, match_literals and the alternative
 * branch of match_arms). Handled:
 *   - a scrutinee of `Int`, `String` or `Bool`: literal arms and at most a final `_`, or both Bool values;
 *   - a scrutinee of an enum the module declares without type parameters: case arms (bare or qualified by the
 *     enum's name) that bind each payload field by name or ignore it with `_`, and at most a final `_`;
 *   - the `if c: a else: b` form the parser writes as a match over `Bool`;
 *   - arms that run statements and end in one value of one type, or that are all statements (a `Void` match).
 * Every diagnostic case (a duplicate or unreachable arm, a missing case or `_`, a payload count that differs, an unread
 * payload, mismatched arm types) and every other construct leaves the function to the Rust checker. */
#include <string.h>

#include "check_body.h"
#include "ms/constfold.h"

/* What the arms matched so far. */
typedef struct MatchSeen {
    MsBuf keys; /* MsStr: the spelling of each literal, to find a repeat */
    bool wildcard;
    bool has_true, has_false;
    bool *cases;         /* by case index: matched already */
    uint32_t cases_seen; /* how many are */
} MatchSeen;

/* The enum a match takes apart: its cases, and the symbol that names it. */
typedef struct MatchEnum {
    const MsCaseRow *cases;
    uint32_t ncases;
    MsSymId sym;
} MatchEnum;

/* What the match decides as it goes: the scrutinee, the result so far, and whether the arms carry values. */
typedef struct MatchState {
    MsTy scrutinee;
    MsTy result;
    bool valued; /* the first arm ends in a value, so every arm must */
    MatchSeen seen;
    MatchEnum enum_type;
    bool is_enum;
} MatchState;

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

/* The name an arm's path gives: a name, or the member of a qualified case; 0 for anything else. */
static MsSym match_path_name(const MsExpr *path) {
    if (path->kind == MS_E_NAME) {
        return path->u.sym;
    }
    return path->kind == MS_E_MEMBER ? path->u.member.name : 0;
}

static bool match_is_wildcard(const MsBody *b, const MsExpr *path) {
    if (path->kind != MS_E_NAME) {
        return false;
    }
    const MsStr name = ms_name(b->c->names, path->u.sym);
    return name.len == 1 && name.ptr[0] == '_';
}

/* The wildcard arm: once, last, and only while values or cases remain. */
static bool match_wildcard_arm(const MatchState *m, bool last) {
    const bool both_bools = m->seen.has_true && m->seen.has_false;
    const bool all_cases = m->is_enum && m->seen.cases_seen == m->enum_type.ncases;
    return !m->seen.wildcard && last && !both_bools && !all_cases;
}

/* A literal arm's pattern against the scrutinee; false when it is not one handled without a diagnostic. */
static bool match_literal_pattern(MsBody *b, const MsArm *arm, MatchState *m) {
    if (arm->bindings.len != 0) {
        return false;
    }
    bool is_bool = false;
    const MsStr key = match_literal_key(b, arm->path, &is_bool);
    if (key.len == 0 || m->seen.wildcard || match_seen_before(&m->seen, key)) {
        return false;
    }
    if (ms_body_expr(b, arm->path, m->scrutinee) == MS_TY_NONE) {
        return false;
    }
    if (is_bool) {
        m->seen.has_true = m->seen.has_true || arm->path->u.flag;
        m->seen.has_false = m->seen.has_false || !arm->path->u.flag;
    }
    MS_VEC_PUSH(m->seen.keys, MsStr, key);
    return true;
}

/* The enum's case a pattern names, or the case count when it names none. A member path must be qualified by the
 * enum's own name (as the module sees it). */
static uint32_t match_find_case(const MsBody *b, const MatchEnum *type, const MsExpr *path) {
    const MsSym name = match_path_name(path);
    if (path->kind == MS_E_MEMBER) {
        const MsExpr *left = path->u.member.left;
        const MsSymId owner = left->kind == MS_E_NAME ? ms_map_get(&b->c->mods[b->module].names, left->u.sym) : MS_NONE;
        if (owner != type->sym) {
            return type->ncases;
        }
    }
    for (uint32_t i = 0; i < type->ncases && name != 0; i++) {
        if (type->cases[i].name == name) {
            return i;
        }
    }
    return type->ncases;
}

/* Records the case an arm matches, allocating the column on first use. */
static void match_record_case(MsBody *b, const MsArm *arm, uint32_t index) {
    MsFacts *facts = b->facts;
    if (facts->arm_case == NULL) {
        const size_t nodes = (size_t)facts->node_count + 1;
        facts->arm_case = MS_NEW_N(&b->c->arena, uint32_t, nodes);
        memset(facts->arm_case, 0xff, nodes * sizeof *facts->arm_case);
    }
    facts->arm_case[arm->id] = index;
}

/* A case arm's pattern: a case of the enum, once, before any `_`, with one name (or `_`) per payload field. The payload
 * names are bound; their binding ids go to `first`..`count`. */
static bool match_case_pattern(MsBody *b, const MsArm *arm, MatchState *m, uint32_t *first) {
    const uint32_t index = match_find_case(b, &m->enum_type, arm->path);
    if (index == m->enum_type.ncases || m->seen.wildcard || m->seen.cases[index]) {
        return false;
    }
    const MsCaseRow *row = &m->enum_type.cases[index];
    // A bare lowercase name names the case and carries no payload names.
    const uint32_t nbindings = arm->bare ? 0 : arm->bindings.len;
    if (row->nfields != nbindings) {
        return false;
    }
    m->seen.cases[index] = true;
    m->seen.cases_seen++;
    match_record_case(b, arm, index);
    *first = b->facts->bindings.count;
    for (uint32_t i = 0; i < nbindings; i++) {
        const MsSym name = arm->bindings.ptr[i].name;
        const MsStr text = ms_name(b->c->names, name);
        const MsKind kind = ms_ty_kind(&b->c->tys, row->fields[i].ty);
        if (kind == MS_K_INVALID || kind == MS_K_INFERRED || kind == MS_K_VARIABLE || row->fields[i].ty == MS_TY_NONE) {
            return false;
        }
        if (text.len == 1 && text.ptr[0] == '_') {
            continue;
        }
        if (ms_body_bind(b, name, row->fields[i].ty, arm->id, 0, MS_ROLE_ARM) == MS_NONE) {
            return false;
        }
    }
    return true;
}

/* Ends the payload names an arm bound: each must have been read unless it starts with `_`, and none is visible after. */
static bool match_close_payloads(MsBody *b, uint32_t first) {
    const MsBindings *bindings = &b->facts->bindings;
    bool all_read = true;
    for (uint32_t i = first; i < bindings->count; i++) {
        const MsStr name = ms_name(b->c->names, bindings->name[i]);
        const bool ignored = name.len != 0 && name.ptr[0] == '_';
        all_read = all_read && (ignored || (bindings->flags[i] & MS_BIND_READ) != 0);
        b->closed[i] = true;
    }
    return all_read;
}

/* An arm's statements and value (or none) against the result so far; false when the arm is left to Rust. */
static bool check_arm_body(MsBody *b, const MsArm *arm, MatchState *m, bool first_arm) {
    if (first_arm) {
        m->valued = arm->value != NULL;
    }
    if ((arm->value != NULL) != m->valued) {
        return false;
    }
    if (!m->valued) {
        // A statement-only arm must let control through, or the match would not.
        return ms_body_block(b, &arm->body);
    }
    const MsTy ty = ms_body_block_value(b, &arm->body, arm->value, m->result);
    if (ty == MS_TY_NONE || ty == b->void_ty) {
        return false;
    }
    m->result = ty;
    return true;
}

/* One arm: its pattern, then its body with the payload names in scope. */
static bool check_arm(MsBody *b, const MsArm *arm, bool first_arm, bool last, MatchState *m) {
    uint32_t first_payload = b->facts->bindings.count;
    if (match_is_wildcard(b, arm->path)) {
        const bool ok = arm->bindings.len == 0 && match_wildcard_arm(m, last);
        m->seen.wildcard = true;
        return ok && check_arm_body(b, arm, m, first_arm);
    }
    const bool pattern = m->is_enum ? match_case_pattern(b, arm, m, &first_payload)
                                    : match_literal_pattern(b, arm, m);
    if (!pattern) {
        return false;
    }
    const bool body = check_arm_body(b, arm, m, first_arm);
    return match_close_payloads(b, first_payload) && body;
}

/* The enum a type is, when the match can take it apart: declared by this module, without type parameters. */
static bool match_enum_of(MsBody *b, MsTy ty, MatchEnum *out) {
    const MsTyTable *tys = &b->c->tys;
    const uint32_t def = tys->def[ty];
    if (ms_ty_kind(tys, ty) != MS_K_ALTERNATIVE || tys->nargs[ty] != 0 || def == 0) {
        return false;
    }
    const MsDef *row = ms_def(b->c, def - 1);
    out->cases = row->cases;
    out->ncases = row->ncases;
    out->sym = def - 1;
    return row->ncases != 0;
}

/* Whether the arms covered every value or case. */
static bool match_covered(const MatchState *m) {
    if (m->seen.wildcard) {
        return true;
    }
    if (m->is_enum) {
        return m->seen.cases_seen == m->enum_type.ncases;
    }
    return m->seen.has_true && m->seen.has_false;
}

MsTy ms_body_match(MsBody *b, const MsExpr *e, MsTy expected) {
    MatchState m = {.result = expected};
    m.scrutinee = ms_body_expr(b, e->u.match.scrutinee, MS_TY_NONE);
    const bool literal = m.scrutinee == b->int_ty || m.scrutinee == b->string_ty || m.scrutinee == b->bool_ty;
    const uint32_t count = e->u.match.arms.len;
    if (m.scrutinee == MS_TY_NONE || count == 0) {
        return ms_body_unsupported(b);
    }
    m.is_enum = !literal && match_enum_of(b, m.scrutinee, &m.enum_type);
    if ((!literal && !m.is_enum) || (e->u.match.arms.ptr[0]->from_if && m.scrutinee != b->bool_ty)) {
        return ms_body_unsupported(b);
    }
    if (m.is_enum) {
        m.seen.cases = MS_NEW_N(&b->c->arena, bool, m.enum_type.ncases);
        memset(m.seen.cases, 0, m.enum_type.ncases * sizeof *m.seen.cases);
    }
    bool ok = true;
    for (uint32_t i = 0; i < count && ok && b->supported; i++) {
        ok = check_arm(b, e->u.match.arms.ptr[i], i == 0, i == count - 1, &m);
    }
    const bool covered = ok && match_covered(&m);
    ms_buf_free(&m.seen.keys);
    if (!ok || !covered || !b->supported) {
        return ms_body_unsupported(b);
    }
    if (m.valued) {
        return m.result;
    }
    return expected == MS_TY_NONE || expected == b->void_ty ? b->void_ty : ms_body_unsupported(b);
}
