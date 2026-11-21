/* The effect scan: what a checked body references, read from the checker's facts. Mirrors the
 * `Scan` visitor of crates/ms-check/src/effects.rs for the constructs the C body checker handles so
 * far (named calls, constants, writes through a member); the rest follow the call columns
 * (methods, interface conversions) as the checker fills them. */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include "ms/effects.h"
#include "ms/facts.h"
#include "ms/methods.h"
#include "ms/walk.h"

typedef struct ScanState {
    MsArena *arena;
    const MsCheck *check;
    const MsFacts *facts;
    MsScanEdge *edges;
    uint32_t nedges, cap;
    bool unknown, write, partial;
} ScanState;

/* Whether `sym` is a callable node: a function, type or constant some loaded module declares. */
static bool scan_is_node(const MsCheck *c, MsSymId sym) {
    const MsSyms *syms = &c->syms;
    if (sym >= syms->count || syms->module[sym] == MS_NONE || syms->decl[sym] == NULL) {
        return false;
    }
    const uint8_t kind = syms->decl[sym]->kind;
    return kind == MS_D_FN || kind == MS_D_TYPE || kind == MS_D_CONST;
}

bool ms_effect_method_is_node(const MsCheck *c, const MsMethods *m, uint32_t row) {
    if (row >= m->count || m->native[row] != MS_NATIVE_SOURCE || m->decl[row] == NULL) {
        return false;
    }
    for (uint32_t k = 0; k < m->nvars[row]; k++) {
        const MsTy var = m->vars[m->vars_at[row] + k];
        if (var < c->var_info_cap && c->var_info[var].nbounds != 0) {
            return false;
        }
    }
    return true;
}

MsDispatch ms_effect_dispatch(const MsCheck *c, const MsFacts *facts, uint32_t call) {
    const MsKind kind = ms_ty_kind(&c->tys, facts->call_receiver[call]);
    if (kind == MS_K_PRIMITIVE) {
        return MS_DISPATCH_NOTHING;
    }
    return kind == MS_K_CONTRACT || kind == MS_K_VARIABLE ? MS_DISPATCH_UNKNOWN : MS_DISPATCH_PARTIAL;
}

/* Records a reference to `callee`; the first one keeps its position. */
static void scan_edge(ScanState *s, MsSymId callee, MsPos pos) {
    for (uint32_t i = 0; i < s->nedges; i++) {
        if (s->edges[i].callee == callee) {
            return;
        }
    }
    if (s->nedges == s->cap) {
        MsScanEdge *grown = MS_NEW_N(s->arena, MsScanEdge, s->cap == 0 ? 8 : s->cap * 2);
        for (uint32_t i = 0; i < s->nedges; i++) {
            grown[i] = s->edges[i];
        }
        s->edges = grown;
        s->cap = s->cap == 0 ? 8 : s->cap * 2;
    }
    s->edges[s->nedges++] = (MsScanEdge){callee, pos};
}

/* A call, or a constant read (a call of no arguments): an edge to a source callee, a constructor
 * edge for a type, `unknown` for anything else but `core/panic`. */
static void scan_call(ScanState *s, const MsExpr *e) {
    const MsSyms *syms = &s->check->syms;
    const MsSymId callee = s->facts->call_callee[e->id];
    const uint32_t row = s->facts->call_method[e->id];
    if (row != MS_NONE && ms_effect_method_is_node(s->check, s->facts->methods, row) && s->facts->call_interface[e->id] == MS_TY_NONE) {
        scan_edge(s, ms_effect_method_node(s->check, row), e->pos);
        return;
    }
    if (row != MS_NONE) {
        s->partial = true;
        return;
    }
    if (s->facts->call_interface[e->id] != MS_TY_NONE) {
        const MsDispatch dispatch = ms_effect_dispatch(s->check, s->facts, e->id);
        s->partial = s->partial || dispatch == MS_DISPATCH_PARTIAL;
        s->unknown = s->unknown || dispatch == MS_DISPATCH_UNKNOWN;
        return;
    }
    if (callee == MS_NONE) {
        s->unknown = true;
        return;
    }
    if (syms->decl[callee] != NULL && syms->decl[callee]->kind == MS_D_TYPE) {
        // A type the runtime provides (`Error`) has no body to charge.
        if (scan_is_node(s->check, callee) && syms->native[callee] == MS_NATIVE_SOURCE) {
            scan_edge(s, callee, e->pos);
        }
        return;
    }
    if (syms->native[callee] == MS_NATIVE_SOURCE) {
        scan_edge(s, callee, e->pos);
        return;
    }
    const MsStr name = ms_name(s->check->names, syms->native_name[callee]);
    if (name.len != sizeof "core/panic" - 1 || memcmp(name.ptr, "core/panic", name.len) != 0) {
        s->unknown = true;
    }
}

static void scan_stmt(void *ctx, const MsStmt *stmt) {
    ScanState *s = ctx;
    if (stmt->kind == MS_S_ASSIGN && stmt->u.assign.member_target) {
        s->write = true;
    }
}

/* Turning a value into an interface hands out its methods, so the conversion is charged for them: the
 * impls of the interface for the source type, and the type's own methods the interface's operations name. */
