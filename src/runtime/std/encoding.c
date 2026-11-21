/* @std/data/encoding natives: RFC 4648 Base64 and Base32 (padded or not, both alphabets), hexadecimal and
 * ASCII85. Every decoder is strict: no whitespace, canonical length, zero trailing bits, padding only at the
 * end. An optional byte budget `has_max`/`max` is checked in this order: a negative one is InvalidInput, then
 * the text's shape (InvalidData), then the decoded size against the budget (LimitExceeded), then the symbols.
 * Results are written through `out`: empty unless the call succeeds. */
#include <string.h>

#include "abi/status.h"
#include "base/alloc.h"
#include "base/bytes.h"
#include "base/chars.h"
#include "runtime/std/encoding.h"
#include "base/strbuild.h"

static const char base64_symbols[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static const char base64_url_symbols[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
static const char base32_symbols[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
static const char base32_hex_symbols[] = "0123456789ABCDEFGHIJKLMNOPQRSTUV";
static const char hex_digits[] = "0123456789abcdef";

/* The shape of a Base-2^bits alphabet: `bits` per symbol, `group` symbols per padded block. */
typedef struct Alphabet {
  const char *symbols;
  unsigned bits;
  unsigned group;
} Alphabet;

static Alphabet base64_alphabet(bool url_safe) {
  return (Alphabet){url_safe ? base64_url_symbols : base64_symbols, 6, 4};
}
static Alphabet base32_alphabet(bool hex) {
  return (Alphabet){hex ? base32_hex_symbols : base32_symbols, 5, 8};
}

enum { NOT_A_SYMBOL = 0xFF };

/* ---- results
 * ----------------------------------------------------------------------------------------------------- */

/* A text built in place: short ones in `small`, which becomes an inline string, longer ones in the string's
 * allocation. */
typedef struct Text {
  uint8_t small[MS_STRING_INLINE_MAX + 1];
  uint8_t *heap; /* owned when the text does not fit `small` */
  uint8_t *bytes;
  size_t length;
} Text;

/* Room for `length` bytes of ASCII text, returned for the caller to fill. */
static uint8_t *text_begin(Text *text, size_t length) {
  text->length = length;
  text->heap = NULL;
  text->bytes = text->small;
  if (length > MS_STRING_INLINE_MAX) {
    text->heap = ms_alloc(length);
    text->bytes = text->heap;
  }
  return text->bytes;
}

static MsString text_finish(const Text *text) {
  const MsString result = ms_string_from_span(ms_span_of(text->bytes, text->length));
  ms_free(text->heap);
  return result;
}

/* Bytes of exactly `length` bytes to fill (an empty value for none). */
static uint8_t *bytes_begin(MsBytes *out, size_t length) {
  *(out) = (MsBytes){0};
  if (length == 0) {
    return NULL;
  }
  out->ptr = ms_alloc(length);
  out->len = out->cap = length;
  return out->ptr;
}

static void bytes_discard(MsBytes *out) {
  ms_free(out->ptr);
  *(out) = (MsBytes){0};
}

/* The byte budget; false for a negative one. */
static bool budget_of(uint8_t has_max, int64_t max, size_t *budget) {
  if (!has_max) {
    *budget = SIZE_MAX;
    return true;
  }
  *budget = max < 0 ? 0 : (size_t)max;
  return max >= 0;
}

static MsSpan text_in(const MsString *text) {
  return ms_string_span(text);
}

/* ---- Base64 and Base32: groups of symbols
 * ------------------------------------------------------------------------ */

/* The encoded length of `bytes` bytes: whole symbols, then padding up to a block when `padded`. */
static size_t encoded_length(size_t bytes, Alphabet alphabet, bool padded) {
  const size_t symbols =
      (bytes / alphabet.bits) * 8 + ((bytes % alphabet.bits) * 8 + alphabet.bits - 1) / alphabet.bits;
  return padded ? (symbols + alphabet.group - 1) / alphabet.group * alphabet.group : symbols;
}

static MsString encode_symbols(const MsBytes *data, Alphabet alphabet, bool padded) {
  Text text;
  const size_t length = encoded_length(data->len, alphabet, padded);
  uint8_t *out = text_begin(&text, length);
  const uint8_t *in = data->ptr;
  const unsigned mask = (1u << alphabet.bits) - 1;
  uint32_t accumulator = 0;
  unsigned held = 0;
  size_t written = 0;
  for (size_t i = 0; i < data->len; i++) {
    accumulator = (accumulator << 8) | in[i];
    held += 8;
    while (held >= alphabet.bits) {
      held -= alphabet.bits;
      out[written++] = (uint8_t)alphabet.symbols[(accumulator >> held) & mask];
    }
    accumulator &= (1u << held) - 1;
  }
  if (held > 0) {
    out[written++] = (uint8_t)alphabet.symbols[(accumulator << (alphabet.bits - held)) & mask];
  }
  memset(out + written, '=', length - written);
  return text_finish(&text);
}

/* Maps each symbol byte to its value; every other byte to NOT_A_SYMBOL. */
static void reverse_table(Alphabet alphabet, uint8_t table[256]) {
  memset(table, NOT_A_SYMBOL, 256);
  for (size_t i = 0; i < ((size_t)1 << alphabet.bits); i++) {
    table[(uint8_t)alphabet.symbols[i]] = (uint8_t)i;
  }
}

/* Decodes the `count` symbols at `symbols` into `out`, which holds exactly their whole bytes. False for a
 * byte outside the alphabet or for leftover bits that are not zero. */
static bool decode_symbols(const uint8_t *symbols, size_t count, Alphabet alphabet, uint8_t *out) {
  uint8_t table[256];
  reverse_table(alphabet, table);
  uint32_t accumulator = 0;
  unsigned held = 0;
  size_t written = 0;
  for (size_t i = 0; i < count; i++) {
    const uint8_t digit = table[symbols[i]];
    if (digit == NOT_A_SYMBOL) {
      return false;
    }
    accumulator = (accumulator << alphabet.bits) | digit;
    held += alphabet.bits;
    if (held >= 8) {
      held -= 8;
      out[written++] = (uint8_t)(accumulator >> held);
      accumulator &= (1u << held) - 1;
    }
  }
  return accumulator == 0;
}

static size_t trailing_padding(MsSpan text) {
  size_t padding = 0;
  while (padding < text.len && text.ptr[text.len - 1 - padding] == '=') {
    padding++;
  }
  return padding;
}

static bool has_whitespace(MsSpan text) {
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '\r' || text.ptr[i] == '\n' || text.ptr[i] == '\t' || text.ptr[i] == ' ') {
      return true;
    }
  }
  return false;
}

/* The whole bytes `symbols` symbols hold. */
static size_t decoded_length(size_t symbols, Alphabet alphabet) {
  return symbols / 8 * alphabet.bits + symbols % 8 * alphabet.bits / 8;
}

/* Decodes `count` symbols of `text` once their count and the budget are settled. */
static uint8_t decode_into(MsSpan text, size_t count, Alphabet alphabet, MsBytes *out) {
  uint8_t *bytes = bytes_begin(out, decoded_length(count, alphabet));
  if (decode_symbols(text.ptr, count, alphabet, bytes)) {
    return MS_STATUS_OK;
  }
  bytes_discard(out);
  return MS_STATUS_INVALID_DATA;
}

uint8_t msstd_encoding_base64_decode(const MsString *text, uint8_t url_safe, uint8_t has_max, int64_t max,
                                     MsBytes *out) {
  *(out) = (MsBytes){0};
  size_t budget = 0;
  if (!budget_of(has_max, max, &budget)) {
    return MS_STATUS_INVALID_INPUT;
  }
  const MsSpan in = text_in(text);
  const size_t padding = trailing_padding(in);
  if (has_whitespace(in) || padding > 2 || in.len % 4 != 0) {
    return MS_STATUS_INVALID_DATA;
  }
  if (in.len / 4 * 3 - padding > budget) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  return decode_into(in, in.len - padding, base64_alphabet(url_safe), out);
}

uint8_t msstd_encoding_base64_decode_unpadded(const MsString *text, uint8_t url_safe, uint8_t has_max,
                                              int64_t max, MsBytes *out) {
  *(out) = (MsBytes){0};
  size_t budget = 0;
  if (!budget_of(has_max, max, &budget)) {
    return MS_STATUS_INVALID_INPUT;
  }
  const MsSpan in = text_in(text);
  const Alphabet alphabet = base64_alphabet(url_safe);
  if (in.len % 4 == 1) {
    return MS_STATUS_INVALID_DATA;
  }
  if (decoded_length(in.len, alphabet) > budget) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  return decode_into(in, in.len, alphabet, out);
}

uint8_t msstd_encoding_base32_decode(const MsString *text, uint8_t hex_alphabet, uint8_t padded,
                                     uint8_t has_max, int64_t max, MsBytes *out) {
  *(out) = (MsBytes){0};
  size_t budget = 0;
  if (!budget_of(has_max, max, &budget)) {
    return MS_STATUS_INVALID_INPUT;
  }
  const MsSpan in = text_in(text);
  const Alphabet alphabet = base32_alphabet(hex_alphabet);
  const size_t padding = trailing_padding(in);
  const size_t count = in.len - padding;
  // Padding belongs only to padded text and completes its last block; a last block of 1, 3 or 6 symbols holds
  // no bytes.
  const size_t tail = count % alphabet.group;
  const bool tail_ok = tail == 0 || tail == 2 || tail == 4 || tail == 5 || tail == 7;
  if ((padding > 0 && !padded) || (padded && in.len % alphabet.group != 0) || !tail_ok ||
      (padded && padding != (alphabet.group - tail) % alphabet.group)) {
    return MS_STATUS_INVALID_DATA;
  }
  if (decoded_length(count, alphabet) > budget) {
    // An `=` before the padding is bad data whatever the budget.
    return memchr(in.ptr, '=', count) != NULL ? MS_STATUS_INVALID_DATA : MS_STATUS_LIMIT_EXCEEDED;
  }
  return decode_into(in, count, alphabet, out);
}

void msstd_encoding_base64_encode(const MsBytes *data, uint8_t url_safe, MsString *out) {
  *out = encode_symbols(data, base64_alphabet(url_safe), true);
}

void msstd_encoding_base64_encode_unpadded(const MsBytes *data, uint8_t url_safe, MsString *out) {
  *out = encode_symbols(data, base64_alphabet(url_safe), false);
}

void msstd_encoding_base32_encode(const MsBytes *data, uint8_t hex_alphabet, uint8_t padded, MsString *out) {
  *out = encode_symbols(data, base32_alphabet(hex_alphabet), padded);
}

/* ---- hexadecimal
 * ------------------------------------------------------------------------------------------------- */

void msstd_encoding_hex_encode(const MsBytes *data, MsString *out) {
  Text text;
  uint8_t *digits = text_begin(&text, data->len * 2);
  const uint8_t *in = data->ptr;
  for (size_t i = 0; i < data->len; i++) {
    digits[2 * i] = (uint8_t)hex_digits[in[i] >> 4];
    digits[2 * i + 1] = (uint8_t)hex_digits[in[i] & 15];
  }
  *out = text_finish(&text);
}

static int hex_value(uint8_t digit) {
  if (ms_ascii_is_digit(digit)) {
    return digit - '0';
  }
  const uint8_t lower = ms_ascii_to_lower(digit);
  return lower >= 'a' && lower <= 'f' ? lower - 'a' + 10 : -1;
}

/* The budget is checked before the length's parity and the digits. */
uint8_t msstd_encoding_hex_decode(const MsString *text, uint8_t has_max, int64_t max, MsBytes *out) {
  *(out) = (MsBytes){0};
  size_t budget = 0;
  if (!budget_of(has_max, max, &budget)) {
    return MS_STATUS_INVALID_INPUT;
  }
  const MsSpan in = text_in(text);
  if (in.len / 2 > budget) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  if (in.len % 2 != 0) {
    return MS_STATUS_INVALID_DATA;
  }
  uint8_t *bytes = bytes_begin(out, in.len / 2);
  for (size_t i = 0; i < in.len / 2; i++) {
    const int high = hex_value(in.ptr[2 * i]);
    const int low = hex_value(in.ptr[2 * i + 1]);
    if (high < 0 || low < 0) {
      bytes_discard(out);
      return MS_STATUS_INVALID_DATA;
    }
    bytes[i] = (uint8_t)(high << 4 | low);
  }
  return MS_STATUS_OK;
}

/* ---- ASCII85
 * ----------------------------------------------------------------------------------------------------- */

/* Unframed, Go's alphabet: `z` stands for a zero group and a partial final group of n bytes keeps n + 1
 * digits. */
enum { ASCII85_BASE = 85, ASCII85_FIRST = '!', ASCII85_LAST = 'u', ASCII85_GROUP = 5 };

void msstd_encoding_ascii85_encode(const MsBytes *data, MsString *out) {
  // The widest result: five digits per four bytes, rounded up.
  const size_t widest = (data->len + 3) / 4 * ASCII85_GROUP;
  uint8_t *digits = ms_alloc(widest + 1);
  size_t written = 0;
  for (size_t at = 0; at < data->len; at += 4) {
    const size_t count = data->len - at < 4 ? data->len - at : 4;
    uint8_t word[4] = {0};
    memcpy(word, (const uint8_t *)data->ptr + at, count);
    uint32_t value = (uint32_t)word[0] << 24 | (uint32_t)word[1] << 16 | (uint32_t)word[2] << 8 | word[3];
    if (count == 4 && value == 0) {
      digits[written++] = 'z';
      continue;
    }
    uint8_t group[ASCII85_GROUP];
    for (size_t i = ASCII85_GROUP; i-- > 0;) {
      group[i] = (uint8_t)(ASCII85_FIRST + value % ASCII85_BASE);
      value /= ASCII85_BASE;
    }
    memcpy(digits + written, group, count + 1);
    written += count + 1;
  }
  *out = ms_string_from_span(ms_span_of(digits, written));
  ms_free(digits);
}

/* The decoded bytes so far, growing as groups complete. */
typedef struct Collected {
  uint8_t *bytes;
  size_t length, capacity;
} Collected;

/* Appends `count` bytes of `value` (most significant first); false when the total would pass `budget`. */
static bool collect(Collected *collected, uint32_t value, size_t count, size_t budget) {
  if (count > budget - collected->length) {
    return false;
  }
  if (collected->capacity - collected->length < count) {
    collected->capacity = collected->capacity == 0 ? 64 : collected->capacity * 2;
    collected->bytes = ms_realloc(collected->bytes, collected->capacity);
  }
  for (size_t i = 0; i < count; i++) {
    collected->bytes[collected->length++] = (uint8_t)(value >> (24 - 8 * i));
  }
  return true;
}

static uint8_t collect_status(Collected *collected, uint32_t value, size_t count, size_t budget) {
  return collect(collected, value, count, budget) ? MS_STATUS_OK : MS_STATUS_LIMIT_EXCEEDED;
}

/* The status of appending the first `count` bytes of a group worth `word`: a group past 2^32 - 1 is bad data.
 */
static uint8_t group_status(Collected *collected, uint64_t word, size_t count, size_t budget) {
  if (word > UINT32_MAX) {
    return MS_STATUS_INVALID_DATA;
  }
  return collect_status(collected, (uint32_t)word, count, budget);
}

/* ASCII controls and space between digits are ignored. */
uint8_t msstd_encoding_ascii85_decode(const MsString *text, uint8_t has_max, int64_t max, MsBytes *out) {
  *(out) = (MsBytes){0};
  size_t budget = 0;
  if (!budget_of(has_max, max, &budget)) {
    return MS_STATUS_INVALID_INPUT;
  }
  const MsSpan in = text_in(text);
  Collected collected = {0};
  uint64_t word = 0;
  size_t digits = 0;
  uint8_t status = MS_STATUS_OK;
  for (size_t i = 0; i < in.len && status == MS_STATUS_OK; i++) {
    const uint8_t byte = in.ptr[i];
    if (byte <= ' ') {
      continue;
    }
    if (byte == 'z') {
      status = digits != 0 ? MS_STATUS_INVALID_DATA : collect_status(&collected, 0, 4, budget);
    } else if (byte < ASCII85_FIRST || byte > ASCII85_LAST) {
      status = MS_STATUS_INVALID_DATA;
    } else {
      word = word * ASCII85_BASE + (uint64_t)(byte - ASCII85_FIRST);
      digits++;
    }
    if (digits == ASCII85_GROUP && status == MS_STATUS_OK) {
      status = group_status(&collected, word, 4, budget);
      word = 0;
      digits = 0;
    }
  }
  if (status == MS_STATUS_OK && digits == 1) {
    status = MS_STATUS_INVALID_DATA;
  }
  if (status == MS_STATUS_OK && digits > 1) {
    // Pad the partial group with the highest digit; the bytes kept are its first digits - 1.
    for (size_t i = digits; i < ASCII85_GROUP; i++) {
      word = word * ASCII85_BASE + (ASCII85_BASE - 1);
    }
    status = group_status(&collected, word, digits - 1, budget);
  }
  if (status != MS_STATUS_OK || collected.length == 0) {
    ms_free(collected.bytes);
    return status;
  }
  out->ptr = ms_realloc(collected.bytes, collected.length);
  out->len = out->cap = collected.length;
  return MS_STATUS_OK;
}
