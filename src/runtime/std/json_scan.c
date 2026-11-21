/* The JSON scanner of @std/data/json: a strict parser that reports a document as events (json.h). It keeps
 * number text as written, rejects repeated object keys, trailing values and unpaired surrogate escapes, and
 * walks the document with an explicit stack, so nesting costs heap and not native stack. It owns the output
 * buffer helpers and the error text of a syntax error too. */
#include <stdio.h>

#include "runtime/std/json_internal.h"
#include "base/array.h"
#include "base/list.h"
#include "base/chars.h"
#include "base/strbuild.h"
#include "base/utf8.h"

/* ---- output buffer ---- */

/* Room for `extra` more bytes. */
MS_NODISCARD static bool buffer_reserve(JsonBuffer *buffer, size_t extra) {
  size_t needed = 0;
  if (!ms_size_add(buffer->bytes.len, extra, &needed) || needed > buffer->limit) {
    return false;
  }
  ms_list_reserve(&buffer->bytes, 1, extra);
  return true;
}

bool json_buffer_append(JsonBuffer *buffer, MsSpan bytes) {
  if (!buffer_reserve(buffer, bytes.len)) {
    return false;
  }
  if (bytes.len != 0) {
    memcpy(buffer->bytes.ptr + buffer->bytes.len, bytes.ptr, bytes.len);
  }
  buffer->bytes.len += bytes.len;
  return true;
}

bool json_buffer_push(JsonBuffer *buffer, uint8_t byte) {
  return json_buffer_append(buffer, ms_span_of(&byte, 1));
}

bool json_buffer_fill(JsonBuffer *buffer, uint8_t byte, size_t count) {
  if (!buffer_reserve(buffer, count)) {
    return false;
  }
  if (count != 0) {
    memset(buffer->bytes.ptr + buffer->bytes.len, byte, count);
  }
  buffer->bytes.len += count;
  return true;
}

void json_buffer_free(JsonBuffer *buffer) {
  ms_list_free(&buffer->bytes);
}

/* ---- limits ---- */

/* An optional non-negative budget; unset is unlimited. */
MS_NODISCARD static bool budget(uint8_t has_value, int64_t value, size_t *out) {
  *out = SIZE_MAX;
  if (!has_value) {
    return true;
  }
  if (value < 0 || (uint64_t)value > SIZE_MAX) {
    return false;
  }
  *out = (size_t)value;
  return true;
}

uint8_t json_limits(size_t length, uint8_t has_max_bytes, int64_t max_bytes, uint8_t has_max_depth,
                    int64_t max_depth, uint8_t has_max_values, int64_t max_values, JsonLimits *out) {
  size_t bytes = 0;
  JsonLimits limits = {0};
  if (!budget(has_max_bytes, max_bytes, &bytes) || !budget(has_max_depth, max_depth, &limits.max_depth) ||
      !budget(has_max_values, max_values, &limits.max_values)) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (length > bytes || length > MS_STRING_MAX_LENGTH) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  if (limits.max_depth > JSON_DEPTH_CEILING) {
    limits.max_depth = JSON_DEPTH_CEILING;
  }
  *out = limits;
  return MS_STATUS_OK;
}

/* ---- the scanner ---- */

typedef struct Scanner {
  MsSpan text;
  size_t pos;
  size_t count;
  JsonLimits limits;
  bool limit_hit;
  bool duplicate;
  const JsonSinkOps *ops;
  void *sink;
  JsonBuffer scratch; /* owned: the decoded text of the string being read */
  uint8_t *open;      /* owned: '[' or '{' for each open container */
  size_t open_length;
  size_t open_capacity;
} Scanner;

static bool at_end(const Scanner *scanner) {
  return scanner->pos >= scanner->text.len;
}

static uint8_t byte_at(const Scanner *scanner, size_t index) {
  return scanner->text.ptr[index];
}

#define BYTES_LOW UINT64_C(0x0101010101010101)
#define BYTES_HIGH UINT64_C(0x8080808080808080)

/* The bytes of `word` that are zero have their high bit set in the result (exact for the lowest such byte,
 * which is the one the scanners use). */
