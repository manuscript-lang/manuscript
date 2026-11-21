/* The @std/data/html natives: escaping and character-reference decoding, ported from Go's html/escape.go. */
#include "base/strbuild.h"
#include "runtime/std/html.h"
#include "runtime/std/html_internal.h"

/* All entities that do not end with ';' are 6 or fewer bytes long. */
enum { LONGEST_WITHOUT_SEMICOLON = 6, MAX_SCALAR = 0x10FFFF, SATURATED = 0x110000 };

/* Windows-1252 replacements for numeric references 0x80..=0x9F. */
static const uint32_t REPLACEMENT[32] = {0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
                                         0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
                                         0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
                                         0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178};

static void push_rune(MsStrBuild *out, uint32_t rune) {
  ms_strbuild_append_utf8(out, rune > MAX_SCALAR || (rune >= 0xD800 && rune <= 0xDFFF) ? 0xFFFDu : rune);
}

/* Orders `name` against an entity's name, bytewise. */
static int compare_name(MsSpan name, const MsHtmlEntity *entity) {
  const size_t common = name.len < entity->length ? name.len : entity->length;
  for (size_t i = 0; i < common; i++) {
    const uint8_t left = name.ptr[i];
    const uint8_t right = (uint8_t)entity->name[i];
    if (left != right) {
      return left < right ? -1 : 1;
    }
  }
  return name.len == entity->length ? 0 : (name.len < entity->length ? -1 : 1);
}

