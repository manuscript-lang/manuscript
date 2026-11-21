/* Unit test of src/runtime/sys stack-overflow reporting: a thread recurses until its stack overflows and the fault
 * callback, running on the alternate stack, sees an address near the stack's end. Run by `make c-test`
 * without sanitizers, which install handlers of their own. */
#include <stdio.h>
#include <stdlib.h>

#include "ms_rt/sys.h"

extern void _exit(int status);

static uintptr_t lowest_seen;
static volatile int stop_depth = -1; /* never reached; keeps the recursion from being "infinite" to the compiler */

static void report(uintptr_t address) {
    const bool inside = address != 0 && address < lowest_seen;
    fputs(inside ? "sys_fault ok\n" : "sys_fault: address outside the stack\n", stderr);
    _exit(inside ? 0 : 1);
}

static int recurse(int depth) {
    volatile char frame[512];
    frame[0] = (char)depth;
    if (lowest_seen == 0 || (uintptr_t)frame < lowest_seen) {
        lowest_seen = (uintptr_t)frame;
    }
    return depth == stop_depth ? frame[0] : recurse(depth + 1) + frame[0];
}

static void overflow(void *arg) {
    (void)arg;
    if (!ms_sys_fault_handler_install(report)) {
        fputs("sys_fault: install failed\n", stderr);
        _exit(1);
    }
    (void)recurse(0);
}

int main(void) {
    MsSysThread *thread = ms_sys_thread_spawn((size_t)256 << 10, overflow, NULL);
    if (thread == NULL) {
        return 1;
    }
    ms_sys_thread_join(thread);
    fputs("sys_fault: the overflow was not reported\n", stderr);
    return 1;
}
