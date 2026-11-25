/* runtime/core/list.c: list natives for construction, reads and single-element changes. A mutator changes
 * the list in place; the slot of a stored element is consumed (ownership moves into the list); borrowed
 * arguments are copied. A view (`cap == 0` with a buffer) borrows its elements: nothing frees, drops or grows
 * it in place. */
#include "runtime/core/list.h"

#include "base/alloc.h"
#include "runtime/core/stats.h"
#include "base/hash.h"
#include "base/index.h"
#include "runtime/core/index_fault.h"
#include "runtime/core/list_support.h"
#include "runtime/core/scratch.h"

#define INLINE_COPY_BYTES 64

static const MsList empty_list = {0};

void msrt_list_new(MsList *out) {
  *out = empty_list;
}

void msrt_list_with_capacity(const MsTypeDesc *d, int64_t cap, MsList *out) {
  MsList list = empty_list;
  if (cap > 0) {
    ms_list_reserve(&list, d->size, (size_t)cap);
  }
  *out = list;
}

void msrt_list_drop(MsList *v, const MsTypeDesc *d) {
  ms_list_drop_desc(v, d);
}

void msrt_list_copy(const MsList *v, const MsTypeDesc *d, MsList *out) {
  if (v->len != 0) {
    ms_stats_copy(0, v->len * d->size);
  }
  ms_list_clone_desc(v, d, out);
}

void msrt_list_clone(const MsList *v, const MsTypeDesc *d, MsList *out) {
  msrt_list_copy(v, d, out);
}

/* One copy of the `count` elements of `v` from `start`, pushed onto the list of lists `out`. */
static void push_run(const MsList *v, const MsTypeDesc *d, size_t start, size_t count, MsList *out) {
  MsList run = {0};
  ms_list_reserve(&run, d->size, count);
  for (size_t at = 0; at < count; at++) {
    ms_slot_copy(d, ms_list_slot(v, d, start + at), ms_list_slot(&run, d, at));
    run.len = at + 1;
  }
  ms_list_push(out, sizeof run, &run);
}

void msrt_list_chunks(const MsList *v, const MsTypeDesc *d, int64_t size, MsList *out) {
  *out = empty_list;
  if (size <= 0) {
    return;
  }
  const size_t width = (uint64_t)size > v->len ? v->len : (size_t)size;
  for (size_t start = 0; start < v->len; start += width) {
    const size_t left = v->len - start;
    push_run(v, d, start, left < width ? left : width, out);
  }
}

void msrt_list_windows(const MsList *v, const MsTypeDesc *d, int64_t size, MsList *out) {
  *out = empty_list;
  if (size <= 0 || (uint64_t)size > v->len) {
    return;
  }
  const size_t width = (size_t)size;
  for (size_t start = 0; start + width <= v->len; start++) {
    push_run(v, d, start, width, out);
  }
}

/* A bitwise copy of `v` in a fresh buffer that owns nothing: the generated sort permutes its slots (moves
 * only), so a comparator that exits early leaves the original list intact. Pair it with
 * msrt_list_free_raw; never drop it as a list. */
void msrt_list_shadow(const MsList *v, const MsTypeDesc *d, MsList *out) {
  if (v->len == 0) {
    *out = empty_list;
    return;
  }
  *out = msrt_list_with_slots(d, v->len, v->len);
  if (out->ptr == NULL) {
    return;
  }
  __builtin_memcpy(out->ptr, v->ptr, v->len * d->size);
}

/* Frees the buffer of a shadow without touching its slots. */
void msrt_list_free_raw(MsList *v) {
  ms_free(v->ptr);
  *v = empty_list;
}

void msrt_list_push(MsList *v, const MsTypeDesc *d, const uint8_t *e) {
  ms_list_push(v, d->size, e);
}

void msrt_list_append(MsList *v, const MsTypeDesc *d, const uint8_t *e) {
  ms_list_push(v, d->size, e);
}

