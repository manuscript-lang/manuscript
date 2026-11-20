/* The ownership walk (ms/ownership.h): `walk.rs`, `exprs.rs`, `stmts.rs` and `returns.rs` of the
 * Rust pass, for the statements and expressions the body checker accepts so far.
 *
 * One owner holds each value. A plain name bound to a name of a type that does not copy borrows
 * it until its last use, and while the borrow is live the origin may not move. A use is a move
 * when the position owns what it takes (a binding's initial value, a returned value); a move of
 * a borrowed binding or a binding used again is a diagnostic.
 *
 * Bindings are columns indexed by binding id; the live borrows are one array in push order, so
 * the first conflicting borrow is the first one found. */
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/ownership.h"

/* Who may change a binding (`Perm` in walk.rs). */
typedef enum Perm { PERM_MUTABLE, PERM_IMMUTABLE, PERM_BORROWED } Perm;

typedef struct Borrow {
    uint32_t holder;
    uint32_t origin; /* the binding borrowed from */
    MsPos pos;
    const char *why;
} Borrow;

typedef struct BorrowSet {
    Borrow *items;
    uint32_t len, cap;
} BorrowSet;

/* What a caller needs of a function: whether its non-copy result is a reference into some of its
 * parameters (bit i is parameter i), and whether the walk handles it at all. */
typedef struct OwnSummary {
    uint32_t borrowed_params;
    bool usable;
    bool returns_borrow;
} OwnSummary;

typedef struct OwnWalk {
    MsCheck *check;
    MsModId module;
    const MsFacts *facts;
    MsClassifier *classifier;
    const MsLiveness *live;
    const MsFunc *function;
    uint8_t *perm;      /* by binding id: Perm */
    uint8_t *class_of;  /* by binding id: MsClass */
    uint32_t *origin;   /* by binding id: what a borrowed binding borrows from, else MS_NONE */
    bool *is_param;     /* by binding id */
    uint32_t *param_index; /* by binding id: the parameter's position, else MS_NONE */
    OwnSummary *summaries; /* by declaration node id */
    uint32_t borrowed_params;
    bool quiet;         /* a summary round: diagnostics are left to the final pass */
    bool *deferred;     /* by binding id: a part of a parameter that the match or `if` would consume if it moved */
    BorrowSet active;   /* live borrows in push order; a released one has holder MS_NONE */
    uint32_t *pending;  /* holders whose borrows end with the statement */
    uint32_t npending, pending_cap;
    uint32_t pending_base; /* the pending holders below it belong to an enclosing statement */
    MsPos borrowed_return, owned_return; /* the first return of each kind in the function */
    bool has_borrowed_return, has_owned_return;
    uint32_t *declared; /* bindings in scope, innermost last */
    uint32_t ndeclared, declared_cap;
    bool supported;
} OwnWalk;

typedef enum Demand { DEMAND_READ, DEMAND_MOVE } Demand;

static void own_match(OwnWalk *w, const MsExpr *e, Demand demand, bool returning);
static void own_call(OwnWalk *w, const MsExpr *e, Demand demand);

static MsStr own_name(const OwnWalk *w, uint32_t binding) {
    return ms_name(w->check->names, w->facts->bindings.name[binding]);
}

static void own_error(OwnWalk *w, MsPos pos, MsStr message) {
    if (w->quiet) {
        return;
    }
    const MsModuleRow *row = &w->check->mods[w->module];
    for (uint32_t i = 0; i < row->ndiags; i++) {
        const MsDiag *seen = &row->diags[i].diag;
        if (seen->pos.offset == pos.offset && seen->message.len == message.len &&
            memcmp(seen->message.ptr, message.ptr, message.len) == 0) {
            return;
        }
    }
    const MsCheckDiag diag = {.diag = {.pos = pos, .message = message}, .phase = MS_PHASE_OWNERSHIP};
    ms_report(w->check, w->module, &diag);
}

/* ---- bindings and borrows ---- */

static void own_declare(OwnWalk *w, uint32_t binding, Perm perm, bool parameter) {
    if (w->ndeclared == w->declared_cap) {
        w->declared_cap = ms_capacity_for(w->declared_cap, w->ndeclared + 1);
        w->declared = ms_array_resize(w->declared, w->declared_cap, sizeof *w->declared);
    }
    w->declared[w->ndeclared++] = binding;
    w->perm[binding] = (uint8_t)perm;
    w->class_of[binding] = (uint8_t)ms_classify(w->classifier, w->facts->bindings.ty[binding]);
    w->origin[binding] = MS_NONE;
    w->is_param[binding] = parameter;
    w->param_index[binding] = MS_NONE;
    w->deferred[binding] = false;
}

