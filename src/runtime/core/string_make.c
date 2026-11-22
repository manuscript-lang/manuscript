/* runtime/core/string_make.c: the natives that make strings from bytes or from other strings: construction,
 * clones, concatenation, append, repeat and reverse. The result rules are in string_support.h. */
#include "abi/status.h"
#include "base/alloc.h"
#include "base/chars.h"
#include "base/utf8.h"
#include "runtime/core/fault.h"
#include "runtime/core/string.h"
#include "runtime/core/string_support.h"

/* ---- shared constructors ---- */

void msrt_string_limit_fault(void) {
  ms_fault_text(MS_FAULT_KIND_FAULT, "string: limit exceeded");
}

size_t msrt_string_total(size_t a, size_t b) {
  size_t total = 0;
  if (!ms_size_add(a, b, &total) || total > MSRT_STRING_LIMIT) {
    msrt_string_limit_fault();
  }
  return total;
}

MsString msrt_string_make(MsSpan text) {
  if (text.len == 0) {
    return ms_string_empty();
  }
  if (text.len == 1 && text.ptr[0] < 0x80) {
    return ms_string_from_span(text); /* inline: a short string is its two words */
  }
  if (text.len > MSRT_STRING_LIMIT) {
    msrt_string_limit_fault();
  }
  return ms_string_from_span(text);
}

MsString msrt_string_view_of(MsSpan text) {
  if (text.len <= MS_STRING_INLINE_MAX) {
    return ms_string_from_span(text);
  }
  return ms_string_view(text);
}

uint8_t *msrt_string_block(size_t length, MsString *out) {
  if (length > MSRT_STRING_LIMIT) {
    msrt_string_limit_fault();
  }
  uint8_t *block = ms_alloc(length);
  *out = (MsString){.owned = block, .tagged = length};
  return block;
}

MsString msrt_string_from_block(uint8_t *block, size_t length) {
  if (length > MS_STRING_INLINE_MAX) {
    return (MsString){.owned = block, .tagged = length};
  }
  const MsString small = msrt_string_make(ms_span_of(block, length));
  ms_free(block);
  return small;
}

/* A string that is a copy of `string`: the same two words when they own nothing. */
/* An optional string's `none` is a static string with a null pointer, which no real string is (a literal points at
 * its bytes), so the copy of `none` stays `none` rather than becoming an empty string. */
static MsString cloned(const MsString *string) {
  if (string->tagged == (UINT64_C(2) << MS_STRING_TAG_SHIFT) && string->low_bits == 0) {
    return *string;
  }
  return ms_string_clone(string);
}

/* ---- construction ---- */

void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsString *out) {
  *out = msrt_string_make(ms_span_of(ptr, len));
}

void msrt_string_empty(MsString *out) {
  *out = ms_string_empty();
}

void msrt_string_clone(const MsString *s, MsString *out) {
  *out = cloned(s);
}

/* `tagged` is the second word of an owned string or a view, never of an inline string. */
void msrt_str_copy(const uint8_t *ptr, size_t tagged, MsString *out) {
  *out = ms_string_from_span(ms_span_of(ptr, tagged & MS_STRING_LENGTH_MASK));
}

void msrt_str_free(uint8_t *ptr) {
  ms_free(ptr);
}

void msrt_string_free(const MsString *s) {
  if (msrt_string_owns(s)) {
    ms_free(s->owned);
  }
}

/* ---- concatenation ---- */

/* The parts joined with a single allocation. */
MsString msrt_string_join(const MsSpan *parts, size_t count) {
  size_t total = 0;
  for (size_t index = 0; index < count; index++) {
    total = msrt_string_total(total, parts[index].len);
  }
  uint8_t small[MS_STRING_INLINE_MAX + 1];
  MsString result = ms_string_empty();
  uint8_t *cursor = total <= MS_STRING_INLINE_MAX ? small : msrt_string_block(total, &result);
  for (size_t index = 0; index < count; index++) {
    if (parts[index].len != 0) {
      __builtin_memcpy(cursor, parts[index].ptr, parts[index].len);
    }
    cursor += parts[index].len;
  }
  return total <= MS_STRING_INLINE_MAX ? msrt_string_make(ms_span_of(small, total)) : result;
}

