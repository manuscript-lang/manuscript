/* Type argument inference over the interned type table (include/ms/infer.h). */
#include "ms/infer.h"

#include <string.h>

#define MS_INFER_MAX_DEPTH 1000 /* the checker keeps types within MS_MAX_NESTING */

/* Pairs of (pattern, actual) already matched successfully. A type built by repeated doubling is a
 * DAG of n nodes but a tree of 2^n paths; the set makes the match visit each pair once. */
typedef struct PairSet {
    uint64_t *keys; /* pattern << 32 | actual, plus one so that zero means empty */
    uint32_t mask;
    uint32_t used;
} PairSet;

typedef struct Matcher {
    MsInfer *in;
    PairSet seen;
} Matcher;

static uint32_t pair_hash(uint64_t key) {
    key *= 0x9e3779b97f4a7c15ull;
    return (uint32_t)(key >> 32);
}

static bool pair_seen(const PairSet *s, uint64_t key) {
    if (s->keys == NULL) {
        return false;
    }
    for (uint32_t i = pair_hash(key) & s->mask; s->keys[i] != 0; i = (i + 1) & s->mask) {
        if (s->keys[i] == key) {
            return true;
        }
    }
    return false;
}

static void pair_insert_raw(PairSet *s, uint64_t key) {
    uint32_t i = pair_hash(key) & s->mask;
    while (s->keys[i] != 0) {
        i = (i + 1) & s->mask;
    }
    s->keys[i] = key;
}

static void pair_add(Matcher *m, uint64_t key) {
    PairSet *s = &m->seen;
    if (s->keys == NULL || (s->used + 1) * 2 > s->mask + 1) {
        const uint32_t capacity = s->keys == NULL ? 64 : (s->mask + 1) * 2;
        uint64_t *old = s->keys;
        const uint32_t old_capacity = s->keys == NULL ? 0 : s->mask + 1;
        s->keys = MS_NEW_N(m->in->arena, uint64_t, capacity);
        memset(s->keys, 0, (size_t)capacity * sizeof *s->keys);
        s->mask = capacity - 1;
        for (uint32_t i = 0; i < old_capacity; i++) {
            if (old[i] != 0) {
                pair_insert_raw(s, old[i]);
            }
        }
    }
    pair_insert_raw(s, key);
    s->used++;
}

void ms_infer_init(MsInfer *in, MsCheck *c, MsArena *arena, const MsTy *vars, uint32_t nvars) {
    *in = (MsInfer){.c = c, .arena = arena, .vars = vars, .nvars = nvars};
    in->bound = MS_NEW_N(arena, MsTy, nvars == 0 ? 1 : nvars);
    memset(in->bound, 0, (size_t)(nvars == 0 ? 1 : nvars) * sizeof *in->bound);
}

bool ms_infer_give(MsInfer *in, const MsTy *args, uint32_t count) {
    if (count > in->nvars) {
        return false;
    }
    for (uint32_t i = 0; i < count; i++) {
        in->bound[i] = ms_ty_kind(&in->c->tys, args[i]) == MS_K_INVALID ? MS_TY_NONE : args[i];
    }
    return true;
}

/* The index of the variable `ty` is, or in->nvars. */
static uint32_t infer_variable(const MsInfer *in, MsTy ty) {
    if (ms_ty_kind(&in->c->tys, ty) != MS_K_VARIABLE) {
        return in->nvars;
    }
    for (uint32_t i = 0; i < in->nvars; i++) {
        if (in->c->tys.id[in->vars[i]] == in->c->tys.id[ty]) {
            return i;
        }
    }
    return in->nvars;
}

static MsMatch match_types(Matcher *m, MsTy pattern, MsTy actual, uint32_t depth);