/* The binding whose storage `binding` names: itself, or what it borrows. */
static uint32_t own_resolve(const OwnWalk *w, uint32_t binding) {
    const bool borrowed = w->perm[binding] == PERM_BORROWED && w->origin[binding] != MS_NONE;
    return borrowed ? w->origin[binding] : binding;
}

static void own_push_borrow(OwnWalk *w, const Borrow *borrow) {
    BorrowSet *set = &w->active;
    if (set->len == set->cap) {
        set->cap = ms_capacity_for(set->cap, set->len + 1);
        set->items = ms_array_resize(set->items, set->cap, sizeof *set->items);
    }
    set->items[set->len++] = *borrow;
}

static void own_declare_borrow(OwnWalk *w, uint32_t binding, uint32_t origin, MsPos pos, const char *why) {
    own_declare(w, binding, PERM_BORROWED, false);
    w->origin[binding] = origin;
    const Borrow borrow = {binding, origin, pos, why};
    own_push_borrow(w, &borrow);
}

static bool own_holds_borrow(const OwnWalk *w, uint32_t holder) {
    for (uint32_t i = 0; i < w->active.len; i++) {
        if (w->active.items[i].holder == holder) {
            return true;
        }
    }
    return false;
}

/* The borrows of the holders that finished their last use end with the statement. */
static void own_release_pending(OwnWalk *w) {
    for (uint32_t k = w->pending_base; k < w->npending; k++) {
        for (uint32_t i = 0; i < w->active.len; i++) {
            if (w->active.items[i].holder == w->pending[k]) {
                w->active.items[i].holder = MS_NONE;
            }
        }
    }
    w->npending = w->pending_base;
}

static void own_queue_release(OwnWalk *w, uint32_t holder) {
    if (w->npending == w->pending_cap) {
        w->pending_cap = ms_capacity_for(w->pending_cap, w->npending + 1);
        w->pending = ms_array_resize(w->pending, w->pending_cap, sizeof *w->pending);
    }
    w->pending[w->npending++] = holder;
}

/* ---- diagnostics ---- */

/* A change (`what`: "move" or "reassign") of `binding` while some live borrow reads from it. */
static void own_check_change(OwnWalk *w, MsPos pos, uint32_t binding, const char *what) {
    const uint32_t root = own_resolve(w, binding);
    for (uint32_t i = 0; i < w->active.len; i++) {
        const Borrow *b = &w->active.items[i];
        if (b->holder == MS_NONE || b->origin != root || b->holder == binding) {
            continue;
        }
        const MsStr holder = own_name(w, b->holder);
        const MsStr shown = own_name(w, binding);
        own_error(w, pos,
                  ms_arena_fmt(&w->check->arena,
                               "cannot %s `%.*s` while `%.*s` borrows it (%s, at %u:%u); finish using `%.*s` before "
                               "this, or give `%.*s` its own value by ending its initializer with `.clone()`",
                               what, (int)shown.len, shown.ptr, (int)holder.len, holder.ptr, b->why, b->pos.line,
                               b->pos.column, (int)holder.len, holder.ptr, (int)holder.len, holder.ptr));
        return;
    }
}

/* What a borrowed binding is called in a diagnostic (`role_text` in walk.rs). */
static const char *own_role_text(const OwnWalk *w, uint32_t binding) {
    switch ((MsBindRole)w->facts->bindings.role[binding]) {
    case MS_ROLE_ARM: return "a match payload";
    case MS_ROLE_LOOP: return "a loop variable";
    case MS_ROLE_PATTERN: return "a pattern variable";
    case MS_ROLE_PARAM:
    case MS_ROLE_SELF:
    case MS_ROLE_LET:
    case MS_ROLE_VAR:
    case MS_ROLE_LAMBDA_PARAM: break;
    }
    return "a borrow";
}

static void own_error_borrowed_move(OwnWalk *w, const MsExpr *e, uint32_t binding) {
    const MsStr name = own_name(w, binding);
    own_error(w, e->pos,
              ms_arena_fmt(&w->check->arena,
                           "cannot move `%.*s` out: it is borrowed, not owned (%s); this position keeps its "
                           "own copy, so write `%.*s.clone()`; to avoid the copy, use `%.*s` only where it is read",
                           (int)name.len, name.ptr, own_role_text(w, binding), (int)name.len, name.ptr, (int)name.len,
                           name.ptr));
}

static void own_error_used_again(OwnWalk *w, const MsExpr *e, uint32_t binding) {
    const MsStr name = own_name(w, binding);
    const uint32_t next = w->live->next[e->id];
    const MsPos next_pos = w->live->pos[next];
    own_error(w, e->pos,
              ms_arena_fmt(&w->check->arena,
                           "`%.*s` is moved here but used again at %u:%u; a value has one owner, so move it only at "
                           "its last use, or pass `%.*s.clone()` if the original is still needed",
                           (int)name.len, name.ptr, next_pos.line, next_pos.column, (int)name.len, name.ptr));
}