static inline uint64_t zero_bytes(uint64_t word) {
  return (word - BYTES_LOW) & ~word & BYTES_HIGH;
}

/* How many of the first eight bytes of `word` (in memory order) are spaces: the bytes that differ from 0x20
 * get their high bit set exactly, so the lowest one is the end of the run. */
static inline size_t space_run(uint64_t word) {
  const uint64_t differ = word ^ (BYTES_LOW * ' ');
  const uint64_t not_space = (((differ & ~BYTES_HIGH) + ~BYTES_HIGH) | differ) & BYTES_HIGH;
  return not_space == 0 ? 8 : (size_t)__builtin_ctzll(not_space) / 8;
}

/* The whitespace between tokens: the newline of an indented document, then its run of spaces, up to eight at
 * a time. */
static void skip_space_run(Scanner *scanner) {
  const uint8_t *text = scanner->text.ptr;
  const size_t length = scanner->text.len;
  size_t pos = scanner->pos;
  for (;;) {
    while (pos < length && (text[pos] == '\n' || text[pos] == '\r' || text[pos] == '\t')) {
      pos++;
    }
    size_t run = 0;
    do {
      if (pos + 8 <= length) {
        run = space_run(ms_load64(text + pos));
      } else {
        run = 0;
        while (pos + run < length && text[pos + run] == ' ') {
          run++;
        }
      }
      pos += run;
    } while (run == 8);
    if (pos >= length || (text[pos] != '\n' && text[pos] != '\r' && text[pos] != '\t')) {
      break;
    }
  }
  scanner->pos = pos;
}

/* Skips JSON whitespace. The two common cases stay inline: nothing to skip (a compact document), and the one
 * space after a colon or a comma. */
static inline void skip_space(Scanner *scanner) {
  const size_t pos = scanner->pos;
  const size_t length = scanner->text.len;
  if (pos < length) {
    const uint8_t c = scanner->text.ptr[pos];
    if (c > ' ') {
      return;
    }
    if (c == ' ' && pos + 1 < length && scanner->text.ptr[pos + 1] > ' ') {
      scanner->pos = pos + 1;
      return;
    }
  }
  skip_space_run(scanner);
}

/* The first index at or after `from` of a byte a string must escape: a quote, a backslash or a control
 * character. False when there is none. Eight bytes per step. */
static bool find_special(MsSpan text, size_t from, size_t *at) {
  size_t i = from;
  for (; i + 8 <= text.len; i += 8) {
    const uint64_t word = ms_load64(text.ptr + i);
    const uint64_t control = (word - BYTES_LOW * 0x20) & ~word & BYTES_HIGH;
    const uint64_t hit = control | zero_bytes(word ^ BYTES_LOW * '"') | zero_bytes(word ^ BYTES_LOW * '\\');
    if (hit != 0) {
      *at = i + (size_t)__builtin_ctzll(hit) / 8;
      return true;
    }
  }
  for (; i < text.len; i++) {
    const uint8_t c = text.ptr[i];
    if (c == '"' || c == '\\' || c < 0x20) {
      *at = i;
      return true;
    }
  }
  return false;
}

static bool literal(Scanner *scanner, const char *word) {
  const MsSpan prefix = ms_span_of_text(word);
  const MsSpan rest = ms_span_of(scanner->text.ptr + scanner->pos, scanner->text.len - scanner->pos);
  if (!ms_span_starts_with(rest, prefix)) {
    return false;
  }
  scanner->pos += prefix.len;
  return true;
}

/* How many of the first eight bytes of `word` (in memory order) are ASCII digits. A byte xor 0x30 is below
 * ten exactly when it is a digit; adding 0x76 sets the high bit for ten or more, and the high bit of the xor
 * itself covers bytes from 0x80. A carry can only corrupt bytes above the first non-digit, which is the one
 * that decides. */
static inline size_t digit_run(uint64_t word) {
  const uint64_t shifted = word ^ (BYTES_LOW * 0x30);
  const uint64_t not_digit = ((shifted + BYTES_LOW * 0x76) | shifted) & BYTES_HIGH;
  return not_digit == 0 ? 8 : (size_t)__builtin_ctzll(not_digit) / 8;
}

