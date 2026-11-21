/* The call sites and flow steps of the callables of one module, for the fact model
 * (crates/ms-tooling/src/inspect.rs `Sites` and flow.rs). A site is where a body calls something; its target is a
 * project entity key, or text for what lies outside the project (`@std/log.ms#fn#create`, `Logger.info`,
 * `CaptureTransport`). The flow is the ordered significant steps of a body: calls, branches, loops, match arms, try
 * sites, cleanup scopes and exits, labelled with the source line itself. Both read the checker's columns, so they
 * are only filled for a body the checker kept. */
#include <stdlib.h>
#include <string.h>

#include "ms/dump.h"
#include "ms/hints.h"
#include "ms/facts.h"
#include "ms/hints.h"
#include "ms/methods.h"
#include "ms/walk.h"

typedef enum FsSiteKind { FSITE_FUNCTION, FSITE_CONSTANT, FSITE_OPERATION, FSITE_CONSTRUCT, FSITE_HTTP_SERVE } FsSiteKind;

typedef struct FsSite {
    uint32_t offset; /* where the call expression starts: the key a flow step looks its site up by */
    MsStr target;    /* the entity key of a project callee, else the text of what is called */
    MsStr label;     /* the target as a person reads it */
    FsSiteKind kind;
    bool spawn;   /* a `TaskGroup.spawn` call */
    bool project; /* the target is a project entity: it has a fact */
} FsSite;

typedef struct FsSiteList {
    FsSite *ptr;
    uint32_t len, cap;
} FsSiteList;

/* One step of a flow, and the steps under it. */
typedef struct FsStep FsStep;
typedef struct FsSteps {
    FsStep **ptr;
    uint32_t len, cap;
} FsSteps;

struct FsStep {
    const char *kind;
    MsStr label, reference;
    uint32_t line;
    bool placed; /* it has a file and a line: the output prints them */
    FsSteps children;
};

struct MsSites {
    MsCheck *c;
    MsModId m;
    const MsFacts *facts;
    MsArena arena;
    MsStr file, text;
    MsStr *lines;
    uint32_t nlines;
    FsSiteList sites;    /* the sites of the callable being walked */
};

MsSites *ms_sites_new(MsCheck *c, MsModId m, MsStr text) {
    MsSites *s = calloc(1, sizeof *s);
    if (s == NULL) {
        ms_oom();
    }
    s->c = c;
    s->m = m;
    s->facts = c->mods[m].facts;
    s->file = ms_name(c->names, c->mods[m].path);
    s->text = text;
    uint32_t count = 1;
    for (uint32_t i = 0; i < text.len; i++) {
        count += text.ptr[i] == '\n' ? 1u : 0u;
    }
    s->lines = MS_NEW_N(&s->arena, MsStr, count);
    uint32_t from = 0;
    for (uint32_t i = 0; i <= text.len; i++) {
        if (i == text.len || text.ptr[i] == '\n') {
            s->lines[s->nlines++] = (MsStr){text.ptr + from, i - from};
            from = i + 1;
        }
    }
    return s;
}

void ms_sites_free(MsSites *s) {
    free(s->sites.ptr);
    ms_arena_free(&s->arena);
    free(s);
}

/* ---- the targets of a body ---- */

static MsStr fs_text(MsSites *s, const MsBuf *b) {
    return (MsStr){ms_arena_strndup(&s->arena, b->data == NULL ? "" : (const char *)b->data, b->len), (uint32_t)b->len};
}

static MsStr fs_ty_text(MsSites *s, MsTy ty) {
    MsBuf b = {0};
    ms_ty_show(&b, s->c->names, &s->c->tys, ty);
    const MsStr text = fs_text(s, &b);
    ms_buf_free(&b);
    return text;
}

/* `Contract for Type.method` or `Type.method`: what the inspection calls a method with a body. */
static MsStr fs_method_name(MsSites *s, uint32_t row) {
    const MsMethods *rows = &s->c->methods->methods;
    const MsModule *syntax = s->c->mods[rows->module[row]].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        for (uint32_t k = 0; d->kind == MS_D_IMPL && k < d->u.impl.methods.len; k++) {
            if (&d->u.impl.methods.ptr[k]->func != rows->decl[row]) {
                continue;
            }
            MsBuf b = {0};
            ms_facts_put_impl_name(&b, s->c->names, d);
            ms_buf_putc(&b, '.');
            const MsStr name = ms_name(s->c->names, rows->decl[row]->name);
            ms_buf_put(&b, name.ptr, name.len);
            const MsStr text = fs_text(s, &b);
            ms_buf_free(&b);
            return text;
        }
    }
    return (MsStr){"", 0};
}

