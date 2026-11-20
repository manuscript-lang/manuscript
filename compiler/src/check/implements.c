/* Interface satisfaction (ms/implements.h). */
#include "ms/implements.h"

#include "ms/ty_algebra.h"

/* The built-in property a contract names, when it is one. */
static bool fit_property(const MsTyTable *t, MsTy contract, MsProperty *out) {
    for (uint32_t i = 0; i < 4; i++) {
        if (ms_ty_is(t, contract, ms_property_builtin((MsProperty)i))) {
            *out = (MsProperty)i;
            return true;
        }
    }
    return false;
}

static MsFit fit_primitive_property(const MsTyTable *t, MsTy receiver, MsProperty property) {
    if (ms_ty_kind(t, receiver) != MS_K_PRIMITIVE) {
        return MS_FIT_UNKNOWN;
    }
    // A float has no structural hash.
    const bool hashable_float = property == MS_PROP_HASHABLE && ms_builtin_is_float(t->builtin[receiver]);
    return hashable_float ? MS_FIT_NO : MS_FIT_YES;
}

/* The rows whose receiver is `receiver`: an explicit row for `contract` makes it fit; a generic
 * or extension row that could apply makes the answer UNKNOWN. */
static MsFit fit_rows(const MsCheck *c, const MsMethodTable *table, MsTy receiver, MsTy contract) {
    const MsMethods *m = &table->methods;
    MsFit answer = MS_FIT_NO;
    for (uint32_t i = 0; i < m->count; i++) {
        if (m->contract[i] != contract || (m->receiver[i] != receiver && m->nvars[i] == 0)) {
            continue;
        }
        if (m->nvars[i] != 0 || m->local[i] || ms_ty_kind(&c->tys, m->receiver[i]) == MS_K_VARIABLE) {
            answer = MS_FIT_UNKNOWN;
            continue;
        }
        return MS_FIT_YES;
    }
    return answer;
}

/* The receiver's own method called `name`, when exactly one non-generic row has it. */
static bool fit_method(const MsMethods *m, MsTy receiver, MsSym name, uint32_t *row) {
    bool found = false;
    for (uint32_t i = 0; i < m->count; i++) {
        if (m->receiver[i] != receiver || m->decl[i] == NULL || m->decl[i]->name != name) {
            continue;
        }
        if (found || m->nvars[i] != 0) {
            return false;
        }
        *row = i;
        found = true;
    }
    return found;
}

/* A type satisfies an interface by having its operations: each present with the same signature
 * once `Self` is the receiver. A missing operation is NO; one present with another signature is
 * UNKNOWN, since the C tables do not compare labels and `var`-ness the way the Rust checker does. */
static MsFit fit_shape(MsCheck *c, const MsMethodTable *table, MsTy receiver, MsTy contract) {
    const MsTyTable *t = &c->tys;
    if (t->def[contract] == 0 || t->nargs[contract] != 0) {
        return MS_FIT_UNKNOWN;
    }
    const MsOperations *ops = ms_interface_operations(table, t->def[contract] - 1);
    if (ops == NULL) {
        return MS_FIT_UNKNOWN;
    }
    const MsTy self = ms_self_variable(c, contract);
    MsFit answer = MS_FIT_YES;
    for (uint32_t i = 0; i < ops->count; i++) {
        uint32_t row;
        if (ops->items[i].nvars != 0) {
            return MS_FIT_UNKNOWN;
        }
        if (!fit_method(&table->methods, receiver, ops->items[i].name, &row)) {
            return MS_FIT_NO;
        }
        MsArena scratch = {0};
        const MsTySubst subst = {.vars = &self, .args = &receiver, .count = 1};
        const MsTy wanted = ms_ty_subst(&c->tys, &scratch, ops->items[i].ty, &subst);
        ms_arena_free(&scratch);
        answer = wanted == table->methods.ty[row] ? answer : MS_FIT_UNKNOWN;
    }
    return answer;
}

MsFit ms_implements(MsCheck *c, const MsMethodTable *table, MsTy receiver, MsTy contract) {
    const MsTyTable *t = &c->tys;
    if (receiver == contract) {
        return MS_FIT_YES;
    }
    if (ms_ty_kind(t, contract) != MS_K_CONTRACT) {
        return MS_FIT_UNKNOWN;
    }
    MsProperty property;
    if (fit_property(t, contract, &property)) {
        return fit_primitive_property(t, receiver, property);
    }
    if (ms_ty_is(t, contract, MS_BI_TYPESET)) {
        return ms_type_set_admits(c, receiver, contract) ? MS_FIT_YES : MS_FIT_NO;
    }
    if (ms_ty_kind(t, receiver) == MS_K_VARIABLE) {
        const MsTy *bounds = receiver < c->var_info_cap ? c->var_info[receiver].bounds : NULL;
        const uint32_t count = bounds == NULL ? 0 : c->var_info[receiver].nbounds;
        for (uint32_t i = 0; i < count; i++) {
            if (bounds[i] == contract) {
                return MS_FIT_YES;
            }
        }
        return MS_FIT_NO;
    }
    if (ms_ty_is(t, contract, MS_BI_COMPARABLE) && ms_builtin_comparable(t->builtin[receiver])) {
        return MS_FIT_YES;
    }
    const MsFit explicit_row = fit_rows(c, table, receiver, contract);
    return explicit_row != MS_FIT_NO ? explicit_row : fit_shape(c, table, receiver, contract);
}
