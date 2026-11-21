/* runtime/core/slot.c: the slot and hash natives of generated code: thin calls into base. */
#include "runtime/core/slot.h"

#include "base/hash.h"

void msrt_slot_drop(const MsTypeDesc *d, uint8_t *slot) {
  ms_slot_drop(d, slot);
}

void msrt_slot_copy(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst) {
  ms_slot_copy(d, src, dst);
}

uint8_t msrt_slot_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b) {
  return ms_slot_equal(d, a, b);
}

int64_t msrt_slot_hash(const MsTypeDesc *d, const uint8_t *slot) {
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
