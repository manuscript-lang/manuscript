/* `match` over an enum or `Optional` value in function bodies. Handled: arms that name a case (bare,
 * or qualified by the enum's own name) that bind its payload, a `name:` arm for an `Optional`'s
 * payload, a final `_`, one value per arm.
 * A diagnostic case (unknown, repeated or unreachable case, wrong payload count, missing case)
 * and every other construct leaves the function to the Rust checker. */
#include <string.h>

#include "check/check_body.h"
#include "ms/implements.h"

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

bool ms_body_is_foreign_opaque(const MsBody *b, MsTy ty) {
    const MsCheck *c = b->c;
    const uint32_t def = ty == MS_TY_NONE ? 0 : c->tys.def[ty];
    if (def == 0) {
        return false;
    }
    const MsDecl *decl = c->syms.decl[def - 1];
    if (decl == NULL || c->syms.module[def - 1] == b->module) {
        return false;
    }
    return (decl->kind == MS_D_ENUM && decl->u.enumeration.opaque) || (decl->kind == MS_D_TYPE && decl->u.type.opaque);
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
    if (ms_name_is(b->c->names, name, "_")) {
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

/* Whether `ty` (an enum) has a case called `name`. */
static bool alt_has_case(const MsBody *b, MsTy ty, MsSym name) {
    if (ty == MS_TY_NONE || ms_ty_kind(&b->c->tys, ty) != MS_K_ALTERNATIVE || b->c->tys.def[ty] == 0) {
        return false;
    }
    const MsDef *def = ms_def(b->c, b->c->tys.def[ty] - 1);
    for (uint32_t i = 0; def != NULL && i < def->ncases; i++) {
        if (def->cases[i].name == name) {
            return true;
        }
    }
    return false;
}

/* Whether `name` is a type parameter of the function being checked. */
static bool alt_is_type_parameter(const MsBody *b, MsSym name) {
    for (uint32_t i = 0; b->tparams != NULL && i < b->tparams->len; i++) {
        if (b->tparams->ptr[i]->name == name) {
            return true;
        }
    }
    return false;
}

/* The enum, among the types this module sees, that has a case called `name`: MS_CONFLICT_CASE with it when exactly
 * one does, MS_CONFLICT_CASE_ANY when several do (the map's order must not pick one), else none. A type whose own
 * name is shadowed by a local does not count. */
static MsConflict alt_visible_owner(const MsBody *b, MsSym name, MsTy *owner) {
    const MsNameMap *names = &b->c->mods[b->module].names;
    MsTy found = MS_TY_NONE;
    for (uint32_t i = 0; i < names->cap; i++) {
        if (names->vals[i] == 0) {
            continue;
        }
        const MsSymId sym = names->vals[i] - 1;
        const MsTy ty = b->c->syms.ty[sym];
        if (b->c->syms.kind[sym] != MS_SYM_TYPE || ty == MS_TY_NONE || ms_ty_kind(&b->c->tys, ty) != MS_K_ALTERNATIVE ||
            ms_body_find_binding(b, names->keys[i]) != MS_NONE || alt_is_type_parameter(b, names->keys[i]) ||
            !alt_has_case(b, ty, name)) {
            continue;
        }
        if (found != MS_TY_NONE && found != ty) {
            return MS_CONFLICT_CASE_ANY;
        }
        found = ty;
    }
    *owner = found;
    return found == MS_TY_NONE ? MS_CONFLICT_NONE : MS_CONFLICT_CASE;
}

/* What payload name `name` coincides with (the Rust checker's `match_binding_names`): a type of the module, a case of
 * the payload's own enum, or a case of a visible enum. A name a local or a type parameter already holds is an
 * ordinary shadow, not a conflict. */
static MsConflict alt_payload_conflict(const MsBody *b, MsSym name, MsTy payload, MsTy *owner) {
    *owner = MS_TY_NONE;
    if (ms_name_is(b->c->names, name, "_") || ms_body_find_binding(b, name) != MS_NONE || alt_is_type_parameter(b, name)) {
        return MS_CONFLICT_NONE;
    }
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, name);
    if (sym != MS_NONE) {
        return b->c->syms.kind[sym] == MS_SYM_TYPE ? MS_CONFLICT_TYPE : MS_CONFLICT_NONE;
    }
    if (alt_has_case(b, payload, name)) {
        *owner = payload;
        return MS_CONFLICT_CASE;
    }
    return alt_visible_owner(b, name, owner);
}

/* Binds the payload names of `arm` to the case's field types at the scrutinee's type arguments. A name written in
 * capitals that coincides with a type or a case still binds, and is recorded as a conflict (lint MSL106). */
static bool alt_bind_payload(MsBody *b, const MsArm *arm, MsTy ty, const AltInfo *info, uint32_t index) {
    if (arm->bindings.len != alt_case_fields(info, index)) {
        return false;
    }
    // Every name is resolved before any sibling is bound.
    MsConflict *kinds = MS_NEW_N(&b->c->arena, MsConflict, arm->bindings.len + 1);
    MsTy *owners = MS_NEW_N(&b->c->arena, MsTy, arm->bindings.len + 1);
    for (uint32_t slot = 0; slot < arm->bindings.len; slot++) {
        kinds[slot] = alt_payload_conflict(b, arm->bindings.ptr[slot].name, alt_field_ty(b, info, ty, index, slot), &owners[slot]);
    }
    for (uint32_t slot = 0; slot < arm->bindings.len; slot++) {
        const MsSym name = arm->bindings.ptr[slot].name;
        if (ms_name_is(b->c->names, name, "_")) {
            continue;
        }
        const MsTy field = alt_field_ty(b, info, ty, index, slot);
        const uint32_t binding = ms_body_bind(b, name, field, arm->id, arm->bindings.ptr[slot].pos, 0, MS_ROLE_ARM);
        if (binding == MS_NONE) {
            return false;
        }
        b->facts->bindings.conflict[binding] = (uint8_t)kinds[slot];
        b->facts->bindings.conflict_ty[binding] = owners[slot];
    }
    return true;
}

void ms_body_close_from(MsBody *b, uint32_t first) {
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
    // Arms are all values or all statements. A statement match falls through when some arm does
    // (`b->match_falls`); the statement after one whose arms all return or break is unreachable.
    bool any_falls = false;
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
            ms_body_close_from(b, first);
            if (!b->supported) {
                return ms_body_unsupported(b);
            }
            any_falls = any_falls || falls;
            result = b->void_ty;
            continue;
        }
        const MsTy value = ms_body_block_value(b, &arm->body, arm->value, result);
        ms_body_close_from(b, first);
        if (value == MS_TY_NONE || value == b->void_ty) {
            return ms_body_unsupported(b);
        }
        result = value;
    }
    if (!wildcard && covered != info.ncases) {
        return ms_body_unsupported(b);
    }
    b->match_falls = valued || any_falls;
    return b->match_falls ? result : b->never_ty;
}