static const MsHtmlEntity *search(const MsHtmlEntity *table, size_t count, MsSpan name) {
  size_t low = 0;
  size_t high = count;
  while (low < high) {
    const size_t middle = low + (high - low) / 2;
    const int order = compare_name(name, &table[middle]);
    if (order == 0) {
      return &table[middle];
    }
    if (order < 0) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return NULL;
}

static bool is_alnum(uint8_t c) {
  return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static int digit_value(uint8_t c, uint32_t radix) {
  int value = 99;
  if (c >= '0' && c <= '9') {
    value = c - '0';
  } else if (c >= 'a' && c <= 'f') {
    value = c - 'a' + 10;
  } else if (c >= 'A' && c <= 'F') {
    value = c - 'A' + 10;
  }
  return (uint32_t)value < radix ? value : -1;
}

/* A numeric reference at s[0] == '&', s[1] == '#': appends its rune and returns the bytes consumed, or 1 (the
 * `&` stays literal, appended by the caller) for a reference without digits. */
static size_t numeric_entity(MsSpan s, MsStrBuild *out) {
  size_t i = 2;
  const bool hex = i < s.len && (s.ptr[i] == 'x' || s.ptr[i] == 'X');
  if (hex) {
    i++;
  }
  const uint32_t radix = hex ? 16 : 10;
  const size_t digits_start = i;
  uint32_t x = 0; /* saturates above U+10FFFF so a long digit run maps to U+FFFD */
  while (i < s.len && digit_value(s.ptr[i], radix) >= 0) {
    x = x * radix + (uint32_t)digit_value(s.ptr[i], radix);
    x = x > SATURATED ? SATURATED : x;
    i++;
  }
  const bool terminated = i < s.len && s.ptr[i] == ';';
  /* The tokenizer oracle decodes a digitless `&#x;` as U+FFFD; the string form keeps it literal. */
  if (i == digits_start && !(hex && terminated)) {
    return 0;
  }
  if (terminated) {
    i++;
  }
  uint32_t rune = x;
  if (x >= 0x80 && x <= 0x9F) {
    rune = REPLACEMENT[x - 0x80];
  } else if (x == 0 || (x >= 0xD800 && x <= 0xDFFF) || x > MAX_SCALAR) {
    rune = 0xFFFD;
  }
  push_rune(out, rune);
  return i;
}

static const MsHtmlEntity *lookup(MsSpan name) {
  return search(ms_html_entities, ms_html_entity_count, name);
}

/* The longest prefix of a name without `;` that is an entity, for text outside attributes. */
static size_t legacy_prefix(MsSpan name, MsStrBuild *out) {
  size_t longest = name.len - 1 < LONGEST_WITHOUT_SEMICOLON ? name.len - 1 : LONGEST_WITHOUT_SEMICOLON;
  for (size_t j = longest; j >= 2; j--) {
    const MsHtmlEntity *entity = lookup(ms_span_of(name.ptr, j));
    if (entity != NULL) {
      push_rune(out, entity->first);
      return j + 1;
    }
  }
  return 0;
}

/* Reads a reference at s[0] == '&', appending its replacement (or the consumed bytes unchanged) to `out`, and
 * returns the number of bytes consumed. */
static size_t unescape_entity(MsSpan s, MsStrBuild *out, bool attribute) {
  if (s.len <= 1) {
    ms_strbuild_append(out, ms_span_of(s.ptr, 1));
    return 1;
  }
  if (s.ptr[1] == '#') {
    const size_t used = numeric_entity(s, out);
    if (used == 0) {
      ms_strbuild_append(out, ms_span_of(s.ptr, 1));
      return 1;
    }
    return used;
  }
  size_t i = 1;
  while (i < s.len) {
    const uint8_t c = s.ptr[i++];
    if (is_alnum(c)) {
      continue;
    }
    if (c != ';') {
      i--;
    }
    break;
  }
  const MsSpan name = ms_span_of(s.ptr + 1, i - 1);
  const bool semicolon = name.len > 0 && name.ptr[name.len - 1] == ';';
  if (name.len > 0 && !(attribute && !semicolon && i < s.len && s.ptr[i] == '=')) {
    const MsHtmlEntity *single = lookup(name);
    const MsHtmlEntity *pair =
        single == NULL ? search(ms_html_pair_entities, ms_html_pair_count, name) : NULL;
    if (single != NULL || pair != NULL) {
      const MsHtmlEntity *found = single != NULL ? single : pair;
      push_rune(out, found->first);
      if (found->second != 0) {
        push_rune(out, found->second);
      }
      return i;
    }
    const size_t used = attribute ? 0 : legacy_prefix(name, out);
    if (used != 0) {
      return used;
    }
  }
  ms_strbuild_append(out, ms_span_of(s.ptr, i));
  return i;
}

/* `text` with its references decoded. `literal_empty_hex` keeps `&#x;` literal (the string form). */
static MsString unescape(MsSpan text, bool attribute, bool literal_empty_hex) {
  MsStrBuild out = ms_strbuild_new();
  size_t i = 0;
  while (i < text.len) {
    size_t run = 0;
    while (i + run < text.len && text.ptr[i + run] != '&') {
      run++;
    }
    ms_strbuild_append(&out, ms_span_of(text.ptr + i, run));
    i += run;
    if (i == text.len) {
      break;
    }
    const MsSpan rest = ms_span_of(text.ptr + i, text.len - i);
    if (literal_empty_hex && rest.len >= 4 && rest.ptr[1] == '#' &&
        (rest.ptr[2] == 'x' || rest.ptr[2] == 'X') && rest.ptr[3] == ';') {
      ms_strbuild_append(&out, ms_span_of(rest.ptr, 4));
      i += 4;
    } else {
      i += unescape_entity(rest, &out, attribute);
    }
  }
  const MsString result = ms_strbuild_finish(&out);
  ms_strbuild_free(&out);
  return result;
}

void msstd_html_unescape(const MsString *text, MsString *out) {
  *out = unescape(ms_string_span(text), false, true);
}

void msstd_html_decode(const MsString *text, uint8_t attribute, MsString *out) {
  *out = unescape(ms_string_span(text), attribute != 0, false);
}

void msstd_html_escape(const MsString *text, MsString *out) {
  const MsSpan s = ms_string_span(text);
  MsStrBuild result = ms_strbuild_new();
  size_t start = 0;
  for (size_t i = 0; i < s.len; i++) {
    const char *replacement = NULL;
    switch (s.ptr[i]) {
    case '&':
      replacement = "&amp;";
      break;
    case '\'':
      replacement = "&#39;";
      break;
    case '<':
      replacement = "&lt;";
      break;
    case '>':
      replacement = "&gt;";
      break;
    case '"':
      replacement = "&#34;";
      break;
    default:
      break;
    }
    if (replacement != NULL) {
      ms_strbuild_append(&result, ms_span_of(s.ptr + start, i - start));
      ms_strbuild_append_text(&result, replacement);
      start = i + 1;
    }
  }
  ms_strbuild_append(&result, ms_span_of(s.ptr + start, s.len - start));
  *out = ms_strbuild_finish(&result);
  ms_strbuild_free(&result);
}