/* ---- uses ---- */

static bool own_is_last(const OwnWalk *w, const MsExpr *e) {
    return w->live->state[e->id] != MS_USE_LATER;
}

/* A use that reads or copies: only a holder's last use matters, because its borrows then end. */
static void own_record(OwnWalk *w, const MsExpr *e, uint32_t binding) {
    if (own_is_last(w, e) && own_holds_borrow(w, binding)) {
        own_queue_release(w, binding);
    }
}

static void own_move_out(OwnWalk *w, const MsExpr *e, uint32_t binding) {
    if (w->perm[binding] == PERM_BORROWED && w->deferred[binding]) {
        w->supported = false; /* moving a part out would make the scrutinee consume its parameter */
        return;
    }
    if (w->perm[binding] == PERM_BORROWED) {
        own_error_borrowed_move(w, e, binding);
    } else if (!own_is_last(w, e)) {
        own_error_used_again(w, e, binding);
    }
    if (w->perm[binding] != PERM_BORROWED) {
        own_check_change(w, e->pos, binding, "move");
    }
    own_record(w, e, binding);
}

static void own_use_local(OwnWalk *w, const MsExpr *e, Demand demand) {
    if (w->facts->res_kind[e->id] != MS_RES_BINDING) {
        /* A module constant: a plain value is read; anything else is left to Rust. */
        w->supported = w->supported && ms_classify(w->classifier, w->facts->expr_ty[e->id]) == MS_CLASS_COPY;
        return;
    }
    const uint32_t binding = w->facts->res_ref[e->id];
    if (demand != DEMAND_MOVE || w->class_of[binding] == MS_CLASS_COPY) {
        own_record(w, e, binding);
        return;
    }
    own_move_out(w, e, binding);
}

static void own_expr(OwnWalk *w, const MsExpr *e, Demand demand) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID: return;
    case MS_E_TEXT:
        for (uint32_t i = 0; i < e->u.text.len; i++) {
            if (e->u.text.ptr[i].expr != NULL) {
                own_expr(w, e->u.text.ptr[i].expr, DEMAND_READ);
            }
        }
        return;
    case MS_E_NAME:
        // A module constant reads no local.
        if (w->facts->res_kind[e->id] == MS_RES_BINDING) {
            own_use_local(w, e, demand);
        }
        return;
    case MS_E_UNARY: own_expr(w, e->u.bin.left, DEMAND_READ); return;
    case MS_E_BINARY:
        own_expr(w, e->u.bin.left, DEMAND_READ);
        own_expr(w, e->u.bin.right, DEMAND_READ);
        return;
    case MS_E_MEMBER: own_expr(w, e->u.member.left, DEMAND_READ); return; /* a copied field reads its holder */
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_LAMBDA:
    case MS_E_CALL: own_call(w, e, demand); return;
    case MS_E_MATCH: own_match(w, e, demand, false); return;
    }
}

/* ---- calls ---- */

/* The summary of the function a call names, or NULL when the walk cannot reason about it. */
static const OwnSummary *own_callee(const OwnWalk *w, const MsExpr *e) {
    const uint32_t sym = w->facts->call_callee[e->id];
    const MsDecl *decl = sym == MS_NONE ? NULL : w->check->syms.decl[sym];
    if (decl == NULL || decl->kind != MS_D_FN) {
        return NULL;
    }
    const OwnSummary *summary = &w->summaries[decl->id];
    return summary->usable ? summary : NULL;
}

/* The bindings a call's reference result points into, one per borrowed parameter's argument: a
 * name gives what it names, a nested borrowing call gives its own. False when a source is a
 * temporary, which the call's result then owns a copy of. */
static bool own_call_origins(const OwnWalk *w, const MsExpr *e, uint32_t *out, uint32_t *count) {
    const OwnSummary *callee = own_callee(w, e);
    if (callee == NULL || !callee->returns_borrow) {
        return false;
    }
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        const MsExpr *arg = e->u.call.args.ptr[i].value;
        if ((callee->borrowed_params >> i & 1u) == 0) {
            continue;
        }
        if (arg->kind == MS_E_CALL) {
            if (!own_call_origins(w, arg, out, count)) {
                return false;
            }
        } else if (arg->kind == MS_E_NAME && w->facts->res_kind[arg->id] == MS_RES_BINDING) {
            const uint32_t root = own_resolve(w, w->facts->res_ref[arg->id]);
            bool seen = false;
            for (uint32_t k = 0; k < *count; k++) {
                seen = seen || out[k] == root;
            }
            if (!seen && *count < 4) {
                out[(*count)++] = root;
            }
        } else {
            return false;
        }
    }
    return *count != 0;
}