int64_t msrt_list_length(const MsList *v) {
  return (int64_t)v->len;
}

uint8_t msrt_list_is_empty(const MsList *v) {
  return v->len == 0;
}

static bool insert_inside(int64_t length, int64_t index);
static bool set_inside(int64_t length, int64_t index);
static bool replace_inside(int64_t length, int64_t index);

void msrt_list_reserve(MsList *v, const MsTypeDesc *d, int64_t extra) {
  ms_list_reserve(v, d->size, extra > 0 ? (size_t)extra : 0);
}

/* ---- reads ---- */

/* The element at a possibly negative index, borrowed; `default_value` (may be NULL) when out of range. */
const uint8_t *msrt_list_at(const MsList *v, const MsTypeDesc *d, int64_t index,
                            const uint8_t *default_value) {
  size_t position = 0;
  if (ms_resolve_index(v->len, index, &position)) {
    return ms_list_slot(v, d, position);
  }
  if (default_value == NULL) {
    msrt_post_index(index, (int64_t)v->len);
  }
  return default_value; /* NULL after a posted fault */
}

static int64_t load_i64(const uint8_t *slot) {
  int64_t value = 0;
  __builtin_memcpy(&value, slot, sizeof value);
  return value;
}

/* Position of the first `target` among `count` Ints: eight at a time, so the scan vectorizes. */
static bool find_int(const uint8_t *items, size_t count, int64_t target, size_t *out) {
  enum { CHUNK = 8 };
  size_t start = 0;
  for (; start + CHUNK <= count; start += CHUNK) {
    bool hit = false;
    for (size_t k = 0; k < CHUNK; k++) {
      hit |= load_i64(items + (start + k) * sizeof(int64_t)) == target;
    }
    if (hit) {
      break;
    }
  }
  for (size_t i = start; i < count; i++) {
    if (load_i64(items + i * sizeof(int64_t)) == target) {
      *out = i;
      return true;
    }
  }
  return false;
}

static bool index_of(const MsList *list, const MsTypeDesc *d, const uint8_t *probe, size_t *out) {
  if (d->kind == MS_KIND_INT && list->len > 0) {
    return find_int(list->ptr, list->len, load_i64(probe), out);
  }
  for (size_t i = 0; i < list->len; i++) {
    if (ms_slot_equal(d, ms_list_slot(list, d, i), probe)) {
      *out = i;
      return true;
    }
  }
  return false;
}

uint8_t msrt_list_index_of(const MsList *v, const MsTypeDesc *d, const uint8_t *probe, int64_t *out) {
  size_t position = 0;
  if (!index_of(v, d, probe, &position)) {
    return 0;
  }
  *out = (int64_t)position;
  return 1;
}

uint8_t msrt_list_last_index_of(const MsList *v, const MsTypeDesc *d, const uint8_t *probe, int64_t *out) {
  for (size_t i = v->len; i > 0; i--) {
    if (ms_slot_equal(d, ms_list_slot(v, d, i - 1), probe)) {
      *out = (int64_t)(i - 1);
      return 1;
    }
  }
  return 0;
}

uint8_t msrt_list_contains(const MsList *v, const MsTypeDesc *d, const uint8_t *probe) {
  size_t position = 0;
  return index_of(v, d, probe, &position);
}

int64_t msrt_hash_list(const MsList *v, const MsTypeDesc *d) {
  uint64_t hash = v->len;
  for (size_t i = 0; i < v->len; i++) {
    hash = ms_hash_combine(hash, ms_slot_hash(d, ms_list_slot(v, d, i)));
  }
  return (int64_t)hash;
}

/* ---- element mutators ---- */

