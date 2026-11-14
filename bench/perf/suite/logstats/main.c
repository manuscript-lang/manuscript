#include "common.h"

int main(void) {
    size_t len;
    char *data = read_stdin(&len);
    int64_t rows = 0, latency = 0, classes[4] = {0};
    Table paths; table_init(&paths);
    char *p = data, *end = data + len;
    while (p < end) {
        char *nl = memchr(p, '\n', end - p);
        if (!nl) nl = end;
        if (nl > p) {
            char *f[6]; int n = 0; f[n++] = p;
            for (char *q = p; q < nl && n < 6; q++) if (*q == ' ') f[n++] = q + 1;
            rows++;
            latency += atoll(f[5]);
            classes[f[4][0] - '2']++;
            table_at(&paths, f[3], f[4] - 1 - f[3])->count++;
        }
        p = nl + 1;
    }
    printf("lines: %lld\nstatus: 2xx=%lld 3xx=%lld 4xx=%lld 5xx=%lld\nlatency: %lld\n", (long long)rows,
           (long long)classes[0], (long long)classes[1], (long long)classes[2], (long long)classes[3], (long long)latency);
    Entry *r = ranked(&paths);
    for (int i = 0; i < 5; i++) printf("%.*s %lld\n", (int)r[i].len, r[i].key, (long long)r[i].count);
    return 0;
}