/* Advances `pos` over ASCII digits, up to eight per step; false when there were none. */
static inline MS_ALWAYS_INLINE bool scan_digits(MsSpan text, size_t *pos) {
  const size_t start = *pos;
  size_t i = start;
  while (i + 8 <= text.len) {
    const size_t run = digit_run(ms_load64(text.ptr + i));
    i += run;
    if (run < 8) {
      *pos = i;
      return i > start;
    }
  }
  while (i < text.len && ms_ascii_is_digit(text.ptr[i])) {
    i++;
  }
  *pos = i;
  return i > start;
}

/* Advances `pos` over one JSON number; false when the text there is not one. */
static inline MS_ALWAYS_INLINE bool scan_number(MsSpan text, size_t *pos) {
  if (*pos < text.len && text.ptr[*pos] == '-') {
    (*pos)++;
  }
  if (*pos >= text.len) {
    return false;
  }
  if (text.ptr[*pos] == '0') {
    (*pos)++;
  } else if (!scan_digits(text, pos)) {
    return false;
  }
  if (*pos < text.len && text.ptr[*pos] == '.') {
    (*pos)++;
    if (!scan_digits(text, pos)) {
      return false;
    }
  }
  if (*pos < text.len && (text.ptr[*pos] == 'e' || text.ptr[*pos] == 'E')) {
    (*pos)++;
    if (*pos < text.len && (text.ptr[*pos] == '+' || text.ptr[*pos] == '-')) {
      (*pos)++;
    }
    if (!scan_digits(text, pos)) {
      return false;
    }
  }
  return true;
}

bool json_number_valid(MsSpan text) {
  size_t pos = 0;
  return scan_number(text, &pos) && pos == text.len;
}

/* The value of the four hex digits at text[at..at + 4]. */
static bool hex4(MsSpan text, size_t at, uint32_t *value) {
  size_t end = 0;
  if (!ms_size_add(at, 4, &end) || end > text.len) {
    return false;
  }
  uint32_t result = 0;
  for (size_t i = at; i < end; i++) {
    uint32_t digit = 0;
    if (!ms_hex_digit_value(text.ptr[i], &digit)) {
      return false;
    }
    result = (result << 4) | digit;
  }
  *value = result;
  return true;
}

static bool is_high_surrogate(uint32_t unit) {
  return unit >= 0xD800 && unit <= 0xDBFF;
}
static bool is_low_surrogate(uint32_t unit) {
  return unit >= 0xDC00 && unit <= 0xDFFF;
}

/* Decodes the `\u` escape whose `u` is at pos into one scalar, leaving pos on its last hex digit. A lone
 * surrogate or a high one not followed by a low one is an error. */
static bool decode_unicode(Scanner *scanner, uint32_t *scalar) {
  uint32_t unit = 0;
  if (!hex4(scanner->text, scanner->pos + 1, &unit)) {
    return false;
  }
  scanner->pos += 4;
  if (is_low_surrogate(unit)) {
    return false;
  }
  if (!is_high_surrogate(unit)) {
    *scalar = unit;
    return true;
  }
  uint32_t low = 0;
  const bool escaped = scanner->pos + 2 < scanner->text.len && byte_at(scanner, scanner->pos + 1) == '\\' &&
                       byte_at(scanner, scanner->pos + 2) == 'u';
  if (!hex4(scanner->text, scanner->pos + 3, &low) || !is_low_surrogate(low) || !escaped) {
    return false;
  }
  *scalar = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
  scanner->pos += 6;
  return true;
}

/* The scalar a simple escape letter stands for. */
static bool simple_escape(uint8_t letter, uint8_t *byte) {
  switch (letter) {
  case '"':
  case '\\':
  case '/':
    *byte = letter;
    return true;
  case 'b':
    *byte = '\b';
    return true;
  case 'f':
    *byte = '\f';
    return true;
  case 'n':
    *byte = '\n';
    return true;
  case 'r':
    *byte = '\r';
    return true;
  case 't':
    *byte = '\t';
    return true;
  default:
    return false;
  }
}

