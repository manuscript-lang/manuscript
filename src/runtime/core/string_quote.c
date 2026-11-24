/* runtime/core/string_quote.c: `String.quote`, the double-quoted, escaped spelling of a string, as `%q`
 * writes it. Quote, backslash, line feed, tab and carriage return take a two-byte escape; every other control
 * byte and DEL take `\x` and two lower-case hex digits; all other bytes, whole UTF-8 sequences included, are
 * copied. */
#include "base/strbuild.h"
#include "runtime/core/string_text.h"
#include "runtime/core/string.h"
#include "runtime/core/string_support.h"

/* The letter that follows the backslash of a two-byte escape for `byte`, or 0 when the byte has none. */
static uint8_t pair_escape(uint8_t byte) {
  switch (byte) {
  case '"':
    return '"';
  case '\\':
    return '\\';
  case '\n':
    return 'n';
  case '\t':
    return 't';
  case '\r':
    return 'r';
  default:
    return 0;
  }
}

static bool needs_hex_escape(uint8_t byte) {
  return byte < 0x20 || byte == 0x7F;
}

static void put_escaped(MsStrBuild *out, uint8_t byte) {
  static const char digits[] = "0123456789abcdef";
  const uint8_t letter = pair_escape(byte);
  if (letter != 0) {
    ms_strbuild_append_byte(out, '\\');
    ms_strbuild_append_byte(out, letter);
  } else if (needs_hex_escape(byte)) {
    ms_strbuild_append_text(out, "\\x");
    ms_strbuild_append_byte(out, (uint8_t)digits[byte >> 4u]);
    ms_strbuild_append_byte(out, (uint8_t)digits[byte & 0xFu]);
  } else {
    ms_strbuild_append_byte(out, byte);
  }
}

void msrt_string_quote(const MsString *s, MsString *out) {
  const MsSpan text = msrt_text(s);
  MsStrBuild quoted = ms_strbuild_new();
  ms_strbuild_append_byte(&quoted, '"');
  for (size_t index = 0; index < text.len; index++) {
    put_escaped(&quoted, text.ptr[index]);
  }
  ms_strbuild_append_byte(&quoted, '"');
  if (ms_strbuild_length(&quoted) > MSRT_STRING_LIMIT) {
    ms_strbuild_free(&quoted);
    msrt_string_limit_post();
    return;
  }
  *out = ms_strbuild_finish(&quoted);
  ms_strbuild_free(&quoted);
}
