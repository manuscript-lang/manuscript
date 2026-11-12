#include "common.h"

// Parses RFC 4180 records in place: fields are copied into `row`, quotes and doubled quotes removed.
typedef struct { char *p; size_t len; } Field;

int main(void) {
    size_t len;
    char *data = read_stdin(&len);
    char *p = data, *end = data + len;
    Table regions; table_init(&regions);
    Table products; table_init(&products);
    int64_t rows = 0, quoted = 0;
    int header = 1;
    while (p < end) {
        Field f[6]; int n = 0;
        while (1) {
            char *start = p; char *out = p; size_t flen;
            if (p < end && *p == '"') {
                p++; out = start;
                while (p < end) {
                    if (*p == '"') { if (p + 1 < end && p[1] == '"') { *out++ = '"'; p += 2; continue; } p++; break; }
                    *out++ = *p++;
                }
                flen = out - start;
            } else {
                while (p < end && *p != ',' && *p != '\n') p++;
                flen = p - start;
            }
            if (n < 6) { f[n].p = start; f[n].len = flen; n++; }
            if (p >= end || *p == '\n') { p++; break; }
            p++; // comma
        }
        if (header) { header = 0; continue; }
        if (n < 6) continue;
        int64_t cents = atoll(f[3].p) * atoll(f[4].p);
        Entry *r = table_at(&regions, f[1].p, f[1].len); r->count++; r->sum += cents;
        table_at(&products, f[2].p, f[2].len)->sum += cents;
        if (memchr(f[5].p, ',', f[5].len)) quoted++;
        rows++;
    }
    printf("rows: %lld\nquoted: %lld\n", (long long)rows, (long long)quoted);
    Entry *rr = ranked(&regions);
    // regions by name ascending
    for (size_t i = 0; i < regions.used; i++)
        for (size_t j = i + 1; j < regions.used; j++) {
            size_t k = rr[i].len < rr[j].len ? rr[i].len : rr[j].len;
            int c = memcmp(rr[i].key, rr[j].key, k);
            if (c > 0 || (c == 0 && rr[i].len > rr[j].len)) { Entry t = rr[i]; rr[i] = rr[j]; rr[j] = t; }
        }
    for (size_t i = 0; i < regions.used; i++) printf("%.*s %lld %lld\n", (int)rr[i].len, rr[i].key, (long long)rr[i].count, (long long)rr[i].sum);
    for (size_t i = 0; i < products.used; i++) products.slots[i].count = 0;
    Entry *pp = malloc(products.used * sizeof(Entry)); size_t k = 0;
    for (size_t i = 0; i < products.used; i++) if (products.slots[i].key) { pp[k] = products.slots[i]; pp[k].count = pp[k].sum; k++; }
    qsort(pp, k, sizeof(Entry), by_count_then_key);
    for (int i = 0; i < 5; i++) printf("%.*s %lld\n", (int)pp[i].len, pp[i].key, (long long)pp[i].count);
    return 0;
}