static MsMatch match_function(Matcher *m, MsTy pattern, MsTy actual, uint32_t depth) {
    const MsTyTable *t = &m->in->c->tys;
    if (t->nparams[pattern] != t->nparams[actual]) {
        return MS_MATCH_SHAPE;
    }
    const MsTyParam *pp = ms_ty_params(t, pattern);
    const MsTyParam *pa = ms_ty_params(t, actual);
    for (uint32_t i = 0; i < t->nparams[pattern]; i++) {
        if (((pp[i].flags ^ pa[i].flags) & MS_PARAM_VAR) != 0) {
            return MS_MATCH_SHAPE;
        }
        const MsMatch r = match_types(m, pp[i].ty, pa[i].ty, depth + 1);
        if (r != MS_MATCH_OK) {
            return r;
        }
    }
    if (t->result[pattern] == MS_TY_NONE || t->result[actual] == MS_TY_NONE) {
        return t->result[pattern] == t->result[actual] ? MS_MATCH_OK : MS_MATCH_SHAPE;
    }
    return match_types(m, t->result[pattern], t->result[actual], depth + 1);
}

static MsMatch match_variable(MsInfer *in, uint32_t index, MsTy actual) {
    if (in->bound[index] == MS_TY_NONE) {
        in->bound[index] = actual;
        return MS_MATCH_OK;
    }
    return in->bound[index] == actual ? MS_MATCH_OK : MS_MATCH_CONFLICT;
}

static MsMatch match_types(Matcher *m, MsTy pattern, MsTy actual, uint32_t depth) {
    MsInfer *in = m->in;
    const MsTyTable *t = &in->c->tys;
    if (pattern == actual || ms_ty_kind(t, actual) == MS_K_INVALID || ms_ty_kind(t, pattern) == MS_K_INVALID) {
        return MS_MATCH_OK;
    }
    const uint32_t variable = infer_variable(in, pattern);
    if (variable != in->nvars) {
        return match_variable(in, variable, actual);
    }
    if (depth > MS_INFER_MAX_DEPTH || t->id[pattern] != t->id[actual] || t->nargs[pattern] != t->nargs[actual]) {
        return MS_MATCH_SHAPE;
    }
    const uint64_t key = ((uint64_t)pattern << 32 | actual) + 1;
    if (pair_seen(&m->seen, key)) {
        return MS_MATCH_OK;
    }
    const MsTy *pa = ms_ty_args(t, pattern);
    const MsTy *aa = ms_ty_args(t, actual);
    for (uint32_t i = 0; i < t->nargs[pattern]; i++) {
        const MsMatch r = match_types(m, pa[i], aa[i], depth + 1);
        if (r != MS_MATCH_OK) {
            return r;
        }
    }
    const MsMatch r = ms_ty_kind(t, pattern) == MS_K_FUNCTION ? match_function(m, pattern, actual, depth) : MS_MATCH_OK;
    if (r == MS_MATCH_OK) {
        pair_add(m, key);
    }
    return r;
}

MsMatch ms_infer_match(MsInfer *in, MsTy pattern, MsTy actual) {
    Matcher m = {.in = in};
    return match_types(&m, pattern, actual, 0);
}

MsTy ms_infer_apply(MsInfer *in, MsTy ty) {
    MsTy *vars = MS_NEW_N(in->arena, MsTy, in->nvars == 0 ? 1 : in->nvars);
    MsTy *args = MS_NEW_N(in->arena, MsTy, in->nvars == 0 ? 1 : in->nvars);
    uint32_t count = 0;
    for (uint32_t i = 0; i < in->nvars; i++) {
        if (in->bound[i] != MS_TY_NONE) {
            vars[count] = in->vars[i];
            args[count++] = in->bound[i];
        }
    }
    const MsTySubst subst = {.vars = vars, .args = args, .count = count};
    return count == 0 ? ty : ms_ty_subst(&in->c->tys, in->arena, ty, &subst);
}

uint32_t ms_infer_defaults(MsInfer *in, uint32_t *first) {
    uint32_t missing = 0;
    for (uint32_t i = 0; i < in->nvars; i++) {
        if (in->bound[i] == MS_TY_NONE) {
            const MsTy fallback = ms_var_info(in->c, in->vars[i])->def;
            in->bound[i] = fallback == MS_TY_NONE ? MS_TY_NONE : ms_infer_apply(in, fallback);
        }
        if (in->bound[i] == MS_TY_NONE) {
            *first = missing == 0 ? i : *first;
            missing++;
        }
    }
    return missing;
}
