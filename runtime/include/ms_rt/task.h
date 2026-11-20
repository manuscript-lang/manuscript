/* ms_rt/task.h: the tasks and wake-up tokens generated code and the natives call (runtime/core/task_abi.c, sched_abi.c).
 * Each is a thin layer over runtime/core/task.h that turns a failure status into a fault. Symbols are listed in
 * runtime/symbols/task.txt. msrt_token_post_remote is the one any thread may call. */
/* ms: domain task */
#ifndef MS_RT_TASK_H
#define MS_RT_TASK_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ms_rt/string.h"

typedef void (*MsAbiEntry)(void *);
/* The continuation a function whose stack ran out runs on a larger one. */
typedef void (*MsGrowFn)(void *);

/* ms-sig: msrt_task_spawn(entry: Entry, arg: *mut u8, flags: u32, stack_bytes: usize) -> u64 @domain=task @retains */
uint64_t msrt_task_spawn(MsAbiEntry entry, void *arg, uint32_t flags, size_t stack_bytes);

/* ms-sig: msrt_task_yield() @domain=task */
void msrt_task_yield(void);

/* ms-sig: msrt_token_post_remote(id: u64, value: u64) */
void msrt_token_post_remote(uint64_t token, uint64_t value);

/* ms-sig: msrt_task_wait_fd(fd: i32, events: u32, timeout_ns: i64) -> u32 @domain=task */
uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns);

/* ms-sig: msrt_task_wait_fd_at(fd: i32, events: u32, at_ns: i64) -> u32 @domain=task */
uint32_t msrt_task_wait_fd_at(int32_t fd, uint32_t events, int64_t at_ns);

/* ms-sig: msrt_task_forget_fd(fd: i32) @domain=task */
void msrt_task_forget_fd(int32_t fd);

/* ms-sig: msrt_task_sleep(ns: i64) -> u32 @domain=task */
uint32_t msrt_task_sleep(int64_t ns);

/* ms-sig: msrt_task_read_limit(timeout_ns: i64) -> i64 @domain=task */
int64_t msrt_task_read_limit(int64_t timeout_ns);

/* ms-sig: msrt_task_read_limit_restore(previous: i64) @domain=task */
void msrt_task_read_limit_restore(int64_t previous);

/* ms-sig: msrt_task_current() -> u64 @domain=task */
uint64_t msrt_task_current(void);

/* ms-sig: msrt_task_count() -> usize @domain=task */
size_t msrt_task_count(void);

/* ms-sig: msrt_task_others_stalled() -> bool @domain=task */
bool msrt_task_others_stalled(void);

/* ms-sig: msrt_task_cancel(handle: u64) @domain=task */
void msrt_task_cancel(uint64_t handle);

/* ms-sig: msrt_task_join(handle: u64, msg_out: *mut StrVal) -> u8 @domain=task */
uint8_t msrt_task_join(uint64_t handle, MsStr *message);

/* ms-sig: msrt_task_grow(shim: unsafe extern "C-unwind" fn(*mut u8), block: *mut u8) */
void msrt_task_grow(MsGrowFn shim, void *block);

/* ms-sig: msrt_token_new(flags: u32) -> u64 */
uint64_t msrt_token_new(uint32_t flags);

/* ms-sig: msrt_token_park_at(id: u64, at_ns: i64, value_out: *mut u64) -> u32 */
uint32_t msrt_token_park_at(uint64_t id, int64_t at_ns, uint64_t *value);

/* ms-sig: msrt_token_park(id: u64, timeout_ns: i64, value_out: *mut u64) -> u32 */
uint32_t msrt_token_park(uint64_t id, int64_t timeout_ns, uint64_t *value);

/* ms-sig: msrt_token_post(id: u64, value: u64) */
void msrt_token_post(uint64_t id, uint64_t value);

/* ms-sig: msrt_token_free(id: u64) */
void msrt_token_free(uint64_t id);

#endif
