/* `match` over an enum or `Optional` value in function bodies. Handled: arms that name a case (bare,
 * or qualified by the enum's own name) that bind its payload, a `name:` arm for an `Optional`'s
 * payload, a final `_`, one value per arm.
 * A diagnostic case (unknown, repeated or unreachable case, wrong payload count, missing case)
 * and every other construct leaves the function to the Rust checker. */
#include <string.h>

#include "check/check_body.h"

/* The cases of an enum this module may match, read the same way for `Optional` (whose two cases
 * `some(value)` and `none` the bundled `core.ms` declares but the tables do not carry) and for an
 * enum the module declares. */
typedef struct AltInfo {
    MsDef def;     /* a copy: the table may move while the match is checked */
    bool optional; /* the cases are `some(T)` and `none` */
    MsTy payload;  /* the `T` of an `Optional[T]` */
    uint32_t ncases;
} AltInfo;

static bool alt_info(const MsBody *b, MsTy ty, AltInfo *out) {
    MsCheck *c = b->c;
    if (ms_ty_kind(&c->tys, ty) != MS_K_ALTERNATIVE) {
        return false;
    }
    if (ms_ty_is(&c->tys, ty, MS_BI_OPTIONAL)) {
        *out = (AltInfo){.optional = true, .payload = ms_ty_args(&c->tys, ty)[0], .ncases = 2};
        return c->tys.nargs[ty] == 1;
    }
    if (c->tys.def[ty] == 0) {
        return false;
    }
    const MsSymId sym = c->tys.def[ty] - 1;
    if (ms_map_get(&c->mods[b->module].names, c->syms.name[sym]) != sym) {
        return false; /* declared elsewhere: its cases may be opaque here */
    }
    out->def = *ms_def(c, sym);
    out->optional = false;
    out->ncases = out->def.ncases;
    return out->ncases != 0 && out->def.nvars == c->tys.nargs[ty];
}

bool ms_body_optional_payload(const MsBody *b, MsTy ty, MsTy *payload) {
    AltInfo info = {0};
    if (ty == MS_TY_NONE || !alt_info(b, ty, &info) || !info.optional) {
        return false;
    }
    *payload = info.payload;
    return true;
}

static MsSym alt_case_name(const MsBody *b, const AltInfo *info, uint32_t index) {
    if (info->optional) {
        return ms_intern_cstr(b->c->names, index == 0 ? "some" : "none");
    }
    return info->def.cases[index].name;
}

static uint32_t alt_case_fields(const AltInfo *info, uint32_t index) {
    if (info->optional) {
        return index == 0 ? 1 : 0;
    }
    return info->def.cases[index].nfields;
}

/* The type of payload slot `slot` of case `index` at the scrutinee's type arguments. */
static MsTy alt_field_ty(MsBody *b, const AltInfo *info, MsTy ty, uint32_t index, uint32_t slot) {
    if (info->optional) {
        return info->payload;
    }
    const MsTySubst subst = {.vars = info->def.vars, .args = ms_ty_args(&b->c->tys, ty), .count = info->def.nvars};
    return ms_ty_subst(&b->c->tys, &b->c->arena, info->def.cases[index].fields[slot].ty, &subst);
}

static bool alt_is(const MsBody *b, MsSym name, const char *text) {
    const MsStr s = ms_name(b->c->names, name);
    return s.len == strlen(text) && memcmp(s.ptr, text, s.len) == 0;
}

/* The case an arm names, or MS_NONE; `*wildcard` is set for a `_` arm. A qualifier must be the
 * enum's own name; any other form is a diagnostic or not handled. */
static uint32_t alt_arm_case(const MsBody *b, const MsArm *arm, MsTy ty, const AltInfo *info, bool *wildcard) {
    const MsExpr *path = arm->path;
    MsSym name = 0;
    *wildcard = false;
    if (arm->bare) {
        if (!info->optional) {
            return MS_NONE;
        }
        name = alt_case_name(b, info, 0); /* `value:` binds an Optional's payload */
    } else if (path->kind == MS_E_NAME) {
        name = path->u.sym;
    } else if (path->kind == MS_E_MEMBER && path->u.member.left->kind == MS_E_NAME && !info->optional) {
        const MsSymId owner = ms_map_get(&b->c->mods[b->module].names, path->u.member.left->u.sym);
        if (owner == MS_NONE || b->c->syms.ty[owner] != ty || info->def.nvars != 0) {
            return MS_NONE;
        }
        name = path->u.member.name;
    } else {
        return MS_NONE;
    }
    if (alt_is(b, name, "_")) {
        *wildcard = path->kind == MS_E_NAME && !arm->bare;
        return MS_NONE;
    }
    for (uint32_t i = 0; i < info->ncases; i++) {
        if (alt_case_name(b, info, i) == name) {
            return i;
        }
    }
    return MS_NONE;
}

/* Binds the payload names of `arm` to the case's field types at the scrutinee's type arguments. */
static bool alt_bind_payload(MsBody *b, const MsArm *arm, MsTy ty, const AltInfo *info, uint32_t index) {
    if (arm->bindings.len != alt_case_fields(info, index)) {
        return false;
    }
    for (uint32_t slot = 0; slot < arm->bindings.len; slot++) {
        const MsSym name = arm->bindings.ptr[slot].name;
        if (alt_is(b, name, "_")) {
            continue;
        }
        const MsTy field = alt_field_ty(b, info, ty, index, slot);
        if (ms_body_bind(b, name, field, arm->id, arm->bindings.ptr[slot].pos, 0, MS_ROLE_ARM) == MS_NONE) {
            return false;
        }
    }
    return true;
}