static bool scratch_append(Scanner *scanner, size_t from, size_t to) {
  return json_buffer_append(&scanner->scratch, ms_span_of(scanner->text.ptr + from, to - from));
}

/* Decodes one escape sequence whose backslash is at `at` into the scratch buffer; pos ends after it. */
static bool decode_escape(Scanner *scanner, size_t at) {
  scanner->pos = at + 1;
  if (at_end(scanner)) {
    return false;
  }
  const uint8_t letter = byte_at(scanner, scanner->pos);
  uint8_t simple = 0;
  if (simple_escape(letter, &simple)) {
    scanner->pos++;
    return json_buffer_push(&scanner->scratch, simple);
  }
  uint32_t scalar = 0;
  if (letter != 'u' || !decode_unicode(scanner, &scalar)) {
    return false;
  }
  uint8_t encoded[4] = {0};
  const size_t width = ms_utf8_encode(scalar, encoded);
  scanner->pos++;
  return json_buffer_append(&scanner->scratch, ms_span_of(encoded, width));
}

/* The rest of a string whose first escape or control character is at `at`; the decoded text ends in the
 * scratch buffer. A control character is an error, left at the position where the string's last good byte
 * ended. */
static bool read_escaped(Scanner *scanner, size_t start, size_t at) {
  scanner->scratch.bytes.len = 0;
  if (!scratch_append(scanner, start, at)) {
    return false;
  }
  for (;;) {
    const uint8_t c = byte_at(scanner, at);
    if (c == '"') {
      scanner->pos = at + 1;
      return true;
    }
    if (c != '\\' || !decode_escape(scanner, at)) {
      return false;
    }
    at = scanner->pos;
    size_t next = 0;
    if (!find_special(scanner->text, at, &next) || !scratch_append(scanner, at, next)) {
      return false;
    }
    at = next;
  }
}

/* Reads the string that starts at the opening quote at pos. */
static bool read_string(Scanner *scanner, JsonText *out) {
  const size_t start = scanner->pos + 1;
  size_t end = 0;
  if (!find_special(scanner->text, start, &end)) {
    return false;
  }
  if (byte_at(scanner, end) == '"') {
    scanner->pos = end + 1;
    *out = (JsonText){.bytes = ms_span_of(scanner->text.ptr + start, end - start), .source_offset = start};
    return true;
  }
  if (!read_escaped(scanner, start, end)) {
    return false;
  }
  *out = (JsonText){.bytes = ms_span_of(scanner->scratch.bytes.ptr, scanner->scratch.bytes.len),
                    .source_offset = JSON_DECODED};
  return true;
}

/* The key and colon at an object member position. */
static uint8_t member_key(Scanner *scanner) {
  skip_space(scanner);
  JsonText key = {0};
  if (at_end(scanner) || byte_at(scanner, scanner->pos) != '"' || !read_string(scanner, &key)) {
    return MS_STATUS_INVALID_DATA;
  }
  skip_space(scanner);
  if (at_end(scanner) || byte_at(scanner, scanner->pos) != ':') {
    return MS_STATUS_INVALID_DATA;
  }
  scanner->pos++;
  return scanner->ops->key(scanner->sink, key);
}

static bool push_open(Scanner *scanner, uint8_t opener) {
  void *items = scanner->open;
  if (!ms_array_reserve(&items, &scanner->open_capacity, scanner->open_length + 1, 1)) {
    return false;
  }
  scanner->open = items;
  scanner->open[scanner->open_length++] = opener;
  return true;
}

/* What a scalar or empty container the scanner is at turns into: one sink call, or a failed scan. */
static inline MS_ALWAYS_INLINE uint8_t scalar(Scanner *scanner, uint8_t c) {
  JsonText text = {0};
  switch (c) {
  case 'n':
    return literal(scanner, "null") ? scanner->ops->null(scanner->sink) : MS_STATUS_INVALID_DATA;
  case 't':
    return literal(scanner, "true") ? scanner->ops->boolean(scanner->sink, true) : MS_STATUS_INVALID_DATA;
  case 'f':
    return literal(scanner, "false") ? scanner->ops->boolean(scanner->sink, false) : MS_STATUS_INVALID_DATA;
  case '"':
    return read_string(scanner, &text) ? scanner->ops->string(scanner->sink, text) : MS_STATUS_INVALID_DATA;
  default:
    break;
  }
  const size_t start = scanner->pos;
  if (!scan_number(scanner->text, &scanner->pos)) {
    return MS_STATUS_INVALID_DATA;
  }
  text = (JsonText){.bytes = ms_span_of(scanner->text.ptr + start, scanner->pos - start),
                    .source_offset = start};
  return scanner->ops->number(scanner->sink, text);
}

