/* Unit test of runtime/sys: reservations, regions, guards and the clock. Run by `make c-test`. */
#include <stdio.h>
#include <stdlib.h>

#include "ms_sys.h"

#define CHECK(c)                                                  \
    do {                                                          \
        if (!(c)) {                                               \
            fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #c); \
            exit(1);                                              \
        }                                                         \
    } while (0)

int main(void) {
    size_t page = 4096, len = (size_t)1 << 20;

    uint8_t *p = mssys_map_anon(len);
    CHECK(p != NULL);
    CHECK(mssys_commit(p, len));
    for (size_t i = 0; i < len; i += page) {
        CHECK(p[i] == 0);
        p[i] = 1;
    }
    mssys_prefer_huge_pages(p, len);
    mssys_release(p, len);
    CHECK(mssys_commit(p, len));
    p[0] = 2; /* usable again after release and commit */
    mssys_unmap(p, len);

    /* Regions are aligned to their size, and several coexist. */
    uint8_t *r[4];
    for (int i = 0; i < 4; i++) {
        r[i] = mssys_map_region(len);
        CHECK(r[i] != NULL);
        CHECK((uintptr_t)r[i] % len == 0);
        CHECK(mssys_commit(r[i] + len - page, page));
        r[i][len - 1] = (uint8_t)i;
    }
    for (int i = 0; i < 4; i++) {
        for (int j = i + 1; j < 4; j++) {
            CHECK(r[i] != r[j]);
        }
    }
    /* A guard at the bottom of a region, then its commit_guard no-op or guard page. */
    CHECK(mssys_guard(r[0], page));
    for (int i = 0; i < 4; i++) {
        CHECK(r[i][len - 1] == (uint8_t)i);
        mssys_unmap(r[i], len);
    }

    int64_t a = mssys_monotonic_ns();
    int64_t b = mssys_monotonic_ns();
    CHECK(a > 0 && b >= a);
    puts("sys_mem ok");
    return 0;
}