/* The same over strings. */
static MsString join_strings(const MsString *const *parts, size_t count) {
  MsSpan spans[6];
  for (size_t index = 0; index < count; index++) {
    spans[index] = msrt_text(parts[index]);
  }
  return msrt_string_join(spans, count);
}

void msrt_string_concat(const MsString *a, const MsString *b, MsString *out) {
  if (ms_string_is_empty(b)) {
    *out = cloned(a);
  } else if (ms_string_is_empty(a)) {
    *out = cloned(b);
  } else {
    const MsString *const parts[] = {a, b};
    *out = join_strings(parts, MS_COUNT_OF(parts));
  }
}

void msrt_string_concat3(const MsString *a, const MsString *b, const MsString *c, MsString *out) {
  const MsString *const parts[] = {a, b, c};
  *out = join_strings(parts, MS_COUNT_OF(parts));
}

void msrt_string_concat4(const MsString *a, const MsString *b, const MsString *c, const MsString *d,
                         MsString *out) {
  const MsString *const parts[] = {a, b, c, d};
  *out = join_strings(parts, MS_COUNT_OF(parts));
}

void msrt_string_concat5(const MsString *a, const MsString *b, const MsString *c, const MsString *d,
                         const MsString *e, MsString *out) {
  const MsString *const parts[] = {a, b, c, d, e};
  *out = join_strings(parts, MS_COUNT_OF(parts));
}

void msrt_string_concat6(const MsString *a, const MsString *b, const MsString *c, const MsString *d,
                         const MsString *e, const MsString *f, MsString *out) {
  const MsString *const parts[] = {a, b, c, d, e, f};
  *out = join_strings(parts, MS_COUNT_OF(parts));
}

/* ---- append in place ---- */

/* An owned string records, in bits 31 to 60 of its second word, how many bytes its block holds past the text
 * (a lower bound): the room that lets `s = s + piece` in a loop reuse one block. */
#define SPARE_SHIFT 31
#define SPARE_MAX (((UINT64_C(1) << 30) - 1))

static size_t recorded_spare(const MsString *string) {
  return (size_t)((string->tagged >> SPARE_SHIFT) & SPARE_MAX);
}

static MsString with_spare(MsString string, size_t spare) {
  const uint64_t recorded = spare > SPARE_MAX ? SPARE_MAX : spare;
  string.tagged = (string.tagged & ~(SPARE_MAX << SPARE_SHIFT)) | (recorded << SPARE_SHIFT);
  return string;
}

/* Whether `piece` lies inside the text of `string`, so growing the block would move it. */
static bool lies_within(const MsString *string, MsSpan piece) {
  const uintptr_t start = (uintptr_t)string->owned;
  const uintptr_t at = (uintptr_t)piece.ptr;
  return at >= start && at - start <= ms_string_length(string);
}

/* Whether any part lies inside the text of `string`, so growing the block would move it. */
static bool any_within(const MsString *string, const MsSpan *parts, size_t count) {
  for (size_t index = 0; index < count; index++) {
    if (lies_within(string, parts[index])) {
      return true;
    }
  }
  return false;
}

/* `a` and then the parts, where the caller gives `a` up: an owned `a` grows in place, reallocating a
 * logarithmic number of times over a loop. Otherwise it is a join and `a` is released. */
