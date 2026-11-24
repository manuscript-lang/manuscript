/* Cleanups, shields, cancellation and guards of the running task. See unwind.h.
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

/* ---- the cleanup stack ---- */

size_t ms_cleanup_push(MsCleanupFn function, uint8_t *argument) { // NOLINT(readability-non-const-parameter): the cleanup writes it
  MsUnwind *const unwind = running();
  MsTaskHdr *const hdr = &unwind->hdr;
  const uint32_t serial = ++unwind->cleanup_serial;
  ms_cleanup_list_push(&hdr->cleanups, (MsCleanup){.function = function, .argument = argument, .serial = serial});
  return (size_t)serial << 32 | hdr->cleanups.len;
}

_Static_assert(sizeof(size_t) >= 8, "a cleanup handle holds the entry's serial above its height");

/* The height `handle` names when its entry is still on the stack, else 0. */
static size_t live_height(const MsTaskHdr *hdr, size_t handle) {
  const size_t height = handle & UINT32_MAX;
  if (height == 0 || height > hdr->cleanups.len || hdr->cleanups.ptr[height - 1].serial != (uint32_t)(handle >> 32)) {
    return 0;
  }
  return height;
}

size_t ms_cleanup_base(void) { return running()->hdr.cleanups.len; }

/* Length of the cleanup stack below the innermost guard (0 outside guards). */
static size_t guard_base(const MsUnwind *unwind) {
  return unwind->guards.len == 0 ? 0 : unwind->guards.ptr[unwind->guards.len - 1].cleanups;
}

/* Runs `function(argument)` with cancellation shielded: a cleanup is not cancelled half way. */
static void run_shielded(MsUnwind *unwind, MsCleanupFn function, uint8_t *argument) {
  (void)unwind;
  ms_shield_enter();
  function(argument);
  ms_shield_exit();
}

/* Pops and runs the innermost cleanup above the innermost guard; false when none remain. */
static bool run_one_cleanup(MsUnwind *unwind) {
  MsTaskHdr *const hdr = &unwind->hdr;
  if (hdr->cleanups.len <= guard_base(unwind)) {
    return false;
  }
  const MsCleanup action = hdr->cleanups.ptr[--hdr->cleanups.len];
  /* A retired interior entry has no action but still counts as progress, so unwinding continues to the next
   * live registration or to the guard boundary. */
  if (action.function != NULL) {
    run_shielded(unwind, action.function, action.argument);
  }
  return true;
}

void ms_cleanup_run_pending(void) {
  MsUnwind *const unwind = running();
  while (run_one_cleanup(unwind)) {
  }
}

void ms_cleanup_run(size_t handle) {
  MsUnwind *const unwind = running();
  const size_t height = live_height(&unwind->hdr, handle);
  while (height > 0 && unwind->hdr.cleanups.len >= height) {
    if (!run_one_cleanup(unwind)) {
      break;
    }
  }
}

/* Removes only retired entries from the tail. Cancelled entries reserve their indices until a later discard. */
static void prune_retired(MsTaskHdr *hdr) {
  while (hdr->cleanups.len > 0 && hdr->cleanups.ptr[hdr->cleanups.len - 1].function == NULL) {
    hdr->cleanups.len--;
  }
}

void ms_cleanup_discard(size_t handle) {
  MsTaskHdr *const hdr = &running()->hdr;
  const size_t height = live_height(hdr, handle);
  if (height > 0) {
    hdr->cleanups.len = height - 1;
  }
  prune_retired(hdr);
}

static void do_nothing(uint8_t *argument) { (void)argument; } // NOLINT(readability-non-const-parameter): the cleanup signature

void ms_cleanup_cancel(size_t handle) {
  MsTaskHdr *const hdr = &running()->hdr;
  const size_t height = live_height(hdr, handle);
  if (height == 0) {
    return;
  }
  if (height == hdr->cleanups.len) {
    /* The innermost entry leaves the stack: a loop that cancels and registers again each pass reuses one slot. The
     * handle is dead now, and the entry that takes its height has another serial. */
    hdr->cleanups.len--;
    prune_retired(hdr);
    return;
  }
  hdr->cleanups.ptr[height - 1].function = do_nothing;
  hdr->cleanups.ptr[height - 1].argument = NULL;
}

void ms_cleanup_remove(size_t handle) {
  MsTaskHdr *const hdr = &running()->hdr;
  const size_t height = live_height(hdr, handle);
  if (height > 0) {
    hdr->cleanups.ptr[height - 1].function = NULL;
    hdr->cleanups.ptr[height - 1].argument = NULL;
    prune_retired(hdr);
  }
}

void ms_cleanup_truncate(size_t base) {
  MsTaskHdr *const hdr = &running()->hdr;
  if (base < hdr->cleanups.len) {
    hdr->cleanups.len = base;
  }
}

bool ms_unwind_drops(void) { return running()->unwind_drops; }

static void end_started(size_t base) {
  const MsSched *const sched = ms_sched();
  if (sched->hooks.end_started != NULL) {
    sched->hooks.end_started(base);
  }
}

