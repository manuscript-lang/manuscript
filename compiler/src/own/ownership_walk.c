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
#include "ms/doc.h"
#include "ms/methods.h"
#include "ms/ownership.h"
#include "ms/rt_ops.h"
#include "ms/parse.h"

/* Who may change a binding (`Perm` in walk.rs). */
typedef enum Perm { PERM_MUTABLE, PERM_IMMUTABLE, PERM_BORROWED } Perm;

typedef struct Borrow {
    uint32_t holder;
    uint32_t origin; /* the binding borrowed from */
    MsPos pos;
    const char *why;
    const MsStep *path; /* the part of `origin` it reads, as field steps; the whole binding when empty */
    uint32_t path_len;
} Borrow;

typedef struct BorrowSet {
    Borrow *items;
    uint32_t len, cap;
} BorrowSet;

/* What a caller needs of a function: whether its non-copy result is a reference into some of its
 * parameters (bit i is parameter i), and whether the walk handles it at all. */
typedef struct OwnSummary {
    uint32_t borrowed_params;
    uint32_t consumed;       /* bit i: the function moves its plain parameter i, so callers hand it over */
    const MsPos *consumed_at; /* where, by parameter; NULL when nothing is consumed */
    bool usable;
    MsSite declined; /* where the walk gave up when it is not usable; no file when liveness did */
    bool returns_borrow;
} OwnSummary;

typedef struct OwnWalk {
    MsCheck *check;
    MsModId module;
    MsFacts *facts;
    MsClassifier *classifier;
    const MsLiveness *live;
    const MsFunc *function;
    uint8_t *perm;      /* by binding id: Perm */
    uint8_t *class_of;  /* by binding id: MsClass */
    uint32_t *origin;   /* by binding id: what a borrowed binding borrows from, else MS_NONE */
    bool *is_param;     /* by binding id */
    uint32_t *param_index; /* by binding id: the parameter's position, else MS_NONE */
    OwnSummary *summaries; /* by declaration node id */
    uint32_t floor;     /* inside a lambda: the bindings below it are captured, and must be copies */
    uint32_t borrowed_params;
    uint32_t consumed;  /* parameters this walk moved */
    MsPos consumed_at[32];
    uint8_t *param_mode; /* by binding id: 0 plain, 1 `var`, 2 `move` (parameters only) */
    uint32_t self_binding; /* the receiver of the method being walked, else MS_NONE */
    bool self_consuming;   /* the method is `move`: the receiver is its own, so it may change it */
    bool quiet;         /* a summary round: diagnostics are left to the final pass */
    bool *lent;          /* by binding id: a lambda parameter the caller lends; moving a non-copy one out is left to Rust */
    bool *closure_holds; /* by binding id: a closure that borrows non-copy locals; moving it would let it outlive them */
    bool lambda_escaping; /* the lambda being walked is returned, stored or handed to a `move` parameter */
    uint32_t captured[8]; /* the non-copy bindings the lambda being walked reads */
    uint32_t ncaptured;
    bool *deferred;     /* by binding id: a part of a parameter that the match or `if` would consume if it moved */
    BorrowSet active;   /* live borrows in push order; a released one has holder MS_NONE */
    uint32_t *pending;  /* holders whose borrows end with the statement */
    uint32_t npending, pending_cap;
    uint32_t pending_base; /* the pending holders below it belong to an enclosing statement */
    MsSym note_param;   /* while a move argument is walked: the callee's parameter that consumes it, else MS_NONE */
    MsPos note_at;
    MsPos borrowed_return, owned_return; /* the first return of each kind in the function */
    bool has_borrowed_return, has_owned_return;
    uint32_t hidden;    /* hidden `for` holders handed out so far */
    uint32_t *declared; /* bindings in scope, innermost last */
    uint32_t ndeclared, declared_cap;
    bool supported;
    MsSite declined;    /* where the walk first gave up on the function, for the refusal report */
    const uint32_t *by_node; /* the binding each introducing node made */
} OwnWalk;

/* Gives up on the function (it stays with the Rust ownership pass), noting the first place. */
#define OWN_DECLINE(w) own_decline((w), __FILE__, (uint32_t)__LINE__)
static void own_decline(OwnWalk *w, const char *file, uint32_t line) {
    if (w->supported) {
        w->declined = (MsSite){file, line};
    }
    w->supported = false;
}

typedef enum Demand { DEMAND_READ, DEMAND_MOVE } Demand;

static void own_match(OwnWalk *w, const MsExpr *e, Demand demand, bool returning);
static void own_call(OwnWalk *w, const MsExpr *e, Demand demand);
static void own_lambda(OwnWalk *w, const MsExpr *e, bool escaping);

/* Holders at or above this are not bindings: the hidden borrow a `for` loop keeps on its iterable. */
#define OWN_HIDDEN_HOLDER 0xF0000000u