/* The part of a project entity key after its file and kind. */
static MsStr fs_key_name(MsStr key) {
    uint32_t hashes = 0;
    for (uint32_t i = 0; i < key.len; i++) {
        hashes += key.ptr[i] == '#' ? 1u : 0u;
        if (hashes == 2) {
            return (MsStr){key.ptr + i + 1, key.len - i - 1};
        }
    }
    return key;
}

/* `file::name` for a `file#kind#name` target, as the diagram prints it; other text as it is. */
static MsStr fs_readable(MsSites *s, MsStr id) {
    uint32_t first = id.len, second = id.len;
    for (uint32_t i = 0; i < id.len; i++) {
        if (id.ptr[i] != '#') {
            continue;
        }
        if (first == id.len) {
            first = i;
        } else {
            second = i;
            break;
        }
    }
    if (second == id.len || first == 0 || second == first + 1 || second + 1 == id.len) {
        return id;
    }
    const bool source = first >= 7 && memcmp(id.ptr + first - 7, "+source", 7) == 0;
    const uint32_t file = source ? first - 7 : first;
    return ms_arena_fmt(&s->arena, "%.*s::%.*s", (int)file, id.ptr, (int)(id.len - second - 1), id.ptr + second + 1);
}

static bool fs_callee_text(MsSites *s, const MsExpr *callee, MsStr *out) {
    if (callee->kind == MS_E_NAME) {
        *out = ms_name(s->c->names, callee->u.sym);
        return true;
    }
    if (callee->kind == MS_E_MEMBER) {
        *out = ms_name(s->c->names, callee->u.member.name);
        return true;
    }
    return false;
}

