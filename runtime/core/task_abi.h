/* task_abi.h: the task and token functions generated code and the natives call (`msrt_task_*`, `msrt_token_*`).
 * Each is a thin layer over task.h that turns a failure status into a fault. Internal to runtime/core except for
 * the four ms_sched.h also declares. */
#ifndef MS_CORE_TASK_ABI_H
#define MS_CORE_TASK_ABI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ms_rt/string.h"

typedef void (*MsAbiEntry)(void *);

/* Starts entry(arg) as a task and returns its handle; flags are MS_SPAWN_*, stack_bytes is 0 or MS_TASK_ROOT_STACK. */
uint64_t msrt_task_spawn(MsAbiEntry entry, void *arg, uint32_t flags, size_t stack_bytes);
void msrt_task_yield(void);
/* These four are also declared in ms_sched.h for the natives; the two headers cannot share a translation unit. */
uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns);
uint32_t msrt_task_sleep(int64_t ns);
uint64_t msrt_token_new(uint32_t flags);
uint32_t msrt_token_park(uint64_t id, int64_t timeout_ns, uint64_t *value);
void msrt_token_free(uint64_t id);
uint32_t msrt_task_wait_fd_at(int32_t fd, uint32_t events, int64_t at_ns);
void msrt_task_forget_fd(int32_t fd);
int64_t msrt_task_read_limit(int64_t timeout_ns);
void msrt_task_read_limit_restore(int64_t previous);
uint64_t msrt_task_current(void);
size_t msrt_task_count(void);
bool msrt_task_others_stalled(void);
void msrt_task_cancel(uint64_t handle);
/* How the task ended: 0 returned, 1 faulted (report in *message), 2 cancelled. */
uint8_t msrt_task_join(uint64_t handle, MsStr *message);
void msrt_task_grow(void (*shim)(void *), void *block);

uint32_t msrt_token_park_at(uint64_t id, int64_t at_ns, uint64_t *value);
void msrt_token_post(uint64_t id, uint64_t value);

#endif
