/* The effect scan: what a checked body references, read from the checker's facts. Mirrors the
 * `Scan` visitor of crates/ms-check/src/effects.rs for the constructs the C body checker handles so
 * far (named calls, constants, writes through a member); the rest follow the call columns
 * (methods, interface conversions) as the checker fills them. */
#include <stdlib.h>
#include <string.h>

#include "ms/effects.h"
#include "ms/facts.h"
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
    if (row != MS_NONE && ms_effect_method_is_node(s->facts->methods, row) && s->facts->call_interface[e->id] == MS_TY_NONE) {
        scan_edge(s, ms_effect_method_node(s->check, row), e->pos);
        return;
    }
    if (row != MS_NONE || s->facts->call_interface[e->id] != MS_TY_NONE) {
        s->partial = true;
        return;
    }
    if (callee == MS_NONE) {
        s->unknown = true;
        return;
    }
    if (s->facts->call_type_args_len != NULL && s->facts->call_type_args_len[e->id] != 0) {
        s->partial = true; // the operations of the type arguments are charged too, which the scan does not port yet
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

static void scan_expr(void *ctx, const MsExpr *e) {
    ScanState *s = ctx;
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
