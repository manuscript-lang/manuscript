/* The scheduler of a thread: creation, hooks, the stop request, the clock and teardown. See scheduler.h. */
#include "runtime/core/scheduler.h"

#include "base/alloc.h"
#include "runtime/core/isolate.h"
#include "runtime/sys/sys.h"

enum { MIN_TIMER_LIMIT = 1024 };

_Thread_local MsSched *ms_thread_sched; /* this thread's scheduler: per-thread state the design names */

MsSched *ms_sched_create(void) {
  if (ms_thread_sched == NULL) {
    MsSched *const created = ms_alloc_zeroed(sizeof *created);
    created->timer_limit = MIN_TIMER_LIMIT;
    created->kill_limit = MIN_TIMER_LIMIT;
    created->external_limit = MIN_TIMER_LIMIT;
    ms_thread_sched = created;
  }
  return ms_thread_sched;
}

void ms_sched_set_hooks(const MsSchedHooks *hooks, const MsPollOps *poll) {
  MsSched *const sched = ms_sched();
  sched->hooks = *hooks;
  sched->poll = *poll;
}

uint32_t ms_sched_attach(MsWakeFn wake, void *argument) {
  MsSched *const sched = ms_sched();
  const uint32_t index = ms_isolate_register(wake, argument);
  if (index != MS_NO_ISOLATE) {
    sched->isolate = index;
  }
  return index;
}

int64_t ms_sched_now(void) { return ms_sys_monotonic_ns(); }

void ms_sched_post_completion(uint64_t id, int32_t result, uint32_t kind) {
  (void)kind;
  ms_token_post(id, (uint64_t)(int64_t)result); /* the result sign-extends; the taker casts it back to int32_t */
}

uint8_t ms_sched_stop_request(void) {
  return ms_thread_sched == NULL ? 0 : atomic_load_explicit(&ms_thread_sched->stop_request, memory_order_relaxed);
}

/* Raises the cancel flag of `hdr` to at least `signal`, unless a shield holds the stop back. */
static void raise_cancel(MsTaskHdr *hdr, uint8_t signal) {
  if (atomic_load(&hdr->shield) != 0 || atomic_load(&hdr->stop_shield) != 0) {
    return;
  }
  uint8_t seen = atomic_load(&hdr->cancel);
  while (seen < signal && !atomic_compare_exchange_weak(&hdr->cancel, &seen, signal)) {
  }
}

void ms_sched_publish(MsSched *sched, MsTask *task) {
  /* Sequentially consistent, paired with the stop request store in ms_sched_stop_remote: either that call sees this
   * header, or this call sees its request. */
  atomic_store(&sched->published_hdr, &task->unwind.hdr);
  const uint8_t stop = atomic_load(&sched->stop_request);
  if (stop != 0) {
    raise_cancel(&task->unwind.hdr, stop);
  }
}

static _Atomic(MsSched *) stop_target;

void ms_sched_set_stop_target(void) { atomic_store(&stop_target, ms_sched()); }

void ms_sched_clear_stop_target(void) {
  MsSched *const sched = ms_sched_if_any();
  if (sched != NULL) {
    atomic_store(&sched->published_hdr, NULL);
  }
  atomic_store(&stop_target, NULL);
}

bool ms_sched_sample_window(uintptr_t window[3]) {
  const MsSched *const sched = atomic_load(&stop_target);
  if (sched == NULL) {
    return false;
  }
  const MsTaskHdr *const hdr = atomic_load(&sched->published_hdr);
  if (hdr == NULL) {
    return false;
  }
  /* The header is the first member of the task's unwind state. A sample racing a task switch reads a stale window,
   * which at worst ends the walk early. */
  const MsUnwind *const unwind = (const MsUnwind *)hdr;
  window[0] = unwind->stack_low;
  window[1] = unwind->stack_high;
  window[2] = unwind->stack_chain;
  return true;
}

void ms_sched_stop_remote(uint8_t signal) {
  MsSched *const sched = atomic_load(&stop_target);
  if (sched == NULL) {
    return;
  }
  atomic_store(&sched->stop_request, signal);
  MsTaskHdr *const running = atomic_load(&sched->published_hdr);
  if (running != NULL) {
    raise_cancel(running, signal);
  }
  MsMail *const mail = ms_alloc_zeroed(sizeof *mail);
  mail->kind = MS_MAIL_STOP;
  mail->from = MS_NO_ISOLATE;
  mail->a = signal;
  if (!ms_isolate_post(sched->isolate, mail)) {
    ms_free(mail); /* the isolate ended; there is nothing left to stop */
  }
}

void ms_sched_stop(uint8_t signal) {
  atomic_store_explicit(&ms_sched()->stop_request, signal, memory_order_relaxed);
}

/* Frees a record and what hangs off it. The stack goes to the pool (or is dropped with the regions). */
void ms_task_destroy(MsSched *sched, MsTask *task) {
  if (task->stack != NULL) {
    ms_stacks_release(&sched->stacks, task->stack, task->stack_length);
  }
  if (task->extra != NULL) {
    for (size_t i = 0; i < task->extra->segments.len; i++) {
      ms_stacks_release(&sched->stacks, task->extra->segments.ptr[i], MS_STACK_SLOT);
    }
    ms_segment_list_free(&task->extra->segments);
    ms_teb_list_free(&task->extra->segment_teb);
    ms_free(task->extra);
  }
  ms_cleanup_list_free(&task->unwind.hdr.cleanups);
  ms_guard_list_free(&task->unwind.guards);
  ms_eq_pair_list_free(&task->unwind.eq_pairs);
  ms_fault_text_free(&task->message);
  ms_free(task);
}

void ms_sched_teardown(void) {
  MsSched *const sched = ms_thread_sched;
  if (sched == NULL) {
    return;
  }
  if (ms_isolate_self() != MS_NO_ISOLATE) {
    ms_isolate_unregister(ms_isolate_self(), sched->hooks.discard_mail);
  }
 
  if (sched->hooks.teardown != NULL) {
    sched->hooks.teardown();
  }
  for (size_t i = 0; i < sched->slots.len; i++) {
    if (sched->slots.ptr[i].task != NULL) {
      ms_task_destroy(sched, sched->slots.ptr[i].task);
    }
  }
  if (sched->zombie_stack != NULL) {
    ms_stacks_release(&sched->stacks, sched->zombie_stack, sched->zombie_stack_length);
  }
  ms_park_free(sched);
  ms_token_free_all(sched);
  ms_stacks_destroy(&sched->stacks);
  ms_slot_list_free(&sched->slots);
  ms_index_list_free(&sched->free_slots);
  ms_free(sched->ready);
  ms_thread_sched = NULL;
  ms_free(sched);
}
