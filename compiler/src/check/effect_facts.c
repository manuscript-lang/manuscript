/* Per-entity effect facts for the review tools: the declared effects each project callable reaches,
 * the `allow_effect` patterns in force, and the callables its body names. Builds the reference graph
 * from the checked bodies (effect_scan.c) and the directive lines of each callable's source
 * (effect_directives.c), then resolves it (effect_reach.c). A callable the scan cannot see through
 * yet is reported `partial`, never as an empty answer. */
#include <stdlib.h>
#include <string.h>

#include "ms/check.h"
#include "ms/effects.h"
#include "ms/facts.h"
#include "ms/walk.h"

typedef struct FxNode {
    MsSymId sym;
    bool partial; /* the body is not visible to the scan */
} FxNode;

typedef struct Fx {
    MsArena *arena;
    const MsCheck *c;
    MsModId project;
    MsStr text; /* the project module's source */
    FxNode *nodes;
    MsReachNode *reach;
    uint32_t n, cap;
    uint32_t *index; /* by symbol id: node index + 1 */
    MsSourceLines *lines; /* by module */
    bool *have_lines;
    MsDirectives *header; /* by module */
} Fx;

static uint32_t fx_add(Fx *fx, MsSymId sym) {
    if (fx->index[sym] != 0) {
        return fx->index[sym] - 1;
    }
    if (fx->n == fx->cap) {
        const uint32_t cap = fx->cap == 0 ? 32 : fx->cap * 2;
        FxNode *nodes = MS_NEW_N(fx->arena, FxNode, cap);
        MsReachNode *reach = MS_NEW_N(fx->arena, MsReachNode, cap);
        if (fx->n != 0) {
            memcpy(nodes, fx->nodes, fx->n * sizeof *nodes);
            memcpy(reach, fx->reach, fx->n * sizeof *reach);
        }
        fx->nodes = nodes;
        fx->reach = reach;
        fx->cap = cap;
    }
    fx->nodes[fx->n] = (FxNode){.sym = sym};
    fx->reach[fx->n] = (MsReachNode){.id = fx->n};
    fx->index[sym] = fx->n + 1;
    return fx->n++;
}

static const MsSourceLines *fx_lines(Fx *fx, MsModId m) {
    if (!fx->have_lines[m]) {
        fx->lines[m] = ms_lines_index(fx->arena, m == fx->project ? fx->text : fx->c->mods[m].text);
        fx->header[m] = ms_lines_header(fx->arena, fx->lines[m]);
        fx->have_lines[m] = true;
    }
    return &fx->lines[m];
}

static MsSym fx_decl_name(const MsDecl *d) {
    switch (d->kind) {
    case MS_D_FN: return d->u.fn.name;
    case MS_D_CONST: return d->u.konst.name;
    default: return d->u.type.name;
    }
}

/* Fills node `i`: its directives, and its edges when the scan can read the body. */
static void fx_fill(Fx *fx, uint32_t i) {
    const MsCheck *c = fx->c;
    const MsSymId sym = fx->nodes[i].sym;
    const MsDecl *d = c->syms.decl[sym];
    const MsModId m = c->syms.module[sym];
    MsReachNode *node = &fx->reach[i];
    const MsStr name = ms_name(c->names, fx_decl_name(d));
    const MsSourceLines *lines = fx_lines(fx, m);
    const MsDirectives above = ms_lines_above(fx->arena, *lines, d->pos.line);
    node->file = ms_name(c->names, c->mods[m].path);
    node->label = name;
    node->pos = d->pos;
    node->project = m == fx->project;
    node->entry = node->project && name.len == 4 && memcmp(name.ptr, "main", 4) == 0;
    node->declared = above.declared.names;
    node->ndeclared = above.declared.count;
    node->allow_fn = above.allow;
    node->allow_file = fx->header[m].allow;
    const bool has_body = (d->kind == MS_D_FN && !d->u.fn.external) || d->kind == MS_D_CONST;
    if (!has_body || c->syms.native[sym] != MS_NATIVE_SOURCE) {
        return;
    }
    if (m == fx->project && c->mods[m].facts != NULL && c->mods[m].facts->body_checked != NULL &&
        c->mods[m].facts->body_checked[d->id]) {
        const MsScanNode scan = ms_effect_scan_decl(fx->arena, c, m, d);
        MsReachEdge *edges = MS_NEW_N(fx->arena, MsReachEdge, (size_t)scan.nedges + 1);
        for (uint32_t k = 0; k < scan.nedges; k++) {
            edges[k] = (MsReachEdge){.callee = fx_add(fx, scan.edges[k].callee), .pos = scan.edges[k].pos};
        }
        fx->reach[i].edges = edges; // `fx_add` may have moved the array: write through the index
        fx->reach[i].nedges = scan.nedges;
        fx->nodes[i].partial = scan.partial;
    } else if (node->ndeclared == 0) {
        fx->nodes[i].partial = true; // a body nobody has checked: what it reaches is unknown
    }
}

/* ---- call sites of one body ---- */

typedef struct Sites {
    const MsCheck *c;
    const MsFacts *facts;
    MsModId project;
    MsArena *arena;
    MsStr *calls, *external;
    uint32_t ncalls, nexternal, ccalls, cexternal;
    bool partial;
} Sites;

static void sites_push(Sites *s, MsStr **list, uint32_t *n, uint32_t *cap, MsStr text) {
    for (uint32_t i = 0; i < *n; i++) {
        if ((*list)[i].len == text.len && memcmp((*list)[i].ptr, text.ptr, text.len) == 0) {
            return;
        }
    }
    if (*n == *cap) {
        const uint32_t grown = *cap == 0 ? 8 : *cap * 2;
        MsStr *bigger = MS_NEW_N(s->arena, MsStr, grown);
        if (*n != 0) {
            memcpy(bigger, *list, *n * sizeof *bigger);
        }
        *list = bigger;
        *cap = grown;
    }
    (*list)[(*n)++] = text;
}

