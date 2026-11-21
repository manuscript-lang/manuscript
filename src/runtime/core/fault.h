/* fault.h: raising a fault, the report it leaves and the record the CLI reads. Internal to src/runtime/core.
 *
 * A fault ends the task that raised it. ms_fault captures the source frames, runs the task's cleanups (last in,
 * first out), and leaves by the innermost guard (ms_guard_call) with the report, or, with no guard open, prints
 * the report, writes the record and ends the process. A fault raised by a cleanup is added to the report of the
 * fault being handled, and the remaining cleanups still run.
 *
 * The state of a fault in progress lives in the frame of the function that raised it (`MsFaultFlight`), reached
 * from the task's unwind state, so nothing is global and two tasks can be reporting at once.
 *
 * The record (crates/ms-rt-abi/src/record.rs) is written to the file named by MS_FAULT_RECORD, once, as the process
 * ends; the text on standard error is for people and is never parsed.
 */
#ifndef MS_CORE_FAULT_H
#define MS_CORE_FAULT_H

#include <stdint.h>

#include "frames.h"
#include "ms_rt/fault.h"
#include "ms_rt/safe.h"

/* Outcome of a guarded call (ms_guard_call in unwind.h). */
typedef enum MsGuardStatus {
    MS_GUARD_OK = 0,
    MS_GUARD_FAULT = 1,
    MS_GUARD_CANCELLED = 2,
} MsGuardStatus;

/* The status a process ends with after a fault of `kind`. */
static inline int ms_fault_exit_status(MsFaultKind kind) {
    switch (kind) {
    case MS_FAULT_KIND_TEST_FAILURE:
        return MS_EXIT_TEST_FAILURE;
    case MS_FAULT_KIND_STACK_OVERFLOW:
        return MS_EXIT_STACK_OVERFLOW;
    case MS_FAULT_KIND_OUT_OF_MEMORY:
        return MS_EXIT_NO_MEMORY;
    case MS_FAULT_KIND_FAULT:
    case MS_FAULT_KIND_INCOMPLETE_CLEANUP:
    case MS_FAULT_KIND_DEADLOCK:
    case MS_FAULT_KIND_DIVISION_BY_ZERO:
    case MS_FAULT_KIND_OVERFLOW:
    case MS_FAULT_KIND_INDEX_OUT_OF_RANGE:
        return MS_EXIT_ABORT;
    }
    return MS_EXIT_ABORT;
}

/* A fault raised while another was being reported: its message, owned. */
typedef struct MsFaultNote {
    uint8_t *bytes;
    size_t length;
} MsFaultNote;

/* What a report carries besides its text. The text is the message, then the frames and cleanup faults as printed;
 * `message_length` says where the message ends, which is what the record holds. */
typedef struct MsFaultDetail {
    MsFaultKind kind;
    size_t message_length;
    MsFrameList frames;  /* where the fault was raised */
    MsFrameList started; /* where the task was started, when it ran as one (empty otherwise) */
    MsFaultNote *notes;  /* owned: faults raised by cleanups, in order */
    size_t note_count;
    size_t note_capacity;
} MsFaultDetail;

/* A fault report handed from the fault path to the guard that catches it, and from there to whoever joins the task.
 * Owned by the receiver, which releases it with ms_fault_text_free. `bytes` is the message, then the source frames
 * and cleanup faults as printed. */
typedef struct MsFaultText {
    uint8_t *bytes; /* owned */
    size_t length;
    MsFaultDetail *detail; /* owned, or NULL for a report made without one (a deadlock found by the scheduler) */
} MsFaultText;

/* Frees the report and leaves `*text` empty. */
void ms_fault_text_free(MsFaultText *text) MS_NONNULL;
/* An independent copy of the report, detail included; the caller frees it. */
MsFaultText ms_fault_text_clone(const MsFaultText *text) MS_NONNULL;

/* ---- raising ---- */

/* Raises a fault of `kind` on the running task. Never returns. */
MS_NORETURN void ms_fault(MsFaultKind kind, MsBytes message);
/* An allocation of `bytes` bytes was refused: the full fault path with the size in the message. Reporting can need
 * memory too, so a refusal while reporting one falls back to ms_fault_fatal. */
MS_NORETURN void ms_fault_out_of_memory(size_t bytes);
/* Ends the process now: the message and the record, with no frames and no cleanups. For a fault with no task
 * to leave (a broken invariant) or one that cannot allocate. Allocates nothing. */
MS_NORETURN void ms_fault_fatal(MsFaultKind kind, MsBytes message);

/* ---- reports that outlive the fault ---- */

/* Adds the frames a task was started from to `text`, under a `task started by:` line. `addresses` are what
 * ms_fault_capture_frames returned. */
void ms_fault_text_add_started(MsFaultText *text, const uintptr_t *addresses, size_t count) MS_NONNULL_ARGS(1);
/* Reports a fault that left a guarded task (its cleanups already ran) and ends the process with its status.
 * Frees `text`. */
MS_NORETURN void ms_fault_exit(MsFaultText *text) MS_NONNULL;
/* The return addresses of the frames calling this function, innermost first, at most `capacity`; nothing is
 * allocated. Describe them later with ms_fault_text_add_started. Returns how many were captured. */
size_t ms_fault_capture_frames(uintptr_t *out, size_t capacity) MS_NONNULL;

/* ---- the record ---- */

/* The record as the CLI reads it. Frames, cleanup faults and the site are optional. */
typedef struct MsFaultRecord {
    uint32_t pid;
    MsFaultKind kind;
    MsBytes message;
    const MsFrameList *frames;   /* may be NULL */
    const MsFrameList *started;  /* may be NULL */
    const MsFaultNote *notes;    /* `note_count` of them */
    size_t note_count;
    bool has_site; /* a failed test's `file:line:column` follows */
    MsBytes site;
} MsFaultRecord;

/* Encodes `record`. Returns the size the encoding needs, and writes it only when that fits in `capacity`. */
size_t ms_fault_record_encode(const MsFaultRecord *record, uint8_t *out, size_t capacity) MS_NONNULL_ARGS(1);
/* Writes a record holding only `kind` and `message` (and `site` when `has_site`) to the file MS_FAULT_RECORD names,
 * if there is one. For a failed test and a stop that cleanup did not survive. Allocates only for a record that does
 * not fit in 1 KiB. */
void ms_fault_record_write(MsFaultKind kind, MsBytes message, bool has_site, MsBytes site);

#endif
