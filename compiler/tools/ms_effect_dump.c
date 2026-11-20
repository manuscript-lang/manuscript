/* ms_effect_dump graph < GRAPH | ms_effect_dump directives FILE...
 *
 * Prints what the effect graph and directive code gives, in the form
 * crates/ms-check/examples/c_oracle_effects.rs prints, so the two can be compared. The graph text
 * is described there. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/effects.h"
#include "dump_io.h"

static char *read_all(FILE *file, size_t *length) {
    size_t cap = 4096;
    char *text = malloc(cap);
    *length = 0;
    for (size_t n; (n = fread(text + *length, 1, cap - *length, file)) > 0;) {
        *length += n;
        if (*length == cap) {
            cap *= 2;
            text = realloc(text, cap);
        }
    }
    return text;
}

static void print_list(const MsEffectScope *scope) {
    putchar('[');
    for (uint32_t i = 0; i < scope->count; i++) {
        printf("%s%.*s", i ? "," : "", (int)scope->names[i].len, scope->names[i].ptr);
    }
    putchar(']');
}

static void print_directives(const char *label, const MsDirectives *d) {
    printf("%s declared=", label);
    print_list(&d->declared);
    fputs(" allow=", stdout);
    if (d->allow.present) {
        print_list(&d->allow);
    } else {
        fputs("none", stdout);
    }
    putchar('\n');
}

static int directives_main(int argc, char **argv) {
    for (int a = 0; a < argc; a++) {
        FILE *file = fopen(argv[a], "rb");
        if (file == NULL) {
            fprintf(stderr, "cannot read %s\n", argv[a]);
            return 1;
        }
        size_t length = 0;
        char *text = read_all(file, &length);
        fclose(file);
        MsArena arena = {0};
        MsSourceLines lines = ms_lines_index(&arena, (MsStr){text, (uint32_t)length});
        printf("file %s\n", argv[a]);
        MsDirectives header = ms_lines_header(&arena, lines);
        print_directives("header", &header);
        for (uint32_t line = 1; line <= lines.count; line++) {
            MsDirectives found = ms_lines_above(&arena, lines, line);
            char label[32];
            snprintf(label, sizeof label, "above %u", line);
            if (found.declared.count != 0 || found.allow.present) {
                print_directives(label, &found);
            }
        }
        ms_arena_free(&arena);
        free(text);
    }
    return 0;
}

/* ---- graph text ---- */

typedef struct Tokens {
    char *word[16];
    int count;
} Tokens;

static void split_line(char *line, Tokens *t) {
    t->count = 0;
    for (char *p = line; *p != 0 && t->count < 16;) {
        p += strspn(p, " \t\r");
        if (*p == 0) break;
        t->word[t->count++] = p;
        p += strcspn(p, " \t\r");
        if (*p != 0) *p++ = 0;
    }
}


static MsPos pos_of(char **w) {
    return (MsPos){.line = (uint32_t)atoi(w[0]), .column = (uint32_t)atoi(w[1]), .offset = (uint32_t)atoi(w[2])};
}

/* Interns a graph id such as `a` or `load` into a dense number, in order of first sight. */
static uint32_t id_of(MsNames *names, char *word) { return ms_intern_cstr(names, word); }

static MsEffectScope scope_of(MsArena *arena, Tokens *t) {
    MsStr *names = MS_NEW_N(arena, MsStr, t->count);
    for (int i = 1; i < t->count; i++) {
        names[i - 1] = (MsStr){ms_arena_strndup(arena, t->word[i], strlen(t->word[i])), (uint32_t)strlen(t->word[i])};
    }
    return (MsEffectScope){names, (uint32_t)(t->count - 1), true};
}

static void print_result(const MsNames *names, const MsReachNode *nodes, const MsReach *reach) {
    for (uint32_t i = 0; i < reach->ndeclared; i++) {
        const MsReachDeclared *d = &reach->declared[i];
        MsStr id = ms_name(names, nodes[d->node].id);
        printf("declared %.*s:", (int)id.len, id.ptr);
        for (uint32_t e = 0; e < d->count; e++) {
            printf("%s%.*s", e ? " " : " ", (int)d->effects[e].len, d->effects[e].ptr);
        }
        putchar('\n');
    }
    for (uint32_t i = 0; i < reach->nviolations; i++) {
        const MsViolation *v = &reach->violations[i];
        printf("violation %.*s %u:%u:%u %.*s: ", (int)v->file.len, v->file.ptr, v->pos.line, v->pos.column,
               v->pos.offset, (int)v->effect.len, v->effect.ptr);
        for (uint32_t p = 0; p < v->npath; p++) {
            MsStr label = nodes[v->path[p]].label;
            printf("%s%.*s", p ? " > " : "", (int)label.len, label.ptr);
        }
        putchar('\n');
    }
}

