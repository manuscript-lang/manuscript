/* runtime/core/string_lists.c: strings as lists and lists as strings: chars, lines, fields, scalar_values,
 * from_scalars, to_bytes and view_bytes, plus the scalar-set natives (index_any, trim_chars, scalar_at).
 * Results are written through `out`, which the caller owns from then on. */
#include "abi/status.h"
#include "base/alloc.h"
#include "base/bytes.h"
#include "base/chars.h"
#include "base/search.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "runtime/core/fault.h"
#include "runtime/core/string.h"
#include "runtime/core/string_support.h"

static void out_list(MsStringList list, MsList *out) {
  *out = *ms_string_list_erased(&list);
}

/* ---- chars, lines, fields ---- */

/* `String.chars`: one string per scalar; a stray byte reads as U+FFFD. */
void msrt_string_chars(const MsString *s, MsList *out) {
  static const uint8_t replacement[] = {0xEF, 0xBF, 0xBD};
  const MsSpan text = msrt_text(s);
  MsStringList list = {0};
  ms_string_list_reserve(&list, ms_utf8_count(text.ptr, text.len));
  for (size_t at = 0; at < text.len;) {
    const MsRune rune = ms_utf8_decode(text.ptr + at, text.len - at);
    const bool stray = rune.rune == MS_RUNE_ERROR && rune.width == 1;
    ms_string_list_push(&list, msrt_string_make(stray ? ms_span_of(replacement, sizeof replacement)
                                                      : ms_span_of(text.ptr + at, rune.width)));
    at += rune.width;
  }
  out_list(list, out);
}

/* `String.lines`: the text between line feeds; a carriage return before one is dropped, and a final line
 * without a line feed counts only when it is not empty. */
void msrt_string_lines(const MsString *s, MsList *out) {
  static const uint8_t line_feed = '\n';
  const MsSpan text = msrt_text(s);
  MsStringList list = {0};
  size_t start = 0;
  for (;;) {
    const size_t found = ms_find(text.ptr + start, text.len - start, &line_feed, 1);
    if (found == SIZE_MAX) {
      break;
    }
    size_t end = start + found;
    if (end > start && text.ptr[end - 1] == '\r') {
      end--;
    }
    ms_string_list_push(&list, msrt_string_make(ms_span_of(text.ptr + start, end - start)));
    start += found + 1;
  }
  if (start < text.len) {
    ms_string_list_push(&list, msrt_string_make(ms_span_of(text.ptr + start, text.len - start)));
  }
  out_list(list, out);
}

/* Whether the scalar at the start of `rest` is White_Space, and its width. */
static bool space_at(MsSpan rest, size_t *width) {
  if (rest.ptr[0] < 0x80) {
    *width = 1;
    return ms_ascii_is_space(rest.ptr[0]);
  }
  const MsRune rune = ms_utf8_decode(rest.ptr, rest.len);
  *width = rune.width;
  return ms_utf8_is_space(rune.rune);
}

/* `String.fields`: the runs of text between Unicode White_Space, none empty. */
void msrt_string_fields(const MsString *s, MsList *out) {
  const MsSpan text = msrt_text(s);
  MsStringList list = {0};
  size_t field_start = 0;
  bool in_field = false;
  for (size_t at = 0; at < text.len;) {
    size_t width = 0;
    const bool space = space_at(ms_span_of(text.ptr + at, text.len - at), &width);
    if (space && in_field) {
      ms_string_list_push(&list, msrt_string_make(ms_span_of(text.ptr + field_start, at - field_start)));
      in_field = false;
    } else if (!space && !in_field) {
      in_field = true;
      field_start = at;
    }
    at += width;
  }
  if (in_field) {
    ms_string_list_push(&list, msrt_string_make(ms_span_of(text.ptr + field_start, text.len - field_start)));
  }
  out_list(list, out);
}

/* ---- scalars and bytes ---- */

/* `String.scalar_values`: the scalars as a list of Int. */
void msrt_string_scalar_values(const MsString *s, MsList *out) {
  const MsSpan text = msrt_text(s);
  MsList values = {0};
  ms_list_reserve(&values, sizeof(int64_t), ms_utf8_count(text.ptr, text.len));
  for (size_t at = 0; at < text.len;) {
    const MsRune rune = ms_utf8_decode(text.ptr + at, text.len - at);
    const int64_t value = (int64_t)rune.rune;
    ms_list_push(&values, sizeof value, &value);
    at += rune.width;
  }
  *out = values;
}

static bool is_scalar(int64_t value) {
  const bool surrogate = value >= 0xD800 && value <= 0xDFFF;
  return value >= 0 && value <= 0x10FFFF && !surrogate;
}

