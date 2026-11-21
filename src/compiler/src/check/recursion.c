/* Finite generic applications; see ms/recursion.h. A port of the graph walk of
 * crates/ms-check/src/recursion.rs: sink pruning, strongly connected components, and the
 * ancestor-aware traversal that reports an edge whose type arguments differ from those of the
 * active declaration it returns to. */
#include <stdlib.h>
#include <string.h>

#include "ms/recursion.h"

/* ---- sets of integer sequences ---- */

/* A set of u32 sequences, stored in the arena as [length, values...]; open addressed. */
typedef struct KeySet {
    MsArena *arena;
    const uint32_t **slots; /* owned: NULL for empty */
    uint32_t mask;
    uint32_t count;
} KeySet;

static uint32_t hash_key(const uint32_t *values, uint32_t length) {
    uint32_t h = 2166136261u;
    for (uint32_t i = 0; i < length; i++) {
        h = (h ^ values[i]) * 16777619u;
    }
    return h;
}

static bool key_equals(const uint32_t *stored, const uint32_t *values, uint32_t length) {
    return stored[0] == length && memcmp(stored + 1, values, (size_t)length * sizeof(uint32_t)) == 0;
}

static void keyset_init(KeySet *set, MsArena *arena) {
    set->arena = arena;
    set->mask = 63;
    set->count = 0;
    set->slots = calloc((size_t)set->mask + 1, sizeof *set->slots);
    if (set->slots == NULL) {
        abort();
    }
}

static void keyset_free(KeySet *set) {
    free(set->slots);
    set->slots = NULL;
}

static void keyset_grow(KeySet *set) {
    uint32_t size = (set->mask + 1) * 2;
    const uint32_t **slots = calloc(size, sizeof *slots);
    if (slots == NULL) {
        abort();
    }
    for (uint32_t i = 0; i <= set->mask; i++) {
        const uint32_t *key = set->slots[i];
        if (key == NULL) {
            continue;
        }
        uint32_t at = hash_key(key + 1, key[0]) & (size - 1);
        while (slots[at] != NULL) {
            at = (at + 1) & (size - 1);
        }
        slots[at] = key;
    }
    free(set->slots);
    set->slots = slots;
    set->mask = size - 1;
}

static bool keyset_contains(const KeySet *set, const uint32_t *values, uint32_t length) {
    uint32_t at = hash_key(values, length) & set->mask;
    while (set->slots[at] != NULL) {
        if (key_equals(set->slots[at], values, length)) {
            return true;
        }
        at = (at + 1) & set->mask;
    }
    return false;
}

/* Adds the sequence; false when it was already there. */
static bool keyset_add(KeySet *set, const uint32_t *values, uint32_t length) {
    if (keyset_contains(set, values, length)) {
        return false;
    }
    uint32_t *copy = MS_NEW_N(set->arena, uint32_t, (size_t)length + 1);
    copy[0] = length;
    memcpy(copy + 1, values, (size_t)length * sizeof(uint32_t));
    uint32_t at = hash_key(values, length) & set->mask;
    while (set->slots[at] != NULL) {
        at = (at + 1) & set->mask;
    }
    set->slots[at] = copy;
    set->count++;
    if ((size_t)set->count * 2 > set->mask) {
        keyset_grow(set);
    }
    return true;
}

/* ---- the graph ---- */

typedef struct AppGraph {
    MsArena *arena;
    MsTyTable *tys;
    const MsAppNode *nodes;
    uint32_t count;
    bool *recursive;                 /* by node: can reach a cycle */
    const MsAppEdge **edges;         /* the edges that lead to a recursive node, by node */
    uint32_t *edge_start;            /* count + 1 offsets into edges */
    uint32_t *component;             /* by node: strongly connected component */
} AppGraph;

/* Marks the nodes that can reach a directed cycle: removing sinks also removes their incoming
 * edges, and what remains is the part of the graph that can reach an active ancestor. */