/* The site of a call (or of a read of a constant) from the checker's columns. */
static void fs_resolve(MsSites *s, const MsExpr *e, FsSite *site) {
    const MsCheck *c = s->c;
    const MsFacts *f = s->facts;
    *site = (FsSite){.offset = e->pos.offset, .target = {"indirect", 8}, .kind = FSITE_FUNCTION};
    site->label = site->target;
    if (f->const_use[e->id]) {
        site->kind = FSITE_CONSTANT;
    }
    const MsSymId sym = f->call_callee[e->id];
    if (sym != MS_NONE) {
        const MsDecl *decl = c->syms.decl[sym];
        const MsStr module = ms_name(c->names, c->mods[c->syms.module[sym]].path);
        const MsStr name = ms_name(c->names, c->syms.name[sym]);
        /* A built-in has no symbol of its own in the inspection: it prints as `module#name`. */
        if (decl != NULL && decl->kind != MS_D_TYPE && c->syms.native[sym] != MS_NATIVE_BUILTIN) {
            const char *kind = ms_facts_kind_of(decl);
            site->target = ms_arena_fmt(&s->arena, "%.*s#%s#%.*s", (int)module.len, module.ptr, kind, (int)name.len, name.ptr);
            site->project = !ms_facts_is_std(c, c->syms.module[sym]);
        } else if (decl == NULL || c->syms.native[sym] == MS_NATIVE_BUILTIN) {
            site->target = ms_arena_fmt(&s->arena, "%.*s#%.*s", (int)module.len, module.ptr, (int)name.len, name.ptr);
        }
        site->label = fs_readable(s, site->target);
        if (decl != NULL && decl->kind == MS_D_TYPE) {
            site->kind = FSITE_CONSTRUCT;
            site->project = false;
            const MsTy own = f->coerce_iface[e->id] != MS_TY_NONE ? f->coerce_iface[e->id] : f->expr_ty[e->id];
            site->target = own != MS_TY_NONE ? fs_ty_text(s, own) : name;
            site->label = site->target;
        }
        const MsStr native = c->syms.native_name[sym] != 0 ? ms_name(c->names, c->syms.native_name[sym]) : (MsStr){"", 0};
        if (native.len == 9 && memcmp(native.ptr, "http_serve", 9) == 0) {
            site->kind = FSITE_HTTP_SERVE;
            site->target = site->label = (MsStr){"http_serve", 10};
        }
    }
    if (e->kind == MS_E_CALL && f->res_kind[e->u.call.callee->id] == MS_RES_CASE && f->expr_ty[e->id] != MS_TY_NONE) {
        /* `ok(v)`, `error(e)`: a case of a built-in enum, shown as the type it builds. */
        site->kind = FSITE_CONSTRUCT;
        site->target = site->label = fs_ty_text(s, f->expr_ty[e->id]);
        return;
    }
    const uint32_t row = f->call_method[e->id];
    if (row == MS_NONE && f->call_interface[e->id] == MS_TY_NONE) {
        return;
    }
    const MsMethods *rows = &c->methods->methods;
    site->kind = FSITE_OPERATION;
    MsStr callee = {"", 0};
    if (e->kind == MS_E_CALL) {
        (void)fs_callee_text(s, e->u.call.callee, &callee);
    }
    if (row == MS_NONE) {
        /* An operation of an interface (`clone`, `to_string`): the receiver's type and the name written. */
        const MsStr shown = fs_ty_text(s, f->call_receiver[e->id]);
        site->target = site->label = ms_arena_fmt(&s->arena, "%.*s.%.*s", (int)shown.len, shown.ptr, (int)callee.len, callee.ptr);
        return;
    }
    site->spawn = f->call_receiver[e->id] != MS_TY_NONE && ms_ty_is(&c->tys, f->call_receiver[e->id], MS_BI_TASKGROUP) &&
                  callee.len == 5 && memcmp(callee.ptr, "spawn", 5) == 0;
    if (rows->decl[row] != NULL && rows->decl[row]->body.len > 0) {
        const MsStr name = fs_method_name(s, row);
        if (!ms_facts_is_std(c, rows->module[row])) {
            const MsStr file = ms_name(c->names, c->mods[rows->module[row]].path);
            site->target = ms_arena_fmt(&s->arena, "%.*s#method#%.*s", (int)file.len, file.ptr, (int)name.len, name.ptr);
            site->project = true;
        } else {
            site->target = name;
        }
        site->label = name;
        return;
    }
    const MsTy receiver = f->call_receiver[e->id] != MS_TY_NONE ? f->call_receiver[e->id] : rows->receiver[row];
    const MsStr shown = fs_ty_text(s, receiver);
    site->target = ms_arena_fmt(&s->arena, "%.*s.%.*s", (int)shown.len, shown.ptr, (int)callee.len, callee.ptr);
    site->label = site->target;
}

static void fs_push(MsSites *s, const FsSite *site) {
    if (s->sites.len == s->sites.cap) {
        s->sites.cap = s->sites.cap != 0 ? s->sites.cap * 2 : 32;
        s->sites.ptr = ms_array_resize(s->sites.ptr, s->sites.cap, sizeof *s->sites.ptr);
    }
    s->sites.ptr[s->sites.len++] = *site;
}

/* Whether the binding of `pattern` is closed when its scope ends (the ownership walk marked it a resource). */
static bool fs_scoped(const MsSites *s, const MsPattern *pattern) {
    const MsFacts *f = s->facts;
    if (pattern->kind != MS_P_NAME || f->pattern_binding[pattern->id] == MS_NONE) {
        return false;
    }
    return (f->bindings.flags[f->pattern_binding[pattern->id]] & MS_BIND_RESOURCE) != 0;
}

/* The implicit `close` of a resource binding: its own method when the type has one with a body, else `Type.close`. */
static void fs_cleanup(MsSites *s, const MsStmt *st) {
    const MsFacts *f = s->facts;
    const MsTy ty = f->bindings.ty[f->pattern_binding[st->u.bind.pattern->id]];
    const MsMethods *rows = &s->c->methods->methods;
    /* A cleanup has no call expression, so no flow step looks it up. */
    FsSite site = {.offset = UINT32_MAX, .kind = FSITE_FUNCTION};
    for (uint32_t r = 0; r < rows->count; r++) {
        const MsFunc *fn = rows->decl[r];
        if (fn == NULL || s->c->tys.id[rows->receiver[r]] != s->c->tys.id[ty]) {
            continue;
        }
        const MsStr name = ms_name(s->c->names, fn->name);
        if (name.len != 5 || memcmp(name.ptr, "close", 5) != 0) {
            continue;
        }
        if (fn->body.len == 0) {
            /* A native close: named by its receiver. */
            const MsStr shown = fs_ty_text(s, ty);
            site.target = site.label = ms_arena_fmt(&s->arena, "%.*s.close", (int)shown.len, shown.ptr);
            fs_push(s, &site);
            return;
        }
        const MsStr method = fs_method_name(s, r);
        if (ms_facts_is_std(s->c, rows->module[r])) {
            site.target = method;
        } else {
            const MsStr file = ms_name(s->c->names, s->c->mods[rows->module[r]].path);
            site.target = ms_arena_fmt(&s->arena, "%.*s#method#%.*s", (int)file.len, file.ptr, (int)method.len, method.ptr);
            site.project = true;
        }
        site.label = method;
        fs_push(s, &site);
        return;
    }
    /* No `close` method: a record or collection closes its parts, which is not a call the inspection records. */
}

