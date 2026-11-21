/* stack.h: where task stacks live. Internal to src/runtime/core.
 *
 * Stacks are slices of address space, committed as they grow, so a parked task costs the pages it touched and
 * a new task costs a pointer bump:
 *
 *   region (256 MiB, aligned to its size)
 *   +--------+--------+-- ... --+--------+---------------------+
 *   | slot 0 | slot 1 |         | slot N | last page: the cell |
 *   +--------+--------+-- ... --+--------+---------------------+
 *   slot = 512 KiB, its lowest 64 KiB a guard that faults when touched; the stack grows down from its end.
 *
 * Because a region is aligned to its size, generated code finds the running task's header with one mask of the
 * stack pointer: the last 16 bytes of the region hold the header pointer and the recursion limit
 * (`ms_rt_abi::symbols::ISOLATE_HDR`, `STACK_LIMIT_CELL`). The runtime rewrites the cell on every task switch.
 * A main task takes a whole region for 256 MiB of stack; every other task takes a slot.
 *
 * Slots are never unmapped one at a time: that would split a region's mapping, and vm.max_map_count bounds the
 * mappings of a process (about 32k tasks, issue 2483). A finished task's slot goes to a pool, and regions go back
 * to the system when the scheduler ends.
 */
#ifndef MS_CORE_STACK_H
#define MS_CORE_STACK_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "context.h"

#define MS_STACK_REGION ((size_t)256 << 20)
#define MS_STACK_SLOT ((size_t)512 << 10)
#define MS_STACK_GUARD ((size_t)64 << 10)
#define MS_STACK_PAGE ((size_t)4096)
/* The cell: header pointer at 16 bytes from the region's end, recursion limit at 8. */
#define MS_STACK_CELL_HDR 16
#define MS_STACK_CELL_LIMIT 8
/* Slots per region: the last page holds the cell, so the top slot is left out. */
#define MS_STACK_SLOTS_PER_REGION ((MS_STACK_REGION - MS_STACK_PAGE) / MS_STACK_SLOT)
/* Bytes committed up front at the top of a stack where commits are explicit (Windows). */
#define MS_STACK_INITIAL_COMMIT ((size_t)8192)

_Static_assert(MS_STACK_SLOTS_PER_REGION * MS_STACK_SLOT + MS_STACK_PAGE <= MS_STACK_REGION,
               "the slots and the cell page fit one region");

typedef struct MsStackEntry {
    uint8_t *base; /* start of the slot, guard included */
    size_t length; /* MS_STACK_SLOT, or MS_STACK_REGION for a main task */
} MsStackEntry;

/* One scheduler's stacks. Zero-initialise it; ms_stacks_destroy releases everything. Not thread safe. */
typedef struct MsStacks {
    MsStackEntry *pool; /* owned: finished tasks' stacks, newest last */
    size_t pool_length;
    size_t pool_capacity;
    size_t pool_clean;  /* pool[0..pool_clean) have given their pages back (ms_stacks_trim) */
    uint8_t *carve;     /* next unused slot of the newest region */
    uint8_t *carve_end; /* end of the usable slots of the newest region */
    uint8_t **regions;  /* owned: every region mapped, unmapped by ms_stacks_destroy */
    size_t regions_length;
    size_t regions_capacity;
} MsStacks;

/* The bounds of a prepared stack: lowest usable address, one past the highest, initial stack pointer. */
typedef struct MsStackBounds {
    uintptr_t low;
    uintptr_t high;
    uintptr_t sp;
} MsStackBounds;

/* A pooled or fresh stack of `length` bytes (MS_STACK_SLOT or MS_STACK_REGION), guard installed. False when
 * address space or mappings are used up, or the guard cannot be installed (a stack without its guard must not
 * be used). On success `*base` is the slot's start. */
MS_NODISCARD bool ms_stacks_acquire(MsStacks *stacks, size_t length, uint8_t **base) MS_NONNULL;

/* Hands a stack of a finished task back to the pool. */
void ms_stacks_release(MsStacks *stacks, uint8_t *base, size_t length) MS_NONNULL;

/* Gives the pages of the oldest pooled stacks back to the system, keeping the newest `warm` of them as they
 * are. Each stack is trimmed once. Called before the scheduler blocks, so a quiet server shrinks. */
void ms_stacks_trim(MsStacks *stacks, size_t warm) MS_NONNULL;

/* Unmaps every region and frees the tables. The stacks must be unused. */
void ms_stacks_destroy(MsStacks *stacks) MS_NONNULL;

/* One past the highest usable address of the stack at `base`: a main task's region keeps its last page for the
 * cell, a slot ends where the next begins. */
uintptr_t ms_stack_top(const uint8_t *base, size_t length);

/* Commits the first pages and a guard page below them, where commits are explicit (Windows); the kernel commits
 * the rest as the stack grows. False when the system refuses. */
MS_NODISCARD bool ms_stack_commit_top(uint8_t *base, size_t length) MS_NONNULL;

/* Commits the top of the stack and builds its first frame, so switching to `bounds->sp` calls `entry`. */
MS_NODISCARD bool ms_stack_prepare(uint8_t *base, size_t length, MsCtxEntry entry, MsStackBounds *bounds) MS_NONNULL;

/* The recursion limit of a stack with the given bounds: the lowest address recursive calls may reach before
 * they fault. Cleanups run past it in a reserve, so the limit leaves 1/8 of the stack (clamped) free. */
uintptr_t ms_stack_limit(uintptr_t low, uintptr_t high);

/* Writes the two words of the cell of the region that holds `inside` (any address of a stack in it). Done on
 * every switch. */
void ms_stack_publish(uint8_t *inside, void *header, uintptr_t limit) MS_NONNULL_ARGS(1);

#endif
