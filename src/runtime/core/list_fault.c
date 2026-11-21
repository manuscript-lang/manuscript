/* runtime/core/list_fault.c: sizes and the faults of the list natives. The messages are observable. */
#include "runtime/core/list.h"
#include "runtime/core/fault.h"
#include "runtime/core/list_support.h"

#include "base/alloc.h"
#include "base/strbuild.h"

MS_NORETURN void msrt_list_overflow_fault(void) {
  ms_fault_text(MS_FAULT_KIND_OVERFLOW, "list size overflow");
}

size_t msrt_list_buffer_bytes(size_t count, size_t slot_size) {
  size_t bytes = 0;
  if (!ms_size_mul(count, slot_size == 0 ? 1 : slot_size, &bytes)) {
    msrt_list_overflow_fault();
  }
  return bytes;
}

size_t msrt_list_checked_add(size_t a, size_t b) {
  size_t sum = 0;
  if (!ms_size_add(a, b, &sum)) {
    msrt_list_overflow_fault();
  }
  return sum;
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
  uint8_t *buffer = ms_alloc(msrt_list_buffer_bytes(capacity, d->size));
  return (MsList){.ptr = buffer, .len = count, .cap = capacity};
}

MS_NORETURN void msrt_splice_fault(const char *what, int64_t found, size_t high) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "List.splice: ");
  ms_strbuild_append_text(&message, what);
  ms_strbuild_append_text(&message, " must be between 0 and ");
  ms_strbuild_append_i64(&message, (int64_t)high);
  ms_strbuild_append_text(&message, ", found ");
  ms_strbuild_append_i64(&message, found);
  ms_fault(MS_FAULT_KIND_FAULT, ms_strbuild_span(&message));
}

MS_NORETURN void msrt_bounds_fault(const char *operation, size_t length, int64_t start, int64_t end) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, operation);
  ms_strbuild_append_text(&message, ": start/end must satisfy 0 <= start <= end <= ");
  ms_strbuild_append_i64(&message, (int64_t)length);
  ms_strbuild_append_text(&message, "; found start ");
  ms_strbuild_append_i64(&message, start);
  ms_strbuild_append_text(&message, " and end ");
  ms_strbuild_append_i64(&message, end);
  ms_fault(MS_FAULT_KIND_FAULT, ms_strbuild_span(&message));
}

void msrt_check_bounds(const char *operation, size_t length, int64_t start, int64_t end) {
  if (start < 0 || end < start || (uint64_t)end > length) {
    msrt_bounds_fault(operation, length, start, end);
  }
}

MS_NORETURN void msrt_copy_target_fault(size_t length, int64_t target) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "List.copy_within: target must be between 0 and ");
  ms_strbuild_append_i64(&message, (int64_t)length);
  ms_strbuild_append_text(&message, ", found ");
  ms_strbuild_append_i64(&message, target);
  ms_fault(MS_FAULT_KIND_FAULT, ms_strbuild_span(&message));
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

MS_NORETURN void msrt_fault_destructure(int64_t names, int64_t elements) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "destructuring length mismatch; the pattern binds ");
  ms_strbuild_append_i64(&message, names);
  ms_strbuild_append_text(&message, " names but the list has ");
  ms_strbuild_append_i64(&message, elements);
  ms_strbuild_append_text(&message, " elements");
  ms_fault(MS_FAULT_KIND_FAULT, ms_strbuild_span(&message));
}