static MsStr own_name(const OwnWalk *w, uint32_t binding) {
    if (binding >= OWN_HIDDEN_HOLDER) {
        return (MsStr){.ptr = "for", .len = 3};
    }
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
    if (w->class_of[binding] == MS_CLASS_RESOURCE) {
        w->facts->bindings.flags[binding] |= MS_BIND_RESOURCE;
    }
    w->origin[binding] = MS_NONE;
    w->is_param[binding] = parameter;
    w->param_mode[binding] = 0;
    w->param_index[binding] = MS_NONE;
    w->deferred[binding] = false;
    w->closure_holds[binding] = false;
    w->lent[binding] = false;
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
    const Borrow borrow = {.holder = binding, .origin = origin, .pos = pos, .why = why};
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

/* How to end a borrow that blocks a change: clone the iterable, the captured value or the initializer. */
static MsStr own_borrow_remedy(const OwnWalk *w, const Borrow *b, bool closure, MsStr holder) {
    if (b->holder >= OWN_HIDDEN_HOLDER) {
        return ms_arena_fmt(&w->check->arena, "iterate over a clone instead by appending `.clone()` to the loop's "
                                              "iterable expression");
    }
    if (closure) {
        return ms_arena_fmt(&w->check->arena,
                            "or build `%.*s` from a clone: bind `.clone()` of the captured value first and capture "
                            "that binding",
                            (int)holder.len, holder.ptr);
    }
    return ms_arena_fmt(&w->check->arena, "or give `%.*s` its own value by ending its initializer with `.clone()`",
                        (int)holder.len, holder.ptr);
}

/* A change (`what`: "move", "reassign" or "change") of `target` while some live borrow reads a part
 * of it that overlaps. `shown` is how the diagnostic names the place; a borrow held by `binding`
 * itself (the place's own root) does not count. */
static void own_check_change_place(OwnWalk *w, MsPos pos, uint32_t binding, MsPlace target, MsStr shown,
                                   const char *what) {
    for (uint32_t i = 0; i < w->active.len; i++) {
        const Borrow *b = &w->active.items[i];
        if (b->holder == MS_NONE || b->origin != target.root || b->holder == binding ||
            !ms_place_overlaps((MsPlace){b->origin, b->path, b->path_len}, target)) {
            continue;
        }
        const MsStr holder = own_name(w, b->holder);
        const bool closure = strcmp(b->why, "closure capture") == 0;
        const MsStr remedy = own_borrow_remedy(w, b, closure, holder);
        own_error(w, pos,
                  ms_arena_fmt(&w->check->arena,
                               "cannot %s `%.*s` while `%.*s` borrows it (%s, at %u:%u); finish using `%.*s` before "
                               "this, %.*s",
                               what, (int)shown.len, shown.ptr, (int)holder.len, holder.ptr, b->why, b->pos.line,
                               b->pos.column, (int)holder.len, holder.ptr, (int)remedy.len, remedy.ptr));
        return;
    }
}

/* A change of the whole of `binding`. */
static void own_check_change(OwnWalk *w, MsPos pos, uint32_t binding, const char *what) {
    own_check_change_place(w, pos, binding, ms_place_local(own_resolve(w, binding)), own_name(w, binding), what);
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

/* Why a call argument counts as a move when the callee, not the call, consumes it. */
static MsStr own_consumed_note(OwnWalk *w) {
    if (w->note_param == MS_NONE) {
        return (MsStr){.ptr = "", .len = 0};
    }
    const MsStr param = ms_name(w->check->names, w->note_param);
    const MsStr file = ms_name(w->check->names, w->check->mods[w->module].path);
    return ms_arena_fmt(&w->check->arena, "; the callee consumes its parameter `%.*s` at %.*s:%u:%u (clone it there to avoid the move)",
                        (int)param.len, param.ptr, (int)file.len, file.ptr, w->note_at.line, w->note_at.column);
}

static void own_error_used_again(OwnWalk *w, const MsExpr *e, uint32_t binding) {
    const MsStr name = own_name(w, binding);
    const uint32_t next = w->live->next[e->id];
    const MsPos next_pos = w->live->pos[next];
    const MsStr note = own_consumed_note(w);
    own_error(w, e->pos,
              ms_arena_fmt(&w->check->arena,
                           "`%.*s` is moved here but used again at %u:%u%.*s; a value has one owner, so move it only at "
                           "its last use, or pass `%.*s.clone()` if the original is still needed",
                           (int)name.len, name.ptr, next_pos.line, next_pos.column, (int)note.len, note.ptr,
                           (int)name.len, name.ptr));
}

static void own_error_var_parameter_move(OwnWalk *w, const MsExpr *e, uint32_t binding) {
    const MsStr name = own_name(w, binding);
    own_error(w, e->pos,
              ms_arena_fmt(&w->check->arena,
                           "cannot move `%.*s` out of the function: the caller keeps ownership of a var parameter; "
                           "return `%.*s.clone()` or change the value in place",
                           (int)name.len, name.ptr, (int)name.len, name.ptr));
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
    if (w->lent[binding]) {
        OWN_DECLINE(w); /* the function type borrows its argument: moving it out has its own message */
        return;
    }
    if (w->perm[binding] == PERM_BORROWED && w->deferred[binding]) {
        OWN_DECLINE(w); /* moving a part out would make the scrutinee consume its parameter */
        return;
    }
    if (w->class_of[binding] == MS_CLASS_RESOURCE && w->is_param[binding] && w->perm[binding] == PERM_MUTABLE) {
        OWN_DECLINE(w); /* a resource var parameter has its own message */
        return;
    }
    if (w->perm[binding] == PERM_BORROWED) {
        own_error_borrowed_move(w, e, binding);
    } else if (w->is_param[binding] && w->perm[binding] == PERM_MUTABLE) {
        own_error_var_parameter_move(w, e, binding);
    } else if (!own_is_last(w, e)) {
        own_error_used_again(w, e, binding);
    }
    if (w->perm[binding] != PERM_BORROWED) {
        own_check_change(w, e->pos, binding, "move");
    }
    if (w->is_param[binding]) {
        const uint32_t index = w->param_index[binding];
        if ((w->consumed & (1u << index)) == 0) {
            w->consumed_at[index] = e->pos;
        }
        w->consumed |= 1u << index;
    }
    w->facts->moved_out[e->id] = true;
    own_record(w, e, binding);
}

static void own_use_local(OwnWalk *w, const MsExpr *e, Demand demand) {
    if (w->facts->res_kind[e->id] != MS_RES_BINDING) {
        /* A module constant: a plain value is read; anything else is left to Rust. */
        w->supported = w->supported && ms_classify(w->classifier, w->facts->expr_ty[e->id]) == MS_CLASS_COPY;
        return;
    }
    const uint32_t binding = w->facts->res_ref[e->id];
    if (binding < w->floor && w->class_of[binding] != MS_CLASS_COPY) {
        // a closure reads a value with one owner in place while it lives; one that outlives the
        // statement would have to take it over, which is left to Rust
        if (w->lambda_escaping || demand == DEMAND_MOVE || w->ncaptured == 8) {
            OWN_DECLINE(w);
        } else {
            w->captured[w->ncaptured++] = own_resolve(w, binding);
        }
    }
    if (binding < w->floor && w->lambda_escaping && w->perm[binding] == PERM_MUTABLE) {
        OWN_DECLINE(w); /* an escaping closure copies a `var`: a later use of it is an error left to Rust */
    }
    if (demand == DEMAND_MOVE && w->closure_holds[binding]) {
        OWN_DECLINE(w); /* the closure would outlive the locals it borrows */
    }
    if (demand != DEMAND_MOVE || w->class_of[binding] == MS_CLASS_COPY) {
        own_record(w, e, binding);
        return;
    }
    own_move_out(w, e, binding);
}

/* Whether `e` makes a new value (a concatenation, a text, a record built here) rather than naming
 * or returning one that lives elsewhere. */
static bool own_is_constructor(const OwnWalk *w, const MsExpr *e);

static bool own_is_fresh(const OwnWalk *w, const MsExpr *e) {
    return e->kind == MS_E_BINARY || e->kind == MS_E_TEXT || (e->kind == MS_E_CALL && own_is_constructor(w, e));
}

/* A payload wrapped in `some` where an Optional is expected: a name wraps as it moves or returns,
 * and a fresh value owns what it wraps; a part of something (`r.name`) stays a view (`opt.view`),
 * which this pass does not decide yet. */
static void own_check_wrap(OwnWalk *w, const MsExpr *e) {
    const MsTy optional = w->facts->expr_ty[e->id];
    if (w->facts->some_wrap[e->id] && ms_classify(w->classifier, ms_ty_args(&w->check->tys, optional)[0]) != MS_CLASS_COPY &&
        !own_is_fresh(w, e) && !(e->kind == MS_E_NAME && w->facts->res_kind[e->id] == MS_RES_BINDING)) {
        OWN_DECLINE(w);
    }
}


static void own_construct(OwnWalk *w, const MsExpr *e);

static void own_expr(OwnWalk *w, const MsExpr *e, Demand demand) {
    own_check_wrap(w, e);
    if (w->facts->coerce_iface[e->id] != MS_TY_NONE && e->kind != MS_E_CALL) {
        OWN_DECLINE(w); /* a named value boxed into an interface: moved or copied, not followed yet */
        return;
    }
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
    case MS_E_MEMBER:
        /* A field reads its holder; moving one out of it is a partial move, not modelled yet. */
        if (demand == DEMAND_MOVE && ms_classify(w->classifier, w->facts->expr_ty[e->id]) != MS_CLASS_COPY) {
            OWN_DECLINE(w);
        }
        own_expr(w, e->u.member.left, DEMAND_READ);
        return;
    case MS_E_INDEX:
    case MS_E_APPLY: { /* `xs[i]` read as a type application: the checker admits it only as an index */
        MsExpr *list = NULL;
        MsExpr *index = NULL;
        if (!ms_expr_index(e, &list, &index)) {
            OWN_DECLINE(w);
            return;
        }
        // An element with one owner is read in place; handing it out (returned, bound, passed on) borrows from the list
        // or copies it, which is not followed yet.
        if (demand != DEMAND_READ && ms_classify(w->classifier, w->facts->expr_ty[e->id]) != MS_CLASS_COPY) {
            w->supported = false;
            return;
        }
        own_expr(w, list, DEMAND_READ);
        own_expr(w, index, DEMAND_READ);
        return;
    }
    case MS_E_LIST: /* each entry moves into the list */
        for (uint32_t i = 0; i < e->u.list.len; i++) {
            own_expr(w, e->u.list.ptr[i], DEMAND_MOVE);
        }
        return;
    case MS_E_MAP: /* each key and value moves into the map */
        for (uint32_t i = 0; i < e->u.map.len; i++) {
            own_expr(w, e->u.map.ptr[i].key, DEMAND_MOVE);
            own_expr(w, e->u.map.ptr[i].value, DEMAND_MOVE);
        }
        return;
    case MS_E_PROBE: OWN_DECLINE(w); return; /* not modeled */
    case MS_E_LAMBDA: {
        const uint32_t start = w->ncaptured;
        own_lambda(w, e, demand == DEMAND_MOVE);
        w->ncaptured = start;
        return;
    }
    case MS_E_CALL:
        if (ms_call_builds_case(w->facts, e)) {
            own_construct(w, e); /* each payload moves into the value, a plain one is copied */
            return;
        }
        own_call(w, e, demand);
        return;
    case MS_E_MATCH: own_match(w, e, demand, false); return;
    }
}

/* ---- calls ---- */

/* The summary of a function another module declares, which that module's own walk recorded in its
 * facts (that module is checked and walked now if it has not been): its parameters borrow unless
 * declared `var` or `move`. A native (extern or built-in) function returns a new value. A function
 * that moves a parameter, or whose result borrows from one, is left alone: its summary would name
 * positions in another file. */
static const OwnSummary *own_foreign_callee(const OwnWalk *w, const MsExpr *e, MsSymId sym, const MsDecl *decl) {
    static const OwnSummary foreign = {.usable = true};
    if (w->check->syms.native[sym] != MS_NATIVE_SOURCE ||
        ms_classify(w->classifier, w->facts->expr_ty[e->id]) == MS_CLASS_COPY) {
        return &foreign;
    }
    MsCheck *c = w->check;
    const MsModId home = c->syms.module[sym];
    MsFacts *facts = c->mods[home].facts;
    if (facts == NULL) {
        return NULL;
    }
    if (facts->body_checked == NULL) {
        ms_module_check_bodies_with(c, home, c->methods);
        ms_module_check_ownership(c, home);
    }
    if (facts->body_checked != NULL && facts->ownership_done && facts->body_checked[decl->id]) {
        // Walked by that module: it moves no parameter and its result borrows from none.
        return facts->param_consumed[decl->id] == 0 && !facts->ret_borrowed[decl->id] ? &foreign : NULL;
    }
    // Not walked: nothing is borrowed or moved when no parameter can be (every one copies).
    const MsTyTable *tys = &c->tys;
    const MsTy sig = c->syms.ty[sym];
    for (uint32_t i = 0; i < tys->nparams[sig]; i++) {
        if (ms_classify(w->classifier, ms_ty_params(tys, sig)[i].ty) != MS_CLASS_COPY) {
            return NULL;
        }
    }
    return &foreign;
}

/* Whether a callee is written as a name, alone or with type arguments: `f` or `f[Int]`. */
static bool own_is_plain_name(const MsExpr *callee) {
    return callee->kind == MS_E_NAME || (callee->kind == MS_E_APPLY && callee->u.apply.left->kind == MS_E_NAME);
}

/* The summary of the function a call names, or NULL when the walk cannot reason about it. */
static const OwnSummary *own_callee(const OwnWalk *w, const MsExpr *e) {
    const uint32_t sym = w->facts->call_callee[e->id];
    const MsDecl *decl = sym == MS_NONE ? NULL : w->check->syms.decl[sym];
    // A call to the function being walked reads its summary from the previous round; the rounds
    // iterate from the optimistic start until it settles.
    if (decl == NULL || decl->kind != MS_D_FN) {
        return NULL;
    }
    if (w->check->syms.module[sym] != w->module || decl->u.fn.external) { // an extern has no body to summarize
        return own_foreign_callee(w, e, sym, decl);
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

/* Whether `e` mentions the local `binding` anywhere; an expression kind the walk does not follow counts as
 * a mention, so the caller stays on the safe side. */
static bool own_mentions(const OwnWalk *w, const MsExpr *e, uint32_t binding) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID: return false;
    case MS_E_NAME: return w->facts->res_kind[e->id] == MS_RES_BINDING && w->facts->res_ref[e->id] == binding;
    case MS_E_UNARY: return own_mentions(w, e->u.bin.left, binding);
    case MS_E_BINARY: return own_mentions(w, e->u.bin.left, binding) || own_mentions(w, e->u.bin.right, binding);
    case MS_E_TEXT:
        for (uint32_t i = 0; i < e->u.text.len; i++) {
            if (e->u.text.ptr[i].expr != NULL && own_mentions(w, e->u.text.ptr[i].expr, binding)) {
                return true;
            }
        }
        return false;
    case MS_E_CALL:
        for (uint32_t i = 0; i < e->u.call.args.len; i++) {
            if (own_mentions(w, e->u.call.args.ptr[i].value, binding)) {
                return true;
            }
        }
        return false;
    case MS_E_INDEX: return own_mentions(w, e->u.bin.left, binding) || own_mentions(w, e->u.bin.right, binding);
    case MS_E_APPLY: {
        MsExpr *list = NULL;
        MsExpr *index = NULL;
        return !ms_expr_index(e, &list, &index) || own_mentions(w, list, binding) || own_mentions(w, index, binding);
    }
    case MS_E_MEMBER:
    case MS_E_PROBE:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_LAMBDA:
    case MS_E_MATCH: break;
    }
    return true;
}

/* The local a `var` or `move` argument names, or MS_NONE. */
static uint32_t own_argument_local(const OwnWalk *w, const MsExpr *arg) {
    const bool local = arg->kind == MS_E_NAME && w->facts->res_kind[arg->id] == MS_RES_BINDING;
    return local ? w->facts->res_ref[arg->id] : MS_NONE;
}

/* A call that hands a variable over (`var`, `move`, or a plain parameter the callee consumes) may not
 * pass anything that reads it in another argument: the overlap rule of Rust, left to Rust here. */
static bool own_arguments_overlap(const OwnWalk *w, const MsExpr *call, uint32_t held) {
    for (uint32_t i = 0; i < call->u.call.args.len; i++) {
        const MsExpr *arg = call->u.call.args.ptr[i].value;
        if (((held >> i) & 1u) != 0) {
            const uint32_t binding = own_argument_local(w, arg);
            if (binding == MS_NONE || w->class_of[binding] == MS_CLASS_COPY) {
                continue; /* a computed value has no place; a copied scalar is read by value */
            }
            for (uint32_t j = 0; j < call->u.call.args.len; j++) {
                const MsExpr *other = call->u.call.args.ptr[j].value;
                if (j != i && own_mentions(w, other, binding)) {
                    return true;
                }
            }
        }
    }
    return false;
}

/* A resource parameter handed to a `move` position must itself be declared `move`: a resource has
 * one owner, so who owns it is declared. */
static void own_require_declared_move(OwnWalk *w, const MsExpr *arg) {
    const uint32_t binding = own_argument_local(w, arg);
    if (binding == MS_NONE || !w->is_param[binding] || w->perm[binding] != PERM_IMMUTABLE ||
        w->param_mode[binding] == 2 || w->class_of[binding] != MS_CLASS_RESOURCE) {
        return;
    }
    const MsStr name = own_name(w, binding);
    own_error(w, arg->pos,
              ms_arena_fmt(&w->check->arena,
                           "cannot pass `%.*s` as a `move` argument: it is not declared `move`, so the caller keeps it; "
                           "write `move %.*s: <Type>` in the signature",
                           (int)name.len, name.ptr, (int)name.len, name.ptr));
}

/* A change in place of `place` (a part of local `binding`, shown as `text`): the binding's permission
 * must allow it, then no borrow may read the part. */
static void own_mutate_place(OwnWalk *w, MsPos pos, uint32_t binding, MsPlace place, MsStr text) {
    const MsStr name = own_name(w, binding);
    const uint8_t perm = w->perm[binding];
    if (perm == PERM_BORROWED) {
        const uint32_t origin = w->origin[binding];
        const MsStr from = origin == MS_NONE ? (MsStr){.ptr = "another value", .len = 13} : own_name(w, origin);
        own_error(w, pos,
                  ms_arena_fmt(&w->check->arena,
                               "cannot change `%.*s`: `%.*s` only borrows from `%.*s`; clone it first with `var %.*s = "
                               "%.*s.clone()`",
                               (int)text.len, text.ptr, (int)name.len, name.ptr, (int)from.len, from.ptr, (int)name.len,
                               name.ptr, (int)name.len, name.ptr));
    } else if (perm == PERM_IMMUTABLE && binding == w->self_binding) {
        if (!w->self_consuming) {
            own_error(w, pos,
                      ms_arena_fmt(&w->check->arena,
                                   "cannot change `%.*s`: this method does not change its receiver; write `fn var` in "
                                   "its declaration to allow that",
                                   (int)text.len, text.ptr));
        }
    } else if (perm == PERM_IMMUTABLE && w->is_param[binding] && w->param_mode[binding] != 2) {
        own_error(w, pos,
                  ms_arena_fmt(&w->check->arena,
                               "cannot change `%.*s`: parameter `%.*s` is not declared var; write `var %.*s: <Type>` in "
                               "the signature",
                               (int)text.len, text.ptr, (int)name.len, name.ptr, (int)name.len, name.ptr));
    } else if (perm == PERM_IMMUTABLE && !w->is_param[binding]) {
        own_error(w, pos,
                  ms_arena_fmt(&w->check->arena,
                               "cannot change `%.*s`: `%.*s` is an immutable binding, immutable including its "
                               "contents; declare it `var %.*s` to change it",
                               (int)text.len, text.ptr, (int)name.len, name.ptr, (int)name.len, name.ptr));
    }
    const MsPlace resolved = {own_resolve(w, binding), place.path, place.len};
    own_check_change_place(w, pos, binding, resolved, text, "change");
}

/* A `var` argument names a variable that may change: its permission, then any borrow that reads it. */
static void own_mutate(OwnWalk *w, const MsExpr *arg, uint32_t binding) {
    own_mutate_place(w, arg->pos, binding, ms_place_local(binding), own_name(w, binding));
    own_record(w, arg, binding);
}

/* A `var` argument is a variable changed in place; a `move` one, or a plain one the callee
 * consumes, is handed over; the rest are read. */
static void own_arguments(OwnWalk *w, const MsExpr *call, const OwnSummary *callee) {
    const uint32_t sym = w->facts->call_callee[call->id];
    const MsFunc *function = &w->check->syms.decl[sym]->u.fn;
    uint32_t handed = 0;
    for (uint32_t i = 0; i < call->u.call.args.len; i++) {
        const MsParam *param = function->params.ptr[i];
        handed |= (param->is_mutable || param->moving || (callee->consumed >> i & 1u) != 0 ? 1u : 0u) << i;
    }
    if (own_arguments_overlap(w, call, handed)) {
        OWN_DECLINE(w);
        return;
    }
    for (uint32_t i = 0; i < call->u.call.args.len; i++) {
        const MsExpr *arg = call->u.call.args.ptr[i].value;
        const MsParam *param = function->params.ptr[i];
        if (param->is_mutable) {
            const uint32_t binding = own_argument_local(w, arg);
            if (binding != MS_NONE) {
                own_mutate(w, arg, binding);
                continue;
            }
            MsExpr *part_of = NULL;
            MsExpr *part_at = NULL;
            if (ms_expr_index(arg, &part_of, &part_at) || arg->kind == MS_E_MEMBER) {
                OWN_DECLINE(w); /* a part of a variable is a place too: changing it is left to Rust */
                return;
            }
            own_error(w, arg->pos,
                      ms_arena_fmt(&w->check->arena, "%s",
                                   "a var argument must be a variable or a field of one, not a computed value; bind "
                                   "the value to a var first"));
            own_expr(w, arg, DEMAND_READ);
        } else if (param->moving || (callee->consumed >> i & 1u) != 0) {
            own_require_declared_move(w, arg);
            w->note_param = callee->consumed_at != NULL && (callee->consumed >> i & 1u) != 0 ? param->name : MS_NONE;
            w->note_at = w->note_param == MS_NONE ? w->note_at : callee->consumed_at[i];
            own_expr(w, arg, DEMAND_MOVE);
            w->note_param = MS_NONE;
        } else {
            own_expr(w, arg, DEMAND_READ);
        }
    }
}

/* An operation of a primitive receiver: it borrows the receiver and every argument, and its result is
 * a scalar the checker admitted, so nothing it returns holds a borrow. */
static void own_intrinsic_call(OwnWalk *w, const MsExpr *e) {
    own_expr(w, e->u.call.callee->u.member.left, DEMAND_READ);
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        own_expr(w, e->u.call.args.ptr[i].value, DEMAND_READ);
    }
}