/* The type a contract arm names: a type or enum of this module without type parameters. */
static MsTy alt_contract_target(const MsBody *b, const MsArm *arm) {
    if (arm->bare || arm->path->kind != MS_E_NAME || arm->bindings.len != 1) {
        return MS_TY_NONE;
    }
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, arm->path->u.sym);
    if (sym == MS_NONE || b->c->syms.kind[sym] != MS_SYM_TYPE || b->c->syms.module[sym] != b->module) {
        return MS_TY_NONE;
    }
    const MsTy ty = b->c->syms.ty[sym];
    const MsKind kind = ty == MS_TY_NONE ? MS_K_FUNCTION : ms_ty_kind(&b->c->tys, ty);
    return (kind == MS_K_TYPE || kind == MS_K_ALTERNATIVE) && b->c->tys.nargs[ty] == 0 && ms_def(b->c, sym)->nvars == 0 ? ty : MS_TY_NONE;
}

/* A `match` over an interface value: one `Type(name):` arm for each implementing type the module declares, then
 * a final `_`. The name binds the value as that type. A diagnostic case (a type that does not implement the
 * interface, a repeated type, no final `_`) stays with the Rust checker. */
MsTy ms_body_match_contract(MsBody *b, const MsExpr *e, MsTy expected, MsTy ty) {
    const uint32_t count = e->u.match.arms.len;
    if (b->methods == NULL || count < 2 || e->u.match.arms.ptr[0]->from_if) {
        return ms_body_unsupported(b);
    }
    const bool valued = e->u.match.arms.ptr[0]->value != NULL;
    if (!valued && expected != MS_TY_NONE && expected != b->void_ty) {
        return ms_body_unsupported(b);
    }
    MsTy *seen = MS_NEW_N(&b->c->arena, MsTy, count);
    MsTy result = expected;
    bool any_falls = false;
    for (uint32_t i = 0; i < count && b->supported; i++) {
        const MsArm *arm = e->u.match.arms.ptr[i];
        const bool wildcard = arm->path->kind == MS_E_NAME && !arm->bare && ms_name_is(b->c->names, arm->path->u.sym, "_");
        if ((arm->value != NULL) != valued || wildcard != (i == count - 1) || (wildcard && arm->bindings.len != 0)) {
            return ms_body_unsupported(b);
        }
        const uint32_t first = b->facts->bindings.count;
        if (!wildcard) {
            const MsTy target = alt_contract_target(b, arm);
            for (uint32_t k = 0; k < i; k++) {
                if (target == seen[k]) {
                    return ms_body_unsupported(b);
                }
            }
            if (target == MS_TY_NONE || ms_implements(b->c, b->methods, target, ty) != MS_FIT_YES) {
                return ms_body_unsupported(b);
            }
            seen[i] = target;
            b->facts->arm_contract[arm->id] = target;
            (void)ms_body_record(b, arm->path->id, target); // the name of the type is typed as that type
            const MsSym name = arm->bindings.ptr[0].name;
            MsTy owner = MS_TY_NONE;
            const MsConflict conflict = alt_payload_conflict(b, name, target, &owner);
            if (!ms_name_is(b->c->names, name, "_")) {
                const uint32_t binding = ms_body_bind(b, name, target, arm->id, arm->bindings.ptr[0].pos, 0, MS_ROLE_ARM);
                if (binding == MS_NONE) {
                    return ms_body_unsupported(b);
                }
                b->facts->bindings.conflict[binding] = (uint8_t)conflict;
                b->facts->bindings.conflict_ty[binding] = owner;
            }
        }
        if (!valued) {
            const bool falls = ms_body_block(b, &arm->body);
            ms_body_close_from(b, first);
            if (!b->supported) {
                return ms_body_unsupported(b);
            }
            any_falls = any_falls || falls;
            result = b->void_ty;
            continue;
        }
        const MsTy value = ms_body_block_value(b, &arm->body, arm->value, result);
        ms_body_close_from(b, first);
        if (value == MS_TY_NONE || value == b->void_ty) {
            return ms_body_unsupported(b);
        }
        result = value;
    }
    b->match_falls = valued || any_falls;
    return b->match_falls ? result : b->never_ty;
}

