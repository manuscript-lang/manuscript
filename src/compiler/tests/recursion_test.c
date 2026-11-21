/* Unit test of the finite-application walk (src/compiler/src/check/recursion.c): every directed graph of
 * three generic declarations against the plain ancestor-sensitive traversal it replaces, the named
 * regressions of crates/ms-check/src/recursion/tests.rs, and type substitution. */
#include <stdio.h>
#include <string.h>

#include "ms/recursion.h"

static int failures;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

typedef struct Fixture {
    MsNames names;
    MsTyTable tys;
    MsArena arena;
    MsTy int_type;
} Fixture;

static void fixture_init(Fixture *f) {
    memset(f, 0, sizeof *f);
    ms_names_init(&f->names);
    ms_tys_init(&f->tys);
    MsTyDesc d = {0};
    d.name = d.id = ms_intern_cstr(&f->names, "Int");
    d.kind = MS_K_PRIMITIVE;
    f->int_type = ms_ty_intern(&f->tys, &d);
}

static void fixture_free(Fixture *f) {
    ms_tys_free(&f->tys);
    ms_names_free(&f->names);
    ms_arena_free(&f->arena);
}

static MsTy variable(Fixture *f, const char *id) {
    MsTyDesc d = {0};
    d.name = ms_intern_cstr(&f->names, "T");
    d.id = ms_intern_cstr(&f->names, id);
    d.kind = MS_K_VARIABLE;
    return ms_ty_fresh(&f->tys, &d);
}

static MsTy list_of(Fixture *f, MsTy element) {
    MsTyDesc d = {0};
    d.name = d.id = ms_intern_cstr(&f->names, "List");
    d.kind = MS_K_TYPE;
    d.args = &element;
    d.nargs = 1;
    return ms_ty_intern(&f->tys, &d);
}

static MsAppEdge edge_to(Fixture *f, uint32_t target, MsTy argument, uint32_t at) {
    MsTy *args = MS_NEW_N(&f->arena, MsTy, 1);
    args[0] = argument;
    MsAppEdge e = {args, {"", 0}, target, 1, ms_intern_cstr(&f->names, "graph.ms"), {at, at + 1, 1}};
    return e;
}

/* ---- the traversal the walk replaces: every path, no pruning, no memo ---- */

typedef struct Reference {
    Fixture *f;
    const MsAppNode *nodes;
    const MsTy **active_args;
    bool *active;
    uint32_t errors[64];
    size_t nerrors;
} Reference;

static void reference_visit(Reference *r, uint32_t id, const MsTy *args) {
    r->active[id] = true;
    r->active_args[id] = args;
    const MsAppNode *node = &r->nodes[id];
    MsTySubst subst = {node->variables, args, node->nvariables};
    for (uint32_t i = 0; i < node->nedges; i++) {
        const MsAppEdge *e = &node->edges[i];
        MsTy next = ms_ty_subst(&r->f->tys, &r->f->arena, e->args[0], &subst);
        if (r->active[e->target]) {
            if (r->active_args[e->target][0] != next) {
                r->errors[r->nerrors++] = e->pos.offset;
            }
            continue;
        }
        MsTy *copy = MS_NEW_N(&r->f->arena, MsTy, 1);
        copy[0] = next;
        reference_visit(r, e->target, copy);
    }
    r->active[id] = false;
}

static void test_three_node_graphs(void) {
    Fixture f;
    fixture_init(&f);
    const char *const ids[3] = {"a.T", "b.T", "c.T"};
    MsTy vars[3];
    MsTy lists[3];
    for (int i = 0; i < 3; i++) {
        vars[i] = variable(&f, ids[i]);
        lists[i] = list_of(&f, vars[i]);
    }
    int checked = 0;
    size_t total_faults = 0;
    for (int mask = 0; mask < 512; mask++) {
        for (int mode = 0; mode < 3; mode++) {
            for (int reversed = 0; reversed < 2; reversed++) {
                MsAppEdge edges[3][3];
                MsAppNode nodes[3];
                for (uint32_t i = 0; i < 3; i++) {
                    uint32_t n = 0;
                    for (uint32_t j = 0; j < 3; j++) {
                        if ((mask & (1 << (i * 3 + j))) == 0) {
                            continue;
                        }
                        MsTy arg = lists[i];
                        if (mode == 0) {
                            arg = vars[i];
                        } else if (mode == 1 && (i + j) % 2 == 0) {
                            arg = f.int_type;
                        }
                        edges[i][n++] = edge_to(&f, j, arg, i * 3 + j);
                    }
                    for (uint32_t k = 0; reversed != 0 && k < n / 2; k++) {
                        MsAppEdge swap = edges[i][k];
                        edges[i][k] = edges[i][n - 1 - k];
                        edges[i][n - 1 - k] = swap;
                    }
                    nodes[i] = (MsAppNode){&vars[i], edges[i], 1, n};
                }
                Reference r = {.f = &f, .nodes = nodes};
                const MsTy *active_args[3];
                bool active[3] = {false, false, false};
                r.active_args = active_args;
                r.active = active;
                for (uint32_t root = 0; root < 3; root++) {
                    reference_visit(&r, root, &vars[root]);
                }
                const MsAppFault *faults = NULL;
                size_t n = ms_check_applications(&f.arena, &f.tys, MS_APP_FUNCTIONS, nodes, 3, &faults);
                bool same = n == r.nerrors;
                for (size_t k = 0; same && k < n; k++) {
                    same = faults[k].edge->pos.offset == r.errors[k];
                }
                if (!same) {
                    fprintf(stderr, "mask=%d mode=%d reversed=%d: %zu faults, want %zu\n", mask, mode, reversed, n,
                            r.nerrors);
                }
                CHECK(same);
                total_faults += n;
                checked++;
            }
        }
    }
    CHECK(checked == 3072);
    CHECK(total_faults > 1000); /* the graphs do exercise the diagnostics */
    fixture_free(&f);
}