/* The method that implements `row`, found in the module that declares it. */
static const MsMethod *own_method_of_row(const OwnWalk *w, uint32_t row) {
    const MsMethods *methods = w->facts->methods;
    const MsModule *syntax = w->check->mods[methods->module[row]].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        for (uint32_t k = 0; d->kind == MS_D_IMPL && k < d->u.impl.methods.len; k++) {
            if (&d->u.impl.methods.ptr[k]->func == methods->decl[row]) {
                return d->u.impl.methods.ptr[k];
            }
        }
    }
    return NULL;
}

/* The method `row` and the facts of its module, once that module's walk has run; NULL for a method of this
 * module (walked after the functions) or one the walk did not take. */
static const MsMethod *own_walked_method(const OwnWalk *w, uint32_t row, const MsFacts **facts_out) {
    const MsMethods *methods = w->facts->methods;
    MsCheck *c = w->check;
    const MsModId home = methods->module[row];
    MsFacts *facts = c->mods[home].facts;
    if (home == w->module || facts == NULL || methods->decl[row] == NULL) {
        return NULL;
    }
    if (facts->body_checked == NULL) {
        ms_module_check_bodies_with(c, home, c->methods);
        ms_module_check_ownership(c, home);
    }
    const MsMethod *method = own_method_of_row(w, row);
    if (method == NULL || method->func.external || method->func.body.len == 0 || facts->body_checked == NULL || !facts->ownership_done || !facts->body_checked[method->id]) {
        return NULL;
    }
    *facts_out = facts;
    return method;
}