void msrt_list_insert(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e) {
  if (!insert_inside((int64_t)v->len, index)) {
    return; /* a posted fault consumes nothing: the caller still holds the element and closes it when it leaves */
  }
  size_t position = 0;
  (void)ms_resolve_insert_index(v->len, index, &position);
  ms_list_reserve(v, d->size, 1);
  uint8_t *slot = ms_list_slot(v, d, position);
  __builtin_memmove(slot + d->size, slot, (v->len - position) * d->size);
  ms_copy_slot(slot, e, d->size);
  v->len++;
}

void msrt_list_prepend(MsList *v, const MsTypeDesc *d, const uint8_t *e) {
  msrt_list_insert(v, d, 0, e);
}

/* `insert` of a borrowed element: the list stores its own copy, and the caller keeps `e`. */
void msrt_list_insert_copy(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e) {
  size_t position = 0;
  if (!ms_resolve_insert_index(v->len, index, &position)) { /* before the copy: nothing to release when it faults */
    msrt_post_list_index(0, index, (int64_t)v->len);
    return;
  }
  _Alignas(16) uint8_t scratch[INLINE_COPY_BYTES];
  const bool on_stack = d->size <= sizeof scratch;
  uint8_t *copy = on_stack ? scratch : ms_alloc(d->size);
  ms_slot_copy(d, e, copy);
  msrt_list_insert(v, d, index, copy);
  if (!on_stack) {
    ms_free(copy);
  }
}

/* Moves the last element into `out`; 0 when the list is empty. */
uint8_t msrt_list_pop(MsList *v, const MsTypeDesc *d, uint8_t *out) {
  if (v->len == 0) {
    return 0;
  }
  v->len--;
  ms_copy_slot(out, ms_list_slot(v, d, v->len), d->size);
  return 1;
}

/* Replaces the element at `index` with `e` (consumed); the old element is dropped. */
/* The index checks of the natives that take an owned element, apart from the natives: lowering calls them first, so
 * a bad index faults while the caller still owns the element. */
static bool set_inside(int64_t length, int64_t index) {
  size_t position = 0;
  const bool inside = ms_resolve_index((size_t)length, index, &position);
  if (!inside) {
    msrt_post_list_index(2, index, length);
  }
  return inside;
}

void msrt_list_check_set(int64_t length, int64_t index) {
  (void)set_inside(length, index);
}

static bool replace_inside(int64_t length, int64_t index) {
  size_t position = 0;
  const bool inside = ms_resolve_index((size_t)length, index, &position);
  if (!inside) {
    msrt_post_list_index(4, index, length);
  }
  return inside;
}

void msrt_list_check_replace(int64_t length, int64_t index) {
  (void)replace_inside(length, index);
}

static bool insert_inside(int64_t length, int64_t index) {
  size_t position = 0;
  const bool inside = ms_resolve_insert_index((size_t)length, index, &position);
  if (!inside) {
    msrt_post_list_index(0, index, length);
  }
  return inside;
}

void msrt_list_check_insert(int64_t length, int64_t index) {
  (void)insert_inside(length, index);
}

void msrt_list_set(MsList *v, const MsTypeDesc *d, int64_t index, const uint8_t *e) {
  if (!set_inside((int64_t)v->len, index)) {
    return; /* a posted fault consumes nothing: the caller still holds the element and closes it when it leaves */
  }
  size_t position = 0;
  (void)ms_resolve_index(v->len, index, &position);
  uint8_t *slot = ms_list_slot(v, d, position);
  /* The new element goes in first: dropping the old one runs closes, which may fault, and the list must own the new
   * element by then. */
  MsrtScratch old;
  msrt_scratch_open(&old, d->size);
  ms_copy_slot(old.ptr, slot, d->size);
  ms_copy_slot(slot, e, d->size);
  ms_slot_drop(d, old.ptr);
  msrt_scratch_close(&old);
}

/* Moves the element at `index` into `out` and stores `e` (consumed) in its place; nothing is copied or
 * dropped. */
