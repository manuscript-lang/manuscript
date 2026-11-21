/* Methods of impls: each claimed method is a module function named `Receiver.method` whose
 * parameter 0 is the receiver (a pointer when the method is `var`). A call reaches it through the
 * method row the checker recorded (`call_method`), with the receiver as its first argument; the
 * same rule serves every receiver type, with no case for a type or a method name. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/methods.h"

static MsSym lm_name(Lb *lb, MsTy receiver, MsSym method) {
    const MsStr type = ms_name(lb->c->names, lb->c->tys.name[receiver]);
    const MsStr name = ms_name(lb->c->names, method);
    char *text = MS_NEW_N(&lb->m->arena, char, type.len + name.len + 2);
    const int len = snprintf(text, type.len + name.len + 2, "%.*s.%.*s", (int)type.len, type.ptr, (int)name.len, name.ptr);
    return mir_name(lb->m, text, (size_t)len);
}

static LbCallable lm_callable(Lb *lb, uint32_t row) {
    const MsMethods *methods = lb->facts->methods;
    const LbMethodRow *r = &lb->rows[row];
    return (LbCallable){.fn = &r->method->func,
                        .node = r->method->id,
                        .pos = r->owner_pos,
                        .name = lm_name(lb, methods->receiver[row], r->method->func.name),
                        .sig = methods->ty[row],
                        .self_ty = methods->receiver[row],
                        .mutating = (methods->access[row] & MS_METHOD_MUTATING) != 0};
}

/* The rows of the impl methods module `view` wrote, each with the lines it owns: from its own to
 * the next method's or declaration's. */
static void lm_prepare_view(Lb *lb, uint32_t view) {
    const MsMethods *methods = lb->facts->methods;
    const MsModId module = lb->views[view].module;
    const MsDecl **owners = MS_NEW_N(&lb->mut->arena, const MsDecl *, (size_t)methods->count + 1);
    const MsMethod **found = ms_method_rows(lb->mut, module, methods, owners);
    const MsModule *syntax = lb->c->mods[module].syntax;
    for (uint32_t i = 0; i < methods->count; i++) {
        if (found[i] == NULL) {
            continue;
        }
        const uint32_t first = found[i]->pos.line;
        uint32_t end = UINT32_MAX;
        for (uint32_t k = 0; k < syntax->ndecls; k++) {
            const uint32_t line = syntax->decls[k]->pos.line;
            end = line > first && line < end ? line : end;
        }
        for (uint32_t k = 0; k < methods->count; k++) {
            const uint32_t line = found[k] == NULL ? 0 : found[k]->pos.line;
            end = line > first && line < end ? line : end;
        }
        lb->rows[i] = (LbMethodRow){.method = found[i], .view = view, .owner_pos = ms_impl_first_block(lb->mut, module, owners[i])->pos, .first_line = first, .end_line = end};
    }
}

uint32_t lm_prepare(Lb *lb) {
    const MsMethods *methods = lb->facts->methods; // the program's table: the same from every view
    lb->rows = calloc((size_t)methods->count + 1, sizeof *lb->rows);
    lb->method_func = calloc((size_t)methods->count + 1, sizeof *lb->method_func);
    if (lb->rows == NULL || lb->method_func == NULL) {
        return 0;
    }
    for (uint32_t v = 0; v < lb->nviews; v++) {
        lm_prepare_view(lb, v);
    }
    return methods->count;
}

/* Whether method `row` is lowered this pass; read with its module's view entered. */
static bool lm_eligible(const Lb *lb, uint32_t row, const bool *failed) {
    const LbMethodRow *r = &lb->rows[row];
    // A method of a generic impl needs one copy per type argument, which the lowering does not make yet.
    return lb->facts->body_checked[r->method->id] && lb->facts->methods->nvars[row] == 0 && !failed[row] &&
           !lb_lines_have_diagnostic(&lb->c->mods[lb->module], r->first_line, r->end_line);
}

/* Stubs for the methods the pass lowers, so calls and recursion can name them. */
void lm_stubs(Lb *lb, uint32_t nrows, const bool *failed) {
    for (uint32_t i = 0; i < nrows; i++) {
        lb->method_func[i] = MIR_NONE;
        if (lb->rows[i].method == NULL) {
            continue;
        }
        const uint32_t outer = lb_view_enter(lb, lb->rows[i].view);
        if (!lb->facts->body_checked[lb->rows[i].method->id]) {
            lb_why_unchecked(lb, lb->rows[i].method->func.name, lb->rows[i].method->pos);
        }
        if (lm_eligible(lb, i, failed)) {
            const LbCallable callable = lm_callable(lb, i);
            lb->method_func[i] = lb_add_stub(lb, &callable);
        }
        (void)lb_view_enter(lb, outer);
    }
}

/* Lowers each stubbed method; a method that does not lower is marked in `failed`. True when one
 * did not. */
bool lm_lower(Lb *lb, uint32_t nrows, bool *failed, uint32_t *lowered) {
    bool changed = false;
    for (uint32_t i = 0; i < nrows; i++) {
        if (lb->rows[i].method == NULL || failed[i]) {
            continue;
        }
        (void)lb_view_enter(lb, lb->rows[i].view);
        const LbCallable callable = lm_callable(lb, i);
        const bool done = lb->method_func[i] != MIR_NONE && lb_function(lb, &callable, lb->method_func[i]);
        failed[i] = !done;
        changed = changed || !done;
        *lowered += done ? 1 : 0;
    }
    return changed;
}

bool lm_has(const Lb *lb, uint32_t row) {
    return lb->rows != NULL && row < lb->facts->methods->count && lb->rows[row].method != NULL;
}

LbVal lm_call(Lb *lb, const MsExpr *e, uint32_t row) {
    const MsMethods *methods = lb->facts->methods;
    if (row >= methods->count || lb->method_func == NULL) {
        return lb_unsupported(lb);
    }
    const bool mutating = (methods->access[row] & MS_METHOD_MUTATING) != 0;
    return lb_call_func(lb, e, lb->method_func[row], methods->ty[row], e->u.call.callee->u.member.left, mutating, MS_NONE);
}
