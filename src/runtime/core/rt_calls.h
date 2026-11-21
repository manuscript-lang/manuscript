/* rt_calls.h: what src/runtime/core calls by its exported name and the Rust runtime still defines: faults, objects,
 * strings and the cleanup stack. Each moves to its own C module in turn; the declarations here follow it
 * and the unit tests link src/runtime/tests/support/rt_stubs.c in place of them.
 *
 * The allocator is C already (ms_rt/alloc.h). Faults do not return: they leave by the runtime's jump.
 */
#ifndef MS_RT_CALLS_H
#define MS_RT_CALLS_H

#include "ms_rt/base.h"
#include "ms_rt/safe.h"
#include "ms_rt/desc.h"
#include "ms_rt/fault.h"
#include "ms_rt/map.h"
#include "ms_rt/obj.h"
#include "ms_rt/string.h"

/* The families of fault are ms_rt/fault.h's; core files that predate it keep their spellings. */
#define MS_FAULT_GENERIC MS_FAULT_KIND_FAULT
#define MS_FAULT_OVERFLOW MS_FAULT_KIND_OVERFLOW
#define MS_FAULT_INDEX_OUT_OF_RANGE MS_FAULT_KIND_INDEX_OUT_OF_RANGE

/* Raises a fault of `kind` with the message `msg[0..len]`. */
MS_NORETURN void msfault_raise(uint8_t kind, const uint8_t *msg, size_t len);
/* The faults (msrt_fault and friends), cleanups and task_grow are ms_rt/fault.h and ms_rt/task.h. */

#endif
