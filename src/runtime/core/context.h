/* context.h: stack switching, the lowest layer of tasks. Internal to src/runtime/core.
 *
 * Three assembly routines per target (x86-64 and AArch64; System V, Apple and Windows calling conventions):
 *
 *  - ms_ctx_switch saves the callee-saved registers on the running stack, stores its pointer, and resumes a
 *    stack that was saved the same way (or built by ms_ctx_initial_sp);
 *  - ms_ctx_call_on_stack runs a function on another stack and comes back (stack segments, see task.h);
 *
 * Windows keeps three stack bounds in the thread environment block (TEB); the kernel's guard-page growth and
 * stack walks use them, so a switch installs the bounds of the stack it moves to. The `teb` parameters carry
 * those three words (stack base, stack limit, deallocation stack) and every other target ignores them, so a
 * caller has one code path.
 */
#ifndef MS_CORE_CONTEXT_H
#define MS_CORE_CONTEXT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "base/safe.h"

/* Words of the thread environment block that describe the stack: base, limit, deallocation stack. */
#define MS_CTX_TEB_WORDS 3

/* Entry of a new stack: called once, never returns (the code behind it switches away for good). */
typedef void (*MsCtxEntry)(void);

/* Saves the running context in `*save`, then resumes `next`. Returns when something switches back. */
void ms_ctx_switch(uintptr_t *save, uintptr_t next, const uintptr_t *teb) MS_NONNULL_ARGS(1);

/* Stores the stack pointer in `*save`, runs `function(argument)` on the stack that ends at `top` (16-byte
 * aligned) and returns. `teb` holds six words on Windows: the bounds of the new stack, then the caller's. */
void ms_ctx_call_on_stack(uintptr_t top, void (*function)(void *), void *argument, uintptr_t *save,
                          const uintptr_t *teb) MS_NONNULL_ARGS(2, 4);

/* Writes the first frame of a stack that ends at `top` (16-byte aligned, writable below) so that switching to
 * the result calls `entry` on that stack. */
uintptr_t ms_ctx_initial_sp(uint8_t *top, MsCtxEntry entry) MS_NONNULL;

/* Reads the three stack words of the thread environment block (Windows); zeros elsewhere. */
void ms_ctx_teb_stack(uintptr_t out[MS_CTX_TEB_WORDS]) MS_NONNULL;

#endif