static void find_recursive(AppGraph *g) {
    uint32_t *degree = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 1);
    uint32_t *pred_start = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 2);
    memset(pred_start, 0, ((size_t)g->count + 2) * sizeof *pred_start);
    for (uint32_t id = 0; id < g->count; id++) {
        degree[id] = g->nodes[id].nedges;
        for (uint32_t e = 0; e < g->nodes[id].nedges; e++) {
            pred_start[g->nodes[id].edges[e].target + 2]++;
        }
    }
    for (uint32_t i = 2; i <= g->count + 1; i++) {
        pred_start[i] += pred_start[i - 1];
    }
    uint32_t total = pred_start[g->count + 1];
    uint32_t *preds = MS_NEW_N(g->arena, uint32_t, (size_t)total + 1);
    for (uint32_t id = 0; id < g->count; id++) {
        for (uint32_t e = 0; e < g->nodes[id].nedges; e++) {
            preds[pred_start[g->nodes[id].edges[e].target + 1]++] = id;
        }
    }
    uint32_t *sinks = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 1);
    uint32_t nsinks = 0;
    for (uint32_t id = 0; id < g->count; id++) {
        if (degree[id] == 0) {
            sinks[nsinks++] = id;
        }
    }
    while (nsinks > 0) {
        uint32_t id = sinks[--nsinks];
        for (uint32_t i = pred_start[id]; i < pred_start[id + 1]; i++) {
            if (--degree[preds[i]] == 0) {
                sinks[nsinks++] = preds[i];
            }
        }
    }
    g->recursive = MS_NEW_N(g->arena, bool, (size_t)g->count + 1);
    for (uint32_t id = 0; id < g->count; id++) {
        g->recursive[id] = degree[id] != 0;
    }
}

/* Keeps only the edges that lead to a recursive node, in their original order. */
static void prune_edges(AppGraph *g) {
    size_t total = 0;
    for (uint32_t id = 0; id < g->count; id++) {
        total += g->nodes[id].nedges;
    }
    g->edges = MS_NEW_N(g->arena, const MsAppEdge *, total + 1);
    g->edge_start = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 1);
    uint32_t kept = 0;
    for (uint32_t id = 0; id < g->count; id++) {
        g->edge_start[id] = kept;
        for (uint32_t e = 0; e < g->nodes[id].nedges; e++) {
            const MsAppEdge *edge = &g->nodes[id].edges[e];
            if (g->recursive[edge->target]) {
                g->edges[kept++] = edge;
            }
        }
    }
    g->edge_start[g->count] = kept;
}

/* Depth-first finish order of the pruned graph (iterative, so a long chain cannot overflow). */
static uint32_t *finish_order(AppGraph *g) {
    uint32_t *order = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 1);
    bool *seen = MS_NEW_N(g->arena, bool, (size_t)g->count + 1);
    memset(seen, 0, (size_t)g->count + 1);
    uint32_t *stack = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 1);
    uint32_t *next_edge = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 1);
    uint32_t done = 0;
    for (uint32_t root = 0; root < g->count; root++) {
        if (seen[root]) {
            continue;
        }
        uint32_t depth = 0;
        stack[depth++] = root;
        seen[root] = true;
        next_edge[root] = g->edge_start[root];
        while (depth > 0) {
            uint32_t id = stack[depth - 1];
            if (next_edge[id] == g->edge_start[id + 1]) {
                order[done++] = id;
                depth--;
                continue;
            }
            uint32_t target = g->edges[next_edge[id]++]->target;
            if (!seen[target]) {
                seen[target] = true;
                next_edge[target] = g->edge_start[target];
                stack[depth++] = target;
            }
        }
    }
    return order;
}

/* Strongly connected components, without expanding type arguments (Kosaraju). */
static void find_components(AppGraph *g) {
    uint32_t *order = finish_order(g);
    uint32_t *rev_start = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 2);
    memset(rev_start, 0, ((size_t)g->count + 2) * sizeof *rev_start);
    for (uint32_t i = 0; i < g->edge_start[g->count]; i++) {
        rev_start[g->edges[i]->target + 2]++;
    }
    for (uint32_t i = 2; i <= g->count + 1; i++) {
        rev_start[i] += rev_start[i - 1];
    }
    uint32_t *rev = MS_NEW_N(g->arena, uint32_t, (size_t)g->edge_start[g->count] + 1);
    for (uint32_t id = 0; id < g->count; id++) {
        for (uint32_t i = g->edge_start[id]; i < g->edge_start[id + 1]; i++) {
            rev[rev_start[g->edges[i]->target + 1]++] = id;
        }
    }
    g->component = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 1);
    memset(g->component, 0xff, ((size_t)g->count + 1) * sizeof *g->component);
    uint32_t *stack = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 1);
    uint32_t components = 0;
    for (uint32_t k = g->count; k > 0; k--) {
        uint32_t root = order[k - 1];
        if (g->component[root] != UINT32_MAX) {
            continue;
        }
        uint32_t depth = 0;
        stack[depth++] = root;
        g->component[root] = components;
        while (depth > 0) {
            uint32_t id = stack[--depth];
            for (uint32_t i = rev_start[id]; i < rev_start[id + 1]; i++) {
                if (g->component[rev[i]] == UINT32_MAX) {
                    g->component[rev[i]] = components;
                    stack[depth++] = rev[i];
                }
            }
        }
        components++;
    }
}

/* ---- the walk ---- */

