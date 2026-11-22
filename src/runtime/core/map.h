/* runtime/core/map.h: the map and set natives. Every function takes the address of the map value, the
 * descriptor of its key type and (for a map) of its value type; a set passes NULL for the value type. A map
 * keeps the key descriptor of the module that created it (`MsMap.desc`), so `kd` only serves a map that was
 * made without one. A function that stores a key or value takes ownership of the slot it is given; a name
 * ending in `_borrowed` borrows the key. The table itself is base/map.h. */
#ifndef MS_RUNTIME_CORE_MAP_H
#define MS_RUNTIME_CORE_MAP_H

#include "base/map.h"

/* ms-sig: msrt_map_new(out: *mut MapVal) @domain=map @leaf */
void msrt_map_new(MsMap *out);
/* ms-sig: msrt_map_stamp(m: *mut MapVal, kd: KeyDesc) @domain=map @leaf */
void msrt_map_stamp(MsMap *m, const MsTypeDesc *kd);
/* ms-sig: msrt_map_drop(m: *mut MapVal, kd: KeyDesc, vd: ValDesc) @domain=map @leaf */
void msrt_map_drop(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd);
/* ms-sig: msrt_map_copy(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut MapVal) @domain=map @leaf
 * @method=Map.clone */
void msrt_map_copy(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsMap *out);
/* ms-sig: msrt_map_reserve(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, n: i64) @domain=map @leaf */
void msrt_map_reserve(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, int64_t n);
/* ms-sig: msrt_map_clear(m: *mut MapVal, kd: KeyDesc, vd: ValDesc) @domain=map @leaf */
void msrt_map_clear(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd);
/* ms-sig: msrt_map_length(m: *const MapVal) -> i64 @domain=map @leaf @pure */
int64_t msrt_map_length(const MsMap *m);
/* ms-sig: msrt_map_slot_count(m: *const MapVal) -> i64 @domain=map @leaf @pure */
int64_t msrt_map_slot_count(const MsMap *m);
/* ms-sig: msrt_map_entry_ptrs(m: *const MapVal, kd: KeyDesc, vd: ValDesc, i: i64, key_out: *mut *const u8,
 * val_out: *mut *const u8) -> u8 @domain=map @leaf */
uint8_t msrt_map_entry_ptrs(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, int64_t i,
                            const uint8_t **key_out, const uint8_t **val_out);

/* ms-sig: msrt_map_add(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, key: *mut u8, val: *mut u8) @domain=map
 * @leaf */
void msrt_map_add(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val);
/* ms-sig: msrt_map_add_w8(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, key: *mut u8, val: *mut u8) @domain=map
 * @leaf */
void msrt_map_add_w8(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val);
/* ms-sig: msrt_map_add_sw8(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, key: *mut u8, val: *mut u8) @domain=map
 * @leaf */
void msrt_map_add_sw8(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val);
/* ms-sig: msrt_map_add_borrowed(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8, val: *mut u8)
 * @domain=map @leaf */
void msrt_map_add_borrowed(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                       uint8_t *val);
/* ms-sig: msrt_map_add_default(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, key: *mut u8, val: *mut u8)
 * @domain=map @leaf */
void msrt_map_add_default(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val);
/* ms-sig: msrt_map_add_default_borrowed(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8, val: *mut u8)
 * @domain=map @leaf */
void msrt_map_add_default_borrowed(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                               uint8_t *val);
/* ms-sig: msrt_map_slot_borrowed(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8, default: *mut u8) ->
 * *mut u8 @domain=map @leaf */
uint8_t *msrt_map_slot_borrowed(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                            uint8_t *default_value);
/* ms-sig: msrt_map_remove(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) @domain=map @leaf */
void msrt_map_remove(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
/* ms-sig: msrt_map_merge(m: *mut MapVal, other: *const MapVal, kd: KeyDesc, vd: ValDesc) @domain=map @leaf */
void msrt_map_merge(MsMap *m, const MsMap *other, const MsTypeDesc *kd, const MsTypeDesc *vd);
/* ms-sig: msrt_map_add_table(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, table: *const StrVal) @domain=map
 * @leaf */
void msrt_map_add_table(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const MsString *table);

/* ms-sig: msrt_map_contains(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> u8 @domain=map
 * @leaf */
uint8_t msrt_map_contains(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
/* ms-sig: msrt_map_contains_w8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> u8 @domain=map
 * @leaf @pure @word_key_of=msrt_map_contains */
uint8_t msrt_map_contains_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
/* ms-sig: msrt_map_contains_sw8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> u8 @domain=map
 * @leaf @pure @text_key_of=msrt_map_contains */
uint8_t msrt_map_contains_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
/* ms-sig: msrt_map_get_ptr(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> *const u8
 * @domain=map @leaf */
const uint8_t *msrt_map_get_ptr(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd,
                                const uint8_t *key);
/* ms-sig: msrt_map_get_ptr_w8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> *const u8
 * @domain=map @leaf @pure @word_key_of=msrt_map_get_ptr */
const uint8_t *msrt_map_get_ptr_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd,
                                   const uint8_t *key);
/* ms-sig: msrt_map_get_ptr_sw8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> *const u8
 * @domain=map @leaf @pure @text_key_of=msrt_map_get_ptr */
const uint8_t *msrt_map_get_ptr_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd,
                                    const uint8_t *key);
/* ms-sig: msrt_map_get(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8, out: *mut u8) -> u8
 * @domain=map @leaf */
