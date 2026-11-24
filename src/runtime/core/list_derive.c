/* runtime/core/list_derive.c: list natives that build a new list from one or two others. */
#include "runtime/core/list.h"

#include "base/alloc.h"
#include "base/index.h"
#include "runtime/core/list_support.h"
#include "runtime/core/scratch.h"

#define FIRST_CAPACITY 4
#define DISTINCT_HASH_THRESHOLD 16

static const MsList empty_list = {0};

/* How many elements `take` and `drop` split at: a count of zero or below is zero. */
static size_t split_count(int64_t count, size_t len) {
  if (count <= 0) {
    return 0;
  }
  return (uint64_t)count < len ? (size_t)count : len;
}

/* The status protocol reports bad bounds in `err`. */
static bool slice_bounds(const MsList *v, int64_t start, int64_t end, MsString *err, size_t *from,
                         size_t *to) {
  if (err != NULL) {
    *err = ms_string_empty();
  }
  if (ms_resolve_bounds(v->len, start, end, from, to)) {
    return true;
  }
  if (err != NULL) {
    *err = msrt_list_slice_error(start, end, v->len);
  }
  return false;
}

/* `slice(start, end)`: a copy of the elements. */
uint8_t msrt_list_slice(const MsList *v, const MsTypeDesc *d, int64_t start, int64_t end, MsList *out,
                        MsString *err) {
  size_t from = 0;
  size_t to = 0;
  if (!slice_bounds(v, start, end, err, &from, &to)) {
    return MS_STATUS_OUT_OF_RANGE;
  }
  const MsList range = msrt_list_view_of(v, d, from, to - from);
  ms_list_clone_desc(&range, d, out);
  return MS_STATUS_OK;
}

/* `slice` of a list the caller keeps unchanged while the result is used: the result borrows the elements in
 * place (a view), so nothing is copied. */
uint8_t msrt_list_slice_view(const MsList *v, const MsTypeDesc *d, int64_t start, int64_t end, MsList *out,
                             MsString *err) {
  size_t from = 0;
  size_t to = 0;
  if (!slice_bounds(v, start, end, err, &from, &to)) {
    return MS_STATUS_OUT_OF_RANGE;
  }
  const size_t count = to - from;
  *out = count == 0 ? empty_list : (MsList){.ptr = ms_list_slot(v, d, from), .len = count, .cap = 0};
  return MS_STATUS_OK;
}

void msrt_list_take(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out) {
  const MsList head = msrt_list_view_of(v, d, 0, split_count(count, v->len));
  ms_list_clone_desc(&head, d, out);
}

/* `drop(count)`, named `drop_n` because msrt_list_drop releases a value. */
void msrt_list_drop_n(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out) {
  const size_t skipped = split_count(count, v->len);
  const MsList rest = msrt_list_view_of(v, d, skipped, v->len - skipped);
  ms_list_clone_desc(&rest, d, out);
}

/* How many pieces of `size` elements, starting every `step`, a list of `len` splits into. */
static size_t piece_count(size_t len, size_t size, size_t step, bool short_last) {
  if (short_last) {
    return len / step + (len % step != 0);
  }
  return len >= size ? (len - size) / step + 1 : 0;
}

/* `chunks(size)` and `windows(size)`: lists of copies of `size` consecutive elements, starting every `step`
 * elements. `short_last` keeps a final shorter piece (chunks); otherwise only full pieces are made
 * (windows). `od` describes the outer list's element, a list. */
void msrt_list_pieces(const MsList *v, const MsTypeDesc *d, const MsTypeDesc *od, int64_t size, int64_t step,
                      uint8_t short_last, MsList *out) {
  if (size <= 0) { /* no group of zero or fewer elements exists */
    *out = empty_list;
    return;
  }
  const size_t piece_size = (size_t)size;
  const size_t stride = step > 1 ? (size_t)step : 1;
  MsList result = empty_list;
  const size_t pieces = piece_count(v->len, piece_size, stride, short_last != 0);
  if (pieces != 0) {
    ms_list_reserve(&result, od->size, pieces);
  }
  for (size_t start = 0; start < v->len && (short_last != 0 || v->len - start >= piece_size);
       start += stride) {
    const size_t room = v->len - start;
    const MsList range = msrt_list_view_of(v, d, start, piece_size < room ? piece_size : room);
    MsList piece = empty_list;
    ms_list_clone_desc(&range, d, &piece);
    __builtin_memcpy(ms_list_slot(&result, od, result.len), &piece, sizeof piece);
    result.len++;
  }
  *out = result;
}