/* Whether more than one enum this module names declares a case `name`: a bare `name` is then
 * ambiguous (the Rust checker reports it), so it is left to that checker. */
static bool alt_case_ambiguous(const MsBody *b, MsSym name) {
    MsCheck *c = b->c;
    const MsNameMap *names = &c->mods[b->module].names;
    uint32_t found = 0;
    for (uint32_t slot = 0; slot < names->cap; slot++) {
        if (names->vals[slot] == 0) {
            continue;
        }
        const MsSymId sym = names->vals[slot] - 1;
        if (c->syms.kind[sym] != MS_SYM_TYPE || c->syms.ty[sym] == MS_TY_NONE || ms_ty_kind(&c->tys, c->syms.ty[sym]) != MS_K_ALTERNATIVE) {
            continue;
        }
        const MsDef *def = ms_def(c, sym);
        for (uint32_t i = 0; i < def->ncases; i++) {
            found += def->cases[i].name == name;
        }
    }
    return found > 1;
}

/* The case of the enum `ty` that the bare name `name` spells, or MS_NONE. */
static uint32_t alt_named_case(const MsBody *b, MsTy ty, MsSym name, AltInfo *info) {
    if (ty == MS_TY_NONE || !alt_info(b, ty, info) || info->optional) {
        return MS_NONE;
    }
    for (uint32_t i = 0; i < info->ncases; i++) {
        if (alt_case_name(b, info, i) == name) {
            return alt_case_ambiguous(b, name) ? MS_NONE : i;
        }
    }
    return MS_NONE;
}

bool ms_body_is_case_of(const MsBody *b, MsTy expected, MsSym name) {
    AltInfo info = {0};
    return alt_named_case(b, expected, name, &info) != MS_NONE;
}