static void own_error_kept_borrow(OwnWalk *w, const MsExpr *e, const uint32_t *origins, uint32_t count) {
    const MsStr name = ms_name(w->check->names, e->u.call.callee->u.sym);
    MsStr roots = {0};
    uint32_t order[4];
    for (uint32_t i = 0; i < count; i++) {
        order[i] = origins[i];
    }
    for (uint32_t i = 1; i < count; i++) { /* sorted by name, as Rust lists them */
        for (uint32_t k = i; k > 0; k--) {
            const MsStr a = own_name(w, order[k - 1]);
            const MsStr b = own_name(w, order[k]);
            const size_t n = a.len < b.len ? a.len : b.len;
            const int c = memcmp(a.ptr, b.ptr, n);
            if (c > 0 || (c == 0 && a.len > b.len)) {
                const uint32_t t = order[k];
                order[k] = order[k - 1];
                order[k - 1] = t;
            }
        }
    }
    for (uint32_t i = 0; i < count; i++) {
        const MsStr part = own_name(w, order[i]);
        roots = i == 0 ? part
                       : ms_arena_fmt(&w->check->arena, "%.*s`, `%.*s", (int)roots.len, roots.ptr, (int)part.len, part.ptr);
    }
    own_error(w, e->pos,
              ms_arena_fmt(&w->check->arena,
                           "`%.*s` returns a reference into `%.*s`, which this position would keep; store `.clone()` of "
                           "it, or use it in place",
                           (int)name.len, name.ptr, (int)roots.len, roots.ptr));
}

/* A call of a function this module declares: each argument is read, since a parameter that is
 * not `var` or `move` only borrows. A reference result may not be kept where it would own. */
static void own_call(OwnWalk *w, const MsExpr *e, Demand demand) {
    const OwnSummary *callee = own_callee(w, e);
    if (callee == NULL || e->u.call.callee->kind != MS_E_NAME) {
        w->supported = false;
        return;
    }
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        own_expr(w, e->u.call.args.ptr[i].value, DEMAND_READ);
    }
    const bool copied = ms_classify(w->classifier, w->facts->expr_ty[e->id]) == MS_CLASS_COPY;
    uint32_t origins[4];
    uint32_t count = 0;
    if (callee->returns_borrow && !copied && demand == DEMAND_MOVE && own_call_origins(w, e, origins, &count)) {
        own_error_kept_borrow(w, e, origins, count);
    }
}

/* ---- statements ---- */

/* Whether `value` is a name of another binding that a `let` of a type that does not copy borrows
 * instead of taking: the source is used again, or is itself a borrow. Returns the source. */
static uint32_t own_borrowed_name(const OwnWalk *w, const MsStmt *s, uint32_t binding) {
    const MsExpr *value = s->u.bind.value;
    if (value->kind != MS_E_NAME || w->facts->res_kind[value->id] != MS_RES_BINDING) {
        return MS_NONE;
    }
    const uint32_t source = w->facts->res_ref[value->id];
    const MsBindings *bindings = &w->facts->bindings;
    const bool same_type = bindings->ty[source] == bindings->ty[binding];
    const bool allowed = !s->u.bind.is_mutable || w->perm[source] == PERM_MUTABLE;
    const bool kept = !own_is_last(w, value) || w->perm[source] == PERM_BORROWED;
    return same_type && allowed && kept ? source : MS_NONE;
}

/* `x := f(a)` where `f` returns a reference into `a`: the binding borrows it like a name. */
static bool own_bind_borrowed_call(OwnWalk *w, const MsStmt *s, uint32_t binding) {
    const MsExpr *value = s->u.bind.value;
    const OwnSummary *callee = value->kind == MS_E_CALL ? own_callee(w, value) : NULL;
    uint32_t origins[4];
    uint32_t count = 0;
    if (callee == NULL || !callee->returns_borrow || w->class_of[binding] == MS_CLASS_COPY ||
        !own_call_origins(w, value, origins, &count)) {
        return false;
    }
    if (s->u.bind.is_mutable || count != 1) {
        w->supported = false; /* an exclusive borrow, or one that holds several places */
        return true;
    }
    own_expr(w, value, DEMAND_READ);
    own_declare_borrow(w, binding, origins[0], s->u.bind.pattern->pos, "binding of a part of it");
    return true;
}

