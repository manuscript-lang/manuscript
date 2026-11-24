/* Shields, cancellation and guards of the running task. See unwind.h.
 *
 * Every function acts on the running task's MsUnwind, which lives in its record: switching tasks changes which
 * state these functions see, with nothing to save or restore.
 */
#include "runtime/core/unwind.h"

#include "runtime/core/scheduler.h"

enum { SIGNAL_INTERRUPT = 2 };

static MsUnwind *running(void) { return &ms_task_running()->unwind; }

/* ---- cancellation and shields ---- */

/* Raises the shield depth by one. Only the task's own thread writes the depth (other threads read it), so a load and a
 * store do; an atomic add is a locked instruction on x86, about 9 ns each on the 2026-11-23 benchmark machine. */
static void shield_raise(MsUnwind *unwind) {
  atomic_store_explicit(&unwind->hdr.shield, atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed) + 1,
                        memory_order_relaxed);
}

/* Lowers the shield depth by one. The store that opens the shield is sequentially consistent, as is the read of
 * the stop request in unshielded_flag that follows it: a concurrent stop records its request and then reads the
 * depth, so either that read sees the open shield or this task sees the request, and a stop is never lost. One
 * store that is also the barrier is cheaper than a store and a fence. */
static void shield_lower(MsUnwind *unwind) {
  const uint32_t depth = atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed) - 1;
  if (depth == 0) {
    atomic_store(&unwind->hdr.shield, 0);
  } else {
    atomic_store_explicit(&unwind->hdr.shield, depth, memory_order_relaxed);
  }
}

/* The cancel flag a task has when no shield holds it: the larger of a stop request (unless a stop shield holds
 * it back) and a cancel aimed at the task. */
static uint8_t unshielded_flag(const MsUnwind *unwind) {
  const bool stop_held = atomic_load_explicit(&unwind->hdr.stop_shield, memory_order_relaxed) > 0;
  const uint8_t stop = stop_held ? 0 : ms_sched_stop_request();
  return stop > unwind->task_cancel ? stop : unwind->task_cancel;
}

static void refresh_flag(MsUnwind *unwind) {
  const uint8_t flag =
    atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed) == 0 ? unshielded_flag(unwind) : 0;
  atomic_store_explicit(&unwind->hdr.cancel, flag, memory_order_relaxed);
}

void ms_cancel_set_task(uint8_t value) {
  MsUnwind *const unwind = running();
  unwind->task_cancel = value;
  refresh_flag(unwind);
}

uint8_t ms_cancel_flag(void) { return atomic_load_explicit(&running()->hdr.cancel, memory_order_relaxed); }

void ms_shield_enter(void) {
  MsUnwind *const unwind = running();
  /* Inside a shield the closes run as on a normal exit: a delivered unwind is out of their sight until it ends. */
  const bool outermost = atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed) == 0;
  shield_raise(unwind);
  if (outermost && ms_unwinding_take()) {
    unwind->held_unwinding = true;
  }
  atomic_store_explicit(&unwind->hdr.cancel, 0, memory_order_relaxed);
}

void ms_shield_exit(void) {
  MsUnwind *const unwind = running();
  if (atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed) > 0) {
    shield_lower(unwind);
  }
  refresh_flag(unwind);
  if (unwind->held_unwinding && atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed) == 0) {
    unwind->held_unwinding = false;
    ms_cancel_deliver();
  }
}

void ms_stop_shield_enter(void) {
  MsUnwind *const unwind = running();
  atomic_fetch_add(&unwind->hdr.stop_shield, 1);
  refresh_flag(unwind);
}

void ms_stop_shield_exit(void) {
  MsUnwind *const unwind = running();
  if (atomic_load_explicit(&unwind->hdr.stop_shield, memory_order_relaxed) > 0) {
    atomic_fetch_sub(&unwind->hdr.stop_shield, 1); /* sequentially consistent, as in shield_lower */
  }
  refresh_flag(unwind);
}

bool ms_shielded(void) { return atomic_load_explicit(&running()->hdr.shield, memory_order_relaxed) > 0; }

void ms_cancel_deliver(void) {
  MsUnwind *const unwind = running();
  if (atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed) > 0) {
    unwind->held_unwinding = true;
    return;
  }
  atomic_store_explicit(&unwind->hdr.unwinding, 1, memory_order_relaxed);
}

/* The flag is the task's own, set and cleared on its thread, so no exchange is needed. */
bool ms_unwinding_take(void) {
  MsTaskHdr *const hdr = &running()->hdr;
  if (atomic_load_explicit(&hdr->unwinding, memory_order_relaxed) == 0) {
    return false;
  }
  atomic_store_explicit(&hdr->unwinding, 0, memory_order_relaxed);
  return true;
}

bool ms_unwinding(void) { return atomic_load_explicit(&running()->hdr.unwinding, memory_order_relaxed) != 0; }

/* ---- guards ---- */

uint64_t ms_started_mark(void) { return running()->started; }

uint64_t ms_started_next(void) { return ++running()->started; }

static void end_started(uint64_t mark) {
  const MsSched *const sched = ms_sched();
  if (sched->hooks.end_started != NULL) {
    sched->hooks.end_started(mark);
  }
}

MsGuardStatus ms_guard_call(void (*code)(void *), void *data, MsFaultText *message) {
  MsUnwind *const unwind = running();
  if (message != NULL) {
    *message = (MsFaultText){0};
  }
  const uint64_t mark = unwind->started;
  code(data);
  if (!ms_unwinding_take()) {
    return MS_GUARD_OK;
  }
  /* The frames above have taken their exits and returned: what is left running was started by none of them. */
  unwind->held_unwinding = false;
  end_started(mark);
  if (unwind->pending.detail == NULL) {
    return MS_GUARD_CANCELLED;
  }
  if (message != NULL) {
    *message = unwind->pending;
  } else {
    ms_fault_text_release(&unwind->pending);
  }
  unwind->pending = (MsFaultText){0};
  return MS_GUARD_FAULT;
}