/* Closes the container on top of the stack. */
static uint8_t close_top(Scanner *scanner) {
  const bool is_array = scanner->open[--scanner->open_length] == '[';
  const uint8_t status = scanner->ops->close(scanner->sink, is_array);
  scanner->duplicate = status == MS_STATUS_INVALID_DATA;
  return status;
}

/* The separator after a completed value: closes the containers it ends. JSON_MORE when the next value
 * follows, MS_STATUS_OK when the document is complete. */
static uint8_t after_value(Scanner *scanner) {
  while (scanner->open_length > 0) {
    const uint8_t opener = scanner->open[scanner->open_length - 1];
    skip_space(scanner);
    if (at_end(scanner)) {
      return MS_STATUS_INVALID_DATA;
    }
    const uint8_t separator = byte_at(scanner, scanner->pos++);
    if (separator == (opener == '[' ? ']' : '}')) {
      const uint8_t status = close_top(scanner);
      if (status != MS_STATUS_OK) {
        return status;
      }
      continue;
    }
    if (separator != ',') {
      return MS_STATUS_INVALID_DATA;
    }
    if (opener == '{') {
      const uint8_t status = member_key(scanner);
      if (status != MS_STATUS_OK) {
        return status;
      }
    }
    return JSON_MORE;
  }
  return MS_STATUS_OK;
}

/* Opens the container at pos. JSON_MORE when its first member or element follows, MS_STATUS_OK when it is
 * empty (and so complete). */
static uint8_t open_container(Scanner *scanner, uint8_t opener) {
  if (scanner->open_length + 1 > scanner->limits.max_depth) {
    scanner->limit_hit = true;
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  scanner->pos++;
  skip_space(scanner);
  const bool is_array = opener == '[';
  uint8_t status = scanner->ops->open(scanner->sink, is_array);
  if (status != MS_STATUS_OK) {
    return status;
  }
  if (!at_end(scanner) && byte_at(scanner, scanner->pos) == (is_array ? ']' : '}')) {
    scanner->pos++;
    return scanner->ops->close(scanner->sink, is_array);
  }
  if (!is_array) {
    status = member_key(scanner);
    if (status != MS_STATUS_OK) {
      return status;
    }
  }
  return push_open(scanner, opener) ? JSON_MORE : MS_STATUS_LIMIT_EXCEEDED;
}

/* One value and everything inside it. */
static uint8_t scan_document(Scanner *scanner) {
  for (;;) {
    if (++scanner->count > scanner->limits.max_values) {
      scanner->limit_hit = true;
      return MS_STATUS_LIMIT_EXCEEDED;
    }
    skip_space(scanner);
    if (at_end(scanner)) {
      return MS_STATUS_INVALID_DATA;
    }
    const uint8_t c = byte_at(scanner, scanner->pos);
    uint8_t status = MS_STATUS_INVALID_DATA;
    switch (c) {
    case '[':
    case '{':
      status = open_container(scanner, c);
      if (status == JSON_MORE) {
        continue;
      }
      break;
    case 'n':
    case 't':
    case 'f':
    case '"':
    case '-':
    case '0':
    case '1':
    case '2':
    case '3':
    case '4':
    case '5':
    case '6':
    case '7':
    case '8':
    case '9':
      status = scalar(scanner, c);
      break;
    default:
      break;
    }
    if (status != MS_STATUS_OK) {
      return status;
    }
    status = after_value(scanner);
    if (status != JSON_MORE) {
      return status;
    }
  }
}

/* Whether every `\u` escape of `text` is a scalar value or a surrogate pair. A scan over the whole text that
 * tracks quote parity: a syntax error before such an escape still reports the escape (Go's decoder would
 * replace it). */
static bool unicode_valid(MsSpan text) {
  bool in_string = false;
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t c = text.ptr[i];
    if (c == '"') {
      in_string = !in_string;
    } else if (in_string && c == '\\') {
      if (++i >= text.len) {
        return false;
      }
      if (text.ptr[i] != 'u') {
        continue;
      }
      uint32_t unit = 0;
      if (i + 4 >= text.len || !hex4(text, i + 1, &unit)) {
        return false;
      }
      i += 4;
      uint32_t low = 0;
      if (is_low_surrogate(unit)) {
        return false;
      }
      if (is_high_surrogate(unit)) {
        if (i + 6 >= text.len || text.ptr[i + 1] != '\\' || text.ptr[i + 2] != 'u' ||
            !hex4(text, i + 3, &low) || !is_low_surrogate(low)) {
          return false;
        }
        i += 6;
      }
    }
  }
  return true;
}