/* Whether the method `row` is a native (`: ...`, no body to walk) whose result is a value of its own.
 * A native takes over only the parameters its signature marks `move`, and its result points into the
 * receiver only where the declaration says so (`// ms: borrows`: `xs.get(i)`, `m.keys()`). */
static bool own_is_owning_native(const OwnWalk *w, uint32_t row) {
    const MsMethods *methods = w->facts->methods;
    const MsMethod *method = methods->native[row] == MS_NATIVE_SOURCE ? own_method_of_row(w, row) : NULL;
    if (method == NULL || method->func.external || method->func.body.len != 0) {
        return false;
    }
    return !ms_doc_has_marker(w->check->mods[methods->module[row]].text, method->pos.offset, "borrows");
}

/* Whether method `row` has no body to walk: a runtime operation or an intrinsic declared with `...`. */
static bool own_method_unwalked(const OwnWalk *w, uint32_t row) {
    const MsMethods *methods = w->facts->methods;
    const MsFunc *declared = methods->decl[row];
    return methods->native[row] != MS_NATIVE_SOURCE || (declared != NULL && (declared->external || declared->body.len == 0));
}

/* The arguments of a method call, by what the method does with each parameter: a `var` one changes a
 * variable, a `move` one (or a plain one the method's own walk found it consumes) is handed over, the
 * rest are read. `consumed` has the receiver at bit 0. */
static void own_method_arguments(OwnWalk *w, const MsExpr *e, uint32_t row, uint32_t consumed) {
    const MsTyTable *tys = &w->check->tys;
    const MsTy sig = w->facts->methods->ty[row];
    const MsTyParam *params = ms_ty_params(tys, sig);
    uint32_t handed = 0;
    for (uint32_t i = 0; i < e->u.call.args.len && i < tys->nparams[sig]; i++) {
        const bool takes = (params[i].flags & (MS_PARAM_VAR | MS_PARAM_MOVE)) != 0 || (consumed >> (i + 1) & 1u) != 0;
        handed |= (takes ? 1u : 0u) << i;
    }
    if (own_arguments_overlap(w, e, handed)) {
        OWN_DECLINE(w);
        return;
    }
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        const MsExpr *arg = e->u.call.args.ptr[i].value;
        if (i < tys->nparams[sig] && (params[i].flags & MS_PARAM_VAR) != 0) {
            const uint32_t binding = own_argument_local(w, arg);
            if (binding == MS_NONE) {
                OWN_DECLINE(w); /* a place that is not a variable has its own message */
                return;
            }
            own_mutate(w, arg, binding);
        } else if ((handed >> i & 1u) != 0) {
            own_require_declared_move(w, arg);
            own_expr(w, arg, DEMAND_MOVE);
        } else {
            own_expr(w, arg, DEMAND_READ);
        }
    }
}

/* Whether an argument of the call mentions the variable `held` (a `var`) that the call reads in place
 * while the arguments run: an argument may change it, which the overlap rule of Rust reports. */
static bool own_args_touch(const OwnWalk *w, const MsExpr *call, uint32_t held) {
    if (held == MS_NONE || (w->facts->bindings.flags[held] & MS_BIND_MUTABLE) == 0) {
        return false;
    }
    for (uint32_t i = 0; i < call->u.call.args.len; i++) {
        if (own_mentions(w, call->u.call.args.ptr[i].value, held)) {
            return true;
        }
    }
    return false;
}

/* A method of a type, called on a local or a temporary: a method that changes its receiver changes
 * the local in place, and no argument may read it; the others borrow it. A result that is not a plain
 * value may be a reference into the receiver (`list.get(i)`), which this walk does not follow: the
 * function is left to the Rust checker unless the method is known to return a value of its own. */
