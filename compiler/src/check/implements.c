/* Interface satisfaction (ms/implements.h). */
#include "ms/implements.h"

#include <string.h>

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

/* ---- Equal of a declared type ---- */

/* How deep the structural walk goes before it answers UNKNOWN. */
enum { FIT_DEPTH = 16, FIT_ARGS = 8 };

typedef struct FitWalk {
    MsCheck *c;
    const MsMethodTable *table;
    MsTy active[FIT_DEPTH]; /* the types being decided: a cycle through them is equal */
    uint32_t depth;
} FitWalk;

/* The better of two answers about the parts of one value: one NO decides it, else any UNKNOWN does. */
static MsFit fit_all(MsFit a, MsFit b) {
    if (a == MS_FIT_NO || b == MS_FIT_NO) {
        return MS_FIT_NO;
    }
    return a == MS_FIT_UNKNOWN || b == MS_FIT_UNKNOWN ? MS_FIT_UNKNOWN : MS_FIT_YES;
}

/* Whether the own method of `row` is `equals(other: Self) Bool`, which decides Equal without an impl. */
static bool fit_row_is_equals(const MsCheck *c, const MsMethods *m, uint32_t row) {
    if (!m->inherent[row] || m->decl[row] == NULL) {
        return false;
    }
    const MsStr name = ms_name(c->names, m->decl[row]->name);
    const MsTyTable *t = &c->tys;
    const MsTy sig = m->ty[row];
    return name.len == 6 && memcmp(name.ptr, "equals", 6) == 0 && ms_ty_kind(t, sig) == MS_K_FUNCTION &&
           t->nparams[sig] == 1 && ms_ty_params(t, sig)[0].ty == m->receiver[row] && ms_ty_is(t, t->result[sig], MS_BI_BOOL);
}

static MsFit fit_equal(FitWalk *w, MsTy ty);
static MsFit fit_structural(FitWalk *w, MsTy ty, MsProperty property);

/* The answer for the parts of `ty` a definition lists, once its variables are replaced by the arguments. */
static MsFit fit_equal_parts(FitWalk *w, MsTy ty, const MsTyParam *parts, uint32_t count, const MsDef *def, MsProperty property) {
    MsFit answer = MS_FIT_YES;
    // Interning a substituted type may move the table's argument pool, so the arguments are copied out.
    MsTy args[FIT_ARGS];
    if (def->nvars > FIT_ARGS) {
        return MS_FIT_UNKNOWN;
    }
    memcpy(args, ms_ty_args(&w->c->tys, ty), def->nvars * sizeof *args);
    for (uint32_t i = 0; i < count && answer != MS_FIT_NO; i++) {
        MsArena scratch = {0};
        const MsTySubst subst = {.vars = def->vars, .args = args, .count = def->nvars};
        const MsTy part = ms_ty_subst(&w->c->tys, &scratch, parts[i].ty, &subst);
        ms_arena_free(&scratch);
        answer = fit_all(answer, fit_structural(w, part, property));
    }
    return answer;
}

/* Whether a declared type's own `equals` row or an `Equal` impl decides it: YES when a plain row does,
 * UNKNOWN when a generic or extension row could, NO to go on with the shape. */
static MsFit fit_equal_rows(const FitWalk *w, MsTy ty) {
    const MsMethods *m = &w->table->methods;
    const MsTyTable *t = &w->c->tys;
    MsFit answer = MS_FIT_NO;
    for (uint32_t i = 0; i < m->count; i++) {
        if (t->def[m->receiver[i]] != t->def[ty] || !(m->contract[i] != MS_TY_NONE && ms_ty_is(t, m->contract[i], MS_BI_EQUAL)
                                                       ? true
                                                       : fit_row_is_equals(w->c, m, i))) {
            continue;
        }
        if (m->nvars[i] != 0 || m->local[i] || m->receiver[i] != ty) {
            answer = MS_FIT_UNKNOWN;
            continue;
        }
        return MS_FIT_YES;
    }
    return answer;
}

