/* runtime/core/bytes.c: Bytes natives that search, slice, join and build byte buffers. Decoding to text is in
 * bytes_text.c. */
#include "runtime/core/bytes.h"

#include "base/alloc.h"
#include "base/index.h"
#include "base/search.h"
#include "base/strbuild.h"
#include "runtime/core/fault.h"
#include "runtime/core/index_fault.h"

_Static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__,
               "msrt_bytes_read_word assumes a little-endian host");

static const MsBytes empty_bytes = {0};

static MS_NORETURN void bytes_overflow_fault(void) {
  ms_fault_text(MS_FAULT_KIND_OVERFLOW, "bytes size overflow");
}

/* Faults when `value` is not a byte; `what` names the operation for the message. */
static void check_byte(const char *what, int64_t value) {
  if (value >= 0 && value <= UINT8_MAX) {
    return;
  }
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, what);
  ms_strbuild_append_text(&message, ": value must be between 0 and 255, found ");
  ms_strbuild_append_i64(&message, value);
  ms_fault_built(MS_FAULT_KIND_FAULT, &message);
}

void msrt_bytes_drop(MsBytes *b) {
  ms_bytes_free(b); /* a view borrows its storage and frees nothing */
}

void msrt_bytes_copy(const MsBytes *b, MsBytes *out) {
  *out = ms_bytes_from_span(ms_bytes_span(b));
}

int64_t msrt_bytes_length(const MsBytes *b) {
  return (int64_t)b->len;
}

uint8_t msrt_bytes_is_empty(const MsBytes *b) {
  return b->len == 0;
}

/* ---- search ---- */

static bool find_bytes(const MsBytes *b, const MsBytes *v, size_t *out) {
  const size_t at = ms_find(b->ptr, b->len, v->ptr, v->len);
  if (at == SIZE_MAX) {
    return false;
  }
  *out = at;
  return true;
}

uint8_t msrt_bytes_contains(const MsBytes *b, const MsBytes *v) {
  size_t at = 0;
  return find_bytes(b, v, &at);
}

uint8_t msrt_bytes_index_of(const MsBytes *b, const MsBytes *v, int64_t *out) {
  size_t at = 0;
  if (!find_bytes(b, v, &at)) {
    return 0;
  }
  *out = (int64_t)at;
  return 1;
}

/* `index_of_byte(value, start)`: the first offset at or after `start` holding `value`. */
uint8_t msrt_bytes_index_of_byte(const MsBytes *b, int64_t value, int64_t start, int64_t *out) {
  const size_t from = start > 0 ? (size_t)start : 0;
  if (value < 0 || value > UINT8_MAX || from >= b->len) {
    return 0;
  }
  const uint8_t *hit = __builtin_memchr(b->ptr + from, (int)value, b->len - from);
  if (hit == NULL) {
    return 0;
  }
  *out = (int64_t)(hit - b->ptr);
  return 1;
}

uint8_t msrt_bytes_last_index_of(const MsBytes *b, const MsBytes *v, int64_t *out) {
  const size_t at = ms_rfind(b->ptr, b->len, v->ptr, v->len);
  if (at == SIZE_MAX) {
    return 0;
  }
  *out = (int64_t)at;
  return 1;
}

uint8_t msrt_bytes_starts_with(const MsBytes *b, const MsBytes *v) {
  return v->len <= b->len && (v->len == 0 || __builtin_memcmp(b->ptr, v->ptr, v->len) == 0);
}

uint8_t msrt_bytes_ends_with(const MsBytes *b, const MsBytes *v) {
  return v->len <= b->len && (v->len == 0 || __builtin_memcmp(b->ptr + b->len - v->len, v->ptr, v->len) == 0);
}

uint8_t msrt_bytes_eq(const MsBytes *a, const MsBytes *b) {
  return a->len == b->len && (a->len == 0 || __builtin_memcmp(a->ptr, b->ptr, a->len) == 0);
}

/* ---- reads and views ---- */

int64_t msrt_bytes_get(const MsBytes *b, int64_t index, uint8_t has_default, int64_t default_value) {
  size_t position = 0;
  if (ms_resolve_index(b->len, index, &position)) {
    return b->ptr[position];
  }
  if (has_default == 0) {
    msrt_index_fault(index, (int64_t)b->len);
  }
  return default_value;
}