static void scan_conversion(ScanState *s, const MsExpr *e, MsTy source) {
    const MsMethods *methods = s->facts->methods;
    const MsTy target = s->facts->expr_ty[e->id];
    const MsTyTable *tys = &s->check->tys;
    const MsOperations *ops = tys->def[target] == 0
                                  ? NULL
                                  : ms_interface_operations((const MsMethodTable *)methods, tys->def[target] - 1);
    for (uint32_t row = 0; row < methods->count; row++) {
        if (tys->def[methods->receiver[row]] != tys->def[source] || tys->def[source] == 0 ||
            methods->native[row] != MS_NATIVE_SOURCE || methods->decl[row] == NULL) {
            continue;
        }
        bool charged = methods->contract[row] != MS_TY_NONE && tys->def[target] != 0 &&
                       tys->def[methods->contract[row]] == tys->def[target];
        if (methods->inherent[row] && ops != NULL) {
            const MsMethod *method = ms_method_of_func(methods->decl[row]);
            for (uint32_t k = 0; k < ops->count; k++) {
                charged = charged || ops->items[k].name == method->func.name;
            }
        }
        if (!charged) {
            continue;
        }
        if (ms_effect_method_is_node(s->check, methods, row)) {
            scan_edge(s, ms_effect_method_node(s->check, row), e->pos);
        } else {
            s->partial = true; // a method of a generic impl has no node yet
        }
    }
}

/* A generic call instantiated at a concrete type hands out that type's interface methods: each
 * method an impl or the type itself supplies for an interface is charged where the call names the type. */
static void scan_type_argument(ScanState *s, const MsExpr *e, MsTy ty) {
    const MsTyTable *tys = &s->check->tys;
    const MsKind kind = ms_ty_kind(tys, ty);
    if ((kind != MS_K_TYPE && kind != MS_K_ALTERNATIVE) || tys->def[ty] == 0) {
        return;
    }
    const MsMethods *methods = s->facts->methods;
    for (uint32_t row = 0; row < methods->count; row++) {
        const MsTy receiver = methods->receiver[row];
        if (tys->def[receiver] != tys->def[ty] || (methods->contract[row] == MS_TY_NONE && !methods->inherent[row]) ||
            methods->native[row] != MS_NATIVE_SOURCE || methods->decl[row] == NULL) {
            continue;
        }
        if (ms_effect_method_is_node(s->check, methods, row)) {
            scan_edge(s, ms_effect_method_node(s->check, row), e->pos);
        } else {
            s->partial = true;
        }
    }
}

static void scan_expr(void *ctx, const MsExpr *e) {
    ScanState *s = ctx;
    if (s->facts->coerce_iface[e->id] != MS_TY_NONE) {
        scan_conversion(s, e, s->facts->coerce_iface[e->id]);
    }
    const MsFacts *facts = s->facts;
    for (uint32_t k = 0; facts->call_type_args_len != NULL && k < facts->call_type_args_len[e->id]; k++) {
        scan_type_argument(s, e, facts->type_args[facts->call_type_args_at[e->id] + k]);
    }
    if (s->facts->const_use[e->id]) {
        scan_call(s, e);
        return;
    }
    if (e->kind == MS_E_CALL) {
        scan_call(s, e);
    } else if (e->kind == MS_E_NAME && s->facts->res_kind[e->id] == MS_RES_SYMBOL) {
        /* A function named as a value, or called by name: authority is charged where it is referenced. */
        const MsSymId sym = s->facts->res_ref[e->id];
        if (scan_is_node(s->check, sym) && s->check->syms.native[sym] == MS_NATIVE_SOURCE) {
            scan_edge(s, sym, e->pos);
        }
    }
}

static MsScanNode scan_finish(ScanState *s, uint32_t callable) {
    // A binding that must be closed calls its `close` when its scope ends, an edge no expression names.
    const MsBindings *bindings = &s->facts->bindings;
    for (uint32_t i = 0; i < bindings->count && !s->partial; i++) {
        s->partial = bindings->callable[i] == callable && (bindings->flags[i] & MS_BIND_RESOURCE) != 0;
    }
    return (MsScanNode){.edges = s->edges, .nedges = s->nedges, .unknown = s->unknown, .write = s->write,
                       .partial = s->partial};
}

MsScanNode ms_effect_scan_decl(MsArena *arena, const MsCheck *c, MsModId module, const MsDecl *d) {
    ScanState s = {.arena = arena, .check = c, .facts = c->mods[module].facts};
    const MsVisitor visitor = {.ctx = &s, .stmt = scan_stmt, .expr = scan_expr};
    ms_walk_decl(&visitor, d);
    return scan_finish(&s, d->id);
}

MsScanNode ms_effect_scan_method(MsArena *arena, const MsCheck *c, MsModId module, const MsMethod *method) {
    ScanState s = {.arena = arena, .check = c, .facts = c->mods[module].facts};
    const MsVisitor visitor = {.ctx = &s, .stmt = scan_stmt, .expr = scan_expr};
    ms_walk_callable(&visitor, method->func.params, method->func.body);
    return scan_finish(&s, method->id);
}