static void own_bind(OwnWalk *w, const MsStmt *s) {
    const uint32_t binding = w->facts->pattern_binding[s->u.bind.pattern->id];
    own_declare(w, binding, s->u.bind.is_mutable ? PERM_MUTABLE : PERM_IMMUTABLE, false);
    if (own_bind_borrowed_call(w, s, binding)) {
        return;
    }
    const uint32_t source = w->class_of[binding] == MS_CLASS_COPY ? MS_NONE : own_borrowed_name(w, s, binding);
    if (source == MS_NONE) {
        own_expr(w, s->u.bind.value, DEMAND_MOVE);
        return;
    }
    if (s->u.bind.is_mutable) {
        w->supported = false; /* a `var` borrow of a name: exclusive borrows come with calls and assignment */
        return;
    }
    own_expr(w, s->u.bind.value, DEMAND_READ);
    own_declare_borrow(w, binding, own_resolve(w, source), s->u.bind.pattern->pos, "binding of a borrowed value");
}

/* Whether returning the name hands back a reference into a parameter: a parameter itself, or a
 * borrow whose origin is one. Nothing moves then. */
static bool own_returns_parameter_borrow(const OwnWalk *w, const MsExpr *e) {
    if (e->kind != MS_E_NAME || w->facts->res_kind[e->id] != MS_RES_BINDING) {
        return false;
    }
    const uint32_t binding = w->facts->res_ref[e->id];
    return w->is_param[own_resolve(w, binding)];
}

/* A value handed back to the caller: a parameter's borrow is read, anything else moves out. A
 * match hands back the value of the arm it takes. */
static void own_returned(OwnWalk *w, const MsExpr *e) {
    if (e->kind == MS_E_MATCH) {
        own_match(w, e, DEMAND_MOVE, true);
        return;
    }
    if (ms_classify(w->classifier, w->facts->expr_ty[e->id]) != MS_CLASS_MOVE) {
        own_expr(w, e, DEMAND_MOVE);
        return;
    }
    if (e->kind == MS_E_CALL) {
        const OwnSummary *callee = own_callee(w, e);
        w->supported = w->supported && callee != NULL && !callee->returns_borrow;
    }
    if (own_returns_parameter_borrow(w, e)) {
        w->borrowed_params |= 1u << w->param_index[own_resolve(w, w->facts->res_ref[e->id])];
        w->borrowed_return = w->has_borrowed_return ? w->borrowed_return : e->pos;
        w->has_borrowed_return = true;
        own_expr(w, e, DEMAND_READ);
        return;
    }
    w->owned_return = w->has_owned_return ? w->owned_return : e->pos;
    w->has_owned_return = true;
    own_expr(w, e, DEMAND_MOVE);
}

static void own_return(OwnWalk *w, const MsStmt *s) {
    if (s->u.expr != NULL) {
        own_returned(w, s->u.expr);
    }
}

/* ---- blocks and branches ---- */

static void own_statement(OwnWalk *w, const MsStmt *s);

static bool own_set_holds(const BorrowSet *set, uint32_t holder) {
    for (uint32_t i = 0; i < set->len; i++) {
        if (set->items[i].holder == holder) {
            return true;
        }
    }
    return false;
}

static BorrowSet own_set_copy(const BorrowSet *set) {
    BorrowSet copy = {0};
    if (set->len != 0) {
        copy.cap = ms_capacity_for(0, set->len);
        copy.items = ms_array_resize(NULL, copy.cap, sizeof *copy.items);
        memcpy(copy.items, set->items, sizeof *copy.items * set->len);
        copy.len = set->len;
    }
    return copy;
}

/* The state after two paths: all of `first`, then the live borrows of the current set whose
 * holder `first` does not hold. Takes `first`; the current set is dropped. */
static void own_join(OwnWalk *w, BorrowSet first) {
    BorrowSet second = w->active;
    w->active = first;
    for (uint32_t i = 0; i < second.len; i++) {
        if (second.items[i].holder != MS_NONE && !own_set_holds(&first, second.items[i].holder)) {
            own_push_borrow(w, &second.items[i]);
        }
    }
    free(second.items);
}

/* The bindings declared since `mark` end, and so do the borrows they hold. */
static void own_end_scope(OwnWalk *w, uint32_t mark) {
    for (uint32_t i = 0; i < w->active.len; i++) {
        Borrow *b = &w->active.items[i];
        for (uint32_t k = mark; b->holder != MS_NONE && k < w->ndeclared; k++) {
            if (w->declared[k] == b->holder) {
                b->holder = MS_NONE;
            }
        }
    }
    w->ndeclared = mark;
}

