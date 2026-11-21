/* The task and token ABI. See task_abi.h. */
#include "runtime/core/task_abi.h"

#include "base/alloc.h"
#include "runtime/core/isolate.h"
#include "runtime/core/scheduler.h"

static const char depth_message[] =
    "stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the "
    "recursion for a missing base case, or iterate instead";

uint64_t msrt_task_spawn(MsTaskEntry entry, void *arg, uint32_t flags, size_t stack_bytes) {
  MsTaskStatus status = MS_TASK_OK;
  const MsTaskHandle handle = ms_task_spawn(entry, arg, flags, stack_bytes, &status);
  if (handle == 0) {
    ms_fault_text(MS_FAULT_KIND_FAULT, "cannot start a task: out of address space or mappings");
  }
  return handle;
}

void msrt_task_yield(void) { ms_task_yield(); }

static uint32_t checked_wait(uint32_t result) {
  if ((result & MS_WAIT_FAILED) != 0) {
    ms_fault_text(MS_FAULT_KIND_FAULT, "cannot wait on this file descriptor");
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

static const char *join_failure(MsTaskStatus status) {
  switch (status) {
  case MS_TASK_NO_SUCH_TASK:
    return "join: no such task";
  case MS_TASK_DETACHED:
    return "join: the task is detached";
  case MS_TASK_SELF:
    return "join: a task cannot join itself";
  case MS_TASK_ALREADY_JOINED:
    return "join: the task is already being joined";
  case MS_TASK_OK:
  case MS_TASK_NO_STACK:
  case MS_TASK_STACK_OVERFLOW:
    break;
  }
  return "join: the task cannot be joined";
}

uint8_t msrt_task_join(uint64_t handle, MsString *message) {
  uint8_t outcome = 0;
  MsFaultText text = {0};
  const MsTaskStatus status = ms_task_join(handle, &outcome, &text);
  if (status != MS_TASK_OK) {
    ms_fault_text(MS_FAULT_KIND_FAULT, join_failure(status));
  }
  if (message != NULL) {
    *message = ms_string_from_span(ms_span_of(text.bytes, text.length));
  }
  ms_fault_text_free(&text);
  return outcome;
}

void msrt_task_grow(void (*shim)(void *), void *block) {
  if (ms_task_grow(shim, block) != MS_TASK_OK) {
    ms_fault_text(MS_FAULT_KIND_STACK_OVERFLOW, depth_message);
  }
}

uint64_t msrt_token_new(uint32_t flags) { return ms_token_new(flags); }

static uint32_t checked_park(MsTokenStatus status, uint32_t result) {
  if (status == MS_TOKEN_NO_SUCH_TOKEN) {
    ms_fault_text(MS_FAULT_KIND_FAULT, "park on a token that does not exist");
  }
  if (status == MS_TOKEN_BUSY) {
    ms_fault_text(MS_FAULT_KIND_FAULT, "another task is already waiting on this token");
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
    ms_fault_text(MS_FAULT_KIND_FAULT, "a token was freed while a task waits on it");
  }
}

void msrt_token_post_remote(uint64_t token, uint64_t value) { ms_token_post_remote(token, value); }
