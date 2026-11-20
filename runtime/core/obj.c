/* Objects with a header, and the work counters. See ms_rt/obj.h. */
#include "ms_rt/obj.h"

#include <stdatomic.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/list.h"
#include "rt_calls.h"

enum { MAX_DROP_DEPTH = 4096 };

typedef struct DropState {
    uint32_t depth;
    MsObj *pending; /* dead objects waiting for their drop, linked through their clone slot */
} DropState;

static _Thread_local DropState drops; /* per-thread state, like the scheduler's */

/* A dead object's clone slot is free, and a function pointer is as wide as an object pointer on every target. */
_Static_assert(sizeof(void *) == sizeof(void (*)(void)), "the clone slot links the pending list");

static MsObj *pending_next(const MsObj *dead) {
    MsObj *next;
    memcpy(&next, &dead->clone, sizeof(void *));
    return next;
}

static void run_drop(MsObj *object) {
    if (object->drop == NULL) {
        static const char message[] = "object without drop";
        msrt_fault((const uint8_t *)message, sizeof message - 1);
    }
    object->drop(object);
}

MsObj *msrt_obj_clone(MsObj *object) {
    if (object == NULL) {
        return NULL;
    }
    if (object->clone == NULL) {
        static const char message[] = "copy of a value that has one owner";
        msrt_fault((const uint8_t *)message, sizeof message - 1);
    }
    return object->clone(object);
}

void msrt_obj_drop(MsObj *object) {
    if (object == NULL) {
        return;
    }
    if (drops.depth >= MAX_DROP_DEPTH) {
        memcpy(&object->clone, &drops.pending, sizeof(void *));
        drops.pending = object;
        return;
    }
    drops.depth++;
    run_drop(object);
    drops.depth--;
    if (drops.depth != 0) {
        return;
    }
    while (drops.pending != NULL) {
        MsObj *const next = drops.pending;
        drops.pending = pending_next(next);
        drops.depth = 1;
        run_drop(next);
        drops.depth = 0;
    }
}

/* MIR operations executed, added by the counting calls of an `ms bench --ops` build. */
static _Atomic uint64_t operations;

void msrt_ops_add(int64_t n) { atomic_fetch_add_explicit(&operations, (uint64_t)n, memory_order_relaxed); }

void msrt_counts(uint64_t *out) {
    uint64_t requested[2];
    uint64_t copies[4];
    msrt_heap_requested(requested);
    msrt_copy_counts(copies);
    out[0] = requested[0];
    out[1] = requested[1];
    for (int i = 0; i < 4; i++) {
        out[2 + i] = copies[i];
    }
    out[6] = atomic_load_explicit(&operations, memory_order_relaxed);
}