/* The capacity a concatenation keeps: the spare room the copy-then-extend path used to leave. */
static size_t concat_capacity(size_t a_len, size_t b_len, size_t total) {
  if (b_len == 0) {
    return a_len;
  }
  if (a_len == 0) {
    return total > FIRST_CAPACITY ? total : FIRST_CAPACITY;
  }
  size_t doubled = 0;
  if (!ms_size_mul(a_len, 2, &doubled)) {
    return total; /* doubling would overflow: the exact size still fits */
  }
  return doubled > total ? doubled : total;
}

void msrt_list_concat(const MsList *a, const MsList *b, const MsTypeDesc *d, MsList *out) {
  size_t total = 0;
  if (!msrt_list_checked_add(a->len, b->len, &total)) {
    *out = empty_list;
    return;
  }
  if (total == 0) {
    *out = empty_list;
    return;
  }
  *out = msrt_list_with_slots(d, total, concat_capacity(a->len, b->len, total));
  if (out->ptr == NULL) {
    return; /* a fault was posted */
  }
  msrt_list_copy_range(d, a->ptr, out->ptr, a->len);
  msrt_list_copy_range(d, b->ptr, out->ptr + a->len * d->size, b->len);
}

/* `repeated(count)`: the elements `count` times over, in order. Plain elements copy once and double in
 * place, so a long fill is a few bulk copies. */
void msrt_list_repeat(const MsList *v, const MsTypeDesc *d, int64_t count, MsList *out) {
  const size_t rounds = count > 0 ? (size_t)count : 0;
  size_t total = 0;
  if (!ms_size_mul(v->len, rounds, &total)) {
    msrt_post_list_overflow();
    *out = empty_list;
    return;
  }
  if (total == 0) {
    *out = empty_list;
    return;
  }
  *out = msrt_list_with_slots(d, total, total);
  if (out->ptr == NULL) {
    return; /* a fault was posted */
  }
  uint8_t *buffer = out->ptr;
  if (!ms_desc_is_plain(d)) {
    for (size_t round = 0; round < rounds; round++) {
      msrt_list_copy_range(d, v->ptr, buffer + round * v->len * d->size, v->len);
    }
    return;
  }
  msrt_list_copy_range(d, v->ptr, buffer, v->len);
  for (size_t done = v->len; done < total;) {
    const size_t step = done < total - done ? done : total - done;
    __builtin_memcpy(buffer + done * d->size, buffer, step * d->size);
    done += step;
  }
}

/* `extend`: appends copies of the elements of `other`, which stays unchanged. */
void msrt_list_extend(MsList *v, const MsTypeDesc *d, const MsList *other) {
  if (other->len == 0) {
    return;
  }
  ms_list_reserve(v, d->size, other->len);
  msrt_list_copy_range(d, other->ptr, ms_list_slot(v, d, v->len), other->len);
  v->len += other->len;
}

/* Whether `element` is already in `result`; with `seen` a hash set, adds it to the set when it is new. */
static bool seen_before(MsMap *seen, const MsList *result, const MsTypeDesc *d, const uint8_t *element) {
  if (seen != NULL) {
    if (ms_map_has(seen, d, NULL, element)) {
      return true;
    }
    MsrtScratch copy;
    msrt_scratch_open(&copy, d->size);
    ms_slot_copy(d, element, copy.ptr);
    ms_map_insert(seen, d, NULL, copy.ptr, NULL);
    msrt_scratch_close(&copy);
    return false;
  }
  for (size_t j = 0; j < result->len; j++) {
    if (ms_slot_equal(d, ms_list_slot(result, d, j), element)) {
      return true;
    }
  }
  return false;
}

/* `distinct`: keeps the first of equal elements. A hash set decides membership of a long list. */
void msrt_list_distinct(const MsList *v, const MsTypeDesc *d, MsList *out) {
  MsList result = empty_list;
  MsMap seen = {0};
  const bool hashed = ms_desc_hashable(d) && v->len > DISTINCT_HASH_THRESHOLD;
  for (size_t i = 0; i < v->len; i++) {
    const uint8_t *element = ms_list_slot(v, d, i);
    if (seen_before(hashed ? &seen : NULL, &result, d, element)) {
      continue;
    }
    ms_list_reserve(&result, d->size, 1);
    ms_slot_copy(d, element, ms_list_slot(&result, d, result.len));
    result.len++;
  }
  ms_map_drop(&seen, d, NULL);
  *out = result;
}
