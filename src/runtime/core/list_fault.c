/* runtime/core/list_fault.c: sizes and the faults of the list natives. The messages are observable. */
#include "runtime/core/list.h"
#include "runtime/core/fault.h"
#include "runtime/core/list_support.h"

#include "base/alloc.h"
#include "base/strbuild.h"

void msrt_post_list_overflow(void) {
  ms_fault_post_text(MS_FAULT_KIND_OVERFLOW, "list size overflow");
}

bool msrt_list_buffer_bytes(size_t count, size_t slot_size, size_t *bytes) {
  if (!ms_size_mul(count, slot_size == 0 ? 1 : slot_size, bytes)) {
    msrt_post_list_overflow();
    return false;
  }
  return true;
}

bool msrt_list_checked_add(size_t a, size_t b, size_t *sum) {
  if (!ms_size_add(a, b, sum)) {
    msrt_post_list_overflow();
    return false;
  }
  return true;
}

void msrt_list_copy_range(const MsTypeDesc *d, const uint8_t *src, uint8_t *dst, size_t count) {
  if (count == 0) {
    return;
  }
  if (ms_desc_is_plain(d)) {
    __builtin_memcpy(dst, src, count * d->size);
    return;
  }
  for (size_t i = 0; i < count; i++) {
    ms_slot_copy(d, src + i * d->size, dst + i * d->size);
  }
}

MsList msrt_list_with_slots(const MsTypeDesc *d, size_t count, size_t capacity) {
  size_t bytes = 0;
  if (!msrt_list_buffer_bytes(capacity, d->size, &bytes)) {
    return (MsList){0}; /* a fault was posted: the caller leaves */
  }
  return (MsList){.ptr = ms_alloc(bytes), .len = count, .cap = capacity};
}

void msrt_post_splice(const char *what, int64_t found, size_t high) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "List.splice: ");
  ms_strbuild_append_text(&message, what);
  ms_strbuild_append_text(&message, " must be between 0 and ");
  ms_strbuild_append_i64(&message, (int64_t)high);
  ms_strbuild_append_text(&message, ", found ");
  ms_strbuild_append_i64(&message, found);
  ms_fault_post_built(MS_FAULT_KIND_FAULT, &message);
}

void msrt_post_bounds(const char *operation, size_t length, int64_t start, int64_t end) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, operation);
  ms_strbuild_append_text(&message, ": start/end must satisfy 0 <= start <= end <= ");
  ms_strbuild_append_i64(&message, (int64_t)length);
  ms_strbuild_append_text(&message, "; found start ");
  ms_strbuild_append_i64(&message, start);
  ms_strbuild_append_text(&message, " and end ");
  ms_strbuild_append_i64(&message, end);
  ms_fault_post_built(MS_FAULT_KIND_FAULT, &message);
}

bool msrt_check_bounds(const char *operation, size_t length, int64_t start, int64_t end) {
  if (start < 0 || end < start || (uint64_t)end > length) {
    msrt_post_bounds(operation, length, start, end);
    return false;
  }
  return true;
}

void msrt_post_copy_target(size_t length, int64_t target) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "List.copy_within: target must be between 0 and ");
  ms_strbuild_append_i64(&message, (int64_t)length);
  ms_strbuild_append_text(&message, ", found ");
  ms_strbuild_append_i64(&message, target);
  ms_fault_post_built(MS_FAULT_KIND_FAULT, &message);
}

MsString msrt_list_slice_error(int64_t start, int64_t end, size_t length) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "slice(");
  ms_strbuild_append_i64(&message, start);
  ms_strbuild_append_text(&message, ", ");
  ms_strbuild_append_i64(&message, end);
  ms_strbuild_append_text(&message, ") of a list with ");
  ms_strbuild_append_i64(&message, (int64_t)length);
  ms_strbuild_append_text(&message,
                          " items: bounds must satisfy 0 <= start <= end <= length (negative bounds "
                          "count from the end)");
  return ms_strbuild_finish(&message);
}

void msrt_post_destructure(int64_t names, int64_t elements) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "destructuring length mismatch; the pattern binds ");
  ms_strbuild_append_i64(&message, names);
  ms_strbuild_append_text(&message, " names but the list has ");
  ms_strbuild_append_i64(&message, elements);
  ms_strbuild_append_text(&message, " elements");
  ms_fault_post_built(MS_FAULT_KIND_FAULT, &message);
}
