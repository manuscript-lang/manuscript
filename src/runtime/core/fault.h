/* runtime/core/fault.h: raising a fault, the one way runtime code ends a task it cannot continue.
 *
 * A fault ends the task that raised it: ms_fault captures the source frames, runs the task's cleanups last in,
 * first out, and leaves by the innermost guard (ms_guard_call in unwind.h) with the report, or, with no guard open,
 * prints the report, writes the record and ends the process with the status of its kind (abi/fault.h). A fault
 * raised by a cleanup is added to the report of the fault being handled, and the remaining cleanups still run.
 * The natives in core, io, net and std call these and never return.
 *
 * The state of a fault in progress lives in the frame of the function that raised it, reached from the task's
 * unwind state, so nothing is global and two tasks can be reporting at once. The text on standard error is for
 * people and is never parsed; the record (record.h) is written once, as the process ends. */
#ifndef MS_RUNTIME_CORE_FAULT_H
#define MS_RUNTIME_CORE_FAULT_H

#include <stddef.h>
#include <stdint.h>

#include "abi/fault.h"
#include "base/list.h"
#include "base/safe.h"
#include "base/strbuild.h"
#include "runtime/core/frames.h"
#include "runtime/core/record.h"

/* Outcome of a guarded call (ms_guard_call in unwind.h). */
typedef enum MsGuardStatus {
  MS_GUARD_OK = 0,
  MS_GUARD_FAULT = 1,
  MS_GUARD_CANCELLED = 2,
} MsGuardStatus;

MS_LIST_DEFINE(MsFaultNoteList, ms_fault_note_list, MsFaultNote)

/* What a report carries besides its text. The text is the message, then the frames and cleanup faults as printed;
 * `message_length` says where the message ends, which is what the record holds. */
typedef struct MsFaultDetail {
  MsFaultKind kind;
  size_t message_length;
  MsFrameList frames;    /* where the fault was raised */
  MsFrameList started;   /* where the task was started, when it ran as one (empty otherwise) */
  char *started_names;   /* owned: the file and function names of `started`'s frame, or NULL */
  MsFaultNoteList notes; /* faults raised by cleanups, in order; each note owns its bytes */
} MsFaultDetail;

/* A fault report handed from the fault path to the guard that catches it, and from there to whoever joins the task.
 * Owned by the receiver, which releases it with ms_fault_text_free. */
typedef struct MsFaultText {
  uint8_t *bytes; /* owned: the message, then the frames and cleanup faults as printed */
  size_t length;
  MsFaultDetail *detail; /* owned, or NULL for a report made without one (a deadlock found by the scheduler) */
} MsFaultText;

void ms_fault_text_release(MsFaultText *text) MS_NONNULL;
/* Frees the report and leaves `*text` empty. Most reports are empty (no fault happened), so that test is inline. */
MS_NONNULL static inline void ms_fault_text_free(MsFaultText *text) {
  if (text->bytes != NULL || text->detail != NULL) {
    ms_fault_text_release(text);
  }
}
/* An independent copy of the report, detail included; the caller frees it. */
MsFaultText ms_fault_text_clone(const MsFaultText *text) MS_NONNULL;
/* Adds the line a task was started from to `text`, under a `task started by:` line. `site` is that line as a
 * report shows a frame (`file:line in function`); a line of the standard library is left out. */
void ms_fault_text_add_started(MsFaultText *text, MsSpan site) MS_NONNULL_ARGS(1);

/* ---- raising ---- */

/* Raises a fault of `kind` with `message` (copied before the call returns control to the unwinder). */
MS_NORETURN void ms_fault(MsFaultKind kind, MsSpan message);
/* The same with a message built in `message`, which the fault releases: it never returns, so the caller cannot. */
MS_NORETURN void ms_fault_built(MsFaultKind kind, MsStrBuild *message) MS_NONNULL;

/* Raises a plain fault with a C string literal as the message. */
MS_NORETURN void ms_fault_text(MsFaultKind kind, const char *message);

/* An allocation of `bytes` bytes was refused: the full fault path with the size in the message. Reporting can need
 * memory too, so a refusal while reporting one falls back to ms_fault_fatal. */
MS_NORETURN void ms_fault_out_of_memory(size_t bytes);

/* Ends the process now with the message and the record, with no frames and no cleanups. For a fault with
 * no task to leave (a broken invariant) or one that cannot allocate. Allocates nothing. */
MS_NORETURN void ms_fault_fatal(MsFaultKind kind, MsSpan message);

/* Reports a fault that left a guarded task (its cleanups already ran) and ends the process with its status.
 * Frees `text`. */
MS_NORETURN void ms_fault_exit(MsFaultText *text) MS_NONNULL;

/* Installs the fatal hook of base so its unrecoverable conditions (allocation failure, overflow, a bad
 * index) raise Manuscript faults. Called once by the runtime at start-up. */
void ms_fault_install_base_hook(void);

#endif
