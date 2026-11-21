/* Liveness for the ownership pass (ms/ownership.h): `live.rs`, for the statements and expressions
 * the body checker accepts so far.
 *
 * The walk runs backwards. `later[binding]` is the earliest use of the binding after the point
 * reached, so a use is the last one when `later` is empty, and the use it finds there is its
 * `next`. An operand that runs on some paths only (`and`, `or`) joins the paths with and without
 * it, keeping the earlier use. */
#include <string.h>

#include "ms/ownership.h"

MsLiveness ms_liveness_new(MsArena *arena, const MsFacts *facts) {
    const size_t nodes = (size_t)facts->node_count + 1;
    MsLiveness live = {MS_NEW_N(arena, uint8_t, nodes), MS_NEW_N(arena, uint32_t, nodes),
                       MS_NEW_N(arena, MsPos, nodes),   MS_NEW_N(arena, uint32_t, nodes),
                       MS_NEW_N(arena, uint32_t, nodes)};
    memset(live.state, MS_USE_NONE, nodes * sizeof *live.state);
    memset(live.next, 0xff, nodes * sizeof *live.next);
    memset(live.pos, 0, nodes * sizeof *live.pos);
    memset(live.arm_first, 0xff, nodes * sizeof *live.arm_first);
    memset(live.arm_count, 0, nodes * sizeof *live.arm_count);
    const MsBindings *bindings = &facts->bindings;
    for (uint32_t i = 0; i < bindings->count; i++) {
        if (bindings->role[i] == MS_ROLE_ARM) {
            const uint32_t arm = bindings->decl_node[i];
            live.arm_first[arm] = live.arm_count[arm] == 0 ? i : live.arm_first[arm];
            live.arm_count[arm]++;
        }
    }
    return live;
}

/* What `break` and `continue` reach in the innermost loop: the state after the loop and the
 * state at its head. */
typedef struct LiveLoop {
    const uint32_t *after, *head;
    const struct LiveLoop *outer;
} LiveLoop;

typedef struct LiveWalk {
    MsLiveness *live;
    const MsFacts *facts;
    MsArena *scratch;
    uint32_t *later; /* by binding id: the earliest later use, or MS_NONE */
    uint32_t nbindings;
    const LiveLoop *loop;
    bool supported;
} LiveWalk;

static uint32_t *live_copy_of(const LiveWalk *w, const uint32_t *source) {
    uint32_t *copy = MS_NEW_N(w->scratch, uint32_t, w->nbindings + 1);
    memcpy(copy, source, sizeof(uint32_t) * w->nbindings);
    return copy;
}

static uint32_t *live_snapshot(const LiveWalk *w) {
    return live_copy_of(w, w->later);
}

static void live_expr(LiveWalk *w, const MsExpr *e);
static void live_block(LiveWalk *w, const MsStmts *body);

static void live_use(LiveWalk *w, const MsExpr *e) {
    const uint32_t binding = w->facts->res_ref[e->id];
    const uint32_t next = w->later[binding];
    w->live->state[e->id] = next == MS_NONE ? MS_USE_LAST : MS_USE_LATER;
    w->live->next[e->id] = next;
    w->live->pos[e->id] = e->pos;
    w->later[binding] = e->id;
}

/* Each binding's earlier use on either path. */
static bool live_min_into(uint32_t *into, const uint32_t *from, uint32_t n) {
    bool changed = false;
    for (uint32_t i = 0; i < n; i++) {
        if (from[i] != MS_NONE && (into[i] == MS_NONE || from[i] < into[i])) {
            into[i] = from[i];
            changed = true;
        }
    }
    return changed;
}