static void fs_expr(void *ctx, const MsExpr *e) {
    MsSites *s = ctx;
    if (e->kind == MS_E_CALL || (e->kind == MS_E_NAME && s->facts->const_use[e->id])) {
        FsSite site;
        fs_resolve(s, e, &site);
        fs_push(s, &site);
    }
}

static void fs_stmt(void *ctx, const MsStmt *st) {
    MsSites *s = ctx;
    if (st->kind == MS_S_BIND && fs_scoped(s, st->u.bind.pattern)) {
        fs_cleanup(s, st);
    }
}

/* The site of the call that starts at `offset`; the last one recorded, as the Rust table keeps. */
static const FsSite *fs_at(const MsSites *s, uint32_t offset) {
    for (uint32_t i = s->sites.len; i > 0; i--) {
        if (s->sites.ptr[i - 1].offset == offset) {
            return &s->sites.ptr[i - 1];
        }
    }
    return NULL;
}

/* ---- the flow of a body ---- */

static void fs_steps_push(MsSites *s, FsSteps *list, FsStep *step) {
    if (list->len == list->cap) {
        const uint32_t cap = list->cap != 0 ? list->cap * 2 : 4;
        void **grown = ms_alloc(&s->arena, (size_t)cap * sizeof(void *), _Alignof(void *));
        if (list->len > 0) {
            memcpy(grown, list->ptr, (size_t)list->len * sizeof(void *));
        }
        list->ptr = (FsStep **)grown;
        list->cap = cap;
    }
    list->ptr[list->len++] = step;
}

static void fs_steps_append(MsSites *s, FsSteps *list, const FsSteps *more) {
    for (uint32_t i = 0; i < more->len; i++) {
        fs_steps_push(s, list, more->ptr[i]);
    }
}

static FsStep *fs_step_new(MsSites *s, const char *kind, MsStr label) {
    FsStep *step = MS_NEW(&s->arena, FsStep);
    *step = (FsStep){.kind = kind, .label = label, .reference = {"", 0}};
    return step;
}

static FsStep *fs_step_at(MsSites *s, const char *kind, MsStr label, MsPos pos) {
    FsStep *step = fs_step_new(s, kind, label);
    step->placed = true;
    step->line = pos.line;
    return step;
}

static MsStr fs_trim_blanks(MsStr text) {
    while (text.len > 0 && (text.ptr[0] == ' ' || text.ptr[0] == '\t' || text.ptr[0] == '\r')) {
        text.ptr++;
        text.len--;
    }
    while (text.len > 0 && (text.ptr[text.len - 1] == ' ' || text.ptr[text.len - 1] == '\t' || text.ptr[text.len - 1] == '\r')) {
        text.len--;
    }
    return text;
}

/* The source line of `pos`, trimmed, without a trailing colon: the label of a step. */
static MsStr fs_flow_source(const MsSites *s, MsPos pos) {
    if (pos.line < 1 || pos.line > s->nlines) {
        return (MsStr){"", 0};
    }
    MsStr line = fs_trim_blanks(s->lines[pos.line - 1]);
    if (line.len > 0 && line.ptr[line.len - 1] == ':') {
        line.len--;
    }
    return fs_trim_blanks(line);
}

static bool fs_label_ends_with(MsStr label, MsStr suffix) {
    return label.len >= suffix.len && memcmp(label.ptr + label.len - suffix.len, suffix.ptr, suffix.len) == 0;
}

