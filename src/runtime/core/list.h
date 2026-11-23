/* runtime/core/list.h: the list natives. Every function takes the address of the list value and the
 * descriptor of its element type (base/desc.h). A function that stores an element takes ownership of the slot
 * it is given; a name ending in `_copy` or a borrowed argument leaves the caller's value alone. */
#ifndef MS_RUNTIME_CORE_LIST_H
#define MS_RUNTIME_CORE_LIST_H

#include "abi/status.h"
#include "base/desc.h"
#include "base/map.h"

/* Compares two elements: negative when `a` sorts first. `env` is the comparator closure. It is program code,
 * so it can fault or park; the sorts below are not leaf functions. */
typedef int64_t (*MsCompareFn)(uint8_t *env, const uint8_t *a, const uint8_t *b);

/* ms-sig: msrt_list_new(out: *mut VecVal) @domain=collection @end */
void msrt_list_new(MsList *out);
/* ms-sig: msrt_list_with_capacity(d: ElemDesc, cap: i64, out: *mut VecVal) @domain=collection @end */
void msrt_list_with_capacity(const MsTypeDesc *d, int64_t cap, MsList *out);
/* ms-sig: msrt_list_drop(v: *mut VecVal, d: ElemDesc) @domain=collection @end */
void msrt_list_drop(MsList *v, const MsTypeDesc *d);
/* ms-sig: msrt_list_copy(v: *const VecVal, d: ElemDesc, out: *mut VecVal) @domain=collection @end */
void msrt_list_copy(const MsList *v, const MsTypeDesc *d, MsList *out);
/* `List.clone()`: the same deep copy as msrt_list_copy. */
/* ms-sig: msrt_list_clone(v: *const VecVal, d: ElemDesc, out: *mut VecVal) @domain=collection @end */
void msrt_list_clone(const MsList *v, const MsTypeDesc *d, MsList *out);
/* `List.chunks(size)`: consecutive copies of `size` elements, the last possibly shorter; empty for a `size` of
 * zero or less. `out` is a list of lists. */
/* ms-sig: msrt_list_chunks(v: *const VecVal, d: ElemDesc, size: i64, out: *mut VecVal) @domain=collection
 * */
void msrt_list_chunks(const MsList *v, const MsTypeDesc *d, int64_t size, MsList *out);
/* `List.windows(size)`: every run of `size` consecutive elements as an overlapping copy; empty when the list is
 * shorter than `size` or `size` is zero or less. */
/* ms-sig: msrt_list_windows(v: *const VecVal, d: ElemDesc, size: i64, out: *mut VecVal) @domain=collection
 * */
void msrt_list_windows(const MsList *v, const MsTypeDesc *d, int64_t size, MsList *out);
/* ms-sig: msrt_list_shadow(v: *const VecVal, d: ElemDesc, out: *mut VecVal) @domain=collection @end */
void msrt_list_shadow(const MsList *v, const MsTypeDesc *d, MsList *out);
/* ms-sig: msrt_list_free_raw(v: *mut VecVal) @domain=collection @end */
void msrt_list_free_raw(MsList *v);
/* ms-sig: msrt_list_push(v: *mut VecVal, d: ElemDesc, e: *const u8) @domain=collection @end */
void msrt_list_push(MsList *v, const MsTypeDesc *d, const uint8_t *e);
/* ms-sig: msrt_list_reserve(v: *mut VecVal, d: ElemDesc, extra: i64) @domain=collection @end */
void msrt_list_reserve(MsList *v, const MsTypeDesc *d, int64_t extra);
/* ms-sig: msrt_list_length(v: *const VecVal) -> i64 @domain=collection @op=list.len */
int64_t msrt_list_length(const MsList *v);
/* ms-sig: msrt_list_is_empty(v: *const VecVal) -> u8 @domain=collection
 * */
uint8_t msrt_list_is_empty(const MsList *v);
/* ms-sig: msrt_list_append(v: *mut VecVal, d: ElemDesc, e: *const u8) @domain=collection @op=list.push
 * @inline=list_append */
void msrt_list_append(MsList *v, const MsTypeDesc *d, const uint8_t *e);
/* ms-sig: msrt_list_at(v: *const VecVal, d: ElemDesc, index: i64, default: *const u8) -> *const u8
 * @domain=collection @end */
const uint8_t *msrt_list_at(const MsList *v, const MsTypeDesc *d, int64_t index,
                            const uint8_t *default_value);
/* ms-sig: msrt_list_get(v: *const VecVal, d: ElemDesc, index: i64, default: *const u8, out: *mut u8)
 * @domain=collection @inline=list_get */
void msrt_list_get(const MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *default_value,
                   uint8_t *out);
