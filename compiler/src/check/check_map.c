/* Maps in function bodies: `Map[K, V]` annotations and map literals. Handled: keys of type `Int`,
 * `String` or `Bool` (the types with the key bounds `equals` and `hash`), values of any type the
 * pass admits, and a literal with at least one entry or an expected type that fixes both types.
 * An empty literal without an expected type is left to the Rust checker (it reports the missing
 * annotation). */
#include "check/check_body.h"

/* The `Map` the module sees, or MS_NONE when a declaration shadows it. */
static MsSymId map_symbol(const MsBody *b) {
    return ms_body_visible_builtin(b, MS_BI_MAP);
}

static bool map_is_key(const MsBody *b, MsTy key) {
    return key == b->int_ty || key == b->string_ty || key == b->bool_ty;
}

bool ms_body_is_map(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    if (ty == MS_TY_NONE || !ms_ty_is(tys, ty, MS_BI_MAP) || tys->nargs[ty] != 2) {
        return false;
    }
    const MsTy *args = ms_ty_args(tys, ty);
    return map_is_key(b, args[0]) && ms_body_is_admitted(b, args[1]);
}

/* `Set[T]` of a hashable primitive: a set held and passed like a map. */
bool ms_body_is_set(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    return ty != MS_TY_NONE && ms_ty_is(tys, ty, MS_BI_SET) && tys->nargs[ty] == 1 && map_is_key(b, ms_ty_args(tys, ty)[0]);
}

static MsTy map_of(MsBody *b, MsTy key, MsTy value) {
    const MsSymId sym = map_symbol(b);
    const MsTy args[2] = {key, value};
    return sym == MS_NONE ? MS_TY_NONE : ms_ty_apply(b->c, b->c->syms.ty[sym], args, 2);
}

MsTy ms_body_map_annotation(MsBody *b, const MsTypeRef *t) {
    const MsSymId sym = map_symbol(b);
    if (sym == MS_NONE || ms_map_get(&b->c->mods[b->module].names, t->name) != sym) {
        return ms_body_unsupported(b);
    }
    const MsTy key = ms_body_annotation(b, t->args.ptr[0]);
    const MsTy value = key == MS_TY_NONE ? MS_TY_NONE : ms_body_annotation(b, t->args.ptr[1]);
    const MsTy ty = value == MS_TY_NONE ? MS_TY_NONE : map_of(b, key, value);
    if (ty == MS_TY_NONE || !ms_body_is_map(b, ty)) {
        return ms_body_unsupported(b);
    }
    b->facts->type_ref_ty[t->id] = ty;
    return ty;
}

MsTy ms_body_map(MsBody *b, const MsExpr *e, MsTy expected) {
    const MsMapEntry *entries_ptr = e->u.map.ptr;
    const uint32_t nentries = e->u.map.len;
    MsTy key = MS_TY_NONE, value = MS_TY_NONE;
    if (expected != MS_TY_NONE) {
        if (!ms_body_is_map(b, expected)) {
            return ms_body_unsupported(b);
        }
        key = ms_ty_args(&b->c->tys, expected)[0];
        value = ms_ty_args(&b->c->tys, expected)[1];
    }
    uint32_t first = 0;
    if (key == MS_TY_NONE) {
        if (nentries == 0) {
            return ms_body_unsupported(b); // "cannot infer map key or value type"
        }
        key = ms_body_expr(b, entries_ptr[0].key, MS_TY_NONE);
        value = key == MS_TY_NONE ? MS_TY_NONE : ms_body_expr(b, entries_ptr[0].value, MS_TY_NONE);
        first = 1;
    }
    const MsTy ty = value == MS_TY_NONE ? MS_TY_NONE : map_of(b, key, value);
    if (ty == MS_TY_NONE || !ms_body_is_map(b, ty)) {
        return ms_body_unsupported(b);
    }
    for (uint32_t i = first; i < nentries; i++) {
        b->context = ms_arena_fmt(&b->c->arena, "key of entry %u of the literal, whose keys share one type", i + 1).ptr;
        if (ms_body_expr(b, entries_ptr[i].key, key) == MS_TY_NONE) {
            return MS_TY_NONE;
        }
        b->context = ms_arena_fmt(&b->c->arena, "value of entry %u of the literal, whose values share one type", i + 1).ptr;
        if (ms_body_expr(b, entries_ptr[i].value, value) == MS_TY_NONE) {
            return MS_TY_NONE;
        }
    }
    return ty;
}

/* `m[key]` with the receiver's type `map`: the key keeps its own type and the result is the value. A value
 * with one owner is borrowed in place; the ownership walk declines a function that hands one out. */
MsTy ms_body_map_index(MsBody *b, MsTy map, const MsExpr *key) {
    const MsTy *args = ms_ty_args(&b->c->tys, map);
    if (!ms_body_is_admitted(b, args[1])) {
        return ms_body_unsupported(b);
    }
    return ms_body_expr(b, key, args[0]) == MS_TY_NONE ? MS_TY_NONE : args[1];
}
