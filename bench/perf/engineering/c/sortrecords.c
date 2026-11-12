#include "common.h"

typedef struct { const char *name; size_t len; int64_t score; } Rec;

static int cmp(const void *a, const void *b) {
    const Rec *x = a, *y = b;
    if (x->score != y->score) return x->score < y->score ? 1 : -1;
    size_t n = x->len < y->len ? x->len : y->len;
    int c = memcmp(x->name, y->name, n);
    if (c) return c;
    return x->len < y->len ? -1 : x->len > y->len;
}

int main(void) {
    size_t len;
    char *data = read_stdin(&len);
    size_t cap = 1 << 16, n = 0;
    Rec *recs = malloc(cap * sizeof(Rec));
    char *p = data, *end = data + len;
    while (p < end) {
        char *nl = memchr(p, '\n', end - p);
        if (!nl) nl = end;
        if (nl > p) {
            char *sp = memchr(p, ' ', nl - p);
            if (n == cap) recs = realloc(recs, (cap *= 2) * sizeof(Rec));
            recs[n++] = (Rec){ p, (size_t)(sp - p), atoll(sp + 1) };
        }
        p = nl + 1;
    }
    qsort(recs, n, sizeof(Rec), cmp);
    int64_t check = 0;
    for (size_t i = 0; i < n; i++) check = (check * 31 + recs[i].score + (int64_t)i) % 1000000007;
    printf("records: %zu\nchecksum: %lld\n", n, (long long)check);
    size_t idx[4] = {0, 1, 2, n - 1};
    for (int k = 0; k < 4; k++) printf("%.*s %lld\n", (int)recs[idx[k]].len, recs[idx[k]].name, (long long)recs[idx[k]].score);
    return 0;
}