/* `String.from_scalars`: invalid input when a value is not a Unicode scalar. */
uint8_t msrt_string_from_scalars(const MsList *values, MsString *out) {
  const int64_t *scalars = (const int64_t *)(const void *)values->ptr;
  MsStrBuild text = ms_strbuild_new();
  for (size_t index = 0; index < values->len; index++) {
    if (!is_scalar(scalars[index])) {
      ms_strbuild_free(&text);
      return MS_STATUS_INVALID_INPUT;
    }
    ms_strbuild_append_utf8(&text, (uint32_t)scalars[index]);
  }
  if (ms_strbuild_length(&text) > MSRT_STRING_LIMIT) {
    msrt_string_limit_fault();
  }
  *out = msrt_string_make(ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return MS_STATUS_OK;
}

/* `String.to_bytes`: a copy of the UTF-8 bytes. An empty Bytes has a null pointer. */
void msrt_string_to_bytes(const MsString *s, MsList *out) {
  *out = ms_bytes_from_span(msrt_text(s));
}

/* `String.view_bytes`: the bytes borrowed from the receiver, nothing copied (`cap == 0` marks a view). The
 * bytes of an inline text are the receiver's own storage, so it must stay alive while the view is read. */
void msrt_string_view_bytes(const MsString *s, MsList *out) {
  const MsSpan text = msrt_text(s);
  *out = text.len == 0 ? (MsList){0} : ms_bytes_view(text);
}

/* ---- scalar sets ---- */

/* A set of scalars: the ASCII members are two 64-bit masks, the rest are the set's own bytes from the first
 * non-ASCII one, decoded on demand. */
typedef struct ScalarSet {
  uint64_t low;  /* scalars 0..63 */
  uint64_t high; /* scalars 64..127 */
  MsSpan wide;
} ScalarSet;

static ScalarSet scalar_set(MsSpan members) {
  ScalarSet set = {0};
  for (size_t index = 0; index < members.len; index++) {
    const uint8_t byte = members.ptr[index];
    if (byte < 64) {
      set.low |= UINT64_C(1) << byte;
    } else if (byte < 0x80) {
      set.high |= UINT64_C(1) << (byte - 64);
    } else if (set.wide.len == 0) {
      set.wide = ms_span_of(members.ptr + index, members.len - index);
    }
  }
  return set;
}

static bool set_contains(const ScalarSet *set, uint32_t scalar) {
  if (scalar < 64) {
    return ((set->low >> scalar) & 1) != 0;
  }
  if (scalar < 0x80) {
    return ((set->high >> (scalar - 64)) & 1) != 0;
  }
  for (size_t at = 0; at < set->wide.len;) {
    const MsRune member = ms_utf8_decode(set->wide.ptr + at, set->wide.len - at);
    if (member.rune == scalar) {
      return true;
    }
    at += member.width;
  }
  return false;
}

uint8_t msrt_string_index_any(const MsString *s, const MsString *set, int64_t *out) {
  const MsSpan text = msrt_text(s);
  const ScalarSet members = scalar_set(msrt_text(set));
  for (size_t at = 0; at < text.len;) {
    const MsRune scalar = ms_utf8_decode(text.ptr + at, text.len - at);
    if (set_contains(&members, scalar.rune)) {
      *out = (int64_t)at;
      return 1;
    }
    at += scalar.width;
  }
  return 0;
}

void msrt_string_trim_chars(const MsString *s, const MsString *set, uint8_t from_start, uint8_t from_end,
                            MsString *out) {
  const MsSpan text = msrt_text(s);
  const ScalarSet members = scalar_set(msrt_text(set));
  size_t begin = 0;
  size_t end = text.len;
  while (from_start != 0 && begin < end) {
    const MsRune scalar = ms_utf8_decode(text.ptr + begin, end - begin);
    if (!set_contains(&members, scalar.rune)) {
      break;
    }
    begin += scalar.width;
  }
  while (from_end != 0 && end > begin) {
    const MsRune scalar = ms_utf8_decode_last(text.ptr + begin, end - begin);
    if (!set_contains(&members, scalar.rune)) {
      break;
    }
    end -= scalar.width;
  }
  *out = msrt_string_make(ms_span_of(text.ptr + begin, end - begin));
}

/* `String.scalar_at`: the scalar that starts at byte `offset`, or the default; a fault without one. */
int64_t msrt_string_scalar_at(const MsString *s, int64_t offset, uint8_t has_default, int64_t fallback) {
  const MsSpan text = msrt_text(s);
  if (offset >= 0 && (uint64_t)offset < text.len && !ms_utf8_is_continuation(text.ptr[offset])) {
    return (int64_t)ms_utf8_decode(text.ptr + offset, text.len - (size_t)offset).rune;
  }
  if (has_default != 0) {
    return fallback;
  }
  MsStrBuild message = ms_strbuild_new();
  ms_strbuild_append_text(&message, "String.scalar_at: offset ");
  ms_strbuild_append_i64(&message, offset);
  ms_strbuild_append_text(&message, " does not start a scalar of the ");
  ms_strbuild_append_u64(&message, text.len);
  ms_strbuild_append_text(&message, " byte text; pass a default");
  ms_fault(MS_FAULT_KIND_FAULT, ms_strbuild_span(&message));
}