/* What the walk of one expression collects: the calls and try markers, in evaluation order. */
typedef struct FsPending {
    uint32_t id;
    FsStep *step;
    uint32_t start;
} FsPending;

typedef struct FsEvents {
    MsSites *s;
    FsSteps out;
    bool pending_try;
    struct {
        FsPending *ptr;
        uint32_t len, cap;
    } spawns, pending, closures;
} FsEvents;

static void fs_pending_push(MsSites *s, void *target, FsPending item) {
    struct {
        FsPending *ptr;
        uint32_t len, cap;
    } *list = target;
    (void)s;
    if (list->len == list->cap) {
        list->cap = list->cap != 0 ? list->cap * 2 : 8;
        list->ptr = ms_array_resize(list->ptr, list->cap, sizeof *list->ptr);
    }
    list->ptr[list->len++] = item;
}

/* The steps of `out` from `at` on, removed from it. */
static FsSteps fs_steps_split(MsSites *s, FsSteps *out, uint32_t at) {
    FsSteps tail = {0};
    for (uint32_t i = at; i < out->len; i++) {
        fs_steps_push(s, &tail, out->ptr[i]);
    }
    out->len = at;
    return tail;
}

/* The step for the call at `e`, or NULL when it is not a step: a construction is not. */
static FsStep *fs_flow_call(const FsEvents *ev, const MsExpr *e, bool *spawn) {
    MsSites *s = ev->s;
    const FsSite *site = fs_at(s, e->pos.offset);
    if (site == NULL || site->kind == FSITE_CONSTRUCT) {
        return NULL;
    }
    *spawn = site->spawn;
    if (site->project) {
        const MsStr name = fs_key_name(site->target);
        FsStep *step = fs_step_new(s, "call", ms_arena_fmt(&s->arena, "call %.*s", (int)name.len, name.ptr));
        step->reference = site->target;
        return step;
    }
    return fs_step_new(s, "native", ms_arena_fmt(&s->arena, "native %.*s", (int)site->label.len, site->label.ptr));
}

static void fs_events_expr(void *ctx, const MsExpr *e) {
    FsEvents *ev = ctx;
    MsSites *s = ev->s;
    if (e->kind == MS_E_UNARY && e->op == MS_U_TRY) {
        ev->pending_try = true;
        return;
    }
    if (e->kind == MS_E_LAMBDA) {
        /* A function literal runs when its receiver calls it, not where it is written: its calls are listed under
         * the call that takes it. */
        const MsStr source = fs_flow_source(s, e->pos);
        FsStep *step = fs_step_at(s, "closure", ms_arena_fmt(&s->arena, "closure %.*s", (int)source.len, source.ptr), e->pos);
        fs_pending_push(s, &ev->closures, (FsPending){e->id, step, ev->out.len});
        fs_steps_push(s, &ev->out, step);
        return;
    }
    const bool constant = e->kind == MS_E_NAME && s->facts->const_use[e->id];
    if (!constant && e->kind != MS_E_CALL) {
        return;
    }
    bool spawn = false;
    FsStep *step = fs_flow_call(ev, e, &spawn);
    if (step == NULL) {
        return;
    }
    step->placed = true;
    step->line = e->pos.line;
    if (spawn) {
        /* The started work runs as its own task: its calls belong under the spawn. */
        step->kind = "spawn";
        const MsStr source = fs_flow_source(s, e->pos);
        step->label = ms_arena_fmt(&s->arena, "spawn  %.*s", (int)source.len, source.ptr);
        fs_pending_push(s, &ev->spawns, (FsPending){e->id, step, ev->out.len});
    }
    const bool is_spawn = spawn;
    if (ev->pending_try) {
        step->label = ms_arena_fmt(&s->arena, "try %.*s", (int)step->label.len, step->label.ptr);
        step->kind = "try";
        ev->pending_try = false;
    }
    if (is_spawn) {
        fs_steps_push(s, &ev->out, step);
    } else {
        fs_pending_push(s, &ev->pending, (FsPending){e->id, step, ev->out.len});
    }
}

