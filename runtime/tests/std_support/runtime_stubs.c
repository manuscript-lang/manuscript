/* The runtime services the std natives call and the unit tests do not exercise: strings are plain malloc'd bytes, the
 * program has one task (so nothing parks and the pool is never used), and a stop request never arrives. Linked into
 * every runtime/tests/std_*.c test, which links all of runtime/std. */
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/string.h"

void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out) {
    uint8_t *copy = malloc(len + 1);
    if (copy != NULL && len > 0) {
        memcpy(copy, ptr, len);
    }
    *out = (MsStr){.ptr_word = copy, .tagged = len};
}

void msrt_string_clone(const MsStr *s, MsStr *out) { msrt_string_from_bytes(ms_str_data(s), ms_str_len(s), out); }
void msrt_string_free(const MsStr *s) { free(s->ptr_word); }

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    (void)fd;
    (void)events;
    (void)timeout_ns;
    return 0;
}

bool ms_sched_cancel_pending(void) { return false; }
void ms_sched_cancel_return(void) {}
bool ms_sched_read_limit_passed(void) { return false; }
bool ms_sched_on_pool_thread(void) { return false; }
bool ms_sched_pool_alone(void) { return true; }
bool ms_sched_pool_admit(size_t bytes, bool *cancelled) {
    (void)bytes;
    *cancelled = false;
    return false;
}
void ms_sched_pool_release(void) {}
int ms_sched_pool_run_shielded(void (*run)(void *), void *data) {
    run(data);
    return 0;
}
