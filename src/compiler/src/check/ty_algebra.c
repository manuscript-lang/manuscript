/* Type algebra over the type table (ms/ty_algebra.h). */
#include "ms/ty_algebra.h"

#include <string.h>

/* ---- unification of two implementations' receivers and contracts ---- */

typedef struct Binding {
    MsSym id;
    MsTy ty;
} Binding;

typedef struct Unifier {
    const MsTyTable *t;
    MsArena *scratch;
    const MsTy *vars;
    uint32_t nvars;
    MsBuf bound; /* Binding: the substitution, in the order it was made */
} Unifier;

static bool unifier_is_variable(const Unifier *u, MsSym id) {
    for (uint32_t i = 0; i < u->nvars; i++) {
        if (u->t->id[u->vars[i]] == id) {
            return true;
        }
    }
    return false;
}

static bool unifier_lookup(const Unifier *u, MsSym id, MsTy *ty) {
    for (size_t i = 0; i < MS_VEC_LEN(u->bound, Binding); i++) {
        if (MS_VEC_AT(u->bound, Binding, i).id == id) {
            *ty = MS_VEC_AT(u->bound, Binding, i).ty;
            return true;
        }
    }
    return false;
}

/* Follows the substitution from `ty`, stopping at a cycle. */
static MsTy unifier_deref(const Unifier *u, MsTy ty) {
    MsBuf seen = {0};
    MsTy next;
    while (unifier_lookup(u, u->t->id[ty], &next)) {
        bool again = false;
        for (size_t i = 0; i < MS_VEC_LEN(seen, MsSym); i++) {
            again = again || MS_VEC_AT(seen, MsSym, i) == u->t->id[ty];
        }
        if (again) {
            break;
        }
        MS_VEC_PUSH(seen, MsSym, u->t->id[ty]);
        ty = next;
    }
    ms_buf_free(&seen);
    return ty;
}

static bool unifier_occurs(const Unifier *u, MsSym id, MsTy ty) {
    ty = unifier_deref(u, ty);
    if (u->t->id[ty] == id) {
        return true;
    }
    const MsTy *args = ms_ty_args(u->t, ty);
    for (uint32_t i = 0; i < u->t->nargs[ty]; i++) {
        if (unifier_occurs(u, id, args[i])) {
            return true;
        }
    }
    const MsTyParam *params = ms_ty_params(u->t, ty);
    for (uint32_t i = 0; i < u->t->nparams[ty]; i++) {
        if (unifier_occurs(u, id, params[i].ty)) {
            return true;
        }
    }
    return u->t->result[ty] != MS_TY_NONE && unifier_occurs(u, id, u->t->result[ty]);
}

static bool unifier_matches(Unifier *u, MsTy a, MsTy b);

static bool unifier_matches_function(Unifier *u, MsTy a, MsTy b) {
    const MsTyTable *t = u->t;
    if (t->nparams[a] != t->nparams[b]) {
        return false;
    }
    const MsTyParam *pa = ms_ty_params(t, a);
    const MsTyParam *pb = ms_ty_params(t, b);
    for (uint32_t i = 0; i < t->nparams[a]; i++) {
        bool same_mutability = ((pa[i].flags ^ pb[i].flags) & MS_PARAM_VAR) == 0;
        if (!same_mutability || !unifier_matches(u, pa[i].ty, pb[i].ty)) {
            return false;
        }
    }
    bool both = t->result[a] != MS_TY_NONE && t->result[b] != MS_TY_NONE;
    return both && unifier_matches(u, t->result[a], t->result[b]);
}

/* Binds the variable `id` to `ty` unless that would make the type contain itself. */
static bool unifier_bind(Unifier *u, MsSym id, MsTy ty) {
    if (unifier_occurs(u, id, ty)) {
        return false;
    }
    MS_VEC_PUSH(u->bound, Binding, ((Binding){id, ty}));
    return true;
}