/* Equal as the Rust checker derives it: an explicit `equals` or impl, else every part equal. */
static MsFit fit_equal(FitWalk *w, MsTy ty) {
    const MsTyTable *t = &w->c->tys;
    switch (ms_ty_kind(t, ty)) {
    case MS_K_PRIMITIVE:
    case MS_K_INVALID:
        return MS_FIT_YES;
    case MS_K_FUNCTION:
    case MS_K_CONTRACT:
        return MS_FIT_NO;
    case MS_K_VARIABLE: {
        const MsVarInfo *info = ty < w->c->var_info_cap ? &w->c->var_info[ty] : NULL;
        for (uint32_t i = 0; info != NULL && i < info->nbounds; i++) {
            if (ms_ty_is(t, info->bounds[i], MS_BI_EQUAL) || ms_ty_is(t, info->bounds[i], MS_BI_HASHABLE)) {
                return MS_FIT_YES;
            }
        }
        return MS_FIT_NO;
    }
    default:
        break;
    }
    const MsBuiltin builtin = t->builtin[ty];
    if (builtin == MS_BI_DECIMAL || builtin == MS_BI_BYTES || builtin == MS_BI_DURATION || builtin == MS_BI_INSTANT ||
        builtin == MS_BI_BIGINT || builtin == MS_BI_TIMESTAMP) {
        return MS_FIT_YES;
    }
    if (builtin == MS_BI_REGEX) {
        return MS_FIT_NO;
    }
    if (builtin == MS_BI_LIST || builtin == MS_BI_MAP || builtin == MS_BI_SET) {
        MsFit answer = MS_FIT_YES;
        for (uint32_t i = 0; i < t->nargs[ty]; i++) {
            answer = fit_all(answer, fit_equal(w, ms_ty_args(t, ty)[i]));
        }
        return answer;
    }
    if (builtin != MS_B_NONE || t->def[ty] == 0 || w->depth == FIT_DEPTH) {
        return ms_ty_kind(t, ty) == MS_K_NATIVE && builtin == MS_B_NONE ? MS_FIT_NO : MS_FIT_UNKNOWN;
    }
    for (uint32_t i = 0; i < w->depth; i++) {
        if (w->active[i] == ty) {
            return MS_FIT_YES; // equality handles a cycle
        }
    }
    const MsFit rows = fit_equal_rows(w, ty);
    if (rows != MS_FIT_NO) {
        return rows;
    }
    const MsDef def = *ms_def(w->c, t->def[ty] - 1); // by value: a later ms_def may move the rows
    if (def.nvars != t->nargs[ty]) {
        return MS_FIT_UNKNOWN;
    }
    w->active[w->depth++] = ty;
    MsFit answer = fit_equal_parts(w, ty, def.fields, def.nfields, &def, MS_PROP_EQUAL);
    for (uint32_t k = 0; k < def.ncases && answer != MS_FIT_NO; k++) {
        answer = fit_all(answer, fit_equal_parts(w, ty, def.cases[k].fields, def.cases[k].nfields, &def, MS_PROP_EQUAL));
    }
    w->depth--;
    return answer;
}

/* ---- Clonable and Data of a declared type ---- */

/* Whether a row the standard library marks (`// ms: data`, `// ms: clonable`: a row with no method) vouches
 * for `ty` having `property`. */
static bool fit_vouched(const FitWalk *w, MsTy ty, MsProperty property) {
    const MsMethods *m = &w->table->methods;
    const MsTyTable *t = &w->c->tys;
    for (uint32_t i = 0; i < m->count; i++) {
        if (m->decl[i] == NULL && m->contract[i] != MS_TY_NONE && t->id[m->receiver[i]] == t->id[ty] &&
            ms_ty_is(t, m->contract[i], ms_property_builtin(property))) {
            return true;
        }
    }
    return false;
}

/* Whether a method of the declared type `ty` implements the property or is a `close`, which make the
 * structural answer one the Rust checker decides by other rules. */
static bool fit_has_deciding_row(const FitWalk *w, MsTy ty, MsProperty property) {
    const MsMethods *m = &w->table->methods;
    const MsTyTable *t = &w->c->tys;
    for (uint32_t i = 0; i < m->count; i++) {
        if (t->def[m->receiver[i]] != t->def[ty] || m->decl[i] == NULL) {
            continue;
        }
        if ((m->contract[i] != MS_TY_NONE && ms_ty_is(t, m->contract[i], ms_property_builtin(property))) ||
            ms_name_is(w->c->names, m->decl[i]->name, "close")) {
            return true;
        }
    }
    return false;
}

