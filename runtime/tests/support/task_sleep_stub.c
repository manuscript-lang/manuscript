/* Stand-in for the scheduler's task sleep in connection tests that run without one. */
#include <stdint.h>
#include <time.h>

__attribute__((weak)) uint32_t msrt_task_sleep(int64_t ns) {
    const struct timespec span = {.tv_sec = (time_t)(ns / 1000000000), .tv_nsec = (long)(ns % 1000000000)};
    (void)nanosleep(&span, NULL);
    return 0;
}