/* The statements of a block, then its final value (a match arm's) in the same scope. */
static void own_block_value(OwnWalk *w, const MsStmts *body, const MsExpr *value, Demand demand, bool returning) {
    const uint32_t mark = w->ndeclared;
    const uint32_t outer_base = w->pending_base;
    w->pending_base = w->npending;
    for (uint32_t i = 0; i < body->len && w->supported; i++) {
        own_statement(w, body->ptr[i]);
        own_release_pending(w);
    }
    if (value != NULL && w->supported) {
        if (returning) {
            own_returned(w, value);
        } else {
            own_expr(w, value, demand);
        }
        own_release_pending(w);
    }
    w->pending_base = outer_base;
    own_end_scope(w, mark);
}

static void own_block(OwnWalk *w, const MsStmts *body) {
    own_block_value(w, body, NULL, DEMAND_READ, false);
}

/* ---- matched values and their parts ---- */

/* What a matched value is: owned (moved in, so its parts are too) or a place read in place, whose
 * parts borrow from `origin`. `deferred` marks a parameter that moving a part would consume. */
typedef struct Scrutinee {
    bool owned;
    uint32_t origin;
    bool deferred;
} Scrutinee;

static Scrutinee own_scrutinee(OwnWalk *w, const MsExpr *e) {
    const bool name = e->kind == MS_E_NAME && w->facts->res_kind[e->id] == MS_RES_BINDING;
    if (!name) {
        own_expr(w, e, DEMAND_MOVE);
        return (Scrutinee){true, MS_NONE, false};
    }
    const uint32_t binding = w->facts->res_ref[e->id];
    const bool last_use = w->class_of[binding] != MS_CLASS_COPY && own_is_last(w, e);
    const bool owned_local = w->perm[binding] != PERM_BORROWED && !w->is_param[binding];
    if (last_use && owned_local) {
        own_expr(w, e, DEMAND_MOVE);
        return (Scrutinee){true, MS_NONE, false};
    }
    const bool consumable = last_use && w->perm[binding] == PERM_IMMUTABLE && w->is_param[binding];
    own_expr(w, e, DEMAND_READ);
    return (Scrutinee){false, own_resolve(w, binding), consumable};
}

/* A part of the matched value: a copy or an owned part is a binding of its own, any other part
 * borrows from the scrutinee's origin until its last use. False for a resource. */
static bool own_payload(OwnWalk *w, uint32_t binding, const Scrutinee *source, MsPos pos) {
    own_declare(w, binding, PERM_IMMUTABLE, false);
    if (w->class_of[binding] == MS_CLASS_RESOURCE) {
        return false;
    }
    if (w->class_of[binding] == MS_CLASS_COPY || source->owned) {
        return true;
    }
    own_declare_borrow(w, binding, source->origin, pos, "pattern binding");
    w->deferred[binding] = source->deferred;
    return true;
}

static bool own_arm_payloads(OwnWalk *w, const MsArm *arm, const Scrutinee *source) {
    for (uint32_t k = 0; k < w->live->arm_count[arm->id]; k++) {
        if (!own_payload(w, w->live->arm_first[arm->id] + k, source, arm->pos)) {
            return false;
        }
    }
    return true;
}

/* `name = value`: the value is moved in, then the old one is replaced, which no borrow may read. */
static void own_assign(OwnWalk *w, const MsStmt *s) {
    const uint32_t binding = w->facts->assign_binding[s->id];
    if (binding == MS_NONE || w->perm[binding] != PERM_MUTABLE) {
        w->supported = false; /* a field store or an assignment the checker rejects */
        return;
    }
    own_expr(w, s->u.assign.value, DEMAND_MOVE);
    own_release_pending(w);
    own_check_change(w, s->pos, binding, "reassign");
}

static void own_release_holder(BorrowSet *set, uint32_t holder) {
    for (uint32_t i = 0; i < set->len; i++) {
        set->items[i].holder = set->items[i].holder == holder ? MS_NONE : set->items[i].holder;
    }
}

/* `if name := optional`: the payload lives in the then-branch only. */
static bool own_if_condition(OwnWalk *w, const MsStmt *s, uint32_t *payload) {
    const MsPattern *pattern = s->u.branch.binding;
    *payload = MS_NONE;
    if (pattern == NULL) {
        own_expr(w, s->u.branch.cond, DEMAND_READ);
        return true;
    }
    const Scrutinee source = own_scrutinee(w, s->u.branch.cond);
    *payload = w->facts->pattern_binding[pattern->id];
    return pattern->kind == MS_P_NAME && !s->u.branch.is_mutable && *payload != MS_NONE &&
           own_payload(w, *payload, &source, pattern->pos);
}