/* ms-sig: msrt_list_index_of(v: *const VecVal, d: ElemDesc, probe: *const u8, out: *mut i64) -> u8
 * @domain=collection @end */
uint8_t msrt_list_index_of(const MsList *v, const MsTypeDesc *d, const uint8_t *probe, int64_t *out);
/* ms-sig: msrt_list_last_index_of(v: *const VecVal, d: ElemDesc, probe: *const u8, out: *mut i64) -> u8
 * @domain=collection @end */
uint8_t msrt_list_last_index_of(const MsList *v, const MsTypeDesc *d, const uint8_t *probe, int64_t *out);
/* ms-sig: msrt_list_contains(v: *const VecVal, d: ElemDesc, probe: *const u8) -> u8 @domain=collection @end */
uint8_t msrt_list_contains(const MsList *v, const MsTypeDesc *d, const uint8_t *probe);
/* ms-sig: msrt_list_prepend(v: *mut VecVal, d: ElemDesc, e: *const u8) @domain=collection @end */
void msrt_list_prepend(MsList *v, const MsTypeDesc *d, const uint8_t *e);
/* ms-sig: msrt_list_insert(v: *mut VecVal, d: ElemDesc, index: i64, e: *const u8) @domain=collection @end */
void msrt_list_insert(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e);
/* ms-sig: msrt_list_insert_copy(v: *mut VecVal, d: ElemDesc, index: i64, e: *const u8) @domain=collection
 * */
void msrt_list_insert_copy(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e);
/* ms-sig: msrt_list_pop(v: *mut VecVal, d: ElemDesc, out: *mut u8) -> u8 @domain=collection @end */
uint8_t msrt_list_pop(MsList *v, const MsTypeDesc *d, uint8_t *out);
/* ms-sig: msrt_list_set(v: *mut VecVal, d: ElemDesc, index: i64, e: *const u8) @domain=collection @inline=list_set */
void msrt_list_set(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e);
/* ms-sig: msrt_list_replace(v: *mut VecVal, d: ElemDesc, index: i64, e: *mut u8, out: *mut u8)
 * @domain=collection @end */
void msrt_list_replace(MsList *v, const MsTypeDesc *d, int64_t index, uint8_t *e, uint8_t *out);
/* ms-sig: msrt_list_remove_take(v: *mut VecVal, d: ElemDesc, index: i64, out: *mut VecVal) @domain=collection */
void msrt_list_remove_take(MsList *v, const MsTypeDesc *d, int64_t index, MsList *taken);
/* ms-sig: msrt_list_swap(v: *mut VecVal, d: ElemDesc, i: i64, j: i64) @domain=collection @end */
void msrt_list_swap(MsList *v, const MsTypeDesc *d, int64_t i, int64_t j);
/* ms-sig: msrt_list_remove(v: *mut VecVal, d: ElemDesc, index: i64) @domain=collection @end */
void msrt_list_remove(MsList *v, const MsTypeDesc *d, int64_t index);
/* ms-sig: msrt_list_reverse(v: *mut VecVal, d: ElemDesc) @domain=collection @end */
void msrt_list_reverse(MsList *v, const MsTypeDesc *d);
/* ms-sig: msrt_list_reversed(v: *const VecVal, d: ElemDesc, out: *mut VecVal) @domain=collection @end */
void msrt_list_reversed(const MsList *v, const MsTypeDesc *d, MsList *out);
/* ms-sig: msrt_list_splice(v: *mut VecVal, d: ElemDesc, start: i64, count: i64, replacement: *mut VecVal)
 * @domain=collection @end */
void msrt_list_splice(MsList *v, const MsTypeDesc *d, int64_t start, int64_t count, MsList *replacement);
/* ms-sig: msrt_list_splice_take(v: *mut VecVal, d: ElemDesc, start: i64, count: i64, replacement: *mut VecVal,
 * out: *mut VecVal) @domain=collection */
void msrt_list_splice_take(MsList *v, const MsTypeDesc *d, int64_t start, int64_t count, MsList *replacement,
                           MsList *taken);
/* ms-sig: msrt_list_fill(v: *mut VecVal, d: ElemDesc, value: *const u8, start: i64, end: i64)
 * @domain=collection @end */
void msrt_list_fill(MsList *v, const MsTypeDesc *d, const uint8_t *value, int64_t start, int64_t end);
/* ms-sig: msrt_list_copy_within(v: *mut VecVal, d: ElemDesc, target: i64, start: i64, end: i64)
 * @domain=collection @end */
void msrt_list_copy_within(MsList *v, const MsTypeDesc *d, int64_t target, int64_t start, int64_t end);
/* ms-sig: msrt_list_slice(v: *const VecVal, d: ElemDesc, start: i64, end: i64, out: *mut VecVal, err:
 * ErrSlot) -> u8 @domain=collection @end */
