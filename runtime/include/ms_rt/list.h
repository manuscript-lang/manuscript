/* ms_rt/list.h: lists (runtime/core/list.c). Every function takes the address of the list value and the
 * descriptor of its element type (ms_rt/desc.h). A function that stores an element takes ownership of the slot
 * it is given; a name ending in `_copy` or a lent argument leaves the caller's value alone.
 */
#ifndef MS_RT_LIST_H
#define MS_RT_LIST_H

#include "ms_rt/desc.h"

void msrt_list_new(MsList *out);
void msrt_list_with_capacity(const MsTypeDesc *d, int64_t cap, MsList *out);
void msrt_list_drop(MsList *v, const MsTypeDesc *d);
void msrt_list_copy(const MsList *v, const MsTypeDesc *d, MsList *out);
void msrt_list_shadow(const MsList *v, const MsTypeDesc *d, MsList *out);
void msrt_list_free_raw(MsList *v);
void msrt_list_push(MsList *v, const MsTypeDesc *d, const uint8_t *e);
void msrt_list_reserve(MsList *v, const MsTypeDesc *d, int64_t extra);
const uint8_t *msrt_list_at(const MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *default_value);
void msrt_list_get(const MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *default_value, uint8_t *out);
uint8_t msrt_list_index_of(const MsList *v, const MsTypeDesc *d, const uint8_t *probe, int64_t *out);
uint8_t msrt_list_last_index_of(const MsList *v, const MsTypeDesc *d, const uint8_t *probe, int64_t *out);
uint8_t msrt_list_contains(const MsList *v, const MsTypeDesc *d, const uint8_t *probe);
void msrt_list_prepend(MsList *v, const MsTypeDesc *d, const uint8_t *e);
void msrt_list_insert(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e);
void msrt_list_insert_copy(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e);
uint8_t msrt_list_pop(MsList *v, const MsTypeDesc *d, uint8_t *out);
void msrt_list_set(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e);
void msrt_list_replace(MsList *v, const MsTypeDesc *d, int64_t index, uint8_t *e, uint8_t *out);
void msrt_list_swap(MsList *v, const MsTypeDesc *d, int64_t i, int64_t j);
void msrt_list_remove(MsList *v, const MsTypeDesc *d, int64_t index);
void msrt_list_reverse(MsList *v, const MsTypeDesc *d);
void msrt_list_reversed(const MsList *v, const MsTypeDesc *d, MsList *out);
void msrt_list_splice(MsList *v, const MsTypeDesc *d, int64_t start, int64_t count, MsList *replacement);
void msrt_list_fill(MsList *v, const MsTypeDesc *d, const uint8_t *value, int64_t start, int64_t end);
void msrt_list_copy_within(MsList *v, const MsTypeDesc *d, int64_t target, int64_t start, int64_t end);
uint8_t msrt_list_slice(const MsList *v, const MsTypeDesc *d, int64_t start, int64_t end, MsList *out, MsStr *err);
uint8_t msrt_list_slice_view(const MsList *v, const MsTypeDesc *d, int64_t start, int64_t end, MsList *out, MsStr *err);
void msrt_list_take(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out);
void msrt_list_drop_n(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out);
void msrt_list_pieces(const MsList *v, const MsTypeDesc *d, const MsTypeDesc *od, int64_t size, int64_t step, uint8_t short_last, MsList *out);
void msrt_list_concat(const MsList *a, const MsList *b, const MsTypeDesc *d, MsList *out);
void msrt_list_repeat(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out);
void msrt_list_extend(MsList *v, const MsTypeDesc *d, const MsList *other);
void msrt_list_distinct(const MsList *v, const MsTypeDesc *d, MsList *out);
void msrt_list_keys(const MsList *v, MsList *out);
void msrt_list_range(int64_t start, int64_t end, MsList *out);
uint8_t msrt_list_range_by(int64_t start, int64_t end, int64_t step, uint8_t has_max, int64_t max, MsList *out);
void msrt_list_to_set(const MsList *v, const MsTypeDesc *d, MsMap *out);
int64_t msrt_hash_list(const MsList *v, const MsTypeDesc *d);

#endif