typedef struct NodeList {
    MsReachNode *items;
    uint32_t count, cap;
} NodeList;

typedef struct EdgeList {
    MsReachEdge *items;
    uint32_t count, cap;
} EdgeList;

static void *grown(void *items, uint32_t count, uint32_t *cap, size_t size) {
    if (count < *cap) {
        return items;
    }
    *cap = *cap ? *cap * 2 : 64;
    void *bigger = realloc(items, (size_t)*cap * size);
    if (bigger == NULL) {
        abort();
    }
    return bigger;
}

/* One line of graph text applied to the node list being built. */
static void apply_line(MsArena *arena, MsNames *names, NodeList *nodes, EdgeList *edges, Tokens *t) {
    MsReachNode *node = nodes->count ? &nodes->items[nodes->count - 1] : NULL;
    if (t->count == 0) {
        return;
    }
    if (strcmp(t->word[0], "node") == 0) {
        MsReachNode fresh = {.id = id_of(names, t->word[1]), .label = str_of(t->word[2]),
                             .file = str_of(t->word[3]), .pos = pos_of(t->word + 4),
                             .project = strcmp(t->word[7], "project") == 0,
                             .entry = strcmp(t->word[8], "entry") == 0};
        nodes->items = grown(nodes->items, nodes->count, &nodes->cap, sizeof *nodes->items);
        nodes->items[nodes->count++] = fresh;
    } else if (strcmp(t->word[0], "declared") == 0) {
        MsEffectScope s = scope_of(arena, t);
        node->declared = s.names;
        node->ndeclared = s.count;
    } else if (strcmp(t->word[0], "allow_fn") == 0) {
        node->allow_fn = scope_of(arena, t);
    } else if (strcmp(t->word[0], "allow_file") == 0) {
        node->allow_file = scope_of(arena, t);
    } else if (strcmp(t->word[0], "cap") == 0) {
        node->cap = scope_of(arena, t);
    } else if (strcmp(t->word[0], "edge") == 0) {
        MsReachEdge edge = {.callee = id_of(names, t->word[1]), .pos = pos_of(t->word + 2)};
        edges->items = grown(edges->items, edges->count, &edges->cap, sizeof *edges->items);
        edges->items[edges->count++] = edge;
        node->nedges++;
    }
}

/* Edges were collected in one run in node order; give each node its slice. */
static void attach_edges(MsReachNode *nodes, uint32_t count, const MsReachEdge *edges) {
    uint32_t at = 0;
    for (uint32_t i = 0; i < count; i++) {
        nodes[i].edges = edges + at;
        at += nodes[i].nedges;
    }
}

static int graph_main(void) {
    size_t length = 0;
    char *text = read_all(stdin, &length);
    text = realloc(text, length + 1);
    text[length] = '\0';
    MsArena arena = {0};
    MsNames names;
    ms_names_init(&names);
    NodeList nodes = {0};
    EdgeList edges = {0};
    for (char *line = text, *next; line != NULL && *line != '\0'; line = next) {
        next = strchr(line, '\n');
        if (next != NULL) {
            *next++ = '\0';
        }
        Tokens t;
        split_line(line, &t);
        apply_line(&arena, &names, &nodes, &edges, &t);
    }
    attach_edges(nodes.items, nodes.count, edges.items);
    MsReach reach = {0};
    if (!ms_reach_resolve(&arena, nodes.items, nodes.count, &reach)) {
        fputs("duplicate node id\n", stderr);
        return 1;
    }
    print_result(&names, nodes.items, &reach);
    free(nodes.items);
    free(edges.items);
    ms_names_free(&names);
    ms_arena_free(&arena);
    free(text);
    return 0;
}

int main(int argc, char **argv) {
    if (argc >= 2 && strcmp(argv[1], "graph") == 0) {
        return graph_main();
    }
    if (argc >= 2 && strcmp(argv[1], "directives") == 0) {
        return directives_main(argc - 2, argv + 2);
    }
    fputs("usage: ms_effect_dump graph | directives FILE...\n", stderr);
    return 2;
}
