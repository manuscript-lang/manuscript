/* Freeing deeply nested data in constant stack. See ms_rt/dropq.h. */
#include "dropq.h"

#include "ms_rt/dropq.h"

#include "array.h"
#include "rt_calls.h"
#include "ms_rt/task.h"
#include "ms_rt/alloc.h"
#include "ms_rt/safe.h"

enum { NEST_LIMIT = 256 };

typedef struct Deferred {
    MsDropRun run;
    uint8_t *block;
} Deferred;

typedef struct DropState {
    uint32_t depth;
    bool draining;
    Deferred *pending; /* values waiting to be dropped, newest last */
    size_t length;
    size_t capacity;
} DropState;

static _Thread_local DropState state; /* per-thread state, like the scheduler's */

uint64_t msrt_drop_enter(void) {
    if (state.depth >= NEST_LIMIT) {
        return 1;
    }
    state.depth++;
    return 0;
}

void msrt_drop_defer(MsDropRun run, uint8_t *block) {
    void *pending = state.pending;
    if (!ms_array_reserve(&pending, &state.capacity, state.length + 1, sizeof *state.pending)) {
        run(block); /* no room to defer: nest one level deeper instead of losing the value */
        msrt_free(block);
        return;
    }
    state.pending = pending;
    state.pending[state.length++] = (Deferred){.run = run, .block = block};
}

void msrt_drop_leave(void) {
    if (state.depth > 0) {
        state.depth--;
    }
    if (state.depth != 0 || state.draining) {
        return;
    }
    state.draining = true;
    while (state.length != 0) {
        const Deferred item = state.pending[--state.length];
        item.run(item.block); /* may enter again and defer more: no borrow of the state lives across the call */
        msrt_free(item.block);
    }
    state.draining = false;
    /* The worklist is empty and a thread may exit without another drop: free it so no block outlives the last one. */
    msrt_free(state.pending);
    state.pending = NULL;
    state.capacity = 0;
}

void msdrop_reset(void) {
    state.depth = 0;
    state.draining = false;
}

typedef struct CopyJob {
    MsSlotCopyRun copy;
    const uint8_t *src;
    uint8_t *dst;
} CopyJob;

static void run_copy(void *block) { // NOLINT(readability-non-const-parameter): the grow shim signature
    CopyJob job;
    __builtin_memcpy(&job, block, sizeof job);
    job.copy(job.src, job.dst);
}

void msrt_slot_copy_grown(MsSlotCopyRun copy, const uint8_t *src, uint8_t *dst) { // NOLINT(readability-non-const-parameter): the copy writes it
    /* The job is a heap block, freed here or by the grow's cleanup if the copy leaves by a fault. */
    CopyJob *const job = msrt_alloc(sizeof *job);
    *job = (CopyJob){.copy = copy, .src = src, .dst = dst};
    msrt_task_grow(run_copy, job);
    msrt_free(job);
}