uint8_t msrt_map_get(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                     uint8_t *out);
/* ms-sig: msrt_map_get_w8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8, out: *mut u8) -> u8
 * @domain=map @leaf @word_key_of=msrt_map_get */
uint8_t msrt_map_get_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                        uint8_t *out);
/* ms-sig: msrt_map_get_sw8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8, out: *mut u8) -> u8
 * @domain=map @leaf @text_key_of=msrt_map_get */
uint8_t msrt_map_get_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                         uint8_t *out);

/* ms-sig: msrt_map_keys(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut VecVal) @domain=map @leaf */
void msrt_map_keys(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out);
/* ms-sig: msrt_map_values(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut VecVal) @domain=map @leaf */
void msrt_map_values(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out);
/* ms-sig: msrt_map_keys_view(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut VecVal) @borrows @domain=map @leaf
 * @view_of=msrt_map_keys */
void msrt_map_keys_view(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out);
/* ms-sig: msrt_map_values_view(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut VecVal) @borrows @domain=map
 * @leaf @view_of=msrt_map_values */
void msrt_map_values_view(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out);

/* ms-sig: msrt_set_add(m: *mut MapVal, kd: KeyDesc, key: *const u8) @domain=set @leaf */
void msrt_set_add(MsMap *m, const MsTypeDesc *kd, const uint8_t *key);
/* ms-sig: msrt_set_length(m: *const MapVal) -> i64 @domain=set @leaf @pure */
int64_t msrt_set_length(const MsMap *m);
/* ms-sig: msrt_set_contains(m: *const MapVal, kd: KeyDesc, key: *const u8) -> u8 @domain=set @leaf @pure */
uint8_t msrt_set_contains(const MsMap *m, const MsTypeDesc *kd, const uint8_t *key);
/* ms-sig: msrt_set_remove(m: *mut MapVal, kd: KeyDesc, key: *const u8) @domain=set @leaf */
void msrt_set_remove(MsMap *m, const MsTypeDesc *kd, const uint8_t *key);
/* ms-sig: msrt_set_clear(m: *mut MapVal, kd: KeyDesc) @domain=set @leaf */
void msrt_set_clear(MsMap *m, const MsTypeDesc *kd);
/* ms-sig: msrt_map_get_or(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8, fallback: *const u8, out:
 * *mut u8) @domain=map @leaf */
void msrt_map_get_or(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key,
                     const uint8_t *fallback, uint8_t *out);
/* ms-sig: msrt_set_values(m: *const MapVal, kd: KeyDesc, out: *mut VecVal) @domain=set @leaf */
void msrt_set_values(const MsMap *m, const MsTypeDesc *kd, MsList *out);
/* ms-sig: msrt_set_add_copy(m: *mut MapVal, kd: KeyDesc, key: *const u8) @domain=set @leaf */
void msrt_set_add_copy(MsMap *m, const MsTypeDesc *kd, const uint8_t *key);
/* ms-sig: msrt_set_add_copy_w(m: *mut MapVal, kd: KeyDesc, key: *const u8) @domain=set @leaf */
void msrt_set_add_copy_w(MsMap *m, const MsTypeDesc *kd, const uint8_t *key);
/* ms-sig: msrt_set_contains_w(m: *const MapVal, kd: KeyDesc, key: *const u8) -> u8 @domain=set
 * @leaf @pure */
uint8_t msrt_set_contains_w(const MsMap *m, const MsTypeDesc *kd, const uint8_t *key);
/* ms-sig: msrt_set_union(a: *const MapVal, b: *const MapVal, kd: KeyDesc, out: *mut MapVal) @domain=set @leaf
 */
void msrt_set_union(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out);
/* ms-sig: msrt_set_intersection(a: *const MapVal, b: *const MapVal, kd: KeyDesc, out: *mut MapVal)
 * @domain=set @leaf */
void msrt_set_intersection(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out);
/* ms-sig: msrt_set_difference(a: *const MapVal, b: *const MapVal, kd: KeyDesc, out: *mut MapVal) @domain=set
 * @leaf */
void msrt_set_difference(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out);
/* ms-sig: msrt_set_symmetric_difference(a: *const MapVal, b: *const MapVal, kd: KeyDesc, out: *mut MapVal)
 * @domain=set @leaf */
void msrt_set_symmetric_difference(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out);
/* ms-sig: msrt_set_is_subset_of(a: *const MapVal, b: *const MapVal, kd: KeyDesc) -> u8 @domain=set @leaf */
uint8_t msrt_set_is_subset_of(const MsMap *a, const MsMap *b, const MsTypeDesc *kd);
/* ms-sig: msrt_set_is_superset_of(a: *const MapVal, b: *const MapVal, kd: KeyDesc) -> u8 @domain=set @leaf */
uint8_t msrt_set_is_superset_of(const MsMap *a, const MsMap *b, const MsTypeDesc *kd);
/* ms-sig: msrt_set_is_disjoint_from(a: *const MapVal, b: *const MapVal, kd: KeyDesc) -> u8 @domain=set @leaf
 */
uint8_t msrt_set_is_disjoint_from(const MsMap *a, const MsMap *b, const MsTypeDesc *kd);

/* ms-sig: msrt_map_fill_strings(m: *mut MapVal, vd: ValDesc, keys: *mut StrVal, vals: *mut u8, stride: i64,
 * n: i64) -> i64 @domain=map @leaf */
int64_t msrt_map_fill_strings(MsMap *m, const MsTypeDesc *vd, MsString *keys, uint8_t *vals, int64_t stride,
                              int64_t n);

#endif
