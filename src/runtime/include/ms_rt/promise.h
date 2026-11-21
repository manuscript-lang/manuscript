/* ms_rt/promise.h: the program ABI of promises, wait groups and cancel switches for @std/concurrency/promise.ms
 * (src/runtime/core/promise_abi.c over promise.c, group.c and cancel.c); symbols in src/runtime/symbols/promise.txt. Ids carry a generation, so a stale id never
 * matches. Outcome codes of msrt_promise_wait: 0 ok, 1 the operation's own error, 2 timed out, 3 cancelled, 4 closed
 * (the result was already taken), 5 failed (a fault inside). */
/* ms: domain promise */
#ifndef MS_RT_PROMISE_H
#define MS_RT_PROMISE_H

#include "ms_rt/base.h"
#include "ms_rt/desc.h"
#include "ms_rt/string.h"

/* ms-sig: msrt_cancel_fire(id: i64) @domain=cancel */
void msrt_cancel_fire(int64_t id);
/* ms-sig: msrt_cancel_fired(id: i64) -> u8 @domain=cancel */
uint8_t msrt_cancel_fired(int64_t id);
/* ms-sig: msrt_cancel_free(id: i64) @domain=cancel */
void msrt_cancel_free(int64_t id);
/* ms-sig: msrt_cancel_new() -> i64 @domain=cancel */
int64_t msrt_cancel_new(void);

/* ms-sig: msrt_group_free(group: i64) @domain=promise */
void msrt_group_free(int64_t group);
/* ms-sig: msrt_group_join(group: i64, ids: *const VecVal, from: i64) -> i64 @domain=promise */
int64_t msrt_group_join(int64_t group, const MsVec *ids, int64_t from);
/* ms-sig: msrt_group_new() -> i64 @domain=promise */
int64_t msrt_group_new(void);
/* ms-sig: msrt_group_next(group: i64) -> i64 @domain=promise */
int64_t msrt_group_next(int64_t group);
/* ms-sig: msrt_group_poll(group: i64) -> i64 @domain=promise */
int64_t msrt_group_poll(int64_t group);

/* ms-sig: msrt_promise_cancel(id: i64) @domain=promise */
void msrt_promise_cancel(int64_t id);
/* ms-sig: msrt_promise_defer(id: i64, work: *mut Closure) @domain=promise @keeps:work @retains */
void msrt_promise_defer(int64_t id, MsObj *work);
/* ms-sig: msrt_promise_done(id: i64) -> u8 @domain=promise */
uint8_t msrt_promise_done(int64_t id);
/* ms-sig: msrt_promise_drop(id: i64) @domain=promise */
void msrt_promise_drop(int64_t id);
/* ms-sig: msrt_promise_end(id: i64) -> u8 @domain=promise */
uint8_t msrt_promise_end(int64_t id);
/* ms-sig: msrt_promise_fault_report(id: i64, out: *mut StrVal) @domain=promise */
void msrt_promise_fault_report(int64_t id, MsStr *out);
/* ms-sig: msrt_promise_finished() -> i64 @domain=promise */
int64_t msrt_promise_finished(void);
/* ms-sig: msrt_promise_limit(id: i64, timeout_ns: i64) @domain=promise */
void msrt_promise_limit(int64_t id, int64_t timeout_ns);
/* ms-sig: msrt_promise_drain(id: i64, drain: i64, grace_ns: i64) @domain=promise */
void msrt_promise_drain(int64_t id, int64_t drain, int64_t grace_ns);
/* ms-sig: msrt_promise_new() -> i64 @domain=promise */
int64_t msrt_promise_new(void);
/* ms-sig: msrt_promise_on_cancel(id: i64, cancel: i64) @domain=promise */
void msrt_promise_on_cancel(int64_t id, int64_t cancel);
/* ms-sig: msrt_promise_put(id: i64, value: *mut u8, d: ValueDesc, failed: i64) @domain=promise @takes:value */
void msrt_promise_put(int64_t id, uint8_t *value, const MsTypeDesc *d, int64_t failed);
/* ms-sig: msrt_promise_ready(fd: i64, events: i64, timeout_ns: i64) -> i64 @domain=promise */
int64_t msrt_promise_ready(int64_t fd, int64_t events, int64_t timeout_ns);
/* ms-sig: msrt_promise_run_watched(id: i64, group: i64, ids: *const VecVal, from: i64) -> i64 @domain=promise */
int64_t msrt_promise_run_watched(int64_t id, int64_t group, const MsVec *ids, int64_t from);
/* ms-sig: msrt_promise_sleep(ns: i64) -> i64 @domain=promise */
int64_t msrt_promise_sleep(int64_t ns);
/* ms-sig: msrt_promise_start(id: i64, work: *mut Closure) @domain=promise @keeps:work @spawns */
void msrt_promise_start(int64_t id, MsObj *work);
/* ms-sig: msrt_promise_start_here(id: i64, work: *mut Closure) @domain=promise @keeps:work @spawns */
void msrt_promise_start_here(int64_t id, MsObj *work);
/* ms-sig: msrt_promise_start_idle(id: i64, work: *mut Closure) @domain=promise @keeps:work @spawns */
void msrt_promise_start_idle(int64_t id, MsObj *work);
/* ms-sig: msrt_promise_start_spread(id: i64, work: *mut Closure) @domain=promise @keeps:work @spawns */
void msrt_promise_start_spread(int64_t id, MsObj *work);
/* ms-sig: msrt_promise_take(id: i64, d: ValueDesc, out: *mut u8) -> u8 @domain=promise */
uint8_t msrt_promise_take(int64_t id, const MsTypeDesc *d, uint8_t *out);
/* ms-sig: msrt_promise_wait(id: i64, timeout_ns: i64) -> i64 @domain=promise */
int64_t msrt_promise_wait(int64_t id, int64_t timeout_ns);
/* ms-sig: msrt_promise_wait_any(ids: *const VecVal, timeout_ns: i64) -> i64 @domain=promise */
int64_t msrt_promise_wait_any(const MsVec *ids, int64_t timeout_ns);

#endif