static bool unifier_matches(Unifier *u, MsTy a, MsTy b) {
    const MsTyTable *t = u->t;
    a = unifier_deref(u, a);
    b = unifier_deref(u, b);
    MsSym ida = t->id[a];
    MsSym idb = t->id[b];
    bool var_a = unifier_is_variable(u, ida);
    if (ida == idb && var_a) {
        return true;
    }
    if (var_a) {
        return unifier_bind(u, ida, b);
    }
    if (unifier_is_variable(u, idb)) {
        return unifier_bind(u, idb, a);
    }
    if (ida != idb || t->nargs[a] != t->nargs[b]) {
        return false;
    }
    const MsTy *args_a = ms_ty_args(t, a);
    const MsTy *args_b = ms_ty_args(t, b);
    for (uint32_t i = 0; i < t->nargs[a]; i++) {
        if (!unifier_matches(u, args_a[i], args_b[i])) {
            return false;
        }
    }
    return ms_ty_kind(t, a) != MS_K_FUNCTION || unifier_matches_function(u, a, b);
}

bool ms_ty_overlap(const MsTyTable *t, MsArena *scratch, MsTy a, MsTy b, MsTy x, MsTy y,
                   const MsTy *vars, uint32_t nvars) {
    Unifier u = {t, scratch, vars, nvars, {0}};
    bool overlap = unifier_matches(&u, a, x) && unifier_matches(&u, b, y);
    ms_buf_free(&u.bound);
    return overlap;
}

/* ---- evidence helpers ---- */

/* The interfaces that bound the type variable `ty`. */
static const MsTy *variable_bounds(const MsCheck *c, MsTy ty, uint32_t *count) {
    if (ty >= c->var_info_cap) {
        *count = 0;
        return NULL;
    }
    *count = c->var_info[ty].nbounds;
    return c->var_info[ty].bounds;
}

static bool set_has(const MsTyTable *t, MsTy set, MsTy member) {
    const MsTy *members = ms_ty_args(t, set);
    for (uint32_t i = 0; i < t->nargs[set]; i++) {
        if (members[i] == member) {
            return true;
        }
    }
    return false;
}

/* Whether the type-set bound `bound` lists only members of `set`. */
static bool set_within(const MsTyTable *t, MsTy bound, MsTy set) {
    if (!ms_ty_is(t, bound, MS_BI_TYPESET) || t->nargs[bound] == 0) {
        return false;
    }
    const MsTy *members = ms_ty_args(t, bound);
    for (uint32_t i = 0; i < t->nargs[bound]; i++) {
        if (!set_has(t, set, members[i])) {
            return false;
        }
    }
    return true;
}

bool ms_type_set_admits(const MsCheck *c, MsTy ty, MsTy set) {
    if (ms_ty_kind(&c->tys, ty) != MS_K_VARIABLE) {
        return set_has(&c->tys, set, ty);
    }
    uint32_t count;
    const MsTy *bounds = variable_bounds(c, ty, &count);
    for (uint32_t i = 0; i < count; i++) {
        if (set_within(&c->tys, bounds[i], set)) {
            return true;
        }
    }
    return false;
}

bool ms_builtin_comparable(MsBuiltin builtin) {
    switch (builtin) {
    case MS_BI_STRING:
    case MS_BI_DECIMAL:
    case MS_BI_BIGINT:
    case MS_BI_DURATION:
    case MS_BI_INSTANT:
    case MS_BI_TIMESTAMP:
        return true;
    case MS_B_NONE:
    default:
        return ms_builtin_is_int(builtin) || ms_builtin_is_float(builtin);
    }
}

bool ms_property_of(MsBuiltin contract, MsProperty *out) {
    switch (contract) {
    case MS_BI_EQUAL:
        *out = MS_PROP_EQUAL;
        return true;
    case MS_BI_HASHABLE:
        *out = MS_PROP_HASHABLE;
        return true;
    case MS_BI_CLONABLE:
        *out = MS_PROP_CLONABLE;
        return true;
    case MS_BI_DATA:
        *out = MS_PROP_DATA;
        return true;
    case MS_B_NONE:
    default:
        return false;
    }
}

MsBuiltin ms_property_builtin(MsProperty property) {
    static const MsBuiltin builtins[] = {MS_BI_EQUAL, MS_BI_HASHABLE, MS_BI_CLONABLE, MS_BI_DATA};
    return builtins[property];
}

const char *ms_property_name(MsProperty property) {
    static const char *const names[] = {"Equal", "Hashable", "Clonable", "Data"};
    return names[property];
}