/* Clonable (a value with one owner but no resource, function or handle in it) and Data (plain
 * values only) as the parts of the value decide them. Only a confident YES or NO is given: whatever
 * the Rust checker decides by a declaration it makes (an opaque type, an impl, a native's own `clone`)
 * is UNKNOWN. */
static MsFit fit_data(FitWalk *w, MsTy ty, MsProperty property) {
    const MsTyTable *t = &w->c->tys;
    switch (ms_ty_kind(t, ty)) {
    case MS_K_PRIMITIVE:
        return ms_ty_is(t, ty, MS_BI_NEVER) && property == MS_PROP_DATA ? MS_FIT_NO : MS_FIT_YES;
    case MS_K_INVALID:
        return MS_FIT_YES;
    case MS_K_FUNCTION:
        return MS_FIT_NO;
    case MS_K_NATIVE:
    case MS_K_TYPE:
    case MS_K_ALTERNATIVE:
        break;
    default:
        return MS_FIT_UNKNOWN;
    }
    if (fit_vouched(w, ty, property)) {
        return MS_FIT_YES;
    }
    const MsBuiltin builtin = t->builtin[ty];
    if (builtin == MS_BI_LIST || (property == MS_PROP_CLONABLE && (builtin == MS_BI_MAP || builtin == MS_BI_SET || builtin == MS_BI_OPTIONAL))) {
        MsFit answer = MS_FIT_YES;
        for (uint32_t i = 0; i < t->nargs[ty]; i++) {
            answer = fit_all(answer, fit_structural(w, ms_ty_args(t, ty)[i], property));
        }
        return answer;
    }
    if (ms_ty_kind(t, ty) == MS_K_NATIVE || t->def[ty] == 0 || w->depth == FIT_DEPTH) {
        return MS_FIT_UNKNOWN; // a native owns storage the runtime decides about
    }
    for (uint32_t i = 0; i < w->depth; i++) {
        if (w->active[i] == ty) {
            return property == MS_PROP_CLONABLE ? MS_FIT_YES : MS_FIT_UNKNOWN; // a cycle is cloned; Data decides it elsewhere
        }
    }
    const MsSymId sym = t->def[ty] - 1;
    const MsDecl *decl = sym < w->c->syms.count ? w->c->syms.decl[sym] : NULL;
    if (decl == NULL || decl->kind != MS_D_TYPE || decl->u.type.opaque || fit_has_deciding_row(w, ty, property)) {
        return MS_FIT_UNKNOWN;
    }
    const MsDef def = *ms_def(w->c, sym); // by value: a later ms_def may move the rows
    if (def.nvars != t->nargs[ty]) {
        return MS_FIT_UNKNOWN;
    }
    w->active[w->depth++] = ty;
    MsFit answer = fit_equal_parts(w, ty, def.fields, def.nfields, &def, property);
    for (uint32_t k = 0; k < def.ncases && answer != MS_FIT_NO; k++) {
        answer = fit_all(answer, fit_equal_parts(w, ty, def.cases[k].fields, def.cases[k].nfields, &def, property));
    }
    w->depth--;
    return answer;
}

static MsFit fit_structural(FitWalk *w, MsTy ty, MsProperty property) {
    return property == MS_PROP_EQUAL ? fit_equal(w, ty) : fit_data(w, ty, property);
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

MsFit ms_implements_equal(MsCheck *c, const MsMethodTable *table, MsTy ty) {
    FitWalk walk = {.c = c, .table = table};
    return fit_structural(&walk, ty, MS_PROP_EQUAL);
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
        if ((property == MS_PROP_EQUAL || property == MS_PROP_CLONABLE || property == MS_PROP_DATA) &&
            ms_ty_kind(t, receiver) != MS_K_PRIMITIVE) {
            FitWalk walk = {.c = c, .table = table};
            return fit_structural(&walk, receiver, property);
        }
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
