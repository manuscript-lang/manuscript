/* runtime/core/string_cut.c: the natives that cut a string: trim (as a view, a copy, or in place for a string
 * that dies at the call), slice, view, char_at and padding. */
#include "base/alloc.h"
#include "base/chars.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "runtime/core/fault.h"
#include "runtime/core/string.h"
#include "runtime/core/string_support.h"

/* ---- trim ---- */

typedef struct TrimRange {
  size_t start;
  size_t end;
} TrimRange;

static size_t trim_start_scan(MsSpan text, size_t start, size_t end) {
  while (start < end) {
    if (text.ptr[start] < 0x80) {
      if (!ms_ascii_is_space(text.ptr[start])) {
        break;
      }
      start++;
      continue;
    }
    const MsRune rune = ms_utf8_decode(text.ptr + start, end - start);
    if (!ms_utf8_is_space(rune.rune)) {
      break;
    }
    start += rune.width;
  }
  return start;
}

static size_t trim_end_scan(MsSpan text, size_t start, size_t end) {
  while (end > start) {
    if (text.ptr[end - 1] < 0x80) {
      if (!ms_ascii_is_space(text.ptr[end - 1])) {
        break;
      }
      end--;
      continue;
    }
    const MsRune rune = ms_utf8_decode_last(text.ptr + start, end - start);
    if (!ms_utf8_is_space(rune.rune)) {
      break;
    }
    end -= rune.width;
  }
  return end;
}

/* The range left after trimming white space from the ends asked for. */
static TrimRange trim_range(MsSpan text, bool at_start, bool at_end) {
  TrimRange range = {.start = 0, .end = text.len};
  if (at_start) {
    range.start = trim_start_scan(text, range.start, range.end);
  }
  if (at_end) {
    range.end = trim_end_scan(text, range.start, range.end);
  }
  return range;
}

/* A view of `s` without the white space the flags name: nothing is allocated. */
static void trim_view(const MsString *s, bool at_start, bool at_end, MsString *out) {
  const MsSpan text = msrt_text(s);
  const TrimRange range = trim_range(text, at_start, at_end);
  if (range.start == range.end) {
    *out = ms_string_empty(); /* an empty result borrows nothing */
  } else if (range.end - range.start == text.len && !msrt_string_owns(s)) {
    *out = *s;
  } else {
    *out = msrt_string_view_of(ms_span_of(text.ptr + range.start, range.end - range.start));
  }
}

void msrt_string_trim(const MsString *s, MsString *out) {
  trim_view(s, true, true, out);
}

void msrt_string_trim_start(const MsString *s, MsString *out) {
  trim_view(s, true, false, out);
}

void msrt_string_trim_end(const MsString *s, MsString *out) {
  trim_view(s, false, true, out);
}

/* ---- characters ---- */

/* The character that starts at byte `at` (a lead byte or a stray byte, which reads as U+FFFD) as a
 * one-character string; an offset outside the text gives the empty string. */
void msrt_string_char_at(const MsString *s, int64_t at, MsString *out) {
  static const uint8_t replacement[] = {0xEF, 0xBF, 0xBD};
  const MsSpan text = msrt_text(s);
  if (at < 0 || (uint64_t)at >= text.len) {
    *out = ms_string_empty();
    return;
  }
  const MsRune rune = ms_utf8_decode(text.ptr + at, text.len - (size_t)at);
  if (rune.rune == MS_RUNE_ERROR && rune.width == 1) {
    *out = msrt_string_make(ms_span_of(replacement, sizeof replacement));
    return;
  }
  *out = msrt_string_make(ms_span_of(text.ptr + at, rune.width));
}

/* ---- slices and views ---- */

static bool is_boundary(MsSpan text, size_t index) {
  return index == text.len || !ms_utf8_is_continuation(text.ptr[index]);
}

/* A bound as an offset into `length` bytes: a negative bound counts back from the end. */
static int64_t resolve_bound(int64_t bound, int64_t length) {
  return bound < 0 ? length + bound : bound;
}

static size_t clamp_to_text(int64_t offset, int64_t length) {
  if (offset < 0) {
    return 0;
  }
  return (size_t)(offset > length ? length : offset);
}

/* `String.slice(start, end)`: an owned copy of the bytes [start, end). Bounds outside the text clamp to it
 * and a bound inside a scalar moves inward, so the result is always whole characters and the call never
 * fails. */
void msrt_string_slice(const MsString *s, int64_t start, int64_t end, MsString *out) {
  const MsSpan text = msrt_text(s);
  const int64_t length = (int64_t)text.len;
  size_t first = clamp_to_text(resolve_bound(start, length), length);
  size_t last = clamp_to_text(resolve_bound(end, length), length);
  while (first < last && !is_boundary(text, first)) {
    first++;
  }
  while (last > first && !is_boundary(text, last)) {
    last--;
  }
  if (first >= last) {
    *out = ms_string_empty();
  } else if (last - first == text.len) {
    *out = ms_string_clone(s);
  } else {
    *out = msrt_string_make(ms_span_of(text.ptr + first, last - first));
  }
}

static void post_view_bounds(int64_t start, int64_t end) {
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "String.view: bounds ");
  ms_strbuild_append_i64(&message, start);
  ms_strbuild_append_text(&message, "..");
  ms_strbuild_append_i64(&message, end);
  ms_strbuild_append_text(&message, " are outside the text or inside a scalar");
  ms_fault_post_built(MS_FAULT_KIND_FAULT, &message);
}

/* `String.view(start, end)`: the bytes [start, end) borrowed from the receiver, nothing allocated. A bound
 * outside the text or inside a scalar faults. */
void msrt_string_view(const MsString *s, int64_t start, int64_t end, MsString *out) {
  const MsSpan text = msrt_text(s);
  const int64_t length = (int64_t)text.len;
  const int64_t first = resolve_bound(start, length);
  const int64_t last = resolve_bound(end, length);
  if (first < 0 || last < first || last > length || !is_boundary(text, (size_t)first) ||
      !is_boundary(text, (size_t)last)) {
    post_view_bounds(start, end);
    return;
  }
  *out = last == first ? ms_string_empty()
                       : msrt_string_view_of(ms_span_of(text.ptr + first, (size_t)(last - first)));
}