typedef struct AppWalk {
    AppGraph *g;
    MsAppMode mode;
    const MsTy **active_args; /* by node: the arguments it is applied to, while it is active */
    uint32_t *active_nargs;
    bool *active;
    uint32_t *chain;          /* active nodes, outermost first */
    uint32_t depth;
    KeySet completed;         /* functions: applications known to be fine */
    KeySet visited;           /* types: specializations already explored */
    KeySet reported;          /* types: edges already reported */
    MsBuf faults;             /* MsAppFault */
} AppWalk;

static const MsAppNode *node_of(const AppWalk *w, uint32_t id) {
    return &w->g->nodes[id];
}

static bool same_args(const MsTy *a, const MsTy *b, uint32_t count) {
    return count == 0 || memcmp(a, b, (size_t)count * sizeof *a) == 0;
}

/* The arguments of an edge with the variables of `id` replaced by `args`. */
static MsTy *edge_arguments(AppWalk *w, uint32_t id, const MsTy *args, uint32_t nargs, const MsAppEdge *edge) {
    const MsAppNode *node = node_of(w, id);
    MsTySubst subst = {node->variables, args, node->nvariables < nargs ? node->nvariables : nargs};
    MsTy *next = MS_NEW_N(w->g->arena, MsTy, (size_t)edge->nargs + 1);
    for (uint32_t i = 0; i < edge->nargs; i++) {
        next[i] = ms_ty_subst(w->g->tys, w->g->arena, edge->args[i], &subst);
    }
    return next;
}

static void report_fault(AppWalk *w, const MsAppEdge *edge) {
    MsAppFault fault = {edge};
    ms_buf_put(&w->faults, &fault, sizeof fault);
}

/* ---- functions ---- */

/* The key of applying `id` to `args` while the chain is active: only the active ancestors of the same
 * component can be reached back, so only they affect any cycle comparison. */
static const uint32_t *application_key(AppWalk *w, uint32_t id, const MsTy *args, uint32_t nargs,
                                       uint32_t *length) {
    const AppGraph *g = w->g;
    uint32_t *ancestors = MS_NEW_N(g->arena, uint32_t, (size_t)w->depth + 1);
    uint32_t nancestors = 0;
    for (uint32_t i = 0; i < w->depth; i++) {
        if (g->component[w->chain[i]] == g->component[id]) {
            uint32_t at = nancestors++;
            while (at > 0 && ancestors[at - 1] > w->chain[i]) {
                ancestors[at] = ancestors[at - 1];
                at--;
            }
            ancestors[at] = w->chain[i];
        }
    }
    size_t size = 3 + nargs;
    for (uint32_t i = 0; i < nancestors; i++) {
        size += 2 + w->active_nargs[ancestors[i]];
    }
    uint32_t *key = MS_NEW_N(g->arena, uint32_t, size + 1);
    uint32_t n = 0;
    key[n++] = id;
    key[n++] = nargs;
    for (uint32_t i = 0; i < nargs; i++) {
        key[n++] = args[i];
    }
    key[n++] = nancestors;
    for (uint32_t i = 0; i < nancestors; i++) {
        uint32_t ancestor = ancestors[i];
        uint32_t count = w->active_nargs[ancestor];
        key[n++] = ancestor;
        key[n++] = count;
        for (uint32_t k = 0; k < count; k++) {
            key[n++] = w->active_args[ancestor][k];
        }
    }
    *length = n;
    return key;
}

static bool visit_application(AppWalk *w, uint32_t id, const MsTy *args, uint32_t nargs);

/* One use inside the active declaration `id`; false when it changes the arguments of a cycle. */
static bool visit_edge(AppWalk *w, uint32_t id, const MsTy *args, uint32_t nargs, const MsAppEdge *edge) {
    MsTy *next = edge_arguments(w, id, args, nargs, edge);
    if (w->active[edge->target]) {
        bool equal = w->active_nargs[edge->target] == edge->nargs &&
                     same_args(w->active_args[edge->target], next, edge->nargs);
        if (!equal) {
            report_fault(w, edge);
        }
        return equal;
    }
    return visit_application(w, edge->target, next, edge->nargs);
}

static bool visit_application(AppWalk *w, uint32_t id, const MsTy *args, uint32_t nargs) {
    if (w->active[id]) {
        return true;
    }
    uint32_t key_length = 0;
    const uint32_t *key = application_key(w, id, args, nargs, &key_length);
    if (keyset_contains(&w->completed, key, key_length)) {
        return true;
    }
    bool valid = true;
    w->active[id] = true;
    w->active_args[id] = args;
    w->active_nargs[id] = nargs;
    w->chain[w->depth++] = id;
    for (uint32_t i = w->g->edge_start[id]; i < w->g->edge_start[id + 1]; i++) {
        valid = visit_edge(w, id, args, nargs, w->g->edges[i]) && valid;
    }
    w->depth--;
    w->active[id] = false;
    /* Reusing failures would suppress or reorder diagnostics at their original sites. */
    if (valid) {
        (void)keyset_add(&w->completed, key, key_length);
    }
    return valid;
}