uint8_t json_scan(MsSpan text, JsonLimits limits, const JsonSinkOps *ops, void *sink, JsonStop *stop) {
  Scanner scanner = {
      .text = text, .limits = limits, .ops = ops, .sink = sink, .scratch = {.limit = MS_STRING_MAX_LENGTH}};
  uint8_t status = scan_document(&scanner);
  if (status == MS_STATUS_OK) {
    skip_space(&scanner);
    status = scanner.pos == text.len ? MS_STATUS_OK : MS_STATUS_INVALID_DATA;
  }
  json_buffer_free(&scanner.scratch);
  ms_free(scanner.open);
  *stop = (JsonStop){.at = scanner.pos, .duplicate = scanner.duplicate};
  if (status == MS_STATUS_OK) {
    return MS_STATUS_OK;
  }
  /* A bad unicode escape outranks a limit: Go's decoder would replace what that scan rejects. */
  const bool limit = scanner.limit_hit || status == MS_STATUS_LIMIT_EXCEEDED;
  return limit && unicode_valid(text) ? MS_STATUS_LIMIT_EXCEEDED : MS_STATUS_INVALID_DATA;
}

/* ---- the text of a syntax error ---- */

/* The number of scalars in text[0..at) after its last newline, and the number of newlines. */
static void locate(MsSpan text, size_t at, size_t *line, size_t *column) {
  size_t newlines = 0;
  size_t line_start = 0;
  for (size_t i = 0; i < at; i++) {
    if (text.ptr[i] == '\n') {
      newlines++;
      line_start = i + 1;
    }
  }
  *line = newlines + 1;
  *column = ms_utf8_count(text.ptr + line_start, at - line_start) + 1;
}

/* Unicode general category Cc: the C0 and C1 control characters. */
static bool is_control(uint32_t scalar) {
  return scalar < 0x20 || (scalar >= 0x7F && scalar <= 0x9F);
}

void json_explain(MsSpan text, JsonStop stop, MsString *out) {
  size_t at = stop.at < text.len ? stop.at : text.len;
  while (at > 0 && at < text.len && ms_utf8_is_continuation(text.ptr[at])) {
    at--;
  }
  size_t line = 0;
  size_t column = 0;
  locate(text, at, &line, &column);
  char message[128];
  int length = 0;
  if (stop.duplicate) {
    length = snprintf(message, sizeof message, "line %zu, column %zu: duplicate object key", line, column);
  } else if (at == text.len) {
    length = snprintf(message, sizeof message, "line %zu, column %zu: unexpected end of input", line, column);
  } else {
    const MsRune rune = ms_utf8_decode(text.ptr + at, text.len - at);
    if (is_control(rune.rune)) {
      length = snprintf(message, sizeof message, "line %zu, column %zu: unexpected character U+%04X", line,
                        column, (unsigned)rune.rune);
    } else {
      length = snprintf(message, sizeof message, "line %zu, column %zu: unexpected character `%.*s`", line,
                        column, (int)rune.width, (const char *)text.ptr + at);
    }
  }
  *(out) = ms_string_from_span(ms_span_of((const uint8_t *)message, length > 0 ? (size_t)length : 0));
}
