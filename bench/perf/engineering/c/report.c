#include "common.h"

int main(void) {
    size_t len;
    char *data = read_stdin(&len);
    char *p = data, *end = data + len;
    long long total = 0;
    size_t cap = 1 << 20, n = 0;
    char *out = malloc(cap);
    while (p < end) {
        char *nl = memchr(p, '\n', end - p);
        if (!nl) nl = end;
        if (nl > p) {
            char *sp = memchr(p, ' ', nl - p);
            long long score = atoll(sp + 1);
            total += score;
            if (cap - n < 128 + (size_t)(sp - p)) out = realloc(out, cap *= 2);
            n += sprintf(out + n, "%-12.*s %8lld %lld\n", (int)(sp - p), p, score, score * 3 / 7);
        }
        p = nl + 1;
    }
    n += sprintf(out + n, "total %lld\n", total);
    fwrite(out, 1, n, stdout);
    return 0;
}
