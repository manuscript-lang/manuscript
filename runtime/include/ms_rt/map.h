/* ms_rt/map.h: maps and sets (runtime/core/map.c and map_api.c). Every function takes the address of the map
 * value, the descriptor of its key type and (for a map) of its value type; a set passes NULL for the value
 * type. A map keeps the key descriptor of the module that created it (`MsMap.desc`), so `kd` only serves a
 * map that was made without one. A function that stores a key or value takes ownership of the slot it is
 * given; a name ending in `_lent` borrows the key.
 */
#ifndef MS_RT_MAP_H
#define MS_RT_MAP_H

#include "ms_rt/desc.h"

void msrt_map_new(MsMap *out);
void msrt_map_stamp(MsMap *m, const MsTypeDesc *kd);
void msrt_map_drop(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd);
void msrt_map_copy(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsMap *out);
void msrt_map_reserve(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, int64_t n);
void msrt_map_clear(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd);
int64_t msrt_map_length(const MsMap *m);
int64_t msrt_map_slot_count(const MsMap *m);
uint8_t msrt_map_entry_ptrs(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, int64_t i, const uint8_t **key_out, const uint8_t **val_out);

void msrt_map_add(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val);
void msrt_map_add_w8(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val);
void msrt_map_add_sw8(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val);
void msrt_map_add_lent(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *val);
void msrt_map_add_default(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, uint8_t *key, uint8_t *val);
void msrt_map_add_default_lent(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *val);
uint8_t *msrt_map_slot_lent(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *default_value);
void msrt_map_remove(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
void msrt_map_merge(MsMap *m, const MsMap *other, const MsTypeDesc *kd, const MsTypeDesc *vd);
void msrt_map_add_table(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const MsStr *table);

uint8_t msrt_map_contains(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
uint8_t msrt_map_contains_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
uint8_t msrt_map_contains_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
const uint8_t *msrt_map_get_ptr(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
const uint8_t *msrt_map_get_ptr_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
const uint8_t *msrt_map_get_ptr_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
uint8_t msrt_map_get(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *out);
uint8_t msrt_map_get_w8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *out);
uint8_t msrt_map_get_sw8(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key, uint8_t *out);

void msrt_map_keys(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out);
void msrt_map_values(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out);
void msrt_map_keys_view(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out);
void msrt_map_values_view(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out);

void msrt_set_values(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsList *out);
void msrt_set_add_copy(MsMap *m, const MsTypeDesc *kd, const uint8_t *key);
void msrt_set_add_copy_w(MsMap *m, const MsTypeDesc *kd, const uint8_t *key);
uint8_t msrt_set_contains_w(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key);
void msrt_set_union(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out);
void msrt_set_intersection(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out);
void msrt_set_difference(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out);
void msrt_set_symmetric_difference(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, MsMap *out);
uint8_t msrt_set_is_subset_of(const MsMap *a, const MsMap *b, const MsTypeDesc *kd);
uint8_t msrt_set_is_superset_of(const MsMap *a, const MsMap *b, const MsTypeDesc *kd);
uint8_t msrt_set_is_disjoint_from(const MsMap *a, const MsMap *b, const MsTypeDesc *kd);

#endif
