/* runtime/core/slot.c: the slot and hash natives of generated code: thin calls into base. */
#include "runtime/core/slot.h"

#include "base/hash.h"
#include "runtime/core/task.h"

/* The slot walks recurse once per level of a recursive type through generated helpers, so each grows the task's
 * stack the way a written cyclic function does. */
typedef struct SlotCall {
  const MsTypeDesc *desc;
  const uint8_t *a;
  uint8_t *b;
  uint64_t result;
} SlotCall;

static void drop_call(void *argument) {
  SlotCall *call = argument;
  ms_slot_drop(call->desc, call->b);
}

static void copy_call(void *argument) {
  SlotCall *call = argument;
  ms_slot_copy(call->desc, call->a, call->b);
}

static void eq_call(void *argument) {
  SlotCall *call = argument;
  call->result = ms_slot_equal(call->desc, call->a, call->b);
}

static void hash_call(void *argument) {
  SlotCall *call = argument;
  call->result = ms_slot_hash(call->desc, call->a);
}

void msrt_slot_drop(const MsTypeDesc *d, uint8_t *slot) {
  if (ms_stack_low()) {
    SlotCall call = {.desc = d, .b = slot};
    ms_stack_call(drop_call, &call);
    return;
  }
  ms_slot_drop(d, slot);
}

void msrt_slot_copy(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst) {
  if (ms_stack_low()) {
    SlotCall call = {.desc = d, .a = src, .b = dst};
    ms_stack_call(copy_call, &call);
    return;
  }
  ms_slot_copy(d, src, dst);
}

uint8_t msrt_slot_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b) {
  if (ms_stack_low()) {
    SlotCall call = {.desc = d, .a = a, .b = (uint8_t *)(uintptr_t)b};
    ms_stack_call(eq_call, &call);
    return (uint8_t)call.result;
  }
  return ms_slot_equal(d, a, b);
}

int64_t msrt_slot_hash(const MsTypeDesc *d, const uint8_t *slot) {
  if (ms_stack_low()) {
    SlotCall call = {.desc = d, .a = slot};
    ms_stack_call(hash_call, &call);
    return (int64_t)call.result;
  }
  return (int64_t)ms_slot_hash(d, slot);
}

int64_t msrt_hash_combine(int64_t a, int64_t b) {
  return (int64_t)ms_hash_combine((uint64_t)a, (uint64_t)b);
}

int64_t msrt_hash_bytes(const uint8_t *p, size_t len) {
  return (int64_t)ms_hash_span(ms_span_of(p, len));
}

int64_t msrt_hash_int(int64_t v) {
  return (int64_t)ms_hash_int((uint64_t)v);
}