/* The label of payload field `slot` of case `index` as the enum declares it, or 0 when the tables do not
 * carry it (an Optional's payload has no label). */
static MsSym alt_field_label(const AltInfo *info, uint32_t index, uint32_t slot) {
    if (info->optional) {
        return 0;
    }
    return info->def.cases[index].fields[slot].name;
}

/* `Case(args)` of the enum `ty`, the callee being the case's name (`name`): every argument is
 * positional and checked against the case's field of that position; the callee resolves to the
 * case, as `ok(v)` does for a Result. */
static MsTy alt_call(MsBody *b, const MsExpr *e, MsTy ty, MsSym name) {
    const MsExpr *callee = e->u.call.callee;
    AltInfo info = {0};
    const uint32_t index = alt_named_case(b, ty, name, &info);
    if (index == MS_NONE || e->u.call.args.len != alt_case_fields(&info, index)) {
        return ms_body_unsupported(b);
    }
    for (uint32_t slot = 0; slot < e->u.call.args.len; slot++) {
        const MsTy field = alt_field_ty(b, &info, ty, index, slot);
        const MsArg *arg = &e->u.call.args.ptr[slot];
        // A label must be the field's own name, in order: any other is the Rust checker's to report.
        if ((arg->has_name && arg->name != alt_field_label(&info, index, slot)) || !ms_body_is_admitted(b, field) ||
            ms_body_expr(b, arg->value, field) == MS_TY_NONE) {
            return ms_body_unsupported(b);
        }
    }
    b->facts->res_kind[callee->id] = MS_RES_CASE;
    b->facts->res_ref[callee->id] = index;
    return ty;
}

/* `Case(args)` where the context expects the enum that declares `Case`. */
MsTy ms_body_case_call(MsBody *b, const MsExpr *e, MsTy expected) {
    return alt_call(b, e, expected, e->u.call.callee->u.sym);
}

/* The enum a qualified case `Enum.Case` names: a non-generic enum declared here, `Enum` not
 * shadowed by a local. MS_TY_NONE otherwise. */
static MsTy alt_qualifier(MsBody *b, const MsExpr *member) {
    const MsExpr *left = member->u.member.left;
    if (left->kind != MS_E_NAME || ms_body_find_binding(b, left->u.sym) != MS_NONE) {
        return MS_TY_NONE;
    }
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, left->u.sym);
    const MsSyms *syms = &b->c->syms;
    if (sym == MS_NONE || syms->decl[sym] == NULL || syms->decl[sym]->kind != MS_D_ENUM || syms->nvars[sym] != 0 ||
        ms_body_is_foreign_opaque(b, syms->ty[sym])) {
        return MS_TY_NONE;
    }
    return syms->ty[sym];
}

bool ms_body_is_qualified_case(MsBody *b, const MsExpr *member) { return alt_qualifier(b, member) != MS_TY_NONE; }

MsTy ms_body_qualified_case_call(MsBody *b, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    return alt_call(b, e, alt_qualifier(b, callee), callee->u.member.name);
}

/* `Enum.Case` for a case without payload. */
MsTy ms_body_qualified_case(MsBody *b, const MsExpr *e) {
    const MsTy ty = alt_qualifier(b, e);
    AltInfo info = {0};
    const uint32_t index = alt_named_case(b, ty, e->u.member.name, &info);
    if (index == MS_NONE || alt_case_fields(&info, index) != 0) {
        return ms_body_unsupported(b);
    }
    (void)ms_body_record(b, e->u.member.left->id, ty); // the checker types the enum's name too
    b->facts->res_kind[e->id] = MS_RES_CASE;
    b->facts->res_ref[e->id] = index;
    return ty;
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

bool ms_body_result_label(const MsBody *b, MsTy result, bool success, MsSym label) {
    const MsTyTable *tys = &b->c->tys;
    if (!ms_ty_is(tys, result, MS_BI_RESULT) || tys->def[result] == 0) {
        return false;
    }
    const MsDef def = *ms_def(b->c, tys->def[result] - 1); // by value: a later ms_def may move the rows
    const uint32_t index = success ? 0 : 1;
    return def.ncases == 2 && def.cases[index].nfields == 1 && def.cases[index].fields[0].name == label;
}
