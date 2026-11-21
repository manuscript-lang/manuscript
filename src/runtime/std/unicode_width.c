/* runtime/std/unicode_width.c: @std/unicode display width: the columns a string takes in a terminal. Each
 * scalar is two columns, zero columns or one by runtime/std/unicode_width_table.h, and the emoji sequences
 * adjust that: a variation selector 16 after an emoji makes it two columns, a skin-tone modifier after a
 * modifier base and an emoji joined by a zero width joiner to a two column emoji add nothing. Emoji
 * properties come from PCRE2's tables (runtime/std/unicode.c). Control characters and the line and paragraph
 * separators have no width and are an error, so a caller that measures a string with them does not guess.
 * Scripts whose ligatures change the width (Arabic lam-alef, Hebrew, Khmer coeng, Buginese, Tifinagh, Lisu,
 * Old Turkic) count scalar by scalar. */
#include "runtime/std/unicode.h"

#include "base/utf8.h"
#include "runtime/std/unicode_property.h"
#include "runtime/std/unicode_width_table.h"

enum {
  ZERO_WIDTH_JOINER = 0x200D,
  REGIONAL_FIRST = 0x1F1E6,
  REGIONAL_LAST = 0x1F1FF,
  VARIATION_SELECTOR_16 = 0xFE0F,
  MODIFIER_FIRST = 0x1F3FB,
  MODIFIER_LAST = 0x1F3FF,
};

static bool in_ranges(const MsWidthRange *ranges, size_t count, uint32_t scalar) {
  size_t low = 0;
  size_t high = count;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    if (scalar < ranges[mid].first) {
      high = mid;
    } else if (scalar > ranges[mid].last) {
      low = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

static int64_t scalar_columns(uint32_t scalar) {
  if (scalar < 0x7F) {
    return scalar >= 0x20;
  }
  if (in_ranges(width_wide, MS_COUNT_OF(width_wide), scalar)) {
    return 2;
  }
  return in_ranges(width_zero, MS_COUNT_OF(width_zero), scalar) ? 0 : 1;
}

static bool is_control(uint32_t scalar) {
  return scalar < 0x20 || (scalar >= 0x7F && scalar < 0xA0) || scalar == 0x2028 || scalar == 0x2029;
}

/* Whether the scalar can be an emoji: the code points the Emoji property covers lie in a few blocks, so the
 * common text (Latin, CJK, Indic) never asks PCRE2. */
static bool may_be_emoji(uint32_t scalar) {
  return scalar == '#' || scalar == '*' || (scalar >= '0' && scalar <= '9') || scalar == 0xA9 ||
         scalar == 0xAE || (scalar >= 0x203C && scalar <= 0x3299) || (scalar >= 0x1F000 && scalar <= 0x1FAFF);
}

/* A regional indicator is an emoji, but a selector after one changes nothing: only a pair of them is a flag.
 */
static bool is_emoji(uint32_t scalar) {
  return may_be_emoji(scalar) && (scalar < REGIONAL_FIRST || scalar > REGIONAL_LAST) &&
         ms_unicode_has_property(scalar, PROPERTY_EMOJI);
}

static bool is_pictographic(uint32_t scalar) {
  return may_be_emoji(scalar) && ms_unicode_has_property(scalar, PROPERTY_EXTENDED_PICTOGRAPHIC);
}

static bool is_modifier(uint32_t scalar) {
  return scalar >= MODIFIER_FIRST && scalar <= MODIFIER_LAST;
}

/* The running width and the emoji the last scalars belong to. `head` is the columns that emoji counts for, so
 * a later selector, modifier or joined emoji can raise it to two without counting it twice. */
typedef struct Measure {
  int64_t total;
  int64_t head;
  uint32_t previous;
  bool in_emoji; /* the last non-mark scalar is an emoji (or a modifier or joiner continuing one) */
  bool joiner;   /* the last scalar is a zero width joiner after an emoji */
} Measure;

static void widen_head(Measure *m) {
  m->total += 2 - m->head;
  m->head = 2;
}

/* Adds one scalar. */
static void measure_scalar(Measure *m, uint32_t scalar) {
  const uint32_t previous = m->previous;
  m->previous = scalar;
  const bool joined = m->joiner;
  m->joiner = false;
  if (scalar == ZERO_WIDTH_JOINER) {
    m->joiner = m->in_emoji;
    return;
  }
  if (joined && m->head == 2 && (is_pictographic(scalar) || is_modifier(scalar))) {
    return; /* an emoji joined to a two column emoji is part of it */
  }
  if (scalar == VARIATION_SELECTOR_16 && m->in_emoji && is_emoji(previous)) {
    widen_head(m);
    return;
  }
  if (is_modifier(scalar) && m->in_emoji && ms_unicode_has_property(previous, PROPERTY_EMOJI_MODIFIER_BASE)) {
    widen_head(m);
    return;
  }
  const int64_t columns = scalar_columns(scalar);
  m->total += columns;
  if (columns > 0) {
    m->in_emoji = is_emoji(scalar);
    m->head = m->in_emoji ? columns : 0;
  }
}

uint8_t msstd_unicode_display_width(const MsString *text, int64_t *out) {
  const MsSpan bytes = ms_string_span(text);
  Measure measure = {0};
  for (size_t at = 0; at < bytes.len;) {
    const MsRune decoded = ms_utf8_decode(bytes.ptr + at, bytes.len - at);
    at += decoded.width;
    if (is_control(decoded.rune)) {
      return MS_STATUS_INVALID_DATA;
    }
    measure_scalar(&measure, decoded.rune);
  }
  *out = measure.total;
  return MS_STATUS_OK;
}