uint8_t msrt_bytes_slice(const MsBytes *b, int64_t start, int64_t end, MsBytes *out) {
  size_t from = 0;
  size_t to = 0;
  if (!ms_resolve_bounds(b->len, start, end, &from, &to)) {
    return MS_STATUS_OUT_OF_RANGE;
  }
  *out = ms_bytes_from_span(ms_span_of(b->ptr + from, to - from));
  return MS_STATUS_OK;
}

static MS_NORETURN void view_bounds_fault(int64_t start, int64_t end, size_t length) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "Bytes.view: bounds ");
  ms_strbuild_append_i64(&message, start);
  ms_strbuild_append_text(&message, "..");
  ms_strbuild_append_i64(&message, end);
  ms_strbuild_append_text(&message, " are outside a length of ");
  ms_strbuild_append_i64(&message, (int64_t)length);
  ms_fault_built(MS_FAULT_KIND_FAULT, &message);
}

/* `view(start, end)`: borrows `[start, end)` of the receiver's storage (a view, `cap == 0`, never freed). */
void msrt_bytes_view(const MsBytes *b, int64_t start, int64_t end, MsBytes *out) {
  size_t from = 0;
  size_t to = 0;
  if (!ms_resolve_bounds(b->len, start, end, &from, &to)) {
    view_bounds_fault(start, end, b->len);
  }
  *out = from == to ? empty_bytes : ms_bytes_view(ms_span_of(b->ptr + from, to - from));
}

void msrt_bytes_reversed(const MsBytes *b, MsBytes *out) {
  msrt_bytes_copy(b, out);
  for (size_t front = 0, back = out->len; front + 1 < back; front++) {
    back--;
    const uint8_t held = out->ptr[front];
    out->ptr[front] = out->ptr[back];
    out->ptr[back] = held;
  }
}

void msrt_bytes_with_value(const MsBytes *b, int64_t index, int64_t value, MsBytes *out) {
  size_t position = 0;
  if (!ms_resolve_index(b->len, index, &position)) {
    msrt_collection_index_fault("Bytes.with_value", (int64_t)b->len, index);
  }
  check_byte("Bytes.with_value", value);
  msrt_bytes_copy(b, out);
  out->ptr[position] = (uint8_t)value;
}

/* ---- building ---- */

void msrt_bytes_concat(const MsBytes *a, const MsBytes *b, MsBytes *out) {
  size_t total = 0;
  if (!ms_size_add(a->len, b->len, &total)) {
    bytes_overflow_fault();
  }
  if (total == 0) {
    *out = empty_bytes;
    return;
  }
  uint8_t *buffer = ms_alloc(total);
  if (a->len != 0) {
    __builtin_memcpy(buffer, a->ptr, a->len);
  }
  if (b->len != 0) {
    __builtin_memcpy(buffer + a->len, b->ptr, b->len);
  }
  *out = (MsBytes){.ptr = buffer, .len = total, .cap = total};
}

/* `a.concat(b)` where the caller gives `a` up: appends `b` to `a`'s block, which grows in place when `a` owns one.
 * A view or empty `a` is copied into a new block first. A `b` that points into `a`'s block is copied before the
 * block can move. */
void msrt_bytes_concat_grow(MsBytes *a, const MsBytes *b, MsBytes *out) {
  if (b->len == 0) {
    /* A view does not own its block: the result must be a copy, as it is for a non-empty `b`. */
    *out = (a->cap != 0 || a->len == 0) ? *a : ms_bytes_from_span(ms_bytes_span(a));
    return;
  }
  size_t total = 0;
  if (!ms_size_add(a->len, b->len, &total)) {
    bytes_overflow_fault();
  }
  const bool inside = a->cap != 0 && b->ptr >= a->ptr && b->ptr < a->ptr + a->cap;
  MsBytes held = {0};
  const MsBytes *piece = b;
  if (inside) {
    held = ms_bytes_from_span(ms_bytes_span(b));
    piece = &held;
  }
  __builtin_memcpy(ms_list_extend_grow(a, 1, piece->len), piece->ptr, piece->len);
  if (inside) {
    ms_bytes_free(&held);
  }
  *out = *a;
}

/* Pushes a fresh copy of `part` onto `parts`, a list of Bytes. */
static void push_part(MsList *parts, MsSpan part) {
  const MsBytes item = ms_bytes_from_span(part);
  ms_list_push(parts, sizeof item, &item);
}