static void fs_events_leave(void *ctx, const MsExpr *e) {
    FsEvents *ev = ctx;
    MsSites *s = ev->s;
    if (ev->closures.len > 0 && ev->closures.ptr[ev->closures.len - 1].id == e->id) {
        const FsPending closure = ev->closures.ptr[--ev->closures.len];
        closure.step->children = fs_steps_split(s, &ev->out, closure.start + 1);
    }
    if (ev->pending.len > 0 && ev->pending.ptr[ev->pending.len - 1].id == e->id) {
        const FsPending call = ev->pending.ptr[--ev->pending.len];
        /* Function literals passed as arguments belong to this call. */
        FsSteps args = fs_steps_split(s, &ev->out, call.start);
        for (uint32_t i = 0; i < args.len; i++) {
            if (strcmp(args.ptr[i]->kind, "closure") != 0) {
                fs_steps_push(s, &ev->out, args.ptr[i]);
            }
        }
        for (uint32_t i = 0; i < args.len; i++) {
            if (strcmp(args.ptr[i]->kind, "closure") == 0) {
                fs_steps_push(s, &call.step->children, args.ptr[i]);
            }
        }
        fs_steps_push(s, &ev->out, call.step);
    }
    if (ev->spawns.len > 0 && ev->spawns.ptr[ev->spawns.len - 1].id == e->id) {
        const FsPending spawn = ev->spawns.ptr[--ev->spawns.len];
        spawn.step->children = fs_steps_split(s, &ev->out, spawn.start + 1);
    }
}

/* The calls and try markers inside one expression, in evaluation order: a call's arguments and receiver come first. */
static FsSteps fs_flow_events(MsSites *s, const MsExpr *e) {
    FsEvents ev = {.s = s};
    if (e == NULL) {
        return ev.out;
    }
    const MsVisitor visitor = {.ctx = &ev, .expr = fs_events_expr, .leave_expr = fs_events_leave};
    ms_walk_expr(&visitor, e);
    if (ev.pending_try) {
        fs_steps_push(s, &ev.out, fs_step_at(s, "try", (MsStr){"try", 3}, e->pos));
    }
    free(ev.spawns.ptr);
    free(ev.pending.ptr);
    free(ev.closures.ptr);
    return ev.out;
}

/* What `statement` needs of a statement: a module constant's initializer is a synthetic return. */
typedef enum FsShape { FSHAPE_BRANCH, FSHAPE_LOOP, FSHAPE_EXIT, FSHAPE_RETURN, FSHAPE_PLAIN } FsShape;

typedef struct FsStmtView {
    MsPos pos;
    FsShape shape;
    const MsExpr *target, *value;
    MsStmts body, else_body;
    const MsStmt *original;
} FsStmtView;

static FsStmtView fs_view_of(const MsStmt *st) {
    FsStmtView v = {.pos = st->pos, .shape = FSHAPE_PLAIN, .original = st};
    switch (st->kind) {
    case MS_S_BIND: v.value = st->u.bind.value; break;
    case MS_S_ASSIGN:
        v.target = st->u.assign.member_target ? st->u.assign.target : NULL;
        v.value = st->u.assign.value;
        break;
    case MS_S_CALL: v.value = st->u.expr; break;
    case MS_S_RETURN:
        v.shape = FSHAPE_RETURN;
        v.value = st->u.expr;
        break;
    case MS_S_BREAK:
    case MS_S_CONTINUE: v.shape = FSHAPE_EXIT; break;
    case MS_S_IF:
        v.shape = FSHAPE_BRANCH;
        v.value = st->u.branch.cond;
        v.body = st->u.branch.body;
        v.else_body = st->u.branch.else_body;
        break;
    case MS_S_WHILE:
        v.shape = FSHAPE_LOOP;
        v.value = st->u.loop.cond;
        v.body = st->u.loop.body;
        break;
    default:
        v.shape = FSHAPE_LOOP;
        v.value = st->u.each.iter;
        v.body = st->u.each.body;
        break;
    }
    return v;
}

static FsSteps fs_flow_body(MsSites *s, MsStmts statements);
static FsSteps fs_flow_statement(MsSites *s, const FsStmtView *v);

