/* Lists in function bodies: `List[T]` annotations, list literals and `xs[i]`. Handled: elements that
 * are primitives or lists of those, an index that reads a scalar element, and a literal whose first
 * entry or expected type fixes the element type. A list a literal indexes directly, an index that
 * is not an `Int`, and indexing anything else are left to the Rust checker. */
#include "check/check_body.h"

/* The `List` the module sees, or MS_NONE when a declaration shadows it. */
static MsSymId list_symbol(const MsBody *b) {
    return ms_body_visible_builtin(b, MS_BI_LIST);
}

bool ms_body_is_list(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    if (ty == MS_TY_NONE || !ms_ty_is(tys, ty, MS_BI_LIST) || tys->nargs[ty] != 1) {
        return false;
    }
    const MsTy element = ms_ty_args(tys, ty)[0];
    return ms_body_is_admitted(b, element);
}

static MsTy list_of(MsBody *b, MsTy element) {
    const MsSymId sym = list_symbol(b);
    return sym == MS_NONE ? MS_TY_NONE : ms_ty_apply(b->c, b->c->syms.ty[sym], &element, 1);
}

MsTy ms_body_list_annotation(MsBody *b, const MsTypeRef *t) {
    const MsSymId sym = list_symbol(b);
    if (sym == MS_NONE || ms_map_get(&b->c->mods[b->module].names, t->name) != sym) {
        return ms_body_unsupported(b);
    }
    const MsTy element = ms_body_annotation(b, t->args.ptr[0]);
    const MsTy ty = element == MS_TY_NONE ? MS_TY_NONE : list_of(b, element);
    if (ty == MS_TY_NONE || !ms_body_is_list(b, ty)) {
        return ms_body_unsupported(b);
    }
    b->facts->type_ref_ty[t->id] = ty;
    return ty;
}

MsTy ms_body_list(MsBody *b, const MsExpr *e, MsTy expected) {
    const MsExprs *items = &e->u.list;
    MsTy element = MS_TY_NONE;
    if (expected != MS_TY_NONE) {
        if (!ms_body_is_list(b, expected)) {
            return ms_body_unsupported(b);
        }
        element = ms_ty_args(&b->c->tys, expected)[0];
    }
    uint32_t first = 0;
    if (element == MS_TY_NONE) {
        if (items->len == 0) {
            if (!b->c->mods[b->module].unknown_type) { // one unknown type is reported once; later `<invalid>` only restates it
                ms_body_report(b, e->pos, ms_arena_fmt(&b->c->arena, "cannot infer list element type; add an annotation, e.g. xs: List[Int] := []"));
            }
            return list_of(b, b->invalid_ty); // as Rust: `List[<invalid>]`, which silences what uses it
        }
        element = ms_body_expr(b, items->ptr[0], MS_TY_NONE);
        first = 1;
    }
    const MsTy ty = element == MS_TY_NONE ? MS_TY_NONE : list_of(b, element);
    if (ty == MS_TY_NONE || !ms_body_is_list(b, ty)) {
        return ms_body_unsupported(b);
    }
    for (uint32_t i = first; i < items->len; i++) {
        b->context = ms_arena_fmt(&b->c->arena, "entry %u of the literal, whose entries share one type", i + 1).ptr;
        if (ms_body_expr(b, items->ptr[i], element) == MS_TY_NONE) {
            return MS_TY_NONE;
        }
    }
    return ty;
}

/* `xs[i]`, written as an index or as a bracket that reads as a type application: the receiver must be
 * a local, which makes the bracket an index. */
MsTy ms_body_index(MsBody *b, const MsExpr *e) {
    MsExpr *left = NULL;
    MsExpr *index = NULL;
    if (!ms_expr_index(e, &left, &index) || (e->kind == MS_E_APPLY && (left->kind != MS_E_NAME || ms_body_find_binding(b, left->u.sym) == MS_NONE))) {
        return ms_body_unsupported(b);
    }
    const MsTy list = ms_body_expr(b, left, MS_TY_NONE);
    if (list != MS_TY_NONE && left->kind != MS_E_MAP && ms_body_is_map(b, list)) {
        return ms_body_map_index(b, list, index);
    }
    if (list == MS_TY_NONE || left->kind == MS_E_LIST || !ms_body_is_list(b, list)) {
        return ms_body_unsupported(b);
    }
    const MsTy element = ms_ty_args(&b->c->tys, list)[0];
    return ms_body_expr(b, index, b->int_ty) == MS_TY_NONE ? MS_TY_NONE : element;
}
