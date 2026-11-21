/* The task and token ABI: the functions generated code and the natives call, over the scheduler in task.h. Each
 * turns a failure status into a fault with the message programs have always seen. */
#include "ms_rt/task.h"

#include "scheduler.h"

#define FAULT(message) (ms_sched()->hooks.fault(MS_FAULT_KIND_FAULT, (message)))
#define STACK_OVERFLOW(message) (ms_sched()->hooks.fault(MS_FAULT_KIND_STACK_OVERFLOW, (message)))

static const char depth_message[] =
    "stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the "
    "recursion for a missing base case, or iterate instead";

uint64_t msrt_task_spawn(MsAbiEntry entry, void *arg, uint32_t flags, size_t stack_bytes) {
    MsTaskStatus status = MS_TASK_OK;
    const MsTaskHandle handle = ms_task_spawn(entry, arg, flags, stack_bytes, &status);
    if (handle == 0) {
        FAULT("cannot start a task: out of address space or mappings");
    }
    return handle;
}

void msrt_task_yield(void) { ms_task_yield(); }

static uint32_t checked_wait(uint32_t result) {
    if ((result & MS_WAIT_FAILED) != 0) {
        FAULT("cannot wait on this file descriptor");
    }
    return result;
}

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    return checked_wait(ms_task_wait_fd(fd, events, timeout_ns));
}

uint32_t msrt_task_wait_fd_at(int32_t fd, uint32_t events, int64_t at_ns) {
    return checked_wait(ms_task_wait_fd_at(fd, events, at_ns));
}

void msrt_task_forget_fd(int32_t fd) { ms_task_forget_fd(fd); }

uint32_t msrt_task_sleep(int64_t ns) { return ms_task_sleep(ns < 0 ? 0 : ns); }

int64_t msrt_task_read_limit(int64_t timeout_ns) { return ms_task_read_limit(timeout_ns); }

void msrt_task_read_limit_restore(int64_t previous) { ms_task_read_limit_restore(previous); }

uint64_t msrt_task_current(void) { return ms_task_current(); }

size_t msrt_task_count(void) { return ms_task_count(); }

bool msrt_task_others_stalled(void) { return ms_task_others_stalled(); }

void msrt_task_cancel(uint64_t handle) { ms_task_cancel(handle); }

uint8_t msrt_task_join(uint64_t handle, MsStr *message) {
    uint8_t outcome = 0;
    MsFaultText text = {0};
    const MsTaskStatus status = ms_task_join(handle, &outcome, &text);
    switch (status) {
    case MS_TASK_OK:
        break;
    case MS_TASK_NO_SUCH_TASK:
        FAULT("join: no such task");
        break;
    case MS_TASK_DETACHED:
        FAULT("join: the task is detached");
        break;
    case MS_TASK_SELF:
        FAULT("join: a task cannot join itself");
        break;
    case MS_TASK_ALREADY_JOINED:
        FAULT("join: the task is already being joined");
        break;
    default:
        FAULT("join: the task cannot be joined");
        break;
    }
    if (message != NULL) {
        if (text.bytes != NULL) {
            msrt_string_from_bytes(text.bytes, text.length, message);
        } else {
            *message = (MsStr){0};
        }
    }
    msrt_free(text.bytes);
    return outcome;
}

void msrt_task_grow(MsGrowFn shim, void *block) {
    if (ms_task_grow(shim, block) != MS_TASK_OK) {
        STACK_OVERFLOW(depth_message);
    }
}

uint64_t msrt_token_new(uint32_t flags) {
    const uint64_t id = ms_token_new(flags);
    if (id == 0) {
        FAULT("out of park tokens");
    }
    return id;
}

static uint32_t checked_park(MsTokenStatus status, uint32_t result) {
    if (status == MS_TOKEN_NO_SUCH_TOKEN) {
        FAULT("park on a token that does not exist");
    }
    if (status == MS_TOKEN_BUSY) {
        FAULT("another task is already waiting on this token");
    }
    return result;
}

uint32_t msrt_token_park_at(uint64_t id, int64_t at_ns, uint64_t *value) {
    uint32_t result = 0;
    const MsTokenStatus status = ms_token_park_at(id, at_ns, value, &result);
    return checked_park(status, result);
}

uint32_t msrt_token_park(uint64_t id, int64_t timeout_ns, uint64_t *value) {
    uint32_t result = 0;
    const MsTokenStatus status = ms_token_park(id, timeout_ns, value, &result);
    return checked_park(status, result);
}

void msrt_token_post(uint64_t id, uint64_t value) { ms_token_post(id, value); }

void msrt_token_free(uint64_t id) {
    if (ms_token_free(id) == MS_TOKEN_WAITED_ON) {
        FAULT("a token was freed while a task waits on it");
    }
}