static void sites_expr(void *ctx, const MsExpr *e) {
    Sites *s = ctx;
    if (e->kind != MS_E_CALL) {
        return;
    }
    if (s->facts->call_method[e->id] != MS_NONE || s->facts->call_interface[e->id] != MS_TY_NONE) {
        s->partial = true;
        return;
    }
    const MsSymId callee = s->facts->call_callee[e->id];
    if (callee == MS_NONE) {
        s->partial = true; // a call through a value, or one the checker did not resolve
        return;
    }
    const MsDecl *d = s->c->syms.decl[callee];
    if (s->c->syms.module[callee] == s->project && d != NULL && d->kind == MS_D_FN) {
        sites_push(s, &s->calls, &s->ncalls, &s->ccalls, ms_name(s->c->names, s->c->syms.name[callee]));
    } else {
        sites_push(s, &s->external, &s->nexternal, &s->cexternal, ms_name(s->c->names, s->c->syms.id[callee]));
    }
}

static int fx_str_compare(const void *a, const void *b) {
    const MsStr x = *(const MsStr *)a, y = *(const MsStr *)b;
    const uint32_t common = x.len < y.len ? x.len : y.len;
    const int order = common == 0 ? 0 : memcmp(x.ptr, y.ptr, common);
    return order != 0 ? order : (x.len > y.len) - (x.len < y.len);
}

/* Whether `from` reaches a partial node. */
static bool fx_reaches_partial(const Fx *fx, uint32_t from, bool *seen) {
    if (seen[from]) {
        return false;
    }
    seen[from] = true;
    if (fx->nodes[from].partial) {
        return true;
    }
    for (uint32_t k = 0; k < fx->reach[from].nedges; k++) {
        if (fx_reaches_partial(fx, fx->reach[from].edges[k].callee, seen)) {
            return true;
        }
    }
    return false;
}

MsEntityEffects *ms_effect_facts(MsArena *arena, const MsCheck *c, MsModId module, MsStr text, uint32_t *count) {
    const MsModuleRow *row = &c->mods[module];
    *count = 0;
    if (row->facts == NULL || row->facts->body_checked == NULL) {
        return NULL;
    }
    Fx fx = {.arena = arena, .c = c, .project = module, .text = text};
    fx.index = MS_NEW_N(arena, uint32_t, (size_t)c->syms.count + 1);
    memset(fx.index, 0, ((size_t)c->syms.count + 1) * sizeof *fx.index);
    fx.lines = MS_NEW_N(arena, MsSourceLines, (size_t)c->nmods + 1);
    fx.have_lines = MS_NEW_N(arena, bool, (size_t)c->nmods + 1);
    memset(fx.have_lines, 0, ((size_t)c->nmods + 1) * sizeof *fx.have_lines);
    fx.header = MS_NEW_N(arena, MsDirectives, (size_t)c->nmods + 1);
    MsEntityEffects *rows = MS_NEW_N(arena, MsEntityEffects, (size_t)row->syntax->ndecls + 1);
    memset(rows, 0, ((size_t)row->syntax->ndecls + 1) * sizeof *rows);
    uint32_t *node_of = MS_NEW_N(arena, uint32_t, (size_t)row->syntax->ndecls + 1);
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        const MsDecl *d = row->syntax->decls[i];
        if ((d->kind != MS_D_FN && d->kind != MS_D_CONST) || !row->facts->body_checked[d->id]) {
            continue;
        }
        const MsSymId sym = ms_decl_own_symbol(c, module, d);
        if (sym == MS_NONE) {
            continue;
        }
        node_of[*count] = fx_add(&fx, sym);
        rows[*count].decl = d;
        (*count)++;
    }
    for (uint32_t i = 0; i < fx.n; i++) {
        fx_fill(&fx, i);
    }
    MsReach reach = {0};
    if (!ms_reach_resolve(arena, fx.reach, fx.n, &reach)) {
        *count = 0;
        return NULL;
    }
    bool *seen = MS_NEW_N(arena, bool, (size_t)fx.n + 1);
    for (uint32_t r = 0; r < *count; r++) {
        MsEntityEffects *out = &rows[r];
        const uint32_t node = node_of[r];
        memset(seen, 0, (size_t)fx.n * sizeof *seen);
        out->partial = fx_reaches_partial(&fx, node, seen);
        for (uint32_t k = 0; k < reach.ndeclared; k++) {
            if (reach.declared[k].node == node) {
                out->effects = reach.declared[k].effects;
                out->neffects = reach.declared[k].count;
            }
        }
        if (fx.reach == NULL) {
            continue;
        }
        const MsReachNode *n = &fx.reach[node];
        const MsEffectScope *permit = n->allow_fn.present ? &n->allow_fn : &n->allow_file;
        if (permit->present) {
            out->permits = permit->names;
            out->npermits = permit->count;
        }
        Sites sites = {.c = c, .facts = row->facts, .project = module, .arena = arena};
        const MsVisitor visitor = {.ctx = &sites, .expr = sites_expr};
        ms_walk_decl(&visitor, out->decl);
        if (sites.ncalls != 0) {
            qsort(sites.calls, sites.ncalls, sizeof *sites.calls, fx_str_compare);
        }
        if (sites.nexternal != 0) {
            qsort(sites.external, sites.nexternal, sizeof *sites.external, fx_str_compare);
        }
        out->calls = sites.calls;
        out->ncalls = sites.ncalls;
        out->external = sites.external;
        out->nexternal = sites.nexternal;
        out->partial = out->partial || sites.partial;
    }
    return rows;
}
