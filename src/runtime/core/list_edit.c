/* runtime/core/list_edit.c: list natives that change a range of elements in place. */
#include "runtime/core/list.h"

#include "base/alloc.h"
#include "runtime/core/list_support.h"

/* `splice(start, delete_count, replacement)`: the replacement is consumed and its buffer freed. */
void msrt_list_splice(MsList *v, const MsTypeDesc *d, int64_t start, int64_t count, MsList *replacement) {
  const size_t length = v->len;
  if (start < 0 || (uint64_t)start > length) {
    msrt_splice_fault("start", start, length);
  }
  const size_t from = (size_t)start;
  if (count < 0 || (uint64_t)count > length - from) {
    msrt_splice_fault("delete_count", count, length - from);
  }
  const size_t removed = (size_t)count;
  for (size_t i = from; i < from + removed; i++) {
    ms_slot_drop(d, ms_list_slot(v, d, i));
  }
  const size_t new_len = msrt_list_checked_add(length - removed, replacement->len);
  if (new_len > v->cap) {
    ms_list_reserve(v, d->size, new_len - length);
  }
  const size_t tail = length - from - removed;
  if (tail != 0) {
    __builtin_memmove(ms_list_slot(v, d, from + replacement->len), ms_list_slot(v, d, from + removed),
                      tail * d->size);
  }
  if (replacement->len != 0) {
    __builtin_memcpy(ms_list_slot(v, d, from), replacement->ptr, replacement->len * d->size);
  }
  v->len = new_len;
  ms_list_free(replacement);
}

/* `fill(value, start, end)`: `value` is borrowed and copied into each slot. */
void msrt_list_fill(MsList *v, const MsTypeDesc *d, const uint8_t *value, int64_t start, int64_t end) {
  msrt_check_bounds("List.fill", v->len, start, end);
  for (size_t i = (size_t)start; i < (size_t)end; i++) {
    uint8_t *slot = ms_list_slot(v, d, i);
    ms_slot_drop(d, slot);
    ms_slot_copy(d, value, slot);
  }
}

/* Copies `count` slots from `from` over the slots at `to`, which may overlap: the sources are copied first,
 * the overwritten slots dropped, and the copies moved in. */
static void copy_within_owned(MsList *list, const MsTypeDesc *d, size_t to, size_t from, size_t count) {
  const MsList source = msrt_list_view_of(list, d, from, count);
  MsList scratch = {0};
  ms_list_clone_desc(&source, d, &scratch);
  for (size_t k = 0; k < count; k++) {
    ms_slot_drop(d, ms_list_slot(list, d, to + k));
  }
  __builtin_memcpy(ms_list_slot(list, d, to), scratch.ptr, count * d->size);
  ms_list_free(&scratch);
}

void msrt_list_copy_within(MsList *v, const MsTypeDesc *d, int64_t target, int64_t start, int64_t end) {
  const size_t length = v->len;
  msrt_check_bounds("List.copy_within", length, start, end);
  if (target < 0 || (uint64_t)target > length) {
    msrt_copy_target_fault(length, target);
  }
  const size_t to = (size_t)target;
  if (start == end || to == length) {
    return;
  }
  const size_t wanted = (size_t)(end - start);
  const size_t count = wanted < length - to ? wanted : length - to;
  if (ms_desc_is_plain(d)) {
    __builtin_memmove(ms_list_slot(v, d, to), ms_list_slot(v, d, (size_t)start), count * d->size);
    return;
  }
  copy_within_owned(v, d, to, (size_t)start, count);
}
