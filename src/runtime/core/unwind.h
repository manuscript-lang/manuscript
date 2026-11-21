/* unwind.h: the per-task state a fault, a cancellation or a guard acts on.
 *
 *  - the header block generated code reads and writes inline: recursion limit, cancel flag, guard flag,
 *    shield depths, the `unwinding` byte, and the cleanup stack (offsets are ABI: crates/ms-rt-abi/src/lib.rs
 *    `ISOLATE_HDR_*`);
 *  - the cleanup stack: actions registered by generated code, run last-in first-out when a guarded task is
 *    left by a fault or a cancel;
 *  - guards: ms_guard_call runs code so that a fault or cancel inside it ends the call, not the process, after
 *    running the cleanups registered since entry;
 *  - cancellation: a request aimed at the task, or a stop request (SIGINT, SIGTERM) aimed at the isolate,
 *    sets the cancel flag unless a shield holds it back.
 *
 * Every function acts on the running task; the scheduler owns the records (task.h).
 */
#ifndef MS_RUNTIME_CORE_UNWIND_H
#define MS_RUNTIME_CORE_UNWIND_H

#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "base/list.h"
#include "base/safe.h"
#include "runtime/core/fault.h"

typedef void (*MsCleanupFn)(uint8_t *); /* the argument is the cleanup's own state, as generated code passes it */

/* One registered action. `function` is NULL for an entry removed without disturbing newer ones. */
typedef struct MsCleanup {
  MsCleanupFn function;
  uint8_t *argument;
} MsCleanup;

MS_LIST_DEFINE(MsCleanupList, ms_cleanup_list, MsCleanup)

/* The words generated code reads, one block per task stack. Layout is ABI. */
typedef struct MsTaskHdr {
  uintptr_t limit;              /* lowest stack address recursive calls may reach (0: no limit) */
  _Atomic uint8_t cancel;       /* the signal number once a stop was requested and is not shielded */
  _Atomic uint8_t guarded;      /* non-zero while a guard is open: drop-only cleanups register just then */
  _Atomic uint16_t stop_shield; /* depth of the task's stop shields (SIGINT and SIGTERM held back) */
  _Atomic uint32_t shield;      /* depth of the task's cancellation shields */
  _Atomic uint8_t unwinding;    /* a park delivered a cancel by returning: frames take their cancel exit */
  MsCleanupList cleanups;       /* the cleanup stack, pushed and discarded inline (pointer at offset 24) */
} MsTaskHdr;

_Static_assert(offsetof(MsTaskHdr, cancel) == 8, "ISOLATE_HDR_CANCEL");
_Static_assert(offsetof(MsTaskHdr, guarded) == 9, "ISOLATE_HDR_GUARDED");
_Static_assert(offsetof(MsTaskHdr, unwinding) == 16, "ISOLATE_HDR_UNWINDING");
_Static_assert(offsetof(MsTaskHdr, cleanups) == 24, "the cleanup stack sits at offset 24");
_Static_assert(sizeof(MsCleanup) == 2 * sizeof(uintptr_t), "a cleanup is two words");

/* State captured when a guard opens, restored when a fault or cancel leaves it. */
typedef struct MsGuardFrame {
  uintptr_t *jump;    /* the register save slot of the ms_guard_call frame */
  size_t cleanups;    /* cleanup stack height at entry */
  uintptr_t limit;    /* recursion limit at entry */
  uint32_t segment;   /* the stack segment the guard opened on */
  uint32_t shield;    /* shield depth at entry */
  size_t eq_pairs;    /* equality pairs registered at entry (ms_eq_truncate drops what a fault left behind) */
} MsGuardFrame;

MS_LIST_DEFINE(MsGuardList, ms_guard_list, MsGuardFrame)

/* The pair of objects an equality comparison is inside, to cut a cycle. */
typedef struct MsEqPair {
  uintptr_t a;
  uintptr_t b;
} MsEqPair;
MS_LIST_DEFINE(MsEqPairList, ms_eq_pair_list, MsEqPair)

