/* The program ABI of promises, wait groups and cancel switches. See promise_abi.h. */
#include "runtime/core/promise_abi.h"

#include "runtime/core/cancel.h"
#include "runtime/core/fault_abi.h"
#include "runtime/core/group.h"
#include "runtime/core/promise.h"

void msrt_cancel_fire(int64_t id) { ms_cancel_fire(id); }
uint8_t msrt_cancel_fired(int64_t id) { return ms_cancel_fired(id) ? 1 : 0; }
void msrt_cancel_free(int64_t id) { ms_cancel_free(id); }
int64_t msrt_cancel_new(void) { return ms_cancel_new(); }

void msrt_group_free(int64_t group) { ms_group_free(group); }
int64_t msrt_group_new(void) { return ms_group_new(); }
/* A wait's answer as the program sees it: a cancelled waiter ends the call here, where the runtime holds nothing. */
static int64_t msrt_end_wait(int64_t answer) {
  if (answer != MS_WAITER_CANCELLED) {
    return answer;
  }
  ms_sched_cancel_return();
  return -1;
}

int64_t msrt_group_next(int64_t group) { return msrt_end_wait(ms_group_next(group)); }
int64_t msrt_group_poll(int64_t group) { return ms_group_poll(group); }

int64_t msrt_group_join(int64_t group, const MsList *ids, int64_t from) {
  return ms_group_join(group, (const MsPromise *)(const void *)ids->ptr, ids->len, (size_t)from);
}

void msrt_promise_cancel(int64_t id) { ms_promise_cancel(id); }
int64_t msrt_promise_defer(MsObj *work) { return ms_promise_defer(work); }
uint8_t msrt_promise_done(int64_t id) { return ms_promise_done(id) ? 1 : 0; }
void msrt_promise_drop(int64_t id) { ms_promise_drop(id); }
uint8_t msrt_promise_close(int64_t id) { return ms_promise_close(id) ? 1 : 0; }

void msrt_promise_fault_report(int64_t id, MsString *out) {
  MsFaultText report = ms_promise_fault_report(id);
  *out = ms_string_from_span(ms_span_of(report.bytes, report.length));
  ms_fault_text_free(&report);
}

int64_t msrt_promise_finished(void) {
  const MsPromise id = ms_promise_new();
  ms_promise_io_done_unit(id);
  return id;
}

void msrt_promise_limit(int64_t id, int64_t timeout_ns) { ms_promise_limit(id, timeout_ns); }
void msrt_promise_on_cancel(int64_t id, int64_t cancel) { ms_promise_on_cancel(id, cancel); }

void msrt_promise_drain(int64_t id, int64_t drain, int64_t grace_ns) { ms_promise_drain(id, drain, grace_ns); }

void msrt_promise_put(int64_t id, uint8_t *value, const MsTypeDesc *d, int64_t failed) {
  ms_promise_put(id, value, d, failed != 0);
}

int64_t msrt_promise_ready(int64_t fd, int64_t events, int64_t timeout_ns) {
  return ms_promise_ready((int)fd, (uint32_t)events, timeout_ns);
}

int64_t msrt_promise_run_watched(int64_t id, int64_t group, const MsList *ids, int64_t from) {
  return ms_promise_run_watched(id, group, (const MsPromise *)(const void *)ids->ptr, ids->len, (size_t)from);
}

int64_t msrt_promise_sleep(int64_t ns) { return ms_promise_sleep(ns); }
int64_t msrt_promise_start(MsObj *work, const MsString *site) { return ms_promise_start(work, site); }
int64_t msrt_promise_start_here(MsObj *work, const MsString *site) { return ms_promise_start_here(work, site); }
int64_t msrt_promise_start_idle(MsObj *work, const MsString *site) { return ms_promise_start_idle(work, site); }
int64_t msrt_promise_start_spread(MsObj *work, const MsString *site) { return ms_promise_start_spread(work, site); }

uint8_t msrt_promise_take(int64_t id, const MsTypeDesc *d, uint8_t *out) { return ms_promise_take(id, d, out) ? 1 : 0; }
int64_t msrt_promise_wait(int64_t id, int64_t timeout_ns) { return msrt_end_wait(ms_promise_wait(id, timeout_ns)); }

uint8_t msrt_promise_result(int64_t id, const MsTypeDesc *d, uint8_t *out) {
  bool taken = false;
  (void)msrt_end_wait(ms_promise_result(id, d, out, &taken));
  return taken ? 1 : 0;
}

int64_t msrt_promise_wait_any(const MsList *ids, int64_t timeout_ns) {
  return msrt_end_wait(ms_promise_wait_any((const MsPromise *)(const void *)ids->ptr, ids->len, timeout_ns));
}
