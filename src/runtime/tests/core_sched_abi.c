/* Unit test of the scheduler queries (src/runtime/core/sched_abi.c): the pending-cancel and read-limit
 * answers, as a task sees them. */
#include <stdio.h>
#include <stdlib.h>

#include "ms_sched.h"
#include "../core/task.h"
#include "support/sched_env.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_sched_abi: failed: %s\n", what);
        exit(1);
    }
}

static void main_task(void *unused) {
    (void)unused;
    expect(!ms_sched_cancel_pending(), "no cancel is pending");
    expect(!ms_sched_read_limit_passed(), "no read limit has passed");
    const int64_t before = ms_task_read_limit(1);
    ms_task_sleep(2000000);
    expect(ms_sched_read_limit_passed(), "a read limit that ran out is reported");
    ms_task_read_limit_restore(before);
}

int main(void) {
    ms_test_sched_install();
    uint8_t outcome = 1;
    MsFaultText text = {0};
    expect(ms_task_run_main(main_task, NULL, 0, &outcome, &text) == MS_TASK_OK && outcome == 0, "the main task ends");
    puts("core_sched_abi: ok");
    return 0;
}