/* ---- types ---- */

static void visit_type_application(AppWalk *w, uint32_t id, const MsTy *args, uint32_t nargs);

/* Reports the edge once, when it changes the arguments of the active declaration it returns to. */
static void visit_type_edge(AppWalk *w, uint32_t id, const MsTy *args, uint32_t nargs, const MsAppEdge *edge) {
    MsTy *next = edge_arguments(w, id, args, nargs, edge);
    if (!w->active[edge->target]) {
        visit_type_application(w, edge->target, next, edge->nargs);
        return;
    }
    bool equal = w->active_nargs[edge->target] == edge->nargs &&
                 same_args(w->active_args[edge->target], next, edge->nargs);
    uint32_t site[4] = {edge->file, edge->pos.offset, edge->pos.line, edge->pos.column};
    if (!equal && keyset_add(&w->reported, site, MS_COUNT_OF(site))) {
        report_fault(w, edge);
    }
}

static void visit_type_application(AppWalk *w, uint32_t id, const MsTy *args, uint32_t nargs) {
    /* Shared dependencies need checking once for each specialization; active cycles are checked at
     * the edge before this cache is consulted. */
    uint32_t *key = MS_NEW_N(w->g->arena, uint32_t, (size_t)nargs + 1);
    key[0] = id;
    memcpy(key + 1, args, (size_t)nargs * sizeof *args);
    if (!keyset_add(&w->visited, key, nargs + 1)) {
        return;
    }
    w->active[id] = true;
    w->active_args[id] = args;
    w->active_nargs[id] = nargs;
    for (uint32_t i = w->g->edge_start[id]; i < w->g->edge_start[id + 1]; i++) {
        visit_type_edge(w, id, args, nargs, w->g->edges[i]);
    }
    w->active[id] = false;
}

/* ---- entry point ---- */

static void app_walk_init(AppWalk *w, AppGraph *g, MsAppMode mode) {
    memset(w, 0, sizeof *w);
    w->g = g;
    w->mode = mode;
    w->active_args = MS_NEW_N(g->arena, const MsTy *, (size_t)g->count + 1);
    w->active_nargs = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 1);
    w->active = MS_NEW_N(g->arena, bool, (size_t)g->count + 1);
    memset(w->active, 0, (size_t)g->count + 1);
    w->chain = MS_NEW_N(g->arena, uint32_t, (size_t)g->count + 1);
    keyset_init(&w->completed, g->arena);
    keyset_init(&w->visited, g->arena);
    keyset_init(&w->reported, g->arena);
}

static void app_walk_roots(AppWalk *w) {
    for (uint32_t root = 0; root < w->g->count; root++) {
        if (!w->g->recursive[root]) {
            continue;
        }
        const MsAppNode *node = node_of(w, root);
        if (w->mode == MS_APP_FUNCTIONS) {
            (void)visit_application(w, root, node->variables, node->nvariables);
        } else {
            visit_type_application(w, root, node->variables, node->nvariables);
        }
    }
}

size_t ms_check_applications(MsArena *arena, MsTyTable *tys, MsAppMode mode, const MsAppNode *nodes,
                             uint32_t count, const MsAppFault **faults) {
    AppGraph g = {.arena = arena, .tys = tys, .nodes = nodes, .count = count};
    /* An acyclic suffix cannot produce a diagnostic: prune it, which keeps shared suffixes from
     * being walked once per path. */
    find_recursive(&g);
    prune_edges(&g);
    find_components(&g);
    AppWalk w;
    app_walk_init(&w, &g, mode);
    app_walk_roots(&w);
    size_t n = MS_VEC_LEN(w.faults, MsAppFault);
    MsAppFault *result = MS_NEW_N(arena, MsAppFault, n + 1);
    if (n != 0) {
        memcpy(result, ms_buf_items(&w.faults), n * sizeof *result);
    }
    ms_buf_free(&w.faults);
    keyset_free(&w.completed);
    keyset_free(&w.visited);
    keyset_free(&w.reported);
    *faults = result;
    return n;
}

MsStr ms_application_message(MsArena *arena, MsAppMode mode, const MsAppEdge *edge) {
    if (mode == MS_APP_FUNCTIONS) {
        return ms_arena_fmt(arena,
                            "recursive generic applications must preserve their parameters; a type may refer to "
                            "itself only with the same type arguments (e.g. List[Node[T]] inside Node[T])");
    }
    return ms_arena_fmt(arena,
                        "recursive generic applications must preserve their parameters in %.*s; keep the same "
                        "type arguments in the same positions along a recursive cycle",
                        (int)edge->site.len, edge->site.ptr);
}