static void own_method_call(OwnWalk *w, const MsExpr *e) {
    const MsExpr *receiver = e->u.call.callee->u.member.left;
    const uint32_t row = w->facts->call_method[e->id];
    const MsTy result = w->facts->expr_ty[e->id];
    const MsTyTable *tys = &w->check->tys;
    const MsTy sig = w->facts->methods->ty[row];
    const MsTyParam *params = ms_ty_params(tys, sig);
    bool plain = ms_classify(w->classifier, result) == MS_CLASS_COPY;
    for (uint32_t i = 0; i < tys->nparams[sig]; i++) {
        plain = plain && ms_classify(w->classifier, params[i].ty) == MS_CLASS_COPY;
    }
    // What the method moves of its parameters, and whether its result is a reference into them, is known
    // once its module's walk has run; a call over plain values needs neither.
    uint32_t consumed = 0;
    if (!plain && own_method_unwalked(w, row) && ms_classify(w->classifier, result) == MS_CLASS_COPY) {
        consumed = 0; // nothing to walk: what such a method takes is what its signature says (`move`, `var`), and a plain result borrows nothing
    } else if (!plain && own_is_owning_native(w, row)) {
        // Nothing to learn from a walk either: the result is the native's own value (no `// ms: borrows`).
    } else if (!plain) {
        const MsFacts *home = NULL;
        const MsMethod *walked = w->facts->methods->native[row] == MS_NATIVE_SOURCE ? own_walked_method(w, row, &home) : NULL;
        if (walked == NULL || home->ret_borrowed[walked->id]) {
            OWN_DECLINE(w);
            return;
        }
        consumed = home->param_consumed[walked->id];
    }
    const uint8_t access = w->facts->methods->access[row];
    const bool mutating = (access & MS_METHOD_MUTATING) != 0;
    const uint32_t binding = own_argument_local(w, receiver);
    if ((access & MS_METHOD_CONSUMING) != 0) {
        // The method takes its receiver: a local is moved out, a temporary is dropped by the method.
        if (mutating) {
            OWN_DECLINE(w);
            return;
        }
        own_expr(w, receiver, DEMAND_MOVE);
    } else if (mutating && receiver->kind != MS_E_CALL) { /* a temporary result is changed unseen: nothing else names it */
        bool overlaps = binding == MS_NONE;
        for (uint32_t i = 0; i < e->u.call.args.len && !overlaps; i++) {
            overlaps = own_mentions(w, e->u.call.args.ptr[i].value, binding);
        }
        if (overlaps) {
            OWN_DECLINE(w);
            return;
        }
        own_mutate(w, receiver, binding);
    } else if (own_args_touch(w, e, binding)) {
        OWN_DECLINE(w); /* an argument may change the receiver read in place */
        return;
    } else {
        own_expr(w, receiver, DEMAND_READ);
    }
    own_method_arguments(w, e, row, consumed);
}

static MsPlace own_target_place(OwnWalk *w, const MsExpr *target, uint32_t root, MsStr *text);

/* The local a receiver names, directly or as the root of a field path (`self.sink`). */
static uint32_t own_receiver_root(const OwnWalk *w, const MsExpr *receiver) {
    while (receiver->kind == MS_E_MEMBER) {
        receiver = receiver->u.member.left;
    }
    return own_argument_local(w, receiver);
}

/* The declaration of the operation a call through the interface `contract` names. */
static const MsMethod *own_operation(const OwnWalk *w, MsTy contract, MsSym name) {
    const MsTyTable *tys = &w->check->tys;
    if (tys->def[contract] == 0) {
        return NULL;
    }
    const MsOperations *ops = ms_interface_operations(w->check->methods, tys->def[contract] - 1);
    for (uint32_t i = 0; ops != NULL && i < ops->count; i++) {
        if (ops->items[i].name == name && ops->items[i].nvars == 0) {
            return ops->items[i].decl;
        }
    }
    return NULL;
}

/* An operation of an interface value, dispatched at run time. What the operation declares is what
 * it does: a `var` one changes its receiver (a local, or a part of one, changed in place), a `move`
 * parameter takes its argument, the rest are read; the result is a value of its own. A receiver that
 * is not rooted in a local, an operation that consumes it or a `var` parameter is left to the Rust
 * checker. */
static void own_interface_call(OwnWalk *w, const MsExpr *e) {
    const MsExpr *receiver = e->u.call.callee->u.member.left;
    const MsMethod *op = own_operation(w, w->facts->call_receiver[e->id], e->u.call.callee->u.member.name);
    const uint32_t root = own_receiver_root(w, receiver);
    if (op == NULL || root == MS_NONE || op->consuming || e->u.call.args.len > op->func.params.len) {
        OWN_DECLINE(w);
        return;
    }
    // A result that is not a plain value may be a reference into the receiver or a borrowed argument
    // (`slice`); an operation that changes its receiver and takes its arguments by value hands back a value of its own.
    bool owned = ms_classify(w->classifier, w->facts->expr_ty[e->id]) == MS_CLASS_COPY || op->mutating;
    uint32_t handed = 0;
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        const MsParam *param = op->func.params.ptr[i];
        owned = owned && (param->moving || ms_classify(w->classifier, w->facts->expr_ty[e->u.call.args.ptr[i].value->id]) == MS_CLASS_COPY);
        if (param->is_mutable) {
            OWN_DECLINE(w);
            return;
        }
        handed |= (param->moving ? 1u : 0u) << i;
    }
    if (!owned || own_arguments_overlap(w, e, handed)) {
        OWN_DECLINE(w);
        return;
    }
    if (op->mutating) {
        MsStr text;
        const MsPlace place = own_target_place(w, receiver, root, &text);
        own_mutate_place(w, receiver->pos, root, place, text);
    } else if (own_args_touch(w, e, root)) {
        OWN_DECLINE(w);
        return;
    } else {
        own_expr(w, receiver, DEMAND_READ);
    }
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        const MsExpr *arg = e->u.call.args.ptr[i].value;
        if ((handed >> i & 1u) != 0) {
            own_require_declared_move(w, arg);
        }
        own_expr(w, arg, (handed >> i & 1u) != 0 ? DEMAND_MOVE : DEMAND_READ);
    }
}

/* `Type(a, b)`: a record this module or another declares, built from its arguments. With written
 * type arguments (`Box[Int](1)`, `List[Int]()`, `Map[String, Int]()`) it is the same construction. */
static bool own_is_constructor(const OwnWalk *w, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    if (callee->kind == MS_E_APPLY && callee->u.apply.left->kind == MS_E_NAME) {
        const uint32_t applied = w->facts->call_callee[e->id];
        return applied != MS_NONE && w->check->syms.kind[applied] == MS_SYM_TYPE;
    }
    if (callee->kind != MS_E_NAME) {
        return false;
    }
    // `ok(v)` and `error(e)` build the Result around their argument, as a record is built.
    if (w->facts->res_kind[callee->id] == MS_RES_CASE) {
        return true;
    }
    const uint32_t sym = w->facts->call_callee[e->id];
    const MsDecl *decl = sym == MS_NONE ? NULL : w->check->syms.decl[sym];
    return decl != NULL && decl->kind == MS_D_TYPE;
}

/* Every argument moves into the new record (a copy for a plain value); the record holds no borrow. */
static void own_construct(OwnWalk *w, const MsExpr *e) {
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
        own_expr(w, e->u.call.args.ptr[i].value, DEMAND_MOVE);
    }
}

/* Whether the argument is a place (a name, a field or an element): a borrow of it needs no owner. */
static bool own_is_place_argument(const OwnWalk *w, const MsExpr *arg) {
    return (arg->kind == MS_E_NAME && w->facts->res_kind[arg->id] == MS_RES_BINDING) || arg->kind == MS_E_MEMBER ||
           arg->kind == MS_E_INDEX;
}

/* A borrow-returning call over a temporary: the caller owns the result. When the callee hands back
 * the whole of one temporary argument the caller keeps that temporary; otherwise it copies the
 * result before the temporary is dropped. */
static void own_record_owned_borrow(OwnWalk *w, const MsExpr *e, const OwnSummary *callee) {
    w->facts->call_owned_borrow[e->id] = MS_OWNED_CLONE;
    const uint32_t mask = callee->borrowed_params;
    if (mask == 0 || (mask & (mask - 1)) != 0) {
        return;
    }
    uint32_t param = 0;
    while ((mask >> param & 1u) == 0) {
        param++;
    }
    if (param < e->u.call.args.len && !own_is_place_argument(w, e->u.call.args.ptr[param].value)) {
        w->facts->call_owned_borrow[e->id] = MS_OWNED_WHOLE;
        w->facts->call_owned_param[e->id] = param;
    }
}

/* Whether the call passes every parameter of the function it names, or leaves out only ones with a
 * default (the arguments are positional here: reordered calls were declined). */
static bool own_arguments_fit(const OwnWalk *w, const MsExpr *e) {
    const MsFunc *fn = &w->check->syms.decl[w->facts->call_callee[e->id]]->u.fn;
    if (e->u.call.args.len > fn->params.len) {
        return false;
    }
    for (uint32_t i = e->u.call.args.len; i < fn->params.len; i++) {
        if (fn->params.ptr[i]->def == NULL) {
            return false;
        }
    }
    return true;
}

/* A call of a function this module declares: each argument is read, since a parameter that is
 * not `var` or `move` only borrows. A reference result may not be kept where it would own. */