static FsStep *fs_flow_match(MsSites *s, MsPos pos, const MsExpr *match) {
    FsStep *node = fs_step_at(s, "match", fs_flow_source(s, pos), pos);
    for (uint32_t i = 0; i < match->u.match.arms.len; i++) {
        const MsArm *arm = match->u.match.arms.ptr[i];
        FsStep *child = fs_step_at(s, "arm", fs_flow_source(s, arm->pos), arm->pos);
        FsSteps steps = fs_flow_events(s, arm->value);
        const FsSteps body = fs_flow_body(s, arm->body);
        fs_steps_append(s, &steps, &body);
        for (uint32_t k = 0; k < steps.len; k++) {
            if (strcmp(steps.ptr[k]->kind, "exit") == 0 && fs_label_ends_with(child->label, steps.ptr[k]->label)) {
                continue;
            }
            fs_steps_push(s, &child->children, steps.ptr[k]);
        }
        fs_steps_push(s, &node->children, child);
    }
    return node;
}

static FsSteps fs_flow_statement(MsSites *s, const FsStmtView *v) {
    if (v->shape == FSHAPE_BRANCH || v->shape == FSHAPE_LOOP) {
        FsStep *node = fs_step_at(s, v->shape == FSHAPE_LOOP ? "loop" : "branch", fs_flow_source(s, v->pos), v->pos);
        /* The condition (or the iterated value) is evaluated before the branch body runs. */
        FsSteps out = fs_flow_events(s, v->value);
        /* `if x: return y` shows its `return y` once, not again as an exit step. */
        const FsSteps body = fs_flow_body(s, v->body);
        for (uint32_t i = 0; i < body.len; i++) {
            if (strcmp(body.ptr[i]->kind, "exit") != 0 || !fs_label_ends_with(node->label, body.ptr[i]->label)) {
                fs_steps_push(s, &node->children, body.ptr[i]);
            }
        }
        fs_steps_push(s, &out, node);
        if (v->else_body.len > 0) {
            FsStep *other = fs_step_new(s, "branch", (MsStr){"else", 4});
            other->children = fs_flow_body(s, v->else_body);
            fs_steps_push(s, &out, other);
        }
        return out;
    }
    if (v->shape == FSHAPE_EXIT) {
        FsSteps out = {0};
        const bool next = v->original != NULL && v->original->kind == MS_S_CONTINUE;
        fs_steps_push(s, &out, fs_step_at(s, "exit", next ? (MsStr){"continue", 8} : (MsStr){"break", 5}, v->pos));
        return out;
    }
    FsSteps out = fs_flow_events(s, v->target);
    if (v->value != NULL && v->value->kind == MS_E_MATCH) {
        const FsSteps scrutinee = fs_flow_events(s, v->value->u.match.scrutinee);
        fs_steps_append(s, &out, &scrutinee);
        fs_steps_push(s, &out, fs_flow_match(s, v->pos, v->value));
    } else {
        const FsSteps value = fs_flow_events(s, v->value);
        fs_steps_append(s, &out, &value);
    }
    if (v->shape == FSHAPE_RETURN) {
        fs_steps_push(s, &out, fs_step_at(s, "exit", fs_flow_source(s, v->pos), v->pos));
    }
    return out;
}

static FsSteps fs_flow_body(MsSites *s, MsStmts statements) {
    FsSteps out = {0};
    for (uint32_t i = 0; i < statements.len; i++) {
        const MsStmt *st = statements.ptr[i];
        if (st->kind != MS_S_BIND || !fs_scoped(s, st->u.bind.pattern)) {
            const FsStmtView v = fs_view_of(st);
            const FsSteps more = fs_flow_statement(s, &v);
            fs_steps_append(s, &out, &more);
            continue;
        }
        /* The rest of the block runs inside the resource's scope. */
        const MsStr source = fs_flow_source(s, st->pos);
        FsStep *node = fs_step_at(s, "scope", ms_arena_fmt(&s->arena, "%.*s  [closed on exit]", (int)source.len, source.ptr), st->pos);
        node->children = fs_flow_events(s, st->u.bind.value);
        const FsSteps rest = fs_flow_body(s, (MsStmts){statements.ptr + i + 1, statements.len - i - 1});
        fs_steps_append(s, &node->children, &rest);
        fs_steps_push(s, &out, node);
        break;
    }
    return out;
}

/* ---- output ---- */

