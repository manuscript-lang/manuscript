/* The Unicode properties runtime/std/unicode.c answers with PCRE2's tables, shared with the display width. */
#ifndef MS_RUNTIME_STD_UNICODE_PROPERTY_H
#define MS_RUNTIME_STD_UNICODE_PROPERTY_H

#include <stdbool.h>
#include <stdint.h>

/* A property PCRE2 answers: a pattern that matches exactly the one scalar's bytes when the scalar has it. */
typedef enum Property {
  PROPERTY_PUNCTUATION,
  PROPERTY_SYMBOL,
  PROPERTY_MARK,
  PROPERTY_ALPHABETIC,
  PROPERTY_NUMERIC,
  PROPERTY_ALPHANUMERIC,
  PROPERTY_LOWERCASE,
  PROPERTY_UPPERCASE,
  PROPERTY_WHITESPACE,
  PROPERTY_EMOJI,
  PROPERTY_EXTENDED_PICTOGRAPHIC,
  PROPERTY_EMOJI_MODIFIER_BASE,
  PROPERTY_COUNT
} Property;

/* Whether the scalar has the property; a value that is not a Unicode scalar has none. */
bool ms_unicode_has_property(int64_t value, Property property);

#endif