uint8_t msrt_list_slice(const MsList *v, const MsTypeDesc *d, int64_t start, int64_t end, MsList *out,
                        MsString *err);
/* ms-sig: msrt_list_slice_view(v: *const VecVal, d: ElemDesc, start: i64, end: i64, out: *mut VecVal, err:
 * ErrSlot) -> u8 @borrows @domain=collection @end */
uint8_t msrt_list_slice_view(const MsList *v, const MsTypeDesc *d, int64_t start, int64_t end, MsList *out,
                             MsString *err);
/* ms-sig: msrt_list_take(v: *const VecVal, d: ElemDesc, count: i64, out: *mut VecVal) @domain=collection
 * */
void msrt_list_take(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out);
/* ms-sig: msrt_list_drop_n(v: *const VecVal, d: ElemDesc, count: i64, out: *mut VecVal) @domain=collection
 * @method=List.drop */
void msrt_list_drop_n(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out);
/* ms-sig: msrt_list_pieces(v: *const VecVal, d: ElemDesc, od: *const TypeDesc, size: i64, step: i64,
 * short_last: u8, out: *mut VecVal) @domain=collection @end */
void msrt_list_pieces(const MsList *v, const MsTypeDesc *d, const MsTypeDesc *od, int64_t size, int64_t step,
                      uint8_t short_last, MsList *out);
/* ms-sig: msrt_list_concat(a: *const VecVal, b: *const VecVal, d: ElemDesc, out: *mut VecVal)
 * @domain=collection @end */
void msrt_list_concat(const MsList *a, const MsList *b, const MsTypeDesc *d, MsList *out);
/* ms-sig: msrt_list_repeat(v: *const VecVal, d: ElemDesc, count: i64, out: *mut VecVal) @domain=collection
 * */
void msrt_list_repeat(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out);
/* ms-sig: msrt_list_extend(v: *mut VecVal, d: ElemDesc, other: *const VecVal) @domain=collection @end */
void msrt_list_extend(MsList *v, const MsTypeDesc *d, const MsList *other);
/* ms-sig: msrt_list_distinct(v: *const VecVal, d: ElemDesc, out: *mut VecVal) @domain=collection @end */
void msrt_list_distinct(const MsList *v, const MsTypeDesc *d, MsList *out);
/* ms-sig: msrt_list_keys(v: *const VecVal, out: *mut VecVal) @domain=collection @end */
void msrt_list_keys(const MsList *v, MsList *out);
/* ms-sig: msrt_list_range(start: i64, end: i64, out: *mut VecVal) @domain=collection @end */
void msrt_list_range(int64_t start, int64_t end, MsList *out);
/* ms-sig: msrt_list_range_by(start: i64, end: i64, step: i64, has_max: HasRaw, max: i64, out: *mut VecVal) ->
 * u8 @domain=collection @end */
uint8_t msrt_list_range_by(int64_t start, int64_t end, int64_t step, uint8_t has_max, int64_t max,
                           MsList *out);
/* ms-sig: msrt_list_to_set(v: *const VecVal, d: ElemDesc, out: *mut MapVal) @domain=collection @end */
void msrt_list_to_set(const MsList *v, const MsTypeDesc *d, MsMap *out);
/* ms-sig: msrt_list_sort_in_place(v: *mut VecVal, d: ElemDesc, cmp: CmpFn, env: *mut u8) @domain=collection
 */
void msrt_list_sort_in_place(MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env);
/* ms-sig: msrt_list_sort_ints(v: *mut VecVal, desc: i64) @domain=collection @end */
void msrt_list_sort_ints(MsList *v, int64_t desc);
/* ms-sig: msrt_list_sorted(v: *const VecVal, d: ElemDesc, cmp: CmpFn, env: *mut u8, out: *mut VecVal)
 * @domain=collection */
void msrt_list_sorted(const MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env, MsList *out);
/* ms-sig: msrt_list_sorted_by_difference(v: *const VecVal, d: ElemDesc, cmp: CmpFn, env: *mut u8, desc: i64,
 * out: *mut VecVal) @domain=collection */
void msrt_list_sorted_by_difference(const MsList *v, const MsTypeDesc *d, MsCompareFn cmp, uint8_t *env,
                                    int64_t desc, MsList *out);
/* ms-sig: msrt_hash_list(v: *const VecVal, d: ElemDesc) -> i64 @domain=collection @end */
int64_t msrt_hash_list(const MsList *v, const MsTypeDesc *d);

/* ms-sig: msrt_fault_destructure(names: i64, elements: i64) -> ! @domain=collection @end */
MS_NORETURN void msrt_fault_destructure(int64_t names, int64_t elements);

#endif
