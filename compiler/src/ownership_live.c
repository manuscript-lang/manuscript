/* Liveness for the ownership pass (ms/ownership.h): `live.rs`, for the statements and expressions
 * the body checker accepts so far.
 *
 * The walk runs backwards. `later[binding]` is the earliest use of the binding after the point
 * reached, so a use is the last one when `later` is empty, and the use it finds there is its
 * `next`. An operand that runs on some paths only (`and`, `or`) joins the paths with and without
 * it, keeping the earlier use. */
#include <string.h>

#include "ms/ownership.h"

MsLiveness ms_liveness_new(MsArena *arena, uint32_t node_count) {
    const size_t nodes = (size_t)node_count + 1;
    MsLiveness live = {MS_NEW_N(arena, uint8_t, nodes), MS_NEW_N(arena, uint32_t, nodes),
                       MS_NEW_N(arena, MsPos, nodes)};
    memset(live.state, MS_USE_NONE, nodes * sizeof *live.state);
    memset(live.next, 0xff, nodes * sizeof *live.next);
    memset(live.pos, 0, nodes * sizeof *live.pos);
    return live;
}

typedef struct LiveWalk {
    MsLiveness *live;
    const MsFacts *facts;
    MsArena *scratch;
    uint32_t *later; /* by binding id: the earliest later use, or MS_NONE */
    uint32_t nbindings;
    bool supported;
} LiveWalk;

static void live_expr(LiveWalk *w, const MsExpr *e);

static void live_use(LiveWalk *w, const MsExpr *e) {
    const uint32_t binding = w->facts->res_ref[e->id];
    const uint32_t next = w->later[binding];
    w->live->state[e->id] = next == MS_NONE ? MS_USE_LAST : MS_USE_LATER;
    w->live->next[e->id] = next;
    w->live->pos[e->id] = e->pos;
    w->later[binding] = e->id;
}

/* After an operand that may be skipped: each binding's earlier use on either path. */
static void live_join(LiveWalk *w, const uint32_t *skipped) {
    for (uint32_t i = 0; i < w->nbindings; i++) {
        if (skipped[i] != MS_NONE && (w->later[i] == MS_NONE || skipped[i] < w->later[i])) {
            w->later[i] = skipped[i];
        }
    }
}

static void live_binary(LiveWalk *w, const MsExpr *e) {
    const bool conditional = e->op == MS_B_AND || e->op == MS_B_OR;
    uint32_t *skipped = NULL;
    if (conditional) {
        skipped = MS_NEW_N(w->scratch, uint32_t, w->nbindings + 1);
        memcpy(skipped, w->later, sizeof(uint32_t) * w->nbindings);
    }
    live_expr(w, e->u.bin.right);
    if (conditional) {
        live_join(w, skipped);
    }
    live_expr(w, e->u.bin.left);
}

static void live_expr(LiveWalk *w, const MsExpr *e) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID: return;
    case MS_E_TEXT:
        for (uint32_t i = e->u.text.len; i > 0; i--) {
            if (e->u.text.ptr[i - 1].expr != NULL) {
                live_expr(w, e->u.text.ptr[i - 1].expr);
            }
        }
        return;
    case MS_E_NAME:
        if (w->facts->res_kind[e->id] == MS_RES_BINDING) {
            live_use(w, e);
        }
        return;
    case MS_E_UNARY: live_expr(w, e->u.bin.left); return;
    case MS_E_BINARY: live_binary(w, e); return;
    case MS_E_MEMBER:
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_LAMBDA:
    case MS_E_CALL:
    case MS_E_MATCH: w->supported = false; return;
    }
}

/* A binding's life starts at its definition: nothing before it uses it. */
static void live_define(LiveWalk *w, const MsPattern *pattern) {
    const uint32_t binding = w->facts->pattern_binding[pattern->id];
    if (binding != MS_NONE) {
        w->later[binding] = MS_NONE;
    }
}

static void live_statement(LiveWalk *w, const MsStmt *s) {
    switch ((MsStmtKind)s->kind) {
    case MS_S_BIND:
        live_define(w, s->u.bind.pattern);
        live_expr(w, s->u.bind.value);
        return;
    case MS_S_RETURN:
        /* Nothing runs after a return: the exit holds no live binding. */
        memset(w->later, 0xff, sizeof(uint32_t) * w->nbindings);
        if (s->u.expr != NULL) {
            live_expr(w, s->u.expr);
        }
        return;
    case MS_S_ASSIGN:
    case MS_S_CALL:
    case MS_S_BREAK:
    case MS_S_CONTINUE:
    case MS_S_IF:
    case MS_S_WHILE:
    case MS_S_FOR: w->supported = false; return;
    }
}

bool ms_liveness_function(MsLiveness *live, const MsFacts *facts, const MsFunc *function, MsArena *scratch) {
    LiveWalk w = {.live = live,
                  .facts = facts,
                  .scratch = scratch,
                  .later = MS_NEW_N(scratch, uint32_t, facts->bindings.count + 1),
                  .nbindings = facts->bindings.count,
                  .supported = true};
    memset(w.later, 0xff, sizeof(uint32_t) * (size_t)w.nbindings);
    for (uint32_t i = function->body.len; i > 0 && w.supported; i--) {
        live_statement(&w, function->body.ptr[i - 1]);
    }
    return w.supported;
}
