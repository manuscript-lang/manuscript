/* Effect reach: propagates declared effects through a reference graph and finds the project
 * callables that reach an effect no scope permits.
 *
 * Effect names are numbered by sorted order, each node owns a fixed-width slice of one flat
 * bit array, and propagation is a worklist over caller lists. Mirrors
 * crates/ms-check/src/effect_reach.rs. */
#include <stdlib.h>
#include <string.h>

#include "ms/effects.h"

#define NO_NODE UINT32_MAX

/* ---- bit rows: one fixed-width row of 64-bit words per node ---- */

typedef struct BitRows {
    uint32_t words; /* per row */
    uint64_t *data; /* rows * words */
} BitRows;

static BitRows bit_rows_new(MsArena *arena, uint32_t rows, uint32_t words) {
    size_t total = (size_t)rows * words;
    uint64_t *data = ms_alloc(arena, total * sizeof(uint64_t), _Alignof(uint64_t));
    memset(data, 0, total * sizeof(uint64_t));
    return (BitRows){words, data};
}

static bool bit_has(const BitRows *rows, uint32_t row, uint32_t bit) {
    return (rows->data[(size_t)row * rows->words + bit / 64] >> (bit % 64) & 1u) != 0;
}

static void bit_set(BitRows *rows, uint32_t row, uint32_t bit) {
    rows->data[(size_t)row * rows->words + bit / 64] |= (uint64_t)1 << (bit % 64);
}

static bool row_any(const BitRows *rows, uint32_t row) {
    for (uint32_t w = 0; w < rows->words; w++) {
        if (rows->data[(size_t)row * rows->words + w] != 0) {
            return true;
        }
    }
    return false;
}

/* ---- effect names: sorted, deduplicated ---- */

static int effect_name_compare(MsStr a, MsStr b) {
    uint32_t common = a.len < b.len ? a.len : b.len;
    int order = common == 0 ? 0 : memcmp(a.ptr, b.ptr, common);
    if (order != 0) {
        return order;
    }
    if (a.len == b.len) {
        return 0;
    }
    return a.len < b.len ? -1 : 1;
}

static int effect_name_compare_ptr(const void *a, const void *b) {
    return effect_name_compare(*(const MsStr *)a, *(const MsStr *)b);
}

typedef struct EffectNames {
    MsStr *names;
    uint32_t count;
} EffectNames;

static EffectNames collect_effect_names(MsArena *arena, const MsReachNode *nodes, uint32_t count) {
    uint32_t total = 0;
    for (uint32_t i = 0; i < count; i++) {
        total += nodes[i].ndeclared;
    }
    MsStr *names = MS_NEW_N(arena, MsStr, total);
    uint32_t filled = 0;
    for (uint32_t i = 0; i < count; i++) {
        for (uint32_t d = 0; d < nodes[i].ndeclared; d++) {
            names[filled++] = nodes[i].declared[d];
        }
    }
    if (total != 0) {
        qsort(names, total, sizeof *names, effect_name_compare_ptr);
    }
    uint32_t unique = 0;
    for (uint32_t i = 0; i < total; i++) {
        if (unique == 0 || effect_name_compare(names[unique - 1], names[i]) != 0) {
            names[unique++] = names[i];
        }
    }
    return (EffectNames){names, unique};
}