/* ---- regressions ---- */

static MsAppNode node_with(const MsTy *variable_ptr, const MsAppEdge *edges, uint32_t nedges) {
    return (MsAppNode){variable_ptr, edges, 1, nedges};
}

/* root[T]: b[Int]; a[List[T]]. a[T]: b[Int]. b[T]: a[Int]. */
static void test_ancestor_context(void) {
    Fixture f;
    fixture_init(&f);
    MsTy t[3] = {variable(&f, "root.T"), variable(&f, "a.T"), variable(&f, "b.T")};
    MsAppEdge root_edges[2] = {edge_to(&f, 2, f.int_type, 2), edge_to(&f, 1, list_of(&f, t[0]), 3)};
    MsAppEdge a_edges[1] = {edge_to(&f, 2, f.int_type, 6)};
    MsAppEdge b_edges[1] = {edge_to(&f, 1, f.int_type, 9)};
    MsAppNode nodes[3] = {node_with(&t[0], root_edges, 2), node_with(&t[1], a_edges, 1),
                          node_with(&t[2], b_edges, 1)};
    const MsAppFault *faults = NULL;
    size_t n = ms_check_applications(&f.arena, &f.tys, MS_APP_FUNCTIONS, nodes, 3, &faults);
    /* The checker deduplicates: the sites are 9 and 6, in that order. */
    CHECK(n >= 2);
    CHECK(n > 0 && faults[0].edge->pos.offset == 9);
    CHECK(n > 0 && faults[n - 1].edge->pos.offset == 6);
    for (size_t i = 0; i < n; i++) {
        CHECK(faults[i].edge->pos.offset == 9 || faults[i].edge->pos.offset == 6);
    }
    fixture_free(&f);
}

/* root[T]: fixed[Int]; fixed[T]; fixed[Int]; fixed[T]. fixed[T]: fixed[Int]. */
static void test_reused_success(void) {
    Fixture f;
    fixture_init(&f);
    MsTy t[2] = {variable(&f, "root.T"), variable(&f, "fixed.T")};
    MsAppEdge root_edges[4] = {edge_to(&f, 1, f.int_type, 2), edge_to(&f, 1, t[0], 3),
                               edge_to(&f, 1, f.int_type, 4), edge_to(&f, 1, t[0], 5)};
    MsAppEdge fixed_edges[1] = {edge_to(&f, 1, f.int_type, 8)};
    MsAppNode nodes[2] = {node_with(&t[0], root_edges, 4), node_with(&t[1], fixed_edges, 1)};
    const MsAppFault *faults = NULL;
    size_t n = ms_check_applications(&f.arena, &f.tys, MS_APP_FUNCTIONS, nodes, 2, &faults);
    CHECK(n > 0);
    for (size_t i = 0; i < n; i++) {
        CHECK(faults[i].edge->pos.offset == 8);
    }
    fixture_free(&f);
}

/* Forty branch levels are over a trillion paths but only 41 declarations; each level reaches the
 * next twice with its parameter preserved, and the last calls itself. No fault. */
static void test_branch_chain_is_linear(void) {
    enum { LEVELS = 40 };
    Fixture f;
    fixture_init(&f);
    MsTy vars[LEVELS + 1];
    MsAppNode nodes[LEVELS + 1];
    MsAppEdge edges[LEVELS + 1][2];
    for (uint32_t i = 0; i <= LEVELS; i++) {
        char id[16];
        snprintf(id, sizeof id, "f%u.T", i);
        vars[i] = variable(&f, id);
    }
    for (uint32_t i = 0; i <= LEVELS; i++) {
        uint32_t next = i == LEVELS ? i : i + 1;
        edges[i][0] = edge_to(&f, next, vars[i], i * 2);
        edges[i][1] = edge_to(&f, next, vars[i], i * 2 + 1);
        nodes[i] = node_with(&vars[i], edges[i], i == LEVELS ? 1 : 2);
    }
    const MsAppFault *faults = NULL;
    CHECK(ms_check_applications(&f.arena, &f.tys, MS_APP_FUNCTIONS, nodes, LEVELS + 1, &faults) == 0);
    fixture_free(&f);
}

/* A type that nests itself with a changed argument is reported once, at its field. */
static void test_type_modes(void) {
    Fixture f;
    fixture_init(&f);
    MsTy t = variable(&f, "Node.T");
    MsAppEdge preserved = edge_to(&f, 0, t, 1);
    preserved.site = (MsStr){"Node.next", 9};
    MsAppEdge changed = edge_to(&f, 0, list_of(&f, t), 2);
    changed.site = (MsStr){"Node.kids", 9};
    MsAppEdge edges[2] = {preserved, changed};
    MsAppNode node = node_with(&t, edges, 2);
    const MsAppFault *faults = NULL;
    size_t n = ms_check_applications(&f.arena, &f.tys, MS_APP_TYPES, &node, 1, &faults);
    CHECK(n == 1);
    MsStr message = n == 1 ? ms_application_message(&f.arena, MS_APP_TYPES, faults[0].edge) : (MsStr){"", 0};
    CHECK(strstr(message.ptr, "preserve their parameters in Node.kids; keep the same") != NULL);
    fixture_free(&f);
}

int main(void) {
    test_three_node_graphs();
    test_ancestor_context();
    test_reused_success();
    test_branch_chain_is_linear();
    test_type_modes();
    if (failures != 0) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    puts("recursion: ok");
    return 0;
}
