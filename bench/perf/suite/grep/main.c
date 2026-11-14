#define _GNU_SOURCE
#include "common.h"

int main(void) {
    size_t len;
    char *data = read_stdin(&len);
    int64_t hits = 0;
    char *p = data, *end = data + len;
    while (p < end) {
        char *nl = memchr(p, '\n', end - p);
        if (!nl) nl = end;
        if (memmem(p, nl - p, " POST /api/v2/item/17", 21) && memmem(p, nl - p, " 500 ", 5)) hits++;
        p = nl + 1;
    }
    printf("hits: %lld\n", (long long)hits);
    return 0;
}