static uint32_t effect_slot(const EffectNames *effects, MsStr name) {
    uint32_t low = 0;
    uint32_t high = effects->count;
    while (low < high) {
        uint32_t middle = low + (high - low) / 2;
        int order = effect_name_compare(effects->names[middle], name);
        if (order == 0) {
            return middle;
        }
        if (order < 0) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return NO_NODE; /* unreachable: every declared name was collected */
}

/* ---- the graph in flat form ---- */

typedef struct IdSlot {
    uint32_t id, node;
} IdSlot;

typedef struct Graph {
    const MsReachNode *nodes;
    uint32_t count;
    IdSlot *slots;             /* node ids with their node index, sorted by id */
    uint32_t *caller_start;    /* CSR: callers of node c are callers[caller_start[c] .. caller_start[c + 1]] */
    uint32_t *callers;
    BitRows declared, inner, out;
} Graph;

/* The node with this id, or NO_NODE. */
static uint32_t reach_node_of(const Graph *graph, uint32_t id) {
    uint32_t low = 0;
    uint32_t high = graph->count;
    while (low < high) {
        uint32_t middle = low + (high - low) / 2;
        if (graph->slots[middle].id == id) {
            return graph->slots[middle].node;
        }
        if (graph->slots[middle].id < id) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return NO_NODE;
}

static int compare_slots(const void *a, const void *b) {
    const IdSlot *x = a;
    const IdSlot *y = b;
    if (x->id == y->id) {
        return 0;
    }
    return x->id < y->id ? -1 : 1;
}

/* Sorts the ids for lookup; false when two nodes share one. */
static bool build_index(MsArena *arena, Graph *graph) {
    graph->slots = MS_NEW_N(arena, IdSlot, graph->count);
    for (uint32_t i = 0; i < graph->count; i++) {
        graph->slots[i] = (IdSlot){graph->nodes[i].id, i};
    }
    if (graph->count > 1) {
        qsort(graph->slots, graph->count, sizeof *graph->slots, compare_slots);
    }
    for (uint32_t i = 1; i < graph->count; i++) {
        if (graph->slots[i].id == graph->slots[i - 1].id) {
            return false;
        }
    }
    return true;
}

/* Fills the caller lists: a node with an edge to c is a caller of c (once per edge). */
static void build_callers(MsArena *arena, Graph *graph) {
    uint32_t *start = MS_NEW_N(arena, uint32_t, (size_t)graph->count + 1);
    memset(start, 0, ((size_t)graph->count + 1) * sizeof *start);
    for (uint32_t i = 0; i < graph->count; i++) {
        for (uint32_t e = 0; e < graph->nodes[i].nedges; e++) {
            uint32_t callee = reach_node_of(graph, graph->nodes[i].edges[e].callee);
            if (callee != NO_NODE) {
                start[callee + 1]++;
            }
        }
    }
    for (uint32_t c = 0; c < graph->count; c++) {
        start[c + 1] += start[c];
    }
    uint32_t *callers = MS_NEW_N(arena, uint32_t, start[graph->count]);
    uint32_t *fill = MS_NEW_N(arena, uint32_t, graph->count);
    memcpy(fill, start, graph->count * sizeof *fill);
    for (uint32_t i = 0; i < graph->count; i++) {
        for (uint32_t e = 0; e < graph->nodes[i].nedges; e++) {
            uint32_t callee = reach_node_of(graph, graph->nodes[i].edges[e].callee);
            if (callee != NO_NODE) {
                callers[fill[callee]++] = i;
            }
        }
    }
    graph->caller_start = start;
    graph->callers = callers;
}

/* ---- propagation ---- */

/* Folds the effects each callee shows into its callers until stable. A caller that declares
 * effects of its own keeps showing only those. */
static void propagate(MsArena *arena, Graph *graph) {
    uint32_t words = graph->declared.words;
    uint32_t *work = MS_NEW_N(arena, uint32_t, graph->count);
    bool *queued = MS_NEW_N(arena, bool, graph->count);
    uint32_t pending = 0;
    for (uint32_t i = 0; i < graph->count; i++) {
        queued[i] = row_any(&graph->declared, i);
        if (queued[i]) {
            work[pending++] = i;
        }
    }
    while (pending > 0) {
        uint32_t callee = work[--pending];
        queued[callee] = false;
        for (uint32_t k = graph->caller_start[callee]; k < graph->caller_start[callee + 1]; k++) {
            uint32_t caller = graph->callers[k];
            bool keep_own = row_any(&graph->declared, caller);
            bool grew = false;
            for (uint32_t w = 0; w < words; w++) {
                uint64_t incoming = graph->out.data[(size_t)callee * words + w];
                uint64_t fresh = incoming & ~graph->inner.data[(size_t)caller * words + w];
                if (fresh == 0) {
                    continue;
                }
                graph->inner.data[(size_t)caller * words + w] |= fresh;
                if (!keep_own) {
                    graph->out.data[(size_t)caller * words + w] |= fresh;
                    grew = true;
                }
            }
            if (grew && !queued[caller]) {
                queued[caller] = true;
                work[pending++] = caller;
            }
        }
    }
}

/* ---- paths ---- */

typedef struct Candidate {
    uint32_t node;
} Candidate;

/* Scratch for the search for the shortest chain of references to a declaring callable. Marks carry
 * a generation, so each search starts clean without clearing arrays. */
typedef struct Search {
    uint32_t *parent;
    uint32_t *seen; /* generation in which a node was reached */
    uint32_t generation;
    uint32_t *queue;
    Candidate *step;  /* the candidates of one step, sorted by label */
    Candidate *spare; /* the sort's second buffer */
    size_t searched;  /* work done, as nodes plus edges visited */
} Search;

static bool label_before_or_equal(const MsReachNode *nodes, Candidate a, Candidate b) {
    return effect_name_compare(nodes[a.node].label, nodes[b.node].label) <= 0;
}

/* Stable merge sort by label (equal labels keep their order). */
static void sort_by_label(const MsReachNode *nodes, Search *search, uint32_t count) {
    for (uint32_t width = 1; width < count; width *= 2) {
        for (uint32_t low = 0; low < count; low += 2 * width) {
            uint32_t middle = low + width < count ? low + width : count;
            uint32_t high = low + 2 * width < count ? low + 2 * width : count;
            uint32_t left = low;
            uint32_t right = middle;
            for (uint32_t out = low; out < high; out++) {
                bool take_left = right >= high ||
                                 (left < middle && label_before_or_equal(nodes, search->step[left], search->step[right]));
                search->spare[out] = take_left ? search->step[left++] : search->step[right++];
            }
        }
        memcpy(search->step, search->spare, (size_t)count * sizeof *search->step);
    }
}

static Search search_new(MsArena *arena, uint32_t count) {
    Search search = {0};
    search.parent = MS_NEW_N(arena, uint32_t, count);
    search.seen = MS_NEW_N(arena, uint32_t, count);
    memset(search.seen, 0, (size_t)count * sizeof *search.seen);
    search.queue = MS_NEW_N(arena, uint32_t, count);
    search.step = MS_NEW_N(arena, Candidate, count);
    search.spare = MS_NEW_N(arena, Candidate, count);
    return search;
}

/* Puts the callees of `at` that carry `bit`, are not `start` and are not yet reached into
 * search->step, sorted by label. Returns how many. */
static uint32_t step_candidates(const Graph *graph, Search *search, uint32_t at, uint32_t start,
                                uint32_t bit) {
    const MsReachNode *node = &graph->nodes[at];
    uint32_t found = 0;
    for (uint32_t e = 0; e < node->nedges; e++) {
        uint32_t callee = reach_node_of(graph, node->edges[e].callee);
        bool usable = callee != NO_NODE && callee != start && bit_has(&graph->out, callee, bit) &&
                      search->seen[callee] != search->generation;
        if (usable) {
            search->step[found++] = (Candidate){callee};
        }
    }
    sort_by_label(graph->nodes, search, found);
    return found;
}

/* Writes the chain ending at `last` (via parent links) into path, start first. Returns its length. */
static uint32_t unwind(const Search *search, uint32_t last, uint32_t start, uint32_t *path) {
    uint32_t length = 0;
    for (uint32_t at = last;; at = search->parent[at]) {
        path[length++] = at;
        if (at == start) {
            break;
        }
    }
    for (uint32_t i = 0; i < length / 2; i++) {
        uint32_t swap = path[i];
        path[i] = path[length - 1 - i];
        path[length - 1 - i] = swap;
    }
    return length;
}

/* The shortest chain of references from `start` to a callable that declares effect `bit`, ties
 * broken by label. Written to `path`; returns its length (1 when none is found). */
static uint32_t path_to(const Graph *graph, Search *search, uint32_t start, uint32_t bit,
                        uint32_t *path) {
    search->generation++;
    search->seen[start] = search->generation;
    search->parent[start] = start;
    uint32_t head = 0;
    uint32_t tail = 0;
    search->queue[tail++] = start;
    while (head < tail) {
        uint32_t at = search->queue[head++];
        search->searched += 1 + (size_t)graph->nodes[at].nedges;
        uint32_t found = step_candidates(graph, search, at, start, bit);
        for (uint32_t i = 0; i < found; i++) {
            uint32_t callee = search->step[i].node;
            if (search->seen[callee] == search->generation) {
                continue; /* the same callee listed twice */
            }
            search->seen[callee] = search->generation;
            search->parent[callee] = at;
            if (bit_has(&graph->declared, callee, bit)) {
                return unwind(search, callee, start, path);
            }
            search->queue[tail++] = callee;
        }
    }
    path[0] = start;
    return 1;
}

/* Shortest suffix per node for one effect, shared by every violation of that effect. */
typedef struct SharedPaths {
    uint32_t *next; /* by node: the callee on its shortest chain, or NO_NODE */
} SharedPaths;

static void shared_distances(const Graph *graph, Search *search, uint32_t bit, uint32_t *distance) {
    uint32_t head = 0;
    uint32_t tail = 0;
    for (uint32_t i = 0; i < graph->count; i++) {
        distance[i] = NO_NODE;
        if (bit_has(&graph->declared, i, bit)) {
            distance[i] = 0;
            search->queue[tail++] = i;
        }
    }
    while (head < tail) {
        uint32_t callee = search->queue[head++];
        for (uint32_t k = graph->caller_start[callee]; k < graph->caller_start[callee + 1]; k++) {
            uint32_t caller = graph->callers[k];
            if (distance[caller] == NO_NODE && bit_has(&graph->out, caller, bit)) {
                distance[caller] = distance[callee] + 1;
                search->queue[tail++] = caller;
            }
        }
    }
}

static bool closer(const Graph *graph, const uint32_t *distance, uint32_t candidate, uint32_t old) {
    if (old == NO_NODE || distance[candidate] < distance[old]) {
        return true;
    }
    return distance[candidate] == distance[old] &&
           effect_name_compare(graph->nodes[candidate].label, graph->nodes[old].label) < 0;
}

static SharedPaths shared_paths_new(MsArena *arena, const Graph *graph, Search *search, uint32_t bit) {
    uint32_t *distance = MS_NEW_N(arena, uint32_t, graph->count);
    shared_distances(graph, search, bit, distance);
    SharedPaths shared = {MS_NEW_N(arena, uint32_t, graph->count)};
    for (uint32_t i = 0; i < graph->count; i++) {
        shared.next[i] = NO_NODE;
        for (uint32_t e = 0; e < graph->nodes[i].nedges; e++) {
            uint32_t callee = reach_node_of(graph, graph->nodes[i].edges[e].callee);
            if (callee == NO_NODE || callee == i || distance[callee] == NO_NODE) {
                continue;
            }
            if (closer(graph, distance, callee, shared.next[i])) {
                shared.next[i] = callee;
            }
        }
    }
    return shared;
}

/* The chain from `start` along `next` links to a declaring callable. A cycle back to `start`
 * cannot justify a declaration's own body, so that case falls back to the full search. */
static uint32_t shared_path(const Graph *graph, Search *search, const SharedPaths *shared,
                            uint32_t start, uint32_t bit, uint32_t *path) {
    uint32_t length = 0;
    path[length++] = start;
    uint32_t at = start;
    for (;;) {
        uint32_t next = shared->next[at];
        if (next == NO_NODE || next == start) {
            return path_to(graph, search, start, bit, path);
        }
        path[length++] = next;
        if (bit_has(&graph->declared, next, bit)) {
            return length;
        }
        at = next;
    }
}

/* ---- violations ---- */

static bool scope_permits(MsEffectScope scope, MsStr effect) {
    if (!scope.present) {
        return true;
    }
    for (uint32_t i = 0; i < scope.count; i++) {
        if (ms_effect_matches(scope.names[i], effect)) {
            return true;
        }
    }
    return false;
}

/* Whether the project callable may reach `effect`: every scope that was written must allow it,
 * and a callable with no scope at all may reach nothing. */
static bool may_reach(const MsReachNode *node, MsStr effect) {
    bool unscoped = !node->allow_fn.present && !node->allow_file.present;
    return !unscoped && scope_permits(node->cap, effect) && scope_permits(node->allow_fn, effect) &&
           scope_permits(node->allow_file, effect);
}

typedef struct Found {
    uint32_t node;
    uint32_t order; /* the sequence the violation was found in, so equal nodes keep effect order */
    MsViolation violation;
} Found;

static int compare_found(const void *a, const void *b) {
    const Found *x = a;
    const Found *y = b;
    if (x->node != y->node) {
        return x->node < y->node ? -1 : 1;
    }
    if (x->order == y->order) {
        return 0;
    }
    return x->order < y->order ? -1 : 1;
}

/* Where the violating node first references the next callable of its chain. */
static MsPos violation_pos(const Graph *graph, uint32_t node, const uint32_t *path, uint32_t length) {
    const MsReachNode *from = &graph->nodes[node];
    uint32_t first = length > 1 ? path[1] : node;
    for (uint32_t e = 0; e < from->nedges; e++) {
        if (reach_node_of(graph, from->edges[e].callee) == first) {
            return from->edges[e].pos;
        }
    }
    return from->pos;
}

typedef struct Resolver {
    MsArena *arena;   /* scratch space, freed when resolving ends */
    MsArena *results; /* what the caller keeps */
    Graph graph;
    EffectNames effects;
    Search search;
    uint32_t *path;
    size_t budget; /* once searches cost a graph traversal, share the work per effect */
} Resolver;

static void add_violation(Resolver *r, MsBuf *found, uint32_t node, uint32_t bit,
                          const uint32_t *path, uint32_t length) {
    uint32_t *copy = MS_NEW_N(r->results, uint32_t, length);
    memcpy(copy, path, (size_t)length * sizeof *copy);
    Found row = {
        .node = node,
        .order = (uint32_t)(found->len / sizeof(Found)),
        .violation = {
            .file = r->graph.nodes[node].file,
            .pos = violation_pos(&r->graph, node, path, length),
            .effect = r->effects.names[bit],
            .path = copy,
            .npath = length,
        },
    };
    ms_buf_put(found, &row, sizeof row);
}

/* The violations of one effect: every project node in `starts` reaches it without permission. */
static void report_effect(Resolver *r, MsBuf *found, uint32_t bit, const uint32_t *starts,
                          uint32_t nstarts) {
    bool shared_ready = false;
    SharedPaths shared = {0};
    r->search.searched = 0;
    for (uint32_t s = 0; s < nstarts; s++) {
        uint32_t length = 0;
        if (!shared_ready && r->search.searched > r->budget) {
            shared = shared_paths_new(r->arena, &r->graph, &r->search, bit);
            shared_ready = true;
        }
        if (shared_ready) {
            length = shared_path(&r->graph, &r->search, &shared, starts[s], bit, r->path);
        } else {
            length = path_to(&r->graph, &r->search, starts[s], bit, r->path);
        }
        add_violation(r, found, starts[s], bit, r->path, length);
    }
}

/* The project nodes that reach effect `bit` without permission, in node order. */
static uint32_t unpermitted_for(const Resolver *r, uint32_t bit, uint32_t *starts) {
    uint32_t count = 0;
    for (uint32_t i = 0; i < r->graph.count; i++) {
        const MsReachNode *node = &r->graph.nodes[i];
        if (!node->project || node->entry || !bit_has(&r->graph.inner, i, bit)) {
            continue;
        }
        if (!may_reach(node, r->effects.names[bit])) {
            starts[count++] = i;
        }
    }
    return count;
}

static void collect_violations(Resolver *r, MsReach *out) {
    MsBuf found = {0};
    uint32_t *starts = MS_NEW_N(r->arena, uint32_t, r->graph.count);
    for (uint32_t bit = 0; bit < r->effects.count; bit++) {
        uint32_t nstarts = unpermitted_for(r, bit, starts);
        report_effect(r, &found, bit, starts, nstarts);
    }
    uint32_t total = (uint32_t)(found.len / sizeof(Found));
    if (total > 1) {
        qsort(found.data, total, sizeof(Found), compare_found);
    }
    MsViolation *rows = MS_NEW_N(r->results, MsViolation, total);
    for (uint32_t i = 0; i < total; i++) {
        Found row;
        memcpy(&row, found.data + (size_t)i * sizeof row, sizeof row);
        rows[i] = row.violation;
    }
    ms_buf_free(&found);
    out->violations = rows;
    out->nviolations = total;
}

/* ---- results ---- */

static void collect_declared(Resolver *r, MsReach *out) {
    MsReachDeclared *rows = MS_NEW_N(r->results, MsReachDeclared, r->graph.count);
    uint32_t filled = 0;
    for (uint32_t i = 0; i < r->graph.count; i++) {
        if (!row_any(&r->graph.out, i)) {
            continue;
        }
        MsStr *names = MS_NEW_N(r->results, MsStr, r->effects.count);
        uint32_t count = 0;
        for (uint32_t bit = 0; bit < r->effects.count; bit++) {
            if (bit_has(&r->graph.out, i, bit)) {
                names[count++] = r->effects.names[bit];
            }
        }
        rows[filled++] = (MsReachDeclared){i, names, count};
    }
    out->declared = rows;
    out->ndeclared = filled;
}

/* Seeds the rows with each node's own declared effects: they are what callers see, and what the
 * node itself is held to reach. */
static void seed_declared(Resolver *r) {
    Graph *graph = &r->graph;
    for (uint32_t i = 0; i < graph->count; i++) {
        for (uint32_t d = 0; d < graph->nodes[i].ndeclared; d++) {
            uint32_t bit = effect_slot(&r->effects, graph->nodes[i].declared[d]);
            bit_set(&graph->declared, i, bit);
            bit_set(&graph->out, i, bit);
        }
    }
}

bool ms_reach_resolve(MsArena *arena, const MsReachNode *nodes, uint32_t count, MsReach *out) {
    MsArena scratch = {0};
    Resolver r = {.arena = &scratch, .results = arena, .graph = {.nodes = nodes, .count = count}};
    bool ok = build_index(&scratch, &r.graph);
    MsReach result = {0};
    r.effects = collect_effect_names(&scratch, nodes, count);
    if (ok && r.effects.count != 0) {
        uint32_t words = (r.effects.count + 63) / 64;
        r.graph.declared = bit_rows_new(&scratch, count, words);
        r.graph.inner = bit_rows_new(&scratch, count, words);
        r.graph.out = bit_rows_new(&scratch, count, words);
        build_callers(&scratch, &r.graph);
        seed_declared(&r);
        propagate(&scratch, &r.graph);
        r.search = search_new(&scratch, count);
        r.path = MS_NEW_N(&scratch, uint32_t, count);
        r.budget = count;
        for (uint32_t i = 0; i < count; i++) {
            r.budget += nodes[i].nedges;
        }
        collect_declared(&r, &result);
        collect_violations(&r, &result);
    }
    ms_arena_free(&scratch);
    if (ok) {
        *out = result;
    }
    return ok;
}
