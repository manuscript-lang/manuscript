/* The scheduler services the std natives call and the unit tests do not exercise: the program has one task, so no
 * permit is needed and a stop request never arrives. Linked into every runtime/tests/std_*.c test, which links all of
 * runtime/std. */
#include <stdbool.h>
#include <stddef.h>

bool ms_sched_pool_admit(size_t bytes, bool *cancelled) {
    (void)bytes;
    *cancelled = false;
    return false;
}

void ms_sched_pool_release(void) {}
void ms_sched_cancel_return(void) {}