void msrt_bytes_split(const MsBytes *b, const MsBytes *sep, MsList *out) {
  MsList parts = {0};
  if (sep->len == 0) { /* every byte on its own */
    for (size_t i = 0; i < b->len; i++) {
      push_part(&parts, ms_span_of(b->ptr + i, 1));
    }
    *out = parts;
    return;
  }
  size_t start = 0;
  for (;;) {
    const size_t found = ms_find(b->ptr + start, b->len - start, sep->ptr, sep->len);
    if (found == SIZE_MAX) {
      push_part(&parts, ms_span_of(b->ptr + start, b->len - start));
      break;
    }
    push_part(&parts, ms_span_of(b->ptr + start, found));
    start += found + sep->len;
  }
  *out = parts;
}

/* `values()` and `Bytes(values)`: a `List[UInt8]` stores one byte per element, the layout of the bytes. */
void msrt_bytes_values(const MsBytes *b, MsBytes *out) {
  msrt_bytes_copy(b, out);
}

void msrt_bytes_from_values(const MsBytes *values, MsBytes *out) {
  msrt_bytes_copy(values, out);
}

/* `Bytes([...])` of a list of Ints: each element narrowed to its low byte. */
void msrt_bytes_from_ints(const MsList *values, MsBytes *out) {
  uint8_t *narrowed = ms_alloc(values->len + 1);
  for (size_t at = 0; at < values->len; at++) {
    int64_t element;
    __builtin_memcpy(&element, values->ptr + at * sizeof element, sizeof element);
    narrowed[at] = (uint8_t)element;
  }
  *out = ms_bytes_from_span(ms_span_of(narrowed, values->len));
  ms_free(narrowed);
}

static MsBytes part_at(const MsList *parts, size_t index) {
  MsBytes part;
  __builtin_memcpy(&part, parts->ptr + index * sizeof part, sizeof part);
  return part;
}

/* `join(parts)`: the parts end to end in one allocation. The list holds Bytes values inline. */
void msrt_bytes_join(const MsList *parts, MsBytes *out) {
  size_t total = 0;
  for (size_t i = 0; i < parts->len; i++) {
    if (!ms_size_add(total, part_at(parts, i).len, &total)) {
      bytes_overflow_fault();
    }
  }
  if (total == 0) {
    *out = empty_bytes;
    return;
  }
  uint8_t *buffer = ms_alloc(total);
  size_t at = 0;
  for (size_t i = 0; i < parts->len; i++) {
    const MsBytes part = part_at(parts, i);
    if (part.len != 0) {
      __builtin_memcpy(buffer + at, part.ptr, part.len);
      at += part.len;
    }
  }
  *out = (MsBytes){.ptr = buffer, .len = total, .cap = total};
}

/* `BytesBuilder.append(value)`. */
void msrt_bytes_append(MsBytes *b, int64_t value) {
  check_byte("BytesBuilder.append", value);
  const uint8_t byte = (uint8_t)value;
  ms_list_push(b, 1, &byte);
}

/* `BytesBuilder.append_bytes(values)`. */
void msrt_bytes_extend(MsBytes *b, const MsBytes *values) {
  if (values->len == 0) {
    return;
  }
  __builtin_memcpy(ms_list_extend(b, 1, values->len), values->ptr, values->len);
}

/* ---- fixed-width reads ---- */

/* The `width` bytes (1, 2, 4 or 8) at `at` as an unsigned number, or all eight as the Int with that bit
 * pattern. Missing bytes are an out-of-range status. */
uint8_t msrt_bytes_read_word(const MsBytes *b, int64_t at, int64_t width, uint8_t little, int64_t *out) {
  if (at < 0 || (uint64_t)at > b->len || (width != 1 && width != 2 && width != 4 && width != 8)) {
    return MS_STATUS_OUT_OF_RANGE;
  }
  const size_t start = (size_t)at;
  const size_t count = (size_t)width;
  if (b->len - start < count) {
    return MS_STATUS_OUT_OF_RANGE;
  }
  uint64_t raw = 0;
  __builtin_memcpy(&raw, b->ptr + start, count); /* this host is little-endian: bytes fill the low end */
  if (little == 0 && count != 1) {
    raw = __builtin_bswap64(raw) >> (64 - 8 * count);
  }
  *out = (int64_t)raw;
  return MS_STATUS_OK;
}