/* After an operand that may be skipped: the earlier use on either path. */
static void live_join(LiveWalk *w, const uint32_t *skipped) {
    (void)live_min_into(w->later, skipped, w->nbindings);
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

/* Each arm runs from what follows the match: its body, then its value is read first. The arm's
 * payload bindings start there. The scrutinee is read before every arm. */
static void live_match(LiveWalk *w, const MsExpr *e) {
    const uint32_t *after = live_snapshot(w);
    uint32_t *joined = live_copy_of(w, after);
    memset(joined, 0xff, sizeof(uint32_t) * w->nbindings);
    for (uint32_t i = e->u.match.arms.len; i > 0; i--) {
        const MsArm *arm = e->u.match.arms.ptr[i - 1];
        w->later = live_copy_of(w, after);
        if (arm->value != NULL) {
            live_expr(w, arm->value);
        }
        live_block(w, &arm->body);
        for (uint32_t k = 0; k < w->live->arm_count[arm->id]; k++) {
            w->later[w->live->arm_first[arm->id] + k] = MS_NONE;
        }
        (void)live_min_into(joined, w->later, w->nbindings);
    }
    w->later = joined;
    live_expr(w, e->u.match.scrutinee);
}

/* A call of a module function, of an operation of a primitive or a method of an impl (the receiver
 * is read first), or through a function-typed local (the local is read first). The walk decides
 * what it handles. */
static void live_call(LiveWalk *w, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    const bool through_local = callee->kind == MS_E_NAME && w->facts->res_kind[callee->id] == MS_RES_BINDING;
    const bool operation = callee->kind == MS_E_MEMBER &&
                           (w->facts->call_interface[e->id] != MS_TY_NONE || w->facts->call_method[e->id] != MS_NONE);
    if (w->facts->call_callee[e->id] == MS_NONE && !through_local && !operation) {
        w->supported = false; /* anything else the walk does not follow */
        return;
    }
    for (uint32_t i = e->u.call.args.len; i > 0; i--) {
        live_expr(w, e->u.call.args.ptr[i - 1].value);
    }
    if (operation) {
        live_expr(w, callee->u.member.left);
    } else if (through_local) {
        live_expr(w, callee);
    }
}

/* An anonymous function runs on its own: its body is walked from nothing after it, and what it
 * captures was read when it was made, which the walk does not follow (captures are copies). */
static void live_lambda(LiveWalk *w, const MsExpr *e) {
    uint32_t *outer = w->later;
    const LiveLoop *loop = w->loop;
    w->later = MS_NEW_N(w->scratch, uint32_t, w->nbindings + 1);
    memset(w->later, 0xff, sizeof(uint32_t) * (size_t)w->nbindings);
    w->loop = NULL;
    live_block(w, &e->u.lambda.body);
    w->later = outer;
    w->loop = loop;
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
    case MS_E_MEMBER: live_expr(w, e->u.member.left); return;
    case MS_E_INDEX:
    case MS_E_APPLY: { /* `xs[i]` before name resolution said `xs` is a value */
        const MsExpr *list = NULL;
        const MsExpr *index = NULL;
        if (!ms_expr_index(e, &list, &index)) {
            w->supported = false;
            return;
        }
        live_expr(w, index);
        live_expr(w, list);
        return;
    }
    case MS_E_LIST:
        for (uint32_t i = e->u.list.len; i > 0; i--) {
            live_expr(w, e->u.list.ptr[i - 1]);
        }
        return;
    case MS_E_MAP:
        for (uint32_t i = e->u.map.len; i > 0; i--) {
            live_expr(w, e->u.map.ptr[i - 1].value);
            live_expr(w, e->u.map.ptr[i - 1].key);
        }
        return;
    case MS_E_PROBE: w->supported = false; return; /* not modeled */
    case MS_E_LAMBDA: live_lambda(w, e); return;
    case MS_E_CALL:
        if (ms_call_builds_case(w->facts, e)) {
            live_expr(w, e->u.call.args.ptr[0].value);
            return;
        }
        live_call(w, e);
        return;
    case MS_E_MATCH: live_match(w, e); return;
    }
}
/* A binding's life starts at its definition: nothing before it uses it. */
static void live_define(LiveWalk *w, const MsPattern *pattern) {
    const uint32_t binding = w->facts->pattern_binding[pattern->id];
    if (binding != MS_NONE) {
        w->later[binding] = MS_NONE;
    }
}

static void live_statement(LiveWalk *w, const MsStmt *s);

