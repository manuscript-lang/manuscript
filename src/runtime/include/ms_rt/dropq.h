/* ms_rt/dropq.h: freeing deeply nested data in constant stack (src/runtime/core/dropq.c).
 *
 * The drop glue of a type that can contain itself (a tree, a JSON or TOML value) enters here: below the limit of
 * nested drops it runs as before; at the limit it parks the value in a heap block on a worklist (msrt_drop_defer) and
 * returns, and the drop that started the nest drains the worklist when it finishes (msrt_drop_leave). Each drained
 * value starts a fresh nest, so the stack never holds more than the limit however deep the data is, on the main
 * task and on a 512 KiB task slot alike. Only data deeper than the limit is reordered: its deepest parts are freed
 * after their siblings instead of before. The state is per thread. */
#ifndef MS_RT_DROPQ_H
#define MS_RT_DROPQ_H

#include "ms_rt/base.h"

typedef void (*MsDropRun)(uint8_t *block);
typedef void (*MsSlotCopyRun)(const uint8_t *src, uint8_t *dst);

/* Starts a drop of recursive data: nonzero when the caller must hand the value to msrt_drop_defer and return without
 * calling msrt_drop_leave. */
/* ms-sig: msrt_drop_enter() -> u64 @leaf */
uint64_t msrt_drop_enter(void);
/* Parks the heap block `block` holding a value that `run` drops; the runtime frees the block after `run`. */
/* ms-sig: msrt_drop_defer(run: RunDrop, block: *mut u8) @leaf */
void msrt_drop_defer(MsDropRun run, uint8_t *block);
/* Ends a drop msrt_drop_enter let run; the outermost one drops what was deferred. */
/* ms-sig: msrt_drop_leave() */
void msrt_drop_leave(void);
/* Runs `copy(src, dst)` on a new stack segment: the copy glue of recursive data calls this when the stack is nearly
 * used up, like a recursive function's grow shim (msrt_task_grow). */
/* ms-sig: msrt_slot_copy_grown(copy: RunCopy, src: *const u8, dst: *mut u8) */
void msrt_slot_copy_grown(MsSlotCopyRun copy, const uint8_t *src, uint8_t *dst);

#endif