void ms_cleanup_unwind_to(size_t base) {
  MsUnwind *const unwind = running();
  unwind->unwind_drops = unwind->guards.len > 0;
  /* A cleanup that closes through a park must not see the flag of the cancel it serves. */
  const bool was_unwinding = ms_unwinding_take();
  if (was_unwinding) {
    end_started(base);
  }
  while (unwind->hdr.cleanups.len > base && run_one_cleanup(unwind)) {
  }
  if (was_unwinding) {
    ms_cancel_deliver();
  }
}

/* ---- guards ---- */

bool ms_guard_open(void) { return running()->guards.len > 0; }

static void guards_push(MsUnwind *unwind, MsGuardFrame frame) {
  ms_guard_list_push(&unwind->guards, frame);
  atomic_store_explicit(&unwind->hdr.guarded, 1, memory_order_relaxed);
}

static bool guards_pop(MsUnwind *unwind, MsGuardFrame *frame) {
  if (unwind->guards.len == 0) {
    return false;
  }
  *frame = unwind->guards.ptr[--unwind->guards.len];
  atomic_store_explicit(&unwind->hdr.guarded, unwind->guards.len > 0 ? 1 : 0, memory_order_relaxed);
  return true;
}

bool ms_guard_leave(MsGuardStatus status, MsFaultText message) {
  MsSched *const sched = ms_sched();
  MsTask *const task = ms_task_running();
  MsUnwind *const unwind = &task->unwind;
  MsGuardFrame frame = {0};
  if (!guards_pop(unwind, &frame)) {
    return false;
  }
  unwind->flight = NULL;
  unwind->unwind_drops = false;
  unwind->hdr.limit = frame.limit;
  if (unwind->eq_pairs.len > frame.eq_pairs) {
    unwind->eq_pairs.len = frame.eq_pairs; /* a fault left comparisons open */
  }
  uintptr_t teb[MS_CTX_TEB_WORDS] = {0};
  ms_task_segment_teb(frame.segment, teb);
  ms_task_restore_segment(frame.segment);
  ms_task_publish_limit();
  atomic_store_explicit(&unwind->hdr.shield, frame.shield, memory_order_relaxed);
  refresh_flag(unwind);
  ms_fault_text_free(&sched->guard_message);
  if (status == MS_GUARD_FAULT) {
    sched->guard_message = message;
  } else {
    ms_fault_text_free(&message);
  }
  ms_guard_jump(frame.jump, (uintptr_t)status, teb);
}

/* A cancel delivered by return ends the call like one delivered by jump: the frames above have taken their
 * cancel exits and returned. Cleanups still registered since entry belong to hold-outs that did not unwind. */
static MsGuardStatus finish_unwound_call(MsUnwind *unwind, MsFaultText *message) {
  unwind->held_unwinding = false;
  unwind->unwind_drops = unwind->guards.len > 0;
  end_started(guard_base(unwind));
  while (run_one_cleanup(unwind)) {
  }
  unwind->unwind_drops = false;
  MsGuardFrame frame = {0};
  (void)guards_pop(unwind, &frame);
  if (unwind->pending.detail != NULL) { /* a posted fault, not a cancel, ended the call */
    if (message != NULL) {
      *message = unwind->pending;
    } else {
      ms_fault_text_release(&unwind->pending);
    }
    unwind->pending = (MsFaultText){0};
    return MS_GUARD_FAULT;
  }
  return MS_GUARD_CANCELLED;
}

MsGuardStatus ms_guard_call(void (*code)(void *), void *data, MsFaultText *message) {
  MsSched *const sched = ms_sched();
  MsTask *const task = ms_task_running();
  MsUnwind *const unwind = &task->unwind;
  if (message != NULL) {
    *message = (MsFaultText){0};
  }
  uintptr_t slot = 0;
  guards_push(unwind, (MsGuardFrame){
              .jump = &slot,
              .cleanups = unwind->hdr.cleanups.len,
              .limit = unwind->hdr.limit,
              .segment = task->segment,
              .shield = atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed),
              .eq_pairs = unwind->eq_pairs.len,
            });
  const uintptr_t landed = ms_guard_enter(&slot, code, data);
  if (landed == 0) {
    if (ms_unwinding_take()) {
      return finish_unwound_call(unwind, message);
    }
    MsGuardFrame frame = {0};
    (void)guards_pop(unwind, &frame);
    return MS_GUARD_OK;
  }
  /* A fault or a cancel left the call by a jump; ms_guard_leave already closed the frame. */
  if (message != NULL) {
    *message = sched->guard_message;
  } else {
    ms_fault_text_free(&sched->guard_message);
  }
  sched->guard_message = (MsFaultText){0};
  return (MsGuardStatus)landed;
}

void ms_cancelled(void) {
  MsSched *const sched = ms_sched();
  MsUnwind *const unwind = running();
  const uint8_t signal = ms_sched_stop_request();
  unwind->unwind_drops = unwind->guards.len > 0;
  end_started(guard_base(unwind));
  while (run_one_cleanup(unwind)) {
  }
  if (unwind->guards.len > 0) {
    (void)ms_guard_leave(MS_GUARD_CANCELLED, (MsFaultText){0});
  }
  sched->hooks.exit_process(signal == SIGNAL_INTERRUPT ? MS_EXIT_INTERRUPT : MS_EXIT_TERMINATE);
  for (;;) {
    /* The hook ends the process and never returns. */
  }
}
