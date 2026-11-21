/* Unit test of src/runtime/sys threads and sleeping. Run by `make c-test`. */
#include <stdio.h>
#include <stdlib.h>

#include "ms_rt/sys.h"

#define CHECK(c)                                                  \
    do {                                                          \
        if (!(c)) {                                               \
            fprintf(stderr, "%s:%d: %s\n", __FILE__, __LINE__, #c); \
            exit(1);                                              \
        }                                                         \
    } while (0)

static void bump(void *arg) { *(int *)arg += 41; }

int main(void) {
    /* The argument reaches the thread and the join waits for it, with the default and with a given stack. */
    int a = 1, b = 1;
    MsSysThread *t1 = ms_sys_thread_spawn(0, bump, &a);
    MsSysThread *t2 = ms_sys_thread_spawn((size_t)1 << 20, bump, &b);
    CHECK(t1 != NULL && t2 != NULL);
    ms_sys_thread_join(t1);
    ms_sys_thread_join(t2);
    CHECK(a == 42 && b == 42);

    int64_t before = ms_sys_monotonic_ns();
    ms_sys_sleep_ms(20);
    CHECK(ms_sys_monotonic_ns() - before >= 19 * 1000000);
    puts("sys_thread ok");
    return 0;
}
