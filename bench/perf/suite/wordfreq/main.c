#include "common.h"

int main(void) {
    size_t len;
    char *data = read_stdin(&len);
    for (size_t i = 0; i < len; i++) if (data[i] >= 'A' && data[i] <= 'Z') data[i] += 32;
    Table counts; table_init(&counts);
    int64_t total = 0;
    size_t i = 0;
    while (i < len) {
        while (i < len && (data[i] == ' ' || data[i] == '.' || data[i] == '\n')) i++;
        size_t s = i;
        while (i < len && data[i] != ' ' && data[i] != '.' && data[i] != '\n') i++;
        if (i > s) { table_at(&counts, data + s, i - s)->count++; total++; }
    }
    printf("words: %lld\ndistinct: %zu\n", (long long)total, counts.used);
    Entry *r = ranked(&counts);
    for (int k = 0; k < 10; k++) printf("%.*s %lld\n", (int)r[k].len, r[k].key, (long long)r[k].count);
    return 0;
}
