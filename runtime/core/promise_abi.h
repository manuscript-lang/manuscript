/* promise_abi.h: the program ABI of promises, wait groups and cancel switches for @std/concurrency/promise.ms
 * (promise_abi.c over promise.c, group.c and cancel.c). It moves to ms_rt/ and its symbols are listed in
 * runtime/symbols/promise.txt at the cutover that deletes the Rust promise, scheduler and pipe modules. Ids carry a generation, so a stale id never
 * matches. Outcome codes of msrt_promise_wait: 0 ok, 1 the operation's own error, 2 timed out, 3 cancelled, 4 closed
 * (the result was already taken), 5 failed (a fault inside). */
/* ms: domain promise */
#ifndef MS_CORE_PROMISE_ABI_H
#define MS_CORE_PROMISE_ABI_H

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

void msrt_group_free(int64_t group);
int64_t msrt_group_join(int64_t group, const MsVec *ids, int64_t from);
int64_t msrt_group_new(void);
int64_t msrt_group_next(int64_t group);
int64_t msrt_group_poll(int64_t group);

void msrt_promise_cancel(int64_t id);
void msrt_promise_defer(int64_t id, MsObj *work);
uint8_t msrt_promise_done(int64_t id);
void msrt_promise_drop(int64_t id);
uint8_t msrt_promise_end(int64_t id);
void msrt_promise_fault_report(int64_t id, MsStr *out);
int64_t msrt_promise_finished(void);
void msrt_promise_limit(int64_t id, int64_t timeout_ns);
int64_t msrt_promise_new(void);
void msrt_promise_on_cancel(int64_t id, int64_t cancel);
void msrt_promise_put(int64_t id, uint8_t *value, const MsTypeDesc *d, int64_t failed);
int64_t msrt_promise_ready(int64_t fd, int64_t events, int64_t timeout_ns);
int64_t msrt_promise_run_watched(int64_t id, int64_t group, const MsVec *ids, int64_t from);
int64_t msrt_promise_sleep(int64_t ns);
void msrt_promise_start(int64_t id, MsObj *work);
void msrt_promise_start_here(int64_t id, MsObj *work);
void msrt_promise_start_idle(int64_t id, MsObj *work);
void msrt_promise_start_spread(int64_t id, MsObj *work);
uint8_t msrt_promise_take(int64_t id, const MsTypeDesc *d, uint8_t *out);
int64_t msrt_promise_wait(int64_t id, int64_t timeout_ns);
int64_t msrt_promise_wait_any(const MsVec *ids, int64_t timeout_ns);

#endif
