/* runtime/core/slot.h: drop, copy, equality and hash of the value in a slot, by descriptor, for generated
 * code (the descriptors and the work are base/desc.h). */
#ifndef MS_RUNTIME_CORE_SLOT_H
#define MS_RUNTIME_CORE_SLOT_H

#include "base/desc.h"

/* ms-sig: msrt_slot_drop(d: *const TypeDesc, slot: *mut u8) @leaf */
void msrt_slot_drop(const MsTypeDesc *d, uint8_t *slot);
/* ms-sig: msrt_slot_copy(d: *const TypeDesc, src: *const u8, dst: *mut u8) @leaf */
void msrt_slot_copy(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst);
/* ms-sig: msrt_slot_eq(d: *const TypeDesc, a: *const u8, b: *const u8) -> u8 @domain=slot @leaf */
uint8_t msrt_slot_eq(const MsTypeDesc *d, const uint8_t *a, const uint8_t *b);
/* ms-sig: msrt_slot_hash(d: *const TypeDesc, slot: *const u8) -> i64 @leaf */
int64_t msrt_slot_hash(const MsTypeDesc *d, const uint8_t *slot);
/* ms-sig: msrt_hash_combine(a: i64, b: i64) -> i64 @leaf */
int64_t msrt_hash_combine(int64_t a, int64_t b);
/* ms-sig: msrt_hash_bytes(p: *const u8, len: usize) -> i64 @domain=map @leaf */
int64_t msrt_hash_bytes(const uint8_t *p, size_t len);
/* ms-sig: msrt_hash_int(v: i64) -> i64 @domain=map @leaf */
int64_t msrt_hash_int(int64_t v);

#endif