static void alt_close_from(MsBody *b, uint32_t first) {
    for (uint32_t i = first; i < b->facts->bindings.count; i++) {
        b->closed[i] = true;
    }
}

MsTy ms_body_match_alternative(MsBody *b, const MsExpr *e, MsTy expected, MsTy ty) {
    AltInfo info = {0};
    const uint32_t count = e->u.match.arms.len;
    if (!alt_info(b, ty, &info) || count == 0 || e->u.match.arms.ptr[0]->from_if) {
        return ms_body_unsupported(b);
    }
    bool *seen = MS_NEW_N(&b->c->arena, bool, info.ncases);
    memset(seen, 0, info.ncases * sizeof *seen);
    uint32_t covered = 0;
    bool wildcard = false;
    // Arms are all values or all statements; statement arms, which end the match as a statement, must
    // each fall through (one that returns or breaks changes what follows the match).
    const bool valued = e->u.match.arms.ptr[0]->value != NULL;
    MsTy result = expected;
    if (!valued && expected != MS_TY_NONE && expected != b->void_ty) {
        return ms_body_unsupported(b);
    }
    for (uint32_t i = 0; i < count && b->supported; i++) {
        const MsArm *arm = e->u.match.arms.ptr[i];
        bool is_wildcard = false;
        const uint32_t index = alt_arm_case(b, arm, ty, &info, &is_wildcard);
        const bool last_with_cases_left = i == count - 1 && arm->bindings.len == 0 && covered < info.ncases;
        const bool fresh_case = index != MS_NONE && !seen[index];
        const bool well_formed = (arm->value != NULL) == valued && !wildcard &&
                                 (is_wildcard ? last_with_cases_left : fresh_case);
        if (!well_formed) {
            return ms_body_unsupported(b);
        }
        wildcard = is_wildcard;
        const uint32_t first = b->facts->bindings.count;
        if (!is_wildcard) {
            seen[index] = true;
            covered++;
            b->facts->arm_case[arm->id] = index;
            if (!alt_bind_payload(b, arm, ty, &info, index)) {
                return ms_body_unsupported(b);
            }
        }
        if (!valued) {
            const bool falls = ms_body_block(b, &arm->body);
            alt_close_from(b, first);
            if (!b->supported || !falls) {
                return ms_body_unsupported(b);
            }
            result = b->void_ty;
            continue;
        }
        const MsTy value = ms_body_block_value(b, &arm->body, arm->value, result);
        alt_close_from(b, first);
        if (value == MS_TY_NONE || value == b->void_ty) {
            return ms_body_unsupported(b);
        }
        result = value;
    }
    return wildcard || covered == info.ncases ? result : ms_body_unsupported(b);
}

/* The case of the enum `ty` that the bare name `name` spells, or MS_NONE. */
static uint32_t alt_named_case(const MsBody *b, MsTy ty, MsSym name, AltInfo *info) {
    if (ty == MS_TY_NONE || !alt_info(b, ty, info) || info->optional) {
        return MS_NONE;
    }
    for (uint32_t i = 0; i < info->ncases; i++) {
        if (alt_case_name(b, info, i) == name) {
            return i;
        }
    }
    return MS_NONE;
}

bool ms_body_is_case_of(const MsBody *b, MsTy expected, MsSym name) {
    AltInfo info = {0};
    return alt_named_case(b, expected, name, &info) != MS_NONE;
}

/* `Case(args)` where the context expects the enum that declares `Case`: every argument is
 * positional and checked against the case's field of that position; the callee resolves to the
 * case, as `ok(v)` does for a Result. */
MsTy ms_body_case_call(MsBody *b, const MsExpr *e, MsTy expected) {
    const MsExpr *callee = e->u.call.callee;
    AltInfo info = {0};
    const uint32_t index = alt_named_case(b, expected, callee->u.sym, &info);
    if (index == MS_NONE || e->u.call.args.len != alt_case_fields(&info, index)) {
        return ms_body_unsupported(b);
    }
    for (uint32_t slot = 0; slot < e->u.call.args.len; slot++) {
        const MsTy field = alt_field_ty(b, &info, expected, index, slot);
        if (e->u.call.args.ptr[slot].has_name || !ms_body_is_admitted(b, field) ||
            ms_body_expr(b, e->u.call.args.ptr[slot].value, field) == MS_TY_NONE) {
            return ms_body_unsupported(b);
        }
    }
    b->facts->res_kind[callee->id] = MS_RES_CASE;
    b->facts->res_ref[callee->id] = index;
    return expected;
}

/* A case without payload named where the context expects its enum: `Empty`. */
MsTy ms_body_case_name(MsBody *b, const MsExpr *e, MsTy expected) {
    AltInfo info = {0};
    const uint32_t index = alt_named_case(b, expected, e->u.sym, &info);
    if (index == MS_NONE || alt_case_fields(&info, index) != 0) {
        return ms_body_unsupported(b); // a case with a payload is called, not named
    }
    b->facts->res_kind[e->id] = MS_RES_CASE;
    b->facts->res_ref[e->id] = index;
    return expected;
}
