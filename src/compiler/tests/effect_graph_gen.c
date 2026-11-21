/* effect_graph_gen SEED: prints one random reference graph in the text form of
 * crates/ms-check/examples/c_oracle_effects.rs. Graphs have cycles, duplicate labels and edges,
 * edges to unknown ids, more than 64 effect names, every kind of scope, and sometimes enough nodes
 * that the shared path search takes over from the per-violation one. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint64_t state;

static uint32_t below(uint32_t limit) {
    state = state * 6364136223846793005ull + 1442695040888963407ull;
    return (uint32_t)(state >> 33) % limit;
}

static void print_effect(uint32_t pool) {
    static const char *const areas[] = {"std.fs", "std.net", "db", "std.time", "x.y.z"};
    static const char *const verbs[] = {"read", "write", "connect", "list"};
    uint32_t k = below(pool);
    printf(" %s.%s%s", areas[k % 5], verbs[(k / 5) % 4], k >= 20 ? (const char *[]){"1", "2", "3", "4", "5"}[(k / 20) % 5] : "");
}

static void print_scope(const char *keyword, uint32_t pool) {
    static const char *const patterns[] = {"*", "std.fs.*", "std.net.*", "*.read", "*.write", "db.write", "x.*", "std.*"};
    printf("%s", keyword);
    uint32_t n = below(4);
    for (uint32_t i = 0; i < n; i++) {
        if (below(2) != 0) {
            printf(" %s", patterns[below(8)]);
        } else {
            print_effect(pool);
        }
    }
    putchar('\n');
}

static void print_node(uint32_t i, uint32_t count, uint32_t pool, uint32_t labels, uint32_t density) {
    printf("node n%u L%u f%u.ms %u %u %u %s %s\n", i, below(labels), below(3), below(50) + 1, below(20) + 1,
           below(1000), below(5) == 0 ? "library" : "project", below(12) == 0 ? "entry" : "plain");
    if (below(6) == 0) {
        fputs("declared", stdout);
        uint32_t n = below(3) + 1;
        for (uint32_t d = 0; d < n; d++) {
            print_effect(pool);
        }
        putchar('\n');
    }
    if (below(3) == 0) {
        print_scope("allow_fn", pool);
    }
    if (below(4) == 0) {
        print_scope("allow_file", pool);
    }
    if (below(10) == 0) {
        print_scope("cap", pool);
    }
    uint32_t edges = below(density + 1);
    for (uint32_t e = 0; e < edges; e++) {
        printf("edge n%u %u %u %u\n", below(count + count / 10 + 1), below(50) + 1, below(20) + 1, below(1000));
    }
}

int main(int argc, char **argv) {
    state = argc > 1 ? strtoull(argv[1], NULL, 10) * 2654435761u + 1 : 1;
    uint32_t big = below(8) == 0;
    uint32_t count = big ? 150 + below(150) : below(40) + 1;
    uint32_t pool = below(4) == 0 ? 120 : below(25) + 1;
    uint32_t labels = below(3) == 0 ? 3 : count + 1;
    uint32_t density = big ? 3 : below(5) + 1;
    for (uint32_t i = 0; i < count; i++) {
        print_node(i, count, pool, labels, density);
    }
    return 0;
}
