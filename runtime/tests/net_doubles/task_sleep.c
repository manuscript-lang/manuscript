#define _POSIX_C_SOURCE 200809L
/* A scheduler double for the net tests whose subject sleeps between polls (ms_conn_wait_gone): the calling thread
 * sleeps, and nothing ever cancels it. */
#include <time.h>

#include "ms_sched.h"

uint32_t msrt_task_sleep(int64_t nanoseconds) {
    const struct timespec span = {.tv_sec = nanoseconds / 1000000000, .tv_nsec = nanoseconds % 1000000000};
    nanosleep(&span, NULL);
    return 0;
}