static void own_call(OwnWalk *w, const MsExpr *e, Demand demand) {
    const MsExpr *callee_expr = e->u.call.callee;
    if ((w->facts->call_reordered[e->id] && !own_is_constructor(w, e)) || ms_is_index_store(w->check->names, e)) { /* a construction reads its arguments in source order */
        OWN_DECLINE(w); /* the arguments are paired with parameters by index below; a store has its own order */
        return;
    }
    if (callee_expr->kind == MS_E_NAME && w->facts->res_kind[callee_expr->id] == MS_RES_BINDING) {
        if (own_args_touch(w, e, w->facts->res_ref[callee_expr->id])) {
            OWN_DECLINE(w); /* an argument may change the function value being called */
            return;
        }
        own_expr(w, callee_expr, DEMAND_READ); /* a call through a function-typed local reads it */
        const MsTy fn = w->facts->expr_ty[callee_expr->id];
        for (uint32_t i = 0; i < e->u.call.args.len; i++) {
            const bool moves = (ms_ty_params(&w->check->tys, fn)[i].flags & MS_PARAM_MOVE) != 0;
            if (moves) {
                own_require_declared_move(w, e->u.call.args.ptr[i].value);
            }
            own_expr(w, e->u.call.args.ptr[i].value, moves ? DEMAND_MOVE : DEMAND_READ);
        }
        return;
    }
    if (e->u.call.callee->kind == MS_E_MEMBER && w->facts->call_interface[e->id] != MS_TY_NONE) {
        if (ms_ty_kind(&w->check->tys, w->facts->call_receiver[e->id]) == MS_K_CONTRACT) {
            own_interface_call(w, e);
        } else {
            own_intrinsic_call(w, e);
        }
        return;
    }
    if (e->u.call.callee->kind == MS_E_MEMBER && w->facts->call_method[e->id] != MS_NONE && w->facts->methods != NULL) {
        own_method_call(w, e);
        return;
    }
    if (own_is_constructor(w, e)) {
        own_construct(w, e);
        return;
    }
    const OwnSummary *callee = own_callee(w, e);
    if (callee == NULL || !own_is_plain_name(e->u.call.callee) || !own_arguments_fit(w, e)) {
        OWN_DECLINE(w);
        return;
    }
    own_arguments(w, e, callee);
    const bool copied = ms_classify(w->classifier, w->facts->expr_ty[e->id]) == MS_CLASS_COPY;
    uint32_t origins[4];
    uint32_t count = 0;
    if (!callee->returns_borrow || copied) {
        return;
    }
    if (!own_call_origins(w, e, origins, &count)) {
        own_record_owned_borrow(w, e, callee);
    } else if (demand == DEMAND_MOVE) {
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

typedef struct Scrutinee {
    bool owned;
    uint32_t origin;
    bool deferred;
} Scrutinee;

/* A call of a native whose result points into its receiver local (`s.chars()`): what it yields is the
 * receiver's, so the receiver stays unchanged while the result is in use. */
static Scrutinee own_borrowed_call(OwnWalk *w, const MsExpr *e) {
    const MsExpr *receiver = e->u.call.callee->u.member.left;
    own_expr(w, e, DEMAND_READ);
    if (receiver->kind != MS_E_NAME) { // a temporary: it lives to the end of the statement and nothing else can change it
        return (Scrutinee){true, MS_NONE, false};
    }
    return (Scrutinee){false, own_resolve(w, w->facts->res_ref[receiver->id]), false};
}

/* `x := f(a)` where `f` returns a reference into `a`: the binding borrows it like a name. */
static bool own_bind_borrowed_call(OwnWalk *w, const MsStmt *s, uint32_t binding) {
    const MsExpr *value = s->u.bind.value;
    if (value->kind == MS_E_CALL && w->facts->call_borrows[value->id]) {
        const Scrutinee source = own_borrowed_call(w, value);
        if (source.owned) {
            OWN_DECLINE(w); // a binding of a part of a temporary: Rust's report for it is not followed
            return true;
        }
        own_declare_borrow(w, binding, source.origin, s->u.bind.pattern->pos, "binding of a part of it");
        w->facts->bindings.flags[binding] |= MS_BIND_BORROWS;
        return true;
    }
    const OwnSummary *callee = value->kind == MS_E_CALL ? own_callee(w, value) : NULL;
    uint32_t origins[4];
    uint32_t count = 0;
    if (callee == NULL || !callee->returns_borrow || w->class_of[binding] == MS_CLASS_COPY ||
        !own_call_origins(w, value, origins, &count)) {
        return false;
    }
    if (s->u.bind.is_mutable || count != 1) {
        OWN_DECLINE(w); /* an exclusive borrow, or one that holds several places */
        return true;
    }
    own_expr(w, value, DEMAND_READ);
    own_declare_borrow(w, binding, origins[0], s->u.bind.pattern->pos, "binding of a part of it");
    w->facts->bindings.flags[binding] |= MS_BIND_BORROWS;
    return true;
}

/* `name := fn ...`: the closure lives as long as the name, so what it reads in place stays borrowed
 * until the name's last use. */
static void own_bind_lambda(OwnWalk *w, const MsStmt *s, uint32_t binding) {
    const MsExpr *lambda = s->u.bind.value;
    const uint32_t start = w->ncaptured;
    own_lambda(w, lambda, false);
    for (uint32_t i = start; i < w->ncaptured && w->supported; i++) {
        if (w->captured[i] >= w->facts->lambda_first[lambda->id]) {
            continue; /* a local of an enclosing closure's body, not of this one's surroundings */
        }
        const Borrow borrow = {.holder = binding, .origin = w->captured[i], .pos = lambda->pos, .why = "closure capture"};
        own_push_borrow(w, &borrow);
        w->closure_holds[binding] = true;
    }
    w->ncaptured = start;
}

static bool own_arms_are_names(const OwnWalk *w, const MsExpr *e);

static void own_bind(OwnWalk *w, const MsStmt *s) {
    const uint32_t binding = w->facts->pattern_binding[s->u.bind.pattern->id];
    own_declare(w, binding, s->u.bind.is_mutable ? PERM_MUTABLE : PERM_IMMUTABLE, false);
    if (own_bind_borrowed_call(w, s, binding)) {
        return;
    }
    const MsExpr *value = s->u.bind.value;
    if (value->kind == MS_E_MATCH && w->class_of[binding] != MS_CLASS_COPY && own_arms_are_names(w, value)) {
        OWN_DECLINE(w); /* a binding of a match over names borrows from every arm's origin: left to Rust */
        return;
    }
    if (s->u.bind.value->kind == MS_E_LAMBDA && !s->u.bind.is_mutable) {
        own_bind_lambda(w, s, binding);
        return;
    }
    const uint32_t source = w->class_of[binding] == MS_CLASS_COPY ? MS_NONE : own_borrowed_name(w, s, binding);
    if (source == MS_NONE) {
        own_expr(w, s->u.bind.value, DEMAND_MOVE);
        return;
    }
    if (s->u.bind.is_mutable) {
        OWN_DECLINE(w); /* a `var` borrow of a name: exclusive borrows come with calls and assignment */
        return;
    }
    own_expr(w, s->u.bind.value, DEMAND_READ);
    own_declare_borrow(w, binding, own_resolve(w, source), s->u.bind.pattern->pos, "binding of a borrowed value");
    w->facts->bindings.flags[binding] |= MS_BIND_BORROWS;
}

/* Whether returning the name hands back a reference into a parameter: a parameter itself, or a
 * borrow whose origin is one. Nothing moves then. */
static bool own_returns_parameter_borrow(const OwnWalk *w, const MsExpr *e) {
    if (e->kind != MS_E_NAME || w->facts->res_kind[e->id] != MS_RES_BINDING) {
        return false;
    }
    const uint32_t binding = w->facts->res_ref[e->id];
    const uint32_t root = own_resolve(w, binding);
    return w->is_param[root] && w->param_mode[root] != 2; /* a `move` parameter is owned: returning it moves it */
}

/* Whether the call names the function being walked. */
static bool own_is_self_call(const OwnWalk *w, const MsExpr *e) {
    const uint32_t sym = w->facts->call_callee[e->id];
    return sym != MS_NONE && w->check->syms.decl[sym] != NULL && &w->check->syms.decl[sym]->u.fn == w->function;
}

/* `return f(a)` where `f` returns a reference into `a`: this function hands back a reference into
 * its own parameters when every source is one, and is left to Rust otherwise. */
static void own_returned_borrow_call(OwnWalk *w, const MsExpr *e) {
    uint32_t origins[4];
    uint32_t count = 0;
    if (!own_call_origins(w, e, origins, &count) || count == 0) {
        OWN_DECLINE(w);
        return;
    }
    for (uint32_t i = 0; i < count; i++) {
        if (!w->is_param[origins[i]] || w->param_mode[origins[i]] == 2) { /* a `move` parameter is owned */
            OWN_DECLINE(w);
            return;
        }
        w->borrowed_params |= 1u << w->param_index[origins[i]];
    }
    w->borrowed_return = w->has_borrowed_return ? w->borrowed_return : e->pos;
    w->has_borrowed_return = true;
    own_expr(w, e, DEMAND_READ);
}

/* Whether the call goes through a function-typed local: its result is a new value. */
static bool own_is_value_call(const OwnWalk *w, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    return callee->kind == MS_E_NAME && w->facts->res_kind[callee->id] == MS_RES_BINDING;
}

/* An operation of a primitive whose runtime function is declared `@fresh`: its result is a new value,
 * never a reference into the receiver or an argument (`s.clone()`). */
static bool own_is_fresh_intrinsic(const OwnWalk *w, const MsExpr *e) {
    const MsExpr *callee = e->u.call.callee;
    if (callee->kind != MS_E_MEMBER || w->facts->call_interface[e->id] == MS_TY_NONE ||
        ms_ty_kind(&w->check->tys, w->facts->call_receiver[e->id]) == MS_K_CONTRACT) {
        return false;
    }
    if (ms_ty_kind(&w->check->tys, w->facts->call_receiver[e->id]) == MS_K_VARIABLE) {
        // An operation every value has (`to_string`, `clone`) is recorded against the variable itself, not
        // against a bound that declares it; it builds a new value.
        return w->facts->call_interface[e->id] == w->facts->call_receiver[e->id];
    }
    const MsRtFn *fn = ms_rt_method_fn(w->check, w->facts->call_receiver[e->id], callee->u.member.name);
    return fn != NULL && fn->fresh;
}

/* Whether the call is a method or an interface operation, which `own_call` judges itself. */
static bool own_is_method_call(const OwnWalk *w, const MsExpr *e) {
    if (e->u.call.callee->kind != MS_E_MEMBER) {
        return false;
    }
    if (w->facts->call_interface[e->id] != MS_TY_NONE) {
        return ms_ty_kind(&w->check->tys, w->facts->call_receiver[e->id]) == MS_K_CONTRACT;
    }
    return w->facts->call_method[e->id] != MS_NONE && w->facts->methods != NULL;
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
    if (e->kind == MS_E_CALL && !own_is_constructor(w, e) && !own_is_value_call(w, e) && !own_is_fresh_intrinsic(w, e) && !own_is_method_call(w, e)) {
        const OwnSummary *callee = own_callee(w, e);
        if (callee == NULL || (callee->returns_borrow && own_is_self_call(w, e))) {
            OWN_DECLINE(w);
        } else if (callee->returns_borrow) {
            own_returned_borrow_call(w, e);
            return;
        }
    }
    if (e->kind == MS_E_CALL && own_is_self_call(w, e)) {
        own_expr(w, e, DEMAND_MOVE); /* returns whatever this function returns: neither kind of return */
        return;
    }
    if (!w->facts->some_wrap[e->id] && own_returns_parameter_borrow(w, e)) { /* `some` makes a new value around it */
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
static Scrutinee own_scrutinee(OwnWalk *w, const MsExpr *e) {
    if (e->kind == MS_E_CALL && w->facts->call_borrows[e->id]) {
        return own_borrowed_call(w, e);
    }
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
/* The place a field-path target names, rooted at the local `root`, shown as `p.a.b`. */
static MsPlace own_target_place(OwnWalk *w, const MsExpr *target, uint32_t root, MsStr *text) {
    uint32_t depth = 0;
    for (const MsExpr *e = target; e->kind == MS_E_MEMBER; e = e->u.member.left) {
        depth++;
    }
    MsStep *steps = MS_NEW_N(&w->check->arena, MsStep, (size_t)depth + 1);
    uint32_t at = depth;
    for (const MsExpr *e = target; e->kind == MS_E_MEMBER; e = e->u.member.left) {
        steps[--at] = (MsStep){MS_STEP_FIELD, e->u.member.name, 0};
    }
    const MsPlace place = {root, steps, depth};
    MsBuf shown = {0};
    ms_place_show(&shown, w->check->names, place, w->facts->bindings.name[root]);
    *text = (MsStr){.ptr = ms_arena_strndup(&w->check->arena, shown.data, shown.len), .len = (uint32_t)shown.len};
    ms_buf_free(&shown);
    return place;
}

/* `var.field.path = value`: the value moves in, then the part changes in place under the variable's
 * permission and any borrow that reads an overlapping part. A field that is a resource closes its
 * old value, which this walk does not model yet. */
static void own_field_store(OwnWalk *w, const MsStmt *s, uint32_t root) {
    const MsExpr *target = s->u.assign.target;
    if (ms_classify(w->classifier, w->facts->expr_ty[target->id]) == MS_CLASS_RESOURCE) {
        OWN_DECLINE(w);
        return;
    }
    own_expr(w, s->u.assign.value, DEMAND_MOVE);
    own_release_pending(w);
    MsStr text;
    const MsPlace place = own_target_place(w, target, root, &text);
    own_mutate_place(w, target->pos, root, place, text);
}

static void own_assign(OwnWalk *w, const MsStmt *s) {
    const uint32_t binding = w->facts->assign_binding[s->id];
    if (binding == MS_NONE && w->facts->field_store_root[s->id] != MS_NONE) {
        own_field_store(w, s, w->facts->field_store_root[s->id]);
        return;
    }
    if (binding == MS_NONE || w->perm[binding] != PERM_MUTABLE) {
        OWN_DECLINE(w); /* a field store or an assignment the checker rejects */
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
        OWN_DECLINE(w);
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

/* `for i in a..b`: the bounds are read once; the counter is a fresh copied binding per iteration. */
/* `for name in xs`: the loop variable is a plain value, or borrows a String element, and the list stays
 * unchanged for the whole loop, which a hidden borrow on it says. */
static void own_for_list(OwnWalk *w, const MsStmt *s) {
    const uint32_t mark = w->ndeclared;
    const MsExpr *iter = s->u.each.iter;
    const Scrutinee source = own_scrutinee(w, iter);
    own_release_pending(w);
    const uint32_t hidden = OWN_HIDDEN_HOLDER + w->hidden++;
    if (!source.owned) {
        const Borrow loop = {.holder = hidden, .origin = source.origin, .pos = iter->pos, .why = "the loop is iterating it"};
        own_push_borrow(w, &loop);
    }
    const uint32_t variable = w->by_node[s->id];
    if (variable == MS_NONE) {
        OWN_DECLINE(w);
        return;
    }
    if (ms_classify(w->classifier, w->facts->bindings.ty[variable]) == MS_CLASS_COPY) {
        own_declare(w, variable, PERM_IMMUTABLE, false);
    } else { // a String element is borrowed from the list; moving it out is left to the Rust walk
        own_declare(w, variable, PERM_BORROWED, false);
        w->deferred[variable] = true;
    }
    BorrowSet entry = own_set_copy(&w->active);
    own_block(w, &s->u.each.body);
    own_join(w, entry);
    own_release_holder(&w->active, hidden);
    own_end_scope(w, mark);
}

static void own_for(OwnWalk *w, const MsStmt *s) {
    if (w->facts->each_list[s->id]) {
        own_for_list(w, s);
        return;
    }
    const MsExpr *range = s->u.each.iter;
    own_expr(w, range->u.call.args.ptr[0].value, DEMAND_READ);
    own_expr(w, range->u.call.args.ptr[1].value, DEMAND_READ);
    own_release_pending(w);
    const uint32_t counter = w->by_node[s->id];
    if (counter == MS_NONE) {
        OWN_DECLINE(w);
        return;
    }
    BorrowSet entry = own_set_copy(&w->active);
    own_declare(w, counter, PERM_IMMUTABLE, false);
    own_block(w, &s->u.each.body);
    own_join(w, entry);
}

/* ---- match ---- */

/* One arm: its payloads, body and value share a scope. */
static void own_arm(OwnWalk *w, const MsArm *arm, const Scrutinee *source, Demand demand, bool returning) {
    const uint32_t mark = w->ndeclared;
    if (!own_arm_payloads(w, arm, source)) {
        OWN_DECLINE(w);
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
    // The arms of a match over an interface value bind the whole value as a concrete type: not followed.
    if (ms_ty_kind(&w->check->tys, w->facts->expr_ty[e->u.match.scrutinee->id]) == MS_K_CONTRACT) {
        OWN_DECLINE(w);
        return;
    }
    const bool copied = ms_classify(w->classifier, w->facts->expr_ty[e->id]) == MS_CLASS_COPY;
    const bool borrowed = !returning && demand != DEMAND_MOVE && !copied && own_arms_are_names(w, e);
    w->facts->borrowed_match[e->id] = borrowed;
    /* Arms that are not all references produce a value, so a place among them moves. */
    Demand arm_demand = demand;
    if (!borrowed && demand == DEMAND_READ) {
        arm_demand = DEMAND_MOVE;
    }
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
    case MS_S_FOR: own_for(w, s); return;
    }
}

/* ---- functions ---- */

/* An anonymous function: its parameters are owned by its body, its returns are its own, and it
 * captures only copies, which it reads when it is made. */
static void own_lambda(OwnWalk *w, const MsExpr *e, bool escaping) {
    const bool outer_escaping = w->lambda_escaping;
    w->lambda_escaping = escaping;
    const bool had_borrowed = w->has_borrowed_return, had_owned = w->has_owned_return;
    const MsPos borrowed_at = w->borrowed_return, owned_at = w->owned_return;
    const uint32_t outer_floor = w->floor, outer_params = w->borrowed_params;
    const uint32_t mark = w->ndeclared;
    w->floor = w->facts->lambda_first[e->id];
    for (uint32_t i = 0; i < e->u.lambda.params.len; i++) {
        const uint32_t param = w->by_node[e->u.lambda.params.ptr[i]->id];
        own_declare(w, param, PERM_IMMUTABLE, false);
        w->lent[param] = w->class_of[param] != MS_CLASS_COPY;
    }
    own_block(w, &e->u.lambda.body);
    own_end_scope(w, mark);
    w->floor = outer_floor;
    w->borrowed_params = outer_params;
    w->lambda_escaping = outer_escaping;
    w->has_borrowed_return = had_borrowed;
    w->has_owned_return = had_owned;
    w->borrowed_return = borrowed_at;
    w->owned_return = owned_at;
}

/* The receiver of a method is parameter 0: borrowed, or changed in place when the method is `var`. */
static void own_declare_parameters(OwnWalk *w, const MsFunc *function, const MsMethod *method, const uint32_t *by_node) {
    const uint32_t shift = method != NULL ? 1 : 0;
    if (method != NULL) {
        const uint32_t self = by_node[method->id];
        own_declare(w, self, method->mutating ? PERM_MUTABLE : PERM_IMMUTABLE, true);
        w->self_binding = self;
        w->self_consuming = method->consuming;
        w->param_index[self] = 0;
        w->param_mode[self] = method->mutating ? 1 : 0;
    }
    for (uint32_t i = 0; i < function->params.len; i++) {
        const uint32_t binding = by_node[function->params.ptr[i]->id];
        const MsParam *param = function->params.ptr[i];
        own_declare(w, binding, param->is_mutable ? PERM_MUTABLE : PERM_IMMUTABLE, true);
        w->param_index[binding] = i + shift;
        w->param_mode[binding] = 0;
        if (param->moving) w->param_mode[binding] = 2;
        if (param->is_mutable) w->param_mode[binding] = 1;
    }
}

static bool own_function(OwnWalk *w, const MsFunc *function, const MsMethod *method, const uint32_t *by_node) {
    w->function = function;
    w->floor = 0;
    w->active.len = 0;
    w->npending = 0;
    w->pending_base = 0;
    w->ndeclared = 0;
    w->has_borrowed_return = w->has_owned_return = false;
    w->borrowed_params = 0;
    w->consumed = 0;
    w->note_param = MS_NONE;
    w->self_binding = MS_NONE;
    w->self_consuming = false;
    w->supported = true;
    w->by_node = by_node;
    own_declare_parameters(w, function, method, by_node);
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
    w->closure_holds = MS_NEW_N(arena, bool, n);
    w->lent = MS_NEW_N(arena, bool, n);
    w->param_mode = MS_NEW_N(arena, uint8_t, n);
    w->param_index = MS_NEW_N(arena, uint32_t, n);
    w->summaries = MS_NEW_N(arena, OwnSummary, (size_t)w->facts->node_count + 1);
    memset(w->summaries, 0, ((size_t)w->facts->node_count + 1) * sizeof *w->summaries);
}

/* Walks one function and records what its callers need to know. Returns whether the summary
 * changed. */
static bool own_summarize(OwnWalk *w, const MsDecl *d, const uint32_t *by_node) {
    OwnSummary *summary = &w->summaries[d->id];
    const bool handled = own_function(w, &d->u.fn, NULL, by_node) && d->u.fn.params.len < 32;
    const bool returns_borrow = handled && w->has_borrowed_return && !w->has_owned_return;
    const uint32_t mask = returns_borrow ? w->borrowed_params : 0;
    const uint32_t consumed = handled ? w->consumed : 0;
    const bool changed = summary->usable != handled || summary->returns_borrow != returns_borrow ||
                         summary->borrowed_params != mask || summary->consumed != consumed;
    MsPos *at = NULL;
    if (consumed != 0) {
        at = MS_NEW_N(&w->check->arena, MsPos, 32);
        memcpy(at, w->consumed_at, sizeof w->consumed_at);
    }
    *summary = (OwnSummary){.usable = handled, .returns_borrow = returns_borrow, .borrowed_params = mask,
                            .consumed = consumed, .consumed_at = at,
                            .declined = handled ? (MsSite){0} : w->declined};
    return changed;
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

/* The impl methods of the module the checker claimed, walked once: nothing calls one through a summary,
 * since the checker admits only scalar results for a method call. */
static void own_methods(OwnWalk *w, MsLiveness *live, const uint32_t *by_node) {
    const MsFacts *facts = w->facts;
    if (facts->methods == NULL) {
        return;
    }
    const MsMethod **rows = ms_method_rows(w->check, w->module, facts->methods, NULL);
    w->quiet = false;
    for (uint32_t i = 0; i < facts->methods->count; i++) {
        const MsMethod *method = rows[i];
        if (method == NULL || !facts->body_checked[method->id]) {
            continue;
        }
        const bool walked = ms_liveness_function(live, facts, &method->func) &&
                            own_function(w, &method->func, method, by_node);
        facts->body_checked[method->id] = walked;
        if (!walked) {
            facts->refusal[method->id] = w->declined;
        }
        facts->ret_borrowed[method->id] = walked && w->has_borrowed_return && !w->has_owned_return;
        facts->param_consumed[method->id] = walked ? w->consumed : 0;
    }
}

void ms_module_check_ownership(MsCheck *c, MsModId module) {
    MsModuleRow *row = &c->mods[module];
    MsFacts *facts = row->facts;
    if (facts == NULL || facts->body_checked == NULL || facts->ownership_done) {
        return;
    }
    facts->ownership_done = true;
    MsArena scratch = {0};
    MsLiveness live = ms_liveness_new(&scratch, facts);
    OwnWalk w = {.check = c, .module = module, .facts = facts, .live = &live,
                 .classifier = ms_classifier_new(c)};
    ms_classifier_mark_methods(w.classifier, facts->methods);
    own_allocate(&w, &scratch);
    const uint32_t *by_node = own_bindings_by_node(facts, &scratch);
    // A `test` block walks as a function of no parameters.
    MsFunc **tests = MS_NEW_N(&scratch, MsFunc *, row->syntax->ndecls + 1);
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        const MsFunc *function = &d->u.fn;
        if (d->kind == MS_D_TEST) {
            tests[i] = MS_NEW(&scratch, MsFunc);
            *tests[i] = (MsFunc){.body = d->u.test.body};
            function = tests[i];
        }
        const bool claimed = (d->kind == MS_D_FN || d->kind == MS_D_TEST) && facts->body_checked[d->id];
        w.summaries[d->id].usable = claimed && ms_liveness_function(&live, facts, function);
    }
    // Also for a module without calls: the summaries are where `ret_borrowed` and `param_consumed`
    // come from, and a caller in another module reads them.
    own_summary_rounds(&w, row, by_node);
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        if (d->kind == MS_D_FN && facts->body_checked[d->id]) {
            facts->body_checked[d->id] = w.summaries[d->id].usable && own_function(&w, &d->u.fn, NULL, by_node);
            if (!facts->body_checked[d->id]) {
                MsSite refusal = w.declined;
                if (!w.summaries[d->id].usable) {
                    refusal = w.summaries[d->id].declined;
                    if (refusal.file == NULL) {
                        refusal = (MsSite){"ownership_live.c", 0};
                    }
                }
                facts->refusal[d->id] = refusal;
            }
            facts->ret_borrowed[d->id] = facts->body_checked[d->id] && w.summaries[d->id].returns_borrow;
            facts->param_consumed[d->id] = facts->body_checked[d->id] ? w.summaries[d->id].consumed : 0;
        }
    }
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        if (d->kind == MS_D_TEST && facts->body_checked[d->id]) {
            facts->body_checked[d->id] = w.summaries[d->id].usable && own_function(&w, tests[i], NULL, by_node);
        }
    }
    own_methods(&w, &live, by_node);
    free(w.active.items);
    free(w.declared);
    free(w.pending);
    ms_classifier_free(w.classifier);
    ms_arena_free(&scratch);
}
