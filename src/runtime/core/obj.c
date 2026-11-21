/* Objects with a header. See obj.h. */
#include "runtime/core/obj.h"

#include "runtime/core/fault.h"

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
  __builtin_memcpy(&next, &dead->clone, sizeof(void *));
  return next;
}

static void run_drop(MsObj *object) {
  if (object->drop == NULL) {
    ms_fault_text(MS_FAULT_KIND_FAULT, "object without drop");
  }
  object->drop(object);
}

MsObj *msrt_obj_clone(MsObj *object) {
  if (object == NULL) {
    return NULL;
  }
  if (object->clone == NULL) {
    ms_fault_text(MS_FAULT_KIND_FAULT, "copy of a value that has one owner");
  }
  return object->clone(object);
}

void msrt_obj_drop(MsObj *object) {
  if (object == NULL) {
    return;
  }
  if (drops.depth >= MAX_DROP_DEPTH) {
    __builtin_memcpy(&object->clone, &drops.pending, sizeof(void *));
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

void ms_obj_install_bounded_drop(void) { ms_obj_install_drop(msrt_obj_drop); }
