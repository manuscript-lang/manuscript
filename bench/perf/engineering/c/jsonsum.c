#include "common.h"

// A generic JSON tree in an arena: every value is a node; children of an array or object are
// linked through `next`, and an object member's key is stored in the member node.
enum { NUL, BOOL, NUM, STR, ARR, OBJ };
typedef struct { int type; int64_t num; char *str; size_t len; int first, last, next; char *key; size_t klen; } Node;

static Node *nodes; static size_t nnodes, ncap;
static const char *p, *end;

static int new_node(int type) {
    if (nnodes == ncap) nodes = realloc(nodes, (ncap = ncap ? ncap * 2 : 1024) * sizeof(Node));
    nodes[nnodes] = (Node){ .type = type, .first = -1, .last = -1, .next = -1 };
    return (int)nnodes++;
}

static void skip(void) { while (p < end && (*p == ' ' || *p == '\n' || *p == '\t' || *p == '\r')) p++; }

static char *parse_string(size_t *len) {
    p++; // opening quote
    char *out = malloc(end - p > 0 ? 1 : 1), *w = out; size_t cap = 1;
    const char *s = p;
    while (p < end && *p != '"') { if (*p == '\\') p++; p++; }
    cap = (size_t)(p - s) + 1;
    out = realloc(out, cap); w = out;
    for (const char *q = s; q < p; q++) {
        if (*q == '\\') { q++; switch (*q) { case 'n': *w++ = '\n'; break; case 't': *w++ = '\t'; break; default: *w++ = *q; } }
        else *w++ = *q;
    }
    p++; // closing quote
    *len = w - out;
    return out;
}

static int parse_value(void) {
    skip();
    if (*p == '{' || *p == '[') {
        int obj = *p == '{';
        int n = new_node(obj ? OBJ : ARR);
        p++; skip();
        if (*p == (obj ? '}' : ']')) { p++; return n; }
        while (1) {
            skip();
            char *key = NULL; size_t klen = 0;
            if (obj) { key = parse_string(&klen); skip(); p++; /* colon */ }
            int v = parse_value();
            nodes[v].key = key; nodes[v].klen = klen;
            if (nodes[n].first < 0) nodes[n].first = v; else nodes[nodes[n].last].next = v;
            nodes[n].last = v;
            skip();
            if (*p == ',') { p++; continue; }
            p++; // closing bracket
            return n;
        }
    }
    if (*p == '"') { int n = new_node(STR); nodes[n].str = parse_string(&nodes[n].len); return n; }
    if (*p == 't') { p += 4; int n = new_node(BOOL); nodes[n].num = 1; return n; }
    if (*p == 'f') { p += 5; int n = new_node(BOOL); return n; }
    if (*p == 'n') { p += 4; return new_node(NUL); }
    int n = new_node(NUM);
    char *e; nodes[n].num = strtoll(p, &e, 10); p = e;
    return n;
}

static Node *member(int obj, const char *name) {
    for (int c = nodes[obj].first; c >= 0; c = nodes[c].next)
        if (nodes[c].klen == strlen(name) && !memcmp(nodes[c].key, name, nodes[c].klen)) return &nodes[c];
    return NULL;
}

int main(void) {
    size_t len;
    char *data = read_stdin(&len);
    p = data; end = data + len;
    int root = parse_value();
    Table scores; table_init(&scores);
    Table tags; table_init(&tags);
    int64_t records = 0, active = 0, name_bytes = 0;
    for (int r = nodes[root].first; r >= 0; r = nodes[r].next) {
        records++;
        Node *user = member(r, "user"), *score = member(r, "score"), *act = member(r, "active"), *name = member(r, "name");
        table_at(&scores, user->str, user->len)->sum += score->num;
        for (int t = member(r, "tags")->first; t >= 0; t = nodes[t].next) table_at(&tags, nodes[t].str, nodes[t].len)->count++;
        if (act->num) active++;
        // Length in scalars; the generated names are ASCII.
        name_bytes += name->len;
    }
    printf("records: %lld\nactive: %lld\nname bytes: %lld\n", (long long)records, (long long)active, (long long)name_bytes);
    Entry *pp = malloc(scores.used * sizeof(Entry)); size_t k = 0;
    for (size_t i = 0; i < scores.used; i++) if (scores.slots[i].key) { pp[k] = scores.slots[i]; pp[k].count = pp[k].sum; k++; }
    qsort(pp, k, sizeof(Entry), by_count_then_key);
    for (int i = 0; i < 5; i++) printf("%.*s %lld\n", (int)pp[i].len, pp[i].key, (long long)pp[i].count);
    // tags by name ascending
    Entry *tt = ranked(&tags);
    for (size_t i = 0; i < tags.used; i++)
        for (size_t j = i + 1; j < tags.used; j++)
            if (strncmp(tt[i].key, tt[j].key, tt[i].len < tt[j].len ? tt[i].len : tt[j].len) > 0 || (!strncmp(tt[i].key, tt[j].key, tt[i].len < tt[j].len ? tt[i].len : tt[j].len) && tt[i].len > tt[j].len)) { Entry t = tt[i]; tt[i] = tt[j]; tt[j] = t; }
    for (size_t i = 0; i < tags.used; i++) printf("%.*s %lld\n", (int)tt[i].len, tt[i].key, (long long)tt[i].count);
    return 0;
}