void msrt_list_replace(MsList *v, const MsTypeDesc *d, int64_t index, uint8_t *e, uint8_t *out) {
  if (!replace_inside((int64_t)v->len, index)) {
    __builtin_memset(out, 0, d->size); /* no value: the caller's exit closes the incoming element */
    return;
  }
  size_t position = 0;
  (void)ms_resolve_index(v->len, index, &position);
  uint8_t *slot = ms_list_slot(v, d, position);
  ms_copy_slot(out, slot, d->size);
  ms_copy_slot(slot, e, d->size);
}

/* Exchanges two distinct slots of `size` bytes through a small buffer. */
static void swap_slots(uint8_t *a, uint8_t *b, size_t size) {
  uint8_t scratch[INLINE_COPY_BYTES];
  while (size != 0) {
    const size_t step = size < sizeof scratch ? size : sizeof scratch;
    __builtin_memcpy(scratch, a, step);
    __builtin_memcpy(a, b, step);
    __builtin_memcpy(b, scratch, step);
    a += step;
    b += step;
    size -= step;
  }
}

void msrt_list_swap(MsList *v, const MsTypeDesc *d, int64_t i, int64_t j) {
  size_t first = 0;
  size_t second = 0;
  if (!ms_resolve_index(v->len, i, &first)) {
    msrt_post_list_index(3, i, (int64_t)v->len);
    return;
  }
  if (!ms_resolve_index(v->len, j, &second)) {
    msrt_post_list_index(3, j, (int64_t)v->len);
    return;
  }
  if (first != second) {
    swap_slots(ms_list_slot(v, d, first), ms_list_slot(v, d, second), d->size);
  }
}

/* As `remove`, but the element moves into the list `taken` instead of being dropped. */
void msrt_list_remove_take(MsList *v, const MsTypeDesc *d, int64_t index, MsList *taken) {
  size_t position = 0;
  if (!ms_resolve_index(v->len, index, &position)) {
    msrt_post_list_index(1, index, (int64_t)v->len);
    *taken = empty_list;
    return;
  }
  uint8_t *slot = ms_list_slot(v, d, position);
  *taken = empty_list;
  ms_list_reserve(taken, d->size, 1);
  ms_copy_slot(taken->ptr, slot, d->size);
  taken->len = 1;
  __builtin_memmove(slot, slot + d->size, (v->len - position - 1) * d->size);
  v->len--;
}

void msrt_list_remove(MsList *v, const MsTypeDesc *d, int64_t index) {
  size_t position = 0;
  if (!ms_resolve_index(v->len, index, &position)) {
    msrt_post_list_index(1, index, (int64_t)v->len);
    return;
  }
  uint8_t *slot = ms_list_slot(v, d, position);
  ms_slot_drop(d, slot);
  __builtin_memmove(slot, slot + d->size, (v->len - position - 1) * d->size);
  v->len--;
}

/* Reverses `count` slots whose size is a constant after inlining: the compiler turns the exchange of a one
 * to four word slot into register moves. */
static inline void reverse_slots(uint8_t *items, size_t count, size_t size) {
  size_t front = 0;
  size_t back = count;
  while (front + 1 < back) {
    back--;
    swap_slots(items + front * size, items + back * size, size);
    front++;
  }
}

void msrt_list_reverse(MsList *v, const MsTypeDesc *d) {
  if (v->len < 2) {
    return;
  }
  switch (d->size) {
  case 8:
    reverse_slots(v->ptr, v->len, 8);
    break;
  case 16:
    reverse_slots(v->ptr, v->len, 16);
    break;
  case 24:
    reverse_slots(v->ptr, v->len, 24);
    break;
  case 32:
    reverse_slots(v->ptr, v->len, 32);
    break;
  default:
    reverse_slots(v->ptr, v->len, d->size);
    break;
  }
}

void msrt_list_reversed(const MsList *v, const MsTypeDesc *d, MsList *out) {
  ms_list_clone_desc(v, d, out);
  msrt_list_reverse(out, d);
}