static void own_if(OwnWalk *w, const MsStmt *s) {
    const uint32_t mark = w->ndeclared;
    uint32_t payload = MS_NONE;
    if (!own_if_condition(w, s, &payload)) {
        w->supported = false;
        return;
    }
    own_release_pending(w);
    BorrowSet entry = own_set_copy(&w->active);
    own_block(w, &s->u.branch.body);
    BorrowSet then_state = w->active;
    w->active = entry;
    if (payload != MS_NONE) {
        own_release_holder(&then_state, payload);
        own_release_holder(&w->active, payload);
        w->ndeclared = mark;
    }
    own_block(w, &s->u.branch.else_body);
    own_join(w, then_state);
}

static void own_while(OwnWalk *w, const MsStmt *s) {
    own_expr(w, s->u.loop.cond, DEMAND_READ);
    own_release_pending(w);
    BorrowSet entry = own_set_copy(&w->active);
    own_block(w, &s->u.loop.body);
    own_join(w, entry);
}

/* ---- match ---- */

/* One arm: its payloads, body and value share a scope. */
static void own_arm(OwnWalk *w, const MsArm *arm, const Scrutinee *source, Demand demand, bool returning) {
    const uint32_t mark = w->ndeclared;
    if (!own_arm_payloads(w, arm, source)) {
        w->supported = false;
        return;
    }
    own_block_value(w, &arm->body, arm->value, demand, returning);
    own_end_scope(w, mark);
}

/* Whether every arm yields a name: the match is then a reference to one of them, not a value. */
static bool own_arms_are_names(const OwnWalk *w, const MsExpr *e) {
    for (uint32_t i = 0; i < e->u.match.arms.len; i++) {
        const MsExpr *value = e->u.match.arms.ptr[i]->value;
        if (value == NULL || value->kind != MS_E_NAME || w->facts->res_kind[value->id] != MS_RES_BINDING) {
            return false;
        }
    }
    return true;
}

static void own_match(OwnWalk *w, const MsExpr *e, Demand demand, bool returning) {
    const bool copied = ms_classify(w->classifier, w->facts->expr_ty[e->id]) == MS_CLASS_COPY;
    const bool borrowed = !returning && demand != DEMAND_MOVE && !copied && own_arms_are_names(w, e);
    /* Arms that are not all references produce a value, so a place among them moves. */
    const Demand arm_demand = !borrowed && demand == DEMAND_READ ? DEMAND_MOVE : demand;
    const Scrutinee source = own_scrutinee(w, e->u.match.scrutinee);
    own_release_pending(w);
    BorrowSet entry = own_set_copy(&w->active);
    BorrowSet joined = {0};
    for (uint32_t i = 0; i < e->u.match.arms.len && w->supported; i++) {
        free(w->active.items);
        w->active = own_set_copy(&entry);
        own_arm(w, e->u.match.arms.ptr[i], &source, arm_demand, returning);
        own_join(w, joined);
        joined = w->active;
        w->active = (BorrowSet){0};
    }
    w->active = joined;
    own_join(w, entry);
}

static void own_statement(OwnWalk *w, const MsStmt *s) {
    switch ((MsStmtKind)s->kind) {
    case MS_S_BIND: own_bind(w, s); return;
    case MS_S_RETURN: own_return(w, s); return;
    case MS_S_IF: own_if(w, s); return;
    case MS_S_WHILE: own_while(w, s); return;
    case MS_S_BREAK:
    case MS_S_CONTINUE: return; /* the loop's join covers what the jump skips */
    case MS_S_ASSIGN: own_assign(w, s); return;
    case MS_S_CALL: own_expr(w, s->u.expr, DEMAND_READ); return;
    case MS_S_FOR: w->supported = false; return;
    }
}

/* ---- functions ---- */

static void own_declare_parameters(OwnWalk *w, const MsFunc *function, const uint32_t *by_node) {
    for (uint32_t i = 0; i < function->params.len; i++) {
        const uint32_t binding = by_node[function->params.ptr[i]->id];
        own_declare(w, binding, PERM_IMMUTABLE, true);
        w->param_index[binding] = i;
    }
}

static bool own_function(OwnWalk *w, const MsFunc *function, const uint32_t *by_node) {
    w->function = function;
    w->active.len = 0;
    w->npending = 0;
    w->pending_base = 0;
    w->ndeclared = 0;
    w->has_borrowed_return = w->has_owned_return = false;
    w->borrowed_params = 0;
    w->supported = true;
    own_declare_parameters(w, function, by_node);
    for (uint32_t i = 0; i < function->body.len && w->supported; i++) {
        own_statement(w, function->body.ptr[i]);
        own_release_pending(w);
    }
    if (w->supported && w->has_borrowed_return && w->has_owned_return) {
        own_error(w, w->owned_return,
                  ms_arena_fmt(&w->check->arena,
                               "this function returns a reference into its arguments at %u:%u but a new value here; "
                               "return `.clone()` of the part there, or build a new value on every path",
                               w->borrowed_return.line, w->borrowed_return.column));
    }
    return w->supported;
}

