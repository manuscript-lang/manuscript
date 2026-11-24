/* The isolate registry and mail. See isolate.h. */
#include "runtime/core/isolate.h"

#include <stdatomic.h>

#include "base/alloc.h"
#include "runtime/core/watch.h"

enum { SLOT_FREE = 0, SLOT_STARTING = 1, SLOT_LIVE = 2 };

typedef struct Slot {
  _Atomic uint32_t state;
  _Atomic uint32_t load;           /* tasks the isolate runs, read by thieves picking a place */
  _Atomic uint32_t nudged;         /* woken by ms_isolate_wake_one and has not asked since */
  _Atomic(MsMail *) mail;          /* stack of mail, newest first; producers push, the owner swaps it out */
  MsWakeFn wake;                   /* written before `state` goes live, read-only after */
  void *wake_argument;
} Slot;

/* The registry is the one piece of process-wide state of the scheduler design: every field another thread touches is
 * atomic, and `wake` is published by the release store of `state`. */
static Slot slots[MS_MAX_ISOLATES];
static _Atomic uint32_t live_count;
static _Atomic uint32_t looking_count;
/* One bit per isolate whose poller is (about to be) blocked and needs a wake: one word, so a start that finds
 * nobody asleep reads it once instead of visiting every slot. */
static _Atomic uint64_t asleep;
_Static_assert(MS_MAX_ISOLATES <= 64, "one asleep bit per isolate");
static _Atomic(const MsMailKindOps *) kind_ops[MS_MAIL_KIND_COUNT];

void ms_isolate_set_mail_kind(uint32_t kind, const MsMailKindOps *ops) {
  if (kind < MS_MAIL_KIND_COUNT) {
    atomic_store(&kind_ops[kind], ops);
  }
}

const MsMailKindOps *ms_isolate_mail_kind(uint32_t kind) {
  return kind < MS_MAIL_KIND_COUNT ? atomic_load(&kind_ops[kind]) : NULL;
}
static _Thread_local uint32_t self_index = MS_NO_ISOLATE; /* per-thread, like the scheduler */

uint32_t ms_isolate_register(MsWakeFn wake, void *argument) {
  for (uint32_t i = 0; i < MS_MAX_ISOLATES; i++) {
    uint32_t expected = SLOT_FREE;
    if (!atomic_compare_exchange_strong(&slots[i].state, &expected, SLOT_STARTING)) {
      continue;
    }
    slots[i].wake = wake;
    slots[i].wake_argument = argument;
    atomic_fetch_and(&asleep, ~(UINT64_C(1) << i));
    atomic_store(&slots[i].load, 0);
    atomic_store(&slots[i].nudged, 0);
    atomic_store(&slots[i].mail, NULL);
    atomic_store_explicit(&slots[i].state, SLOT_LIVE, memory_order_release);
    atomic_fetch_add(&live_count, 1);
    self_index = i;
    return i;
  }
  return MS_NO_ISOLATE;
}

void ms_isolate_unregister(uint32_t index, void (*discard)(MsMail *mail)) {
  if (index >= MS_MAX_ISOLATES) {
    return;
  }
  atomic_store(&slots[index].state, SLOT_STARTING); /* refuse new mail while the owner drains the rest */
  MsMail *mail = atomic_exchange(&slots[index].mail, NULL);
  while (mail != NULL) {
    MsMail *const next = mail->next;
    const MsMailKindOps *const ops = ms_isolate_mail_kind(mail->kind);
    if (ops != NULL && ops->discard != NULL) {
      ops->discard(mail);
    } else if (discard != NULL) {
      discard(mail);
    }
    ms_free(mail);
    mail = next;
  }
  atomic_fetch_sub(&live_count, 1);
  if (self_index == index) {
    self_index = MS_NO_ISOLATE;
  }
  atomic_store(&slots[index].state, SLOT_FREE);
}

uint32_t ms_isolate_self(void) { return self_index; }

bool ms_isolate_live(uint32_t index) {
  return index < MS_MAX_ISOLATES && atomic_load_explicit(&slots[index].state, memory_order_acquire) == SLOT_LIVE;
}

uint32_t ms_isolate_count(void) { return atomic_load(&live_count); }

uint32_t ms_isolate_load(uint32_t index) { return index < MS_MAX_ISOLATES ? atomic_load(&slots[index].load) : 0; }

void ms_isolate_set_load(uint32_t load) {
  if (self_index < MS_MAX_ISOLATES) {
    atomic_store_explicit(&slots[self_index].load, load, memory_order_relaxed);
  }
}

