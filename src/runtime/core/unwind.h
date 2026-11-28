/* unwind.h: the per-task state a fault, a cancellation or a guard acts on.
 *
 *  - the header block generated code reads and writes inline: recursion limit, cancel flag, shield depths and the
 *    `unwinding` byte;
 *  - the pending report: a fault is posted (ms_fault_post) and the frames return with the `unwinding` byte set, the
 *    way a delivered cancel leaves them; each call site tests the byte and leaves by its exit;
 *  - guards: ms_guard_call runs code and tells how it ended (returned, posted a fault, or was cancelled);
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

#include "abi/layout.h"
#include "base/safe.h"
#include "runtime/core/fault.h"

/* The words generated code reads, one block per task stack. Layout is ABI. */
typedef struct MsTaskHdr {
  uintptr_t limit;              /* lowest stack address recursive calls may reach (0: no limit) */
  _Atomic uint8_t cancel;       /* the signal number once a stop was requested and is not shielded */
  uint8_t reserved;
  _Atomic uint16_t stop_shield; /* depth of the task's stop shields (SIGINT and SIGTERM held back) */
  _Atomic uint32_t shield;      /* depth of the task's cancellation shields */
  _Atomic uint8_t unwinding;    /* a park delivered a cancel by returning: frames take their cancel exit */
} MsTaskHdr;

_Static_assert(offsetof(MsTaskHdr, cancel) == 8, "ISOLATE_HDR_CANCEL");
_Static_assert(offsetof(MsTaskHdr, unwinding) == MS_HDR_UNWINDING, "ISOLATE_HDR_UNWINDING");

/* Everything of the unwind machinery that belongs to one task. */
typedef struct MsUnwind {
  MsTaskHdr hdr;
  uint64_t started;      /* promises this task has started: each takes the next number (ms_started_mark) */
  uintptr_t stack_low;   /* bounds of the running stack segment, for frame walking (0: unknown) */
  uintptr_t stack_high;
  uintptr_t stack_chain; /* chain cell of the segment below, or 0 on the home segment */
  uint8_t task_cancel;   /* a cancel aimed at this task; 0 when none */
  MsFaultText pending;   /* a posted fault (ms_fault_post) the frames are returning with; empty when none */
  bool reporting;        /* a fault report is being built or written: a fault now ends the process outright */
  bool held_unwinding;   /* an unwind was delivered or posted inside a shield: shown when the outermost shield exits */
} MsUnwind;

/* ---- shields and cancellation ---- */

/* Holds back every cancel from the running task until the matching exit. */
void ms_shield_enter(void);
void ms_shield_exit(void);
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

/* The number of promises the running task has started so far. A guard ends the promises numbered above the mark it took. */
uint64_t ms_started_mark(void);
/* The number for a promise starting now. */
uint64_t ms_started_next(void);

/* Runs `code(data)` and tells how it ended: MS_GUARD_OK when it returned, MS_GUARD_FAULT when a fault was posted
 * inside it (the report in `*message`, owned by the caller), MS_GUARD_CANCELLED when a cancel was delivered. A
 * guard ends the promises the code started and left running. `message` may be NULL. */
MsGuardStatus ms_guard_call(void (*code)(void *), void *data, MsFaultText *message) MS_NONNULL_ARGS(1);

#endif