/* The binding each introducing node made, by node id. */
static uint32_t *own_bindings_by_node(const MsFacts *facts, MsArena *arena) {
    uint32_t *by_node = MS_NEW_N(arena, uint32_t, (size_t)facts->node_count + 1);
    memset(by_node, 0xff, ((size_t)facts->node_count + 1) * sizeof *by_node);
    for (uint32_t i = 0; i < facts->bindings.count; i++) {
        by_node[facts->bindings.decl_node[i]] = i;
    }
    return by_node;
}

static void own_allocate(OwnWalk *w, MsArena *arena) {
    const size_t n = (size_t)w->facts->bindings.count + 1;
    w->perm = MS_NEW_N(arena, uint8_t, n);
    w->class_of = MS_NEW_N(arena, uint8_t, n);
    w->origin = MS_NEW_N(arena, uint32_t, n);
    w->is_param = MS_NEW_N(arena, bool, n);
    w->deferred = MS_NEW_N(arena, bool, n);
    w->param_index = MS_NEW_N(arena, uint32_t, n);
    w->summaries = MS_NEW_N(arena, OwnSummary, (size_t)w->facts->node_count + 1);
    memset(w->summaries, 0, ((size_t)w->facts->node_count + 1) * sizeof *w->summaries);
}

/* Walks one function and records what its callers need to know. Returns whether the summary
 * changed. */
static bool own_summarize(OwnWalk *w, const MsDecl *d, const uint32_t *by_node) {
    OwnSummary *summary = &w->summaries[d->id];
    const bool handled = own_function(w, &d->u.fn, by_node) && d->u.fn.params.len < 32;
    const bool returns_borrow = handled && w->has_borrowed_return && !w->has_owned_return;
    const uint32_t mask = returns_borrow ? w->borrowed_params : 0;
    const bool changed = summary->usable != handled || summary->returns_borrow != returns_borrow ||
                         summary->borrowed_params != mask;
    *summary = (OwnSummary){.usable = handled, .returns_borrow = returns_borrow, .borrowed_params = mask};
    return changed;
}

/* Whether some node is a call of a function: only then does one function's walk depend on another's. */
static bool own_has_calls(const MsFacts *facts) {
    for (uint32_t i = 0; i <= facts->node_count; i++) {
        if (facts->call_callee[i] != MS_NONE && !facts->const_use[i]) {
            return true;
        }
    }
    return false;
}

/* Walks every function whose liveness the pass handles until the summaries stop changing, so a
 * caller sees what its callees return. Diagnostics wait for the final pass. */
static void own_summary_rounds(OwnWalk *w, const MsModuleRow *row, const uint32_t *by_node) {
    enum { MAX_ROUNDS = 12 };
    w->quiet = true;
    for (uint32_t round = 0; round < MAX_ROUNDS; round++) {
        bool changed = false;
        for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
            const MsDecl *d = row->syntax->decls[i];
            if (d->kind == MS_D_FN && w->summaries[d->id].usable) {
                changed = own_summarize(w, d, by_node) || changed;
            }
        }
        if (!changed) {
            w->quiet = false;
            return;
        }
    }
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) { /* no fixpoint: leave every function to Rust */
        w->summaries[row->syntax->decls[i]->id].usable = false;
    }
    w->quiet = false;
}

void ms_module_check_ownership(MsCheck *c, MsModId module) {
    MsModuleRow *row = &c->mods[module];
    MsFacts *facts = row->facts;
    if (facts == NULL || facts->body_checked == NULL) {
        return;
    }
    MsArena scratch = {0};
    MsLiveness live = ms_liveness_new(&scratch, facts);
    OwnWalk w = {.check = c, .module = module, .facts = facts, .live = &live,
                 .classifier = ms_classifier_new(c)};
    own_allocate(&w, &scratch);
    const uint32_t *by_node = own_bindings_by_node(facts, &scratch);
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        const bool claimed = d->kind == MS_D_FN && facts->body_checked[d->id];
        w.summaries[d->id].usable = claimed && ms_liveness_function(&live, facts, &d->u.fn);
    }
    if (own_has_calls(facts)) {
        own_summary_rounds(&w, row, by_node);
    }
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        if (d->kind == MS_D_FN && facts->body_checked[d->id]) {
            facts->body_checked[d->id] = w.summaries[d->id].usable && own_function(&w, &d->u.fn, by_node);
        }
    }
    free(w.active.items);
    free(w.declared);
    free(w.pending);
    ms_classifier_free(w.classifier);
    ms_arena_free(&scratch);
}
