#include "common.h"

int main(void) {
    size_t len;
    char *data = read_stdin(&len);
    Table lines, names; table_init(&lines); table_init(&names);
    int64_t total = 0;
    char *p = data, *end = data + len;
    while (p < end) {
        char *nl = memchr(p, '\n', end - p);
        if (!nl) nl = end;
        if (nl > p) {
            total++;
            table_at(&lines, p, nl - p)->count++;
            char *sp = memchr(p, ' ', nl - p);
            table_at(&names, p, (sp ? sp : nl) - p)->count++;
        }
        p = nl + 1;
    }
    Entry *best = NULL;
    for (size_t i = 0; i < lines.used; i++) {
        Entry *e = &lines.slots[i];
        if (!e->key) continue;
        if (!best || e->count > best->count) { best = e; continue; }
        if (e->count == best->count) {
            size_t n = e->len < best->len ? e->len : best->len;
            int c = memcmp(e->key, best->key, n);
            if (c < 0 || (c == 0 && e->len < best->len)) best = e;
        }
    }
    printf("lines: %lld\ndistinct lines: %zu\ndistinct names: %zu\nmost repeated: %.*s x%lld\n", (long long)total, lines.used, names.used, (int)best->len, best->key, (long long)best->count);
    return 0;
}