static void fs_put_step(MsBuf *out, const MsSites *s, const FsStep *step) {
    ms_buf_puts(out, "{\"label\": ");
    ms_facts_put_json(out, (const char *)step->label.ptr, step->label.len);
    ms_buf_printf(out, ", \"kind\": \"%s\", \"reference\": ", step->kind);
    ms_facts_put_json(out, (const char *)step->reference.ptr, step->reference.len);
    ms_buf_puts(out, ", \"file\": ");
    if (step->placed) {
        ms_facts_put_json(out, (const char *)s->file.ptr, s->file.len);
    } else {
        ms_buf_puts(out, "\"\"");
    }
    ms_buf_printf(out, ", \"line\": %u, \"omitted\": 0, \"children\": [", step->placed ? step->line : 0u);
    for (uint32_t i = 0; i < step->children.len; i++) {
        ms_buf_puts(out, i == 0 ? "" : ", ");
        fs_put_step(out, s, step->children.ptr[i]);
    }
    ms_buf_puts(out, "]}");
}

/* `["a", "b"]`: the targets outside the project, sorted and unique. */
static void fs_put_external(MsBuf *out, const FsSiteList *sites) {
    MsStr *targets = calloc(sites->len + 1u, sizeof *targets);
    if (targets == NULL) {
        ms_oom();
    }
    uint32_t count = 0;
    for (uint32_t i = 0; i < sites->len; i++) {
        if (!sites->ptr[i].project) {
            targets[count++] = sites->ptr[i].target;
        }
    }
    qsort(targets, count, sizeof *targets, ms_str_compare_ptr);
    ms_buf_putc(out, '[');
    const char *sep = "";
    for (uint32_t i = 0; i < count; i++) {
        if (i > 0 && ms_str_compare_ptr(&targets[i - 1], &targets[i]) == 0) {
            continue;
        }
        ms_buf_puts(out, sep);
        ms_facts_put_json(out, targets[i].ptr, targets[i].len);
        sep = ", ";
    }
    ms_buf_putc(out, ']');
    free(targets);
}

static void fs_put_flow(MsBuf *out, const MsSites *s, const FsSteps *steps) {
    ms_buf_putc(out, '[');
    for (uint32_t i = 0; i < steps->len; i++) {
        ms_buf_puts(out, i == 0 ? "" : ", ");
        fs_put_step(out, s, steps->ptr[i]);
    }
    ms_buf_putc(out, ']');
}

bool ms_sites_decl(MsSites *s, const MsDecl *d, MsBuf *external, MsBuf *flow) {
    const MsFacts *f = s->facts;
    const bool body = d->kind == MS_D_FN || d->kind == MS_D_CONST;
    /* A generic body's cleanups depend on the type arguments, which the ownership walk does not see: left unknown. */
    const bool generic = d->kind == MS_D_FN && d->u.fn.type_params.len > 0;
    const bool known = body && !generic && f != NULL && f->body_checked != NULL && f->body_checked[d->id];
    s->sites.len = 0;
    if (!known) {
        ms_buf_puts(external, "[]");
        ms_buf_puts(flow, "[]");
        return false;
    }
    const MsVisitor visitor = {.ctx = s, .expr = fs_expr, .stmt = fs_stmt};
    FsSteps steps = {0};
    if (d->kind == MS_D_FN) {
        ms_walk_callable(&visitor, d->u.fn.params, d->u.fn.body);
        steps = fs_flow_body(s, d->u.fn.body);
    } else {
        ms_walk_expr(&visitor, d->u.konst.value);
        const FsStmtView v = {.pos = d->u.konst.init_pos, .shape = FSHAPE_RETURN, .value = d->u.konst.value};
        steps = fs_flow_statement(s, &v);
    }
    fs_put_external(external, &s->sites);
    fs_put_flow(flow, s, &steps);
    return true;
}

bool ms_sites_method(MsSites *s, const MsDecl *impl, const MsMethod *method, MsBuf *external, MsBuf *flow) {
    (void)impl;
    const MsFacts *f = s->facts;
    const bool known = f != NULL && f->body_checked != NULL && f->body_checked[method->id] && method->func.body.len > 0;
    s->sites.len = 0;
    if (!known) {
        ms_buf_puts(external, "[]");
        ms_buf_puts(flow, "[]");
        return false;
    }
    const MsVisitor visitor = {.ctx = s, .expr = fs_expr, .stmt = fs_stmt};
    ms_walk_callable(&visitor, method->func.params, method->func.body);
    const FsSteps steps = fs_flow_body(s, method->func.body);
    fs_put_external(external, &s->sites);
    fs_put_flow(flow, s, &steps);
    return true;
}
