/* runtime/core/list_edit.c: list natives that change a range of elements in place. */
#include "runtime/core/list.h"

#include "base/alloc.h"
#include "runtime/core/list_support.h"

/* The argument check of `splice`, apart from the native: lowering calls it first, so a bad range faults while the
 * caller still owns the replacement. */
static bool splice_inside(int64_t length, int64_t start, int64_t count) {
  if (start < 0 || start > length) {
    msrt_post_splice("start", start, (size_t)length);
    return false;
  }
  if (count < 0 || count > length - start) {
    msrt_post_splice("delete_count", count, (size_t)(length - start));
    return false;
  }
  return true;
}

void msrt_list_check_splice(int64_t length, int64_t start, int64_t count) {
  (void)splice_inside(length, start, count);
}

/* `splice(start, delete_count, replacement)`: the replacement is consumed and its buffer freed. */
static void splice_into(MsList *v, const MsTypeDesc *d, int64_t start, int64_t count, MsList *replacement,
                        MsList *taken) {
  const size_t length = v->len;
  if (!splice_inside((int64_t)length, start, count)) {
    if (taken != NULL) {
      *taken = (MsList){0};
    }
    return; /* nothing is consumed: the caller still holds the replacement */
  }
  const size_t from = (size_t)start;
  const size_t removed = (size_t)count;
  if (taken != NULL) { /* the deleted elements move out, for the caller to close */
    *taken = (MsList){0};
    if (removed != 0) {
      ms_list_reserve(taken, d->size, removed);
      __builtin_memcpy(taken->ptr, ms_list_slot(v, d, from), removed * d->size);
      taken->len = removed;
    }
  } else {
    for (size_t i = from; i < from + removed; i++) {
      ms_slot_drop(d, ms_list_slot(v, d, i));
    }
  }
  size_t new_len = 0;
  if (!msrt_list_checked_add(length - removed, replacement->len, &new_len)) {
    return;
  }
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

void msrt_list_splice(MsList *v, const MsTypeDesc *d, int64_t start, int64_t count, MsList *replacement) {
  splice_into(v, d, start, count, replacement, NULL);
}

/* As `splice`, but the deleted elements move into `taken` instead of being dropped. */
void msrt_list_splice_take(MsList *v, const MsTypeDesc *d, int64_t start, int64_t count, MsList *replacement,
                           MsList *taken) {
  splice_into(v, d, start, count, replacement, taken);
}

/* The argument check of `fill`, apart from the native (see `msrt_list_check_splice`). */
void msrt_list_check_fill(int64_t length, int64_t start, int64_t end) {
  (void)msrt_check_bounds("List.fill", (size_t)length, start, end);
}

/* `fill(value, start, end)`: `value` is consumed, copied into each slot but the last, which takes it. */
void msrt_list_fill(MsList *v, const MsTypeDesc *d, uint8_t *value, int64_t start, int64_t end) {
  if (!msrt_check_bounds("List.fill", v->len, start, end)) {
    return; /* nothing is consumed: the caller still holds the value */
  }
  if (start == end) {
    ms_slot_drop(d, value);
    return;
  }
  for (size_t i = (size_t)start; i < (size_t)end; i++) {
    uint8_t *slot = ms_list_slot(v, d, i);
    ms_slot_drop(d, slot);
    if (i + 1 == (size_t)end) {
      __builtin_memcpy(slot, value, d->size);
    } else {
      ms_slot_copy(d, value, slot);
    }
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
  if (!msrt_check_bounds("List.copy_within", length, start, end)) {
    return;
  }
  if (target < 0 || (uint64_t)target > length) {
    msrt_post_copy_target(length, target);
    return;
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
