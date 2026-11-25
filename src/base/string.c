/* Owns MsString construction, release, comparison and hashing (see string.h). */
#include "base/string.h"

#include "base/alloc.h"
#include "base/fatal.h"
#include "base/hash.h"

static uint64_t tagged_view(uint64_t tag, size_t length) {
  return (tag << MS_STRING_TAG_SHIFT) | length;
}

static size_t checked_length(size_t length) {
  if (length > MS_STRING_MAX_LENGTH) {
    ms_fatal(MS_FATAL_OUT_OF_RANGE, "string too long");
  }
  return length;
}

MsString ms_string_from_span(MsSpan span) {
  if (span.len <= MS_STRING_INLINE_MAX) {
    return ms_string_make_inline(span);
  }
  uint8_t *copy = ms_alloc(checked_length(span.len));
  __builtin_memcpy(copy, span.ptr, span.len);
  return (MsString){.owned = copy, .tagged = tagged_view(0, span.len)};
}

MsString ms_string_static(MsSpan span) {
  return (MsString){.borrow = span.ptr, .tagged = tagged_view(2, checked_length(span.len))};
}

MsString ms_string_view(MsSpan span) {
  return (MsString){.borrow = span.ptr, .tagged = tagged_view(3, checked_length(span.len))};
}

MsString ms_string_clone(const MsString *string) {
  /* inline bytes are the value, and static bytes live forever: both copy as they are */
  if (ms_string_is_inline(string) || (string->tagged >> MS_STRING_TAG_SHIFT) == 2) {
    return *string;
  }
  return ms_string_from_span(ms_string_span(string));
}

void ms_string_release(MsString *string) {
  if ((string->tagged >> MS_STRING_TAG_SHIFT) == 0) {
    ms_free(string->owned);
  }
  *string = ms_string_empty();
}

bool ms_string_equal(const MsString *a, const MsString *b) {
  if (a->low_bits == b->low_bits && a->tagged == b->tagged) {
    return true;
  }
  const size_t length = ms_string_length(a);
  if (length != ms_string_length(b)) {
    return false;
  }
  const uint8_t *left = ms_string_is_inline(a) ? a->inline_bytes : a->borrow;
  const uint8_t *right = ms_string_is_inline(b) ? b->inline_bytes : b->borrow;
  return length == 0 || __builtin_memcmp(left, right, length) == 0;
}

int ms_string_compare(const MsString *a, const MsString *b) {
  const MsSpan left = ms_string_span(a);
  const MsSpan right = ms_string_span(b);
  const size_t common = left.len < right.len ? left.len : right.len;
  const int order = common == 0 ? 0 : __builtin_memcmp(left.ptr, right.ptr, common);
  if (order != 0) {
    return order < 0 ? -1 : 1;
  }
  return (left.len > right.len) - (left.len < right.len);
}

uint64_t ms_string_hash(const MsString *string) {
  return ms_hash_span(ms_string_span(string));
}
