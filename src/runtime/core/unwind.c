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

/* The cancel flag a task has when no shield holds it: the larger of a stop request (unless a stop shield holds
 * it back) and a cancel aimed at the task. */
static uint8_t unshielded_flag(const MsUnwind *unwind) {
  /* The caller just lowered a shield depth. A concurrent stop records its request and then reads the depth; the
   * fence makes either that read see the lowered depth or this one see the request, so a stop is never lost. */
  atomic_thread_fence(memory_order_seq_cst);
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
  atomic_fetch_add_explicit(&unwind->hdr.shield, 1, memory_order_relaxed);
  atomic_store_explicit(&unwind->hdr.cancel, 0, memory_order_relaxed);
}

void ms_shield_exit(void) {
  MsUnwind *const unwind = running();
  if (atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed) > 0) {
    atomic_fetch_sub_explicit(&unwind->hdr.shield, 1, memory_order_relaxed);
  }
  refresh_flag(unwind);
}

void ms_stop_shield_enter(void) {
  MsUnwind *const unwind = running();
  atomic_fetch_add_explicit(&unwind->hdr.stop_shield, 1, memory_order_relaxed);
  refresh_flag(unwind);
}

void ms_stop_shield_exit(void) {
  MsUnwind *const unwind = running();
  if (atomic_load_explicit(&unwind->hdr.stop_shield, memory_order_relaxed) > 0) {
    atomic_fetch_sub_explicit(&unwind->hdr.stop_shield, 1, memory_order_relaxed);
  }
  refresh_flag(unwind);
}

bool ms_shielded(void) { return atomic_load_explicit(&running()->hdr.shield, memory_order_relaxed) > 0; }

void ms_cancel_deliver(void) { atomic_store_explicit(&running()->hdr.unwinding, 1, memory_order_relaxed); }

bool ms_unwinding_take(void) { return atomic_exchange_explicit(&running()->hdr.unwinding, 0, memory_order_relaxed) != 0; }

bool ms_unwinding(void) { return atomic_load_explicit(&running()->hdr.unwinding, memory_order_relaxed) != 0; }

/* ---- the cleanup stack ---- */

size_t ms_cleanup_push(MsCleanupFn function, uint8_t *argument) { // NOLINT(readability-non-const-parameter): the cleanup writes it
  MsTaskHdr *const hdr = &running()->hdr;
  ms_cleanup_list_push(&hdr->cleanups, (MsCleanup){.function = function, .argument = argument});
  return hdr->cleanups.len;
}

size_t ms_cleanup_base(void) { return running()->hdr.cleanups.len; }

/* Length of the cleanup stack below the innermost guard (0 outside guards). */
static size_t guard_base(const MsUnwind *unwind) {
  return unwind->guards.len == 0 ? 0 : unwind->guards.ptr[unwind->guards.len - 1].cleanups;
}

/* Runs `function(argument)` with cancellation shielded: a cleanup is not cancelled half way. */
static void run_shielded(MsUnwind *unwind, MsCleanupFn function, uint8_t *argument) {
  atomic_fetch_add_explicit(&unwind->hdr.shield, 1, memory_order_relaxed);
  atomic_store_explicit(&unwind->hdr.cancel, 0, memory_order_relaxed);
  function(argument);
  atomic_fetch_sub_explicit(&unwind->hdr.shield, 1, memory_order_relaxed);
  if (atomic_load_explicit(&unwind->hdr.shield, memory_order_relaxed) == 0) {
    atomic_store_explicit(&unwind->hdr.cancel, unshielded_flag(unwind), memory_order_relaxed);
  }
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
  while (handle > 0 && unwind->hdr.cleanups.len >= handle) {
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
  if (handle > 0 && hdr->cleanups.len >= handle) {
    hdr->cleanups.len = handle - 1;
  }
  prune_retired(hdr);
}

static void do_nothing(uint8_t *argument) { (void)argument; } // NOLINT(readability-non-const-parameter): the cleanup signature

void ms_cleanup_cancel(size_t handle) {
  MsTaskHdr *const hdr = &running()->hdr;
  if (handle > 0 && handle <= hdr->cleanups.len) {
    hdr->cleanups.ptr[handle - 1] = (MsCleanup){.function = do_nothing, .argument = NULL};
  }
}

void ms_cleanup_remove(size_t handle) {
  MsTaskHdr *const hdr = &running()->hdr;
  if (handle > 0 && handle <= hdr->cleanups.len) {
    hdr->cleanups.ptr[handle - 1] = (MsCleanup){.function = NULL, .argument = NULL};
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
static MsGuardStatus finish_unwound_call(MsUnwind *unwind) {
  unwind->unwind_drops = unwind->guards.len > 0;
  end_started(guard_base(unwind));
  while (run_one_cleanup(unwind)) {
  }
  unwind->unwind_drops = false;
  MsGuardFrame frame = {0};
  (void)guards_pop(unwind, &frame);
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
      return finish_unwound_call(unwind);
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