bool ms_isolate_post(uint32_t target, MsMail *mail) {
  if (!ms_isolate_live(target)) {
    return false;
  }
  Slot *const slot = &slots[target];
  mail->from = self_index;
  MsMail *head = atomic_load_explicit(&slot->mail, memory_order_relaxed);
  do {
    mail->next = head;
  } while (!atomic_compare_exchange_weak_explicit(&slot->mail, &head, mail, memory_order_release,
                          memory_order_relaxed));
  /* The sleeper sets its `asleep` bit, then looks at the mail; this side pushes, then looks at the bit: with
   * sequentially consistent accesses one of the two sees the other. */
  atomic_thread_fence(memory_order_seq_cst);
  if ((atomic_load(&asleep) >> target & 1) != 0 && slot->wake != NULL) {
    slot->wake(slot->wake_argument);
  }
  return true;
}

MsMail *ms_isolate_take(void) {
  if (self_index >= MS_MAX_ISOLATES) {
    return NULL;
  }
  MsMail *newest = atomic_exchange_explicit(&slots[self_index].mail, NULL, memory_order_acquire);
  MsMail *oldest_first = NULL;
  while (newest != NULL) { /* the stack holds newest first: reverse it */
    MsMail *const next = newest->next;
    newest->next = oldest_first;
    oldest_first = newest;
    newest = next;
  }
  return oldest_first;
}

bool ms_isolate_has_mail(void) {
  return self_index < MS_MAX_ISOLATES && atomic_load_explicit(&slots[self_index].mail, memory_order_relaxed) != NULL;
}

bool ms_isolate_idle_enter(void) {
  if (self_index >= MS_MAX_ISOLATES) {
    return true;
  }
  atomic_fetch_or(&asleep, UINT64_C(1) << self_index);
  atomic_thread_fence(memory_order_seq_cst);
  if (atomic_load(&slots[self_index].mail) != NULL) {
    atomic_fetch_and(&asleep, ~(UINT64_C(1) << self_index));
    return false;
  }
  return true;
}

void ms_isolate_idle_leave(void) {
  if (self_index < MS_MAX_ISOLATES) {
    atomic_fetch_and(&asleep, ~(UINT64_C(1) << self_index));
    ms_watch_stir();
  }
}

uint64_t ms_isolate_resting(uint64_t *live) {
  *live = 0;
  for (uint32_t i = 0; i < MS_MAX_ISOLATES; i++) {
    if (atomic_load(&slots[i].state) != SLOT_LIVE) {
      continue;
    }
    *live |= UINT64_C(1) << i;
  }
  return atomic_load(&asleep) & *live;
}

void ms_token_post_remote(uint64_t token, uint64_t value) {
  const uint32_t target = (uint32_t)(token >> MS_TOKEN_ISOLATE_SHIFT);
  MsMail *const mail = ms_alloc(sizeof *mail);
  *mail = (MsMail){.kind = MS_MAIL_TOKEN, .a = token, .b = value};
  if (!ms_isolate_post(target, mail)) {
    ms_free(mail); /* the isolate is gone: nobody waits on the token */
  }
}

bool ms_isolate_wake_one(uint32_t except) {
  const uint64_t self = except < MS_MAX_ISOLATES ? UINT64_C(1) << except : 0;
  for (uint64_t left = atomic_load(&asleep) & ~self; left != 0; left &= left - 1) {
    const uint32_t i = (uint32_t)__builtin_ctzll(left);
    Slot *const slot = &slots[i];
    if (atomic_load(&slot->state) != SLOT_LIVE || slot->wake == NULL) {
      continue;
    }
    const uint64_t bit = UINT64_C(1) << i;
    if ((atomic_fetch_and(&asleep, ~bit) & bit) != 0) {
      atomic_store(&slot->nudged, 1);
      slot->wake(slot->wake_argument);
      return true;
    }
  }
  return false;
}

bool ms_isolate_take_nudge(void) {
  return self_index < MS_MAX_ISOLATES && atomic_load_explicit(&slots[self_index].nudged, memory_order_relaxed) != 0 &&
         atomic_exchange(&slots[self_index].nudged, 0) != 0;
}

void ms_isolate_look_begin(void) { atomic_fetch_add(&looking_count, 1); }

void ms_isolate_look_end(void) { atomic_fetch_sub(&looking_count, 1); }

bool ms_isolate_any_looking(void) { return atomic_load(&looking_count) != 0; }
