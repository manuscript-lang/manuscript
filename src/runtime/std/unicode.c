/* runtime/std/unicode.c: @std/unicode natives: scalar properties answered by PCRE2's Unicode tables, and
 * UTF-8 validation. ASCII and the control sets are decided here; the rest asks one compiled pattern per
 * property. A value that is not a Unicode scalar has no property. */
#include "runtime/std/unicode.h"

#include "base/chars.h"
#include "base/utf8.h"
#include "runtime/std/unicode_property.h"

#include <pcre2.h>
#include <stdatomic.h>

static const char *const property_patterns[PROPERTY_COUNT] = {
    [PROPERTY_PUNCTUATION] = "^\\p{P}$",
    [PROPERTY_SYMBOL] = "^\\p{S}$",
    [PROPERTY_MARK] = "^\\p{M}$",
    [PROPERTY_ALPHABETIC] = "^\\p{Alphabetic}$",
    [PROPERTY_NUMERIC] = "^\\p{N}$",
    [PROPERTY_ALPHANUMERIC] = "^[\\p{Alphabetic}\\p{N}]$",
    [PROPERTY_LOWERCASE] = "^\\p{Lowercase}$",
    [PROPERTY_UPPERCASE] = "^\\p{Uppercase}$",
    [PROPERTY_WHITESPACE] = "^\\p{White_Space}$",
    [PROPERTY_EMOJI] = "^\\p{Emoji}$",
    [PROPERTY_EXTENDED_PICTOGRAPHIC] = "^\\p{Extended_Pictographic}$",
    [PROPERTY_EMOJI_MODIFIER_BASE] = "^\\p{Emoji_Modifier_Base}$",
};

/* One compiled pattern per property, shared by every thread: a pattern is immutable once compiled, so a
 * thread that loses the race to publish one frees its own. */
static _Atomic(pcre2_code *) compiled[PROPERTY_COUNT];

static pcre2_code *property_code(Property property) {
  pcre2_code *code = atomic_load(&compiled[property]);
  if (code != NULL) {
    return code;
  }
  int error = 0;
  PCRE2_SIZE offset = 0;
  pcre2_code *fresh = pcre2_compile((PCRE2_SPTR)property_patterns[property], PCRE2_ZERO_TERMINATED,
                                    PCRE2_UTF | PCRE2_UCP, &error, &offset, NULL);
  if (fresh == NULL) {
    return NULL;
  }
  pcre2_code *expected = NULL;
  if (atomic_compare_exchange_strong(&compiled[property], &expected, fresh)) {
    return fresh;
  }
  pcre2_code_free(fresh);
  return expected;
}

static bool is_scalar(int64_t value) {
  return value >= 0 && value <= 0x10FFFF && (value < 0xD800 || value > 0xDFFF);
}

bool ms_unicode_has_property(int64_t value, Property property) {
  if (!is_scalar(value)) {
    return false;
  }
  uint8_t encoded[4];
  const size_t length = ms_utf8_encode((uint32_t)value, encoded);
  pcre2_code *code = property_code(property);
  pcre2_match_data *data = code != NULL ? pcre2_match_data_create_from_pattern(code, NULL) : NULL;
  const int result =
      data != NULL ? pcre2_match(code, encoded, length, 0, 0, data, NULL) : PCRE2_ERROR_NOMEMORY;
  pcre2_match_data_free(data);
  return result >= 0;
}

/* The ASCII answer when `value` is ASCII, else the PCRE2 property. */
static uint8_t classify(int64_t value, bool (*ascii)(uint8_t), Property property) {
  if (value >= 0 && value < 0x80) {
    return ascii((uint8_t)value);
  }
  return ms_unicode_has_property(value, property);
}

uint8_t msstd_unicode_is_alphabetic(int64_t value) {
  return classify(value, ms_ascii_is_alpha, PROPERTY_ALPHABETIC);
}

uint8_t msstd_unicode_is_alphanumeric(int64_t value) {
  return classify(value, ms_ascii_is_alnum, PROPERTY_ALPHANUMERIC);
}

uint8_t msstd_unicode_is_numeric(int64_t value) {
  return classify(value, ms_ascii_is_digit, PROPERTY_NUMERIC);
}

uint8_t msstd_unicode_is_lowercase(int64_t value) {
  return classify(value, ms_ascii_is_lower, PROPERTY_LOWERCASE);
}

uint8_t msstd_unicode_is_uppercase(int64_t value) {
  return classify(value, ms_ascii_is_upper, PROPERTY_UPPERCASE);
}

uint8_t msstd_unicode_is_ascii(int64_t value) {
  return value >= 0 && value < 0x80;
}

uint8_t msstd_unicode_is_whitespace(int64_t value) {
  return classify(value, ms_ascii_is_space, PROPERTY_WHITESPACE);
}

uint8_t msstd_unicode_is_control(int64_t value) {
  return (value >= 0 && value < 0x20) || (value >= 0x7F && value < 0xA0);
}

uint8_t msstd_utf8_is_valid(const MsList *data) {
  return ms_utf8_is_valid(data->ptr, data->len);
}

/* The category letter's property; PROPERTY_COUNT for anything but "P", "S" or "M". */
static Property category_property(const MsString *category) {
  const MsSpan text = ms_string_span(category);
  if (text.len != 1) {
    return PROPERTY_COUNT;
  }
  switch (text.ptr[0]) {
  case 'P':
    return PROPERTY_PUNCTUATION;
  case 'S':
    return PROPERTY_SYMBOL;
  case 'M':
    return PROPERTY_MARK;
  default:
    return PROPERTY_COUNT;
  }
}

uint8_t msstd_unicode_in_category(int64_t value, const MsString *category) {
  const Property property = category_property(category);
  return property != PROPERTY_COUNT && ms_unicode_has_property(value, property);
}