/* Everything of the unwind machinery that belongs to one task. */
typedef struct MsUnwind {
  MsTaskHdr hdr;
  MsGuardList guards; /* open guards, innermost last */
  uintptr_t stack_low;   /* bounds of the running stack segment, for frame walking (0: unknown) */
  uintptr_t stack_high;
  uintptr_t stack_chain; /* chain cell of the segment below, or 0 on the home segment */
  uint8_t task_cancel;   /* a cancel aimed at this task; 0 when none */
  struct MsFaultFlight *flight; /* the fault being reported on this task, in its raiser's frame, or NULL */
  bool unwind_drops;     /* a guarded task is being left: drop cleanups act now */
  MsEqPairList eq_pairs; /* the object pairs an equality comparison of this task is inside (cycle guard) */
} MsUnwind;

/* ---- the cleanup stack ---- */

/* Pushes an action; the result is its handle (the new height, counted from 1). */
size_t ms_cleanup_push(MsCleanupFn function, uint8_t *argument) MS_NONNULL_ARGS(1);
/* Height of the cleanup stack, to pass to ms_cleanup_unwind_to or ms_cleanup_truncate. */
size_t ms_cleanup_base(void);
/* Runs the action behind `handle` and every newer one, innermost first, each shielded from cancellation. */
void ms_cleanup_run(size_t handle);
/* Drops the action behind `handle` and every newer one without running them. */
void ms_cleanup_discard(size_t handle);
/* Turns the action behind `handle` into one that does nothing; newer actions stay. */
void ms_cleanup_cancel(size_t handle);
/* Retires exactly this action without running it; the handle must not be used again. */
void ms_cleanup_remove(size_t handle);
/* Runs every cleanup above the innermost guard, innermost first, each shielded from cancellation: the end of a
 * fault. A cleanup that faults is reported by ms_fault, which comes back here. */
void ms_cleanup_run_pending(void);
/* Runs the cleanups above `base`, innermost first, then returns (a cancel exit that goes on returning). */
void ms_cleanup_unwind_to(size_t base);
/* Pops the cleanups above `base` without running them. */
void ms_cleanup_truncate(size_t base);
/* Whether cleanups run because a guarded task is being left (drop cleanups act only then). */
bool ms_unwind_drops(void);

/* ---- shields and cancellation ---- */

/* Holds back every cancel from the running task until the matching exit. */
void ms_shield_enter(void);
void ms_shield_exit(void);
/* Holds back stop requests (SIGINT, SIGTERM) only; a cancel aimed at the task itself still applies. */
void ms_stop_shield_enter(void);
void ms_stop_shield_exit(void);
/* Whether the running task is inside a shield. */
bool ms_shielded(void);
/* Records a cancel aimed at the running task (1) or forgets it (0), and refreshes the cancel flag. */
void ms_cancel_set_task(uint8_t value);
/* The cancel flag of the running task: non-zero when it must stop at its next cancellation point. */
uint8_t ms_cancel_flag(void);
/* Marks the running task as unwinding for a delivered cancel; the caller returns a zero result. */
void ms_cancel_deliver(void);
/* Clears the unwinding byte and answers whether it was set. */
bool ms_unwinding_take(void);
bool ms_unwinding(void);

/* ---- guards ---- */

/* Runs `code(data)`. A fault inside it (ms_guard_exit) or a cancel (ms_cancelled) runs the cleanups registered
 * since entry and returns MS_GUARD_FAULT, with the message in `*message` (owned by the caller), or
 * MS_GUARD_CANCELLED. Returns MS_GUARD_OK when `code` returns. `message` may be NULL. */
MsGuardStatus ms_guard_call(void (*code)(void *), void *data, MsFaultText *message) MS_NONNULL_ARGS(1);
/* Ends the innermost guard with `status` and hands it `message` (taking ownership). No guard open: false. */
bool ms_guard_leave(MsGuardStatus status, MsFaultText message);
/* Whether a guard is open on the running task. */
bool ms_guard_open(void);

/* Unwinds the running task on a stop or cancel request: ends the promises it started, runs every cleanup, then
 * leaves the innermost guard as cancelled, or exits the process with 130 or 143. Never returns. */
MS_NORETURN void ms_cancelled(void);

#endif
