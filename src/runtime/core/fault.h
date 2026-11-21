/* runtime/core/fault.h: raising a fault, the one way runtime code ends a task it cannot continue.
 *
 * A fault ends the task that raised it: its cleanups run last in, first out, and it leaves by the innermost
 * guard with a report, or ends the process with the status of its kind (abi/fault.h). The natives in core, io,
 * net and std call these and never return. Implementation: runtime/core/fault.c. */
#ifndef MS_RUNTIME_CORE_FAULT_H
#define MS_RUNTIME_CORE_FAULT_H

#include "abi/fault.h"
#include "base/safe.h"

/* Raises a fault of `kind` with `message` (copied before the call returns control to the unwinder). */
MS_NORETURN void ms_fault(MsFaultKind kind, MsSpan message);

/* Raises a plain fault with a C string literal as the message. */
MS_NORETURN void ms_fault_text(MsFaultKind kind, const char *message);

/* An allocation of `bytes` bytes was refused: the full fault path with the size in the message. */
MS_NORETURN void ms_fault_out_of_memory(size_t bytes);

/* Ends the process now with the message and the record, with no frames and no cleanups. For a fault with
 * no task to leave (a broken invariant) or one that cannot allocate. Allocates nothing. */
MS_NORETURN void ms_fault_fatal(MsFaultKind kind, MsSpan message);

/* Installs the fatal hook of base so its unrecoverable conditions (allocation failure, overflow, a bad
 * index) raise Manuscript faults. Called once by the runtime at start-up. */
void ms_fault_install_base_hook(void);

#endif