/* The store ends the old value's life; the value runs first, so it may read the old one. */
static void live_assign(LiveWalk *w, const MsStmt *s) {
    const uint32_t binding = w->facts->assign_binding[s->id];
    if (binding == MS_NONE && w->facts->field_store_root[s->id] != MS_NONE) {
        live_expr(w, s->u.assign.target); /* the store uses the variable but keeps it alive */
        live_expr(w, s->u.assign.value);
        return;
    }
    if (binding == MS_NONE) {
        w->supported = false;
        return;
    }
    w->later[binding] = MS_NONE;
    live_expr(w, s->u.assign.value);
}

/* A jump continues from the state at its loop's exit or head. */
static void live_jump(LiveWalk *w, const MsStmt *s) {
    if (w->loop == NULL) {
        w->supported = false;
        return;
    }
    w->later = live_copy_of(w, s->kind == MS_S_BREAK ? w->loop->after : w->loop->head);
}

/* Both branches start from what follows the `if`; afterwards the earlier use on either path counts. */
static void live_if(LiveWalk *w, const MsStmt *s) {
    uint32_t *after = live_snapshot(w);
    live_block(w, &s->u.branch.body);
    if (s->u.branch.binding != NULL) {
        live_define(w, s->u.branch.binding);
    }
    uint32_t *then_later = w->later;
    w->later = after;
    live_block(w, &s->u.branch.else_body);
    live_join(w, then_later);
    live_expr(w, s->u.branch.cond);
}

/* A loop's head sees what follows the loop and the next iteration's reads. Passes repeat until
 * the head stops changing; the last pass leaves the uses the walk reads. */
static void live_while(LiveWalk *w, const MsStmt *s) {
    uint32_t *after = live_snapshot(w);
    uint32_t *head = live_snapshot(w);
    for (;;) {
        w->later = live_copy_of(w, head);
        const LiveLoop here = {after, head, w->loop};
        w->loop = &here;
        live_block(w, &s->u.loop.body);
        w->loop = here.outer;
        live_join(w, after);
        live_expr(w, s->u.loop.cond);
        if (!live_min_into(head, w->later, w->nbindings) || !w->supported) {
            break;
        }
    }
    w->later = head;
}

/* `for i in a..b`: like a `while` whose test reads nothing; the bounds run once before it. */
static void live_for(LiveWalk *w, const MsStmt *s) {
    uint32_t *after = live_snapshot(w);
    uint32_t *head = live_snapshot(w);
    for (;;) {
        w->later = live_copy_of(w, head);
        const LiveLoop here = {after, head, w->loop};
        w->loop = &here;
        live_block(w, &s->u.each.body);
        w->loop = here.outer;
        live_join(w, after);
        if (!live_min_into(head, w->later, w->nbindings) || !w->supported) {
            break;
        }
    }
    w->later = head;
    if (w->facts->each_list[s->id]) {
        live_expr(w, s->u.each.iter);
        return;
    }
    live_expr(w, s->u.each.iter->u.call.args.ptr[1].value);
    live_expr(w, s->u.each.iter->u.call.args.ptr[0].value);
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
    case MS_S_IF: live_if(w, s); return;
    case MS_S_WHILE: live_while(w, s); return;
    case MS_S_BREAK:
    case MS_S_CONTINUE: live_jump(w, s); return;
    case MS_S_ASSIGN: live_assign(w, s); return;
    case MS_S_CALL: live_expr(w, s->u.expr); return;
    case MS_S_FOR: live_for(w, s); return;
    }
}

static void live_block(LiveWalk *w, const MsStmts *body) {
    for (uint32_t i = body->len; i > 0; i--) {
        live_statement(w, body->ptr[i - 1]);
    }
}

bool ms_liveness_function(MsLiveness *live, const MsFacts *facts, const MsFunc *function) {
    MsArena frame = {0}; /* the snapshots of one function */
    LiveWalk w = {.live = live,
                  .facts = facts,
                  .scratch = &frame,
                  .later = MS_NEW_N(&frame, uint32_t, facts->bindings.count + 1),
                  .nbindings = facts->bindings.count,
                  .supported = true};
    memset(w.later, 0xff, sizeof(uint32_t) * (size_t)w.nbindings);
    for (uint32_t i = function->body.len; i > 0 && w.supported; i--) {
        live_statement(&w, function->body.ptr[i - 1]);
    }
    ms_arena_free(&frame);
    return w.supported;
}