MsString msrt_string_append_parts(const MsString *a, const MsSpan *parts, size_t count) {
  const MsString first = *a;
  const size_t length = ms_string_length(&first);
  size_t added = 0;
  for (size_t index = 0; index < count; index++) {
    added = msrt_string_total(added, parts[index].len);
  }
  if (!msrt_string_owns(&first) || length == 0 || any_within(&first, parts, count)) {
    MsSpan all[7] = {msrt_text(&first)};
    for (size_t index = 0; index < count; index++) {
      all[index + 1] = parts[index];
    }
    const MsString result = msrt_string_join(all, count + 1);
    msrt_string_free(&first);
    return result;
  }
  if (added == 0) {
    return first;
  }
  const size_t total = msrt_string_total(length, added);
  uint8_t *block = first.owned;
  size_t spare = recorded_spare(&first);
  if (spare >= added) {
    spare -= added;
  } else {
    const size_t capacity = total + total / 2;
    block = ms_realloc(block, capacity);
    spare = capacity - total;
  }
  uint8_t *cursor = block + length;
  for (size_t index = 0; index < count; index++) {
    if (parts[index].len != 0) {
      __builtin_memcpy(cursor, parts[index].ptr, parts[index].len);
    }
    cursor += parts[index].len;
  }
  return with_spare((MsString){.owned = block, .tagged = total}, spare);
}

/* `a + b` where the caller gives `a` up. */
void msrt_string_append(const MsString *a, const MsString *b, MsString *out) {
  const MsSpan added = msrt_text(b);
  *out = msrt_string_append_parts(a, &added, 1);
}

/* ---- repeat and reverse ---- */

/* Fills `destination` with whole copies of `pattern`: the first copy is written, then the filled part
 * doubles. */
static void fill_repeated(uint8_t *destination, size_t length, MsSpan pattern) {
  if (pattern.len == 1) {
    __builtin_memset(destination, pattern.ptr[0], length);
    return;
  }
  size_t filled = pattern.len < length ? pattern.len : length;
  __builtin_memcpy(destination, pattern.ptr, filled);
  while (filled < length) {
    const size_t step = filled < length - filled ? filled : length - filled;
    __builtin_memcpy(destination + filled, destination, step);
    filled += step;
  }
}

/* `String.repeat`: a count of zero or below, or empty text, gives empty text; a result past the string limit
 * faults like `concat`. */
void msrt_string_repeat(const MsString *s, int64_t count, MsString *out) {
  const MsSpan text = msrt_text(s);
  if (count <= 0 || text.len == 0) {
    *out = ms_string_empty();
    return;
  }
  if ((uint64_t)count > MSRT_STRING_LIMIT / text.len) {
    msrt_string_limit_fault();
  }
  const size_t total = text.len * (size_t)count;
  uint8_t small[MS_STRING_INLINE_MAX + 1];
  MsString result = ms_string_empty();
  uint8_t *destination = total <= MS_STRING_INLINE_MAX ? small : msrt_string_block(total, &result);
  fill_repeated(destination, total, text);
  *out = total <= MS_STRING_INLINE_MAX ? msrt_string_make(ms_span_of(small, total)) : result;
}

/* Writes the scalars of `text` into `destination` last first. A String is valid UTF-8, so a scalar is a lead
 * byte and its continuation bytes and moves as it is, without decoding. */
static void reverse_into(uint8_t *destination, MsSpan text) {
  size_t end = text.len;
  while (end > 0) {
    size_t start = end - 1;
    while (start > 0 && end - start < 4 && ms_utf8_is_continuation(text.ptr[start])) {
      start--;
    }
    __builtin_memcpy(destination, text.ptr + start, end - start);
    destination += end - start;
    end = start;
  }
}

void msrt_string_reverse(const MsString *a, MsString *out) {
  const MsSpan text = msrt_text(a);
  uint8_t small[MS_STRING_INLINE_MAX + 1];
  MsString result = ms_string_empty();
  uint8_t *destination = text.len <= MS_STRING_INLINE_MAX ? small : msrt_string_block(text.len, &result);
  reverse_into(destination, text);
  *out = text.len <= MS_STRING_INLINE_MAX ? msrt_string_make(ms_span_of(small, text.len)) : result;
}
