/* RFC 4648 Base64 (padded or not, both alphabets): the natives behind @std/data/encoding, and the Base64 the
 * runtime itself uses (the WebSocket handshake, JSON bytes, PEM). Hexadecimal, Base32 and ASCII85 are
 * Manuscript (src/stdlib/data/encoding.ms). The decoder is strict: no whitespace, canonical length, zero
 * trailing bits, padding only at the end. An optional byte budget `has_max`/`max` is checked in this order: a
 * negative one is InvalidInput, then the text's shape (InvalidData), then the decoded size against the budget
 * (LimitExceeded), then the symbols. Results are written through `out`: empty unless the call succeeds. */
#include <string.h>

#include "abi/status.h"
#include "base/alloc.h"
#include "base/bytes.h"
#include "base/chars.h"
#include "runtime/std/encoding.h"
#include "base/strbuild.h"

static const char base64_symbols[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static const char base64_url_symbols[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/* The shape of a Base-2^bits alphabet: `bits` per symbol, `group` symbols per padded block. */
typedef struct Alphabet {
  const char *symbols;
  unsigned bits;
  unsigned group;
} Alphabet;

static Alphabet base64_alphabet(bool url_safe) {
  return (Alphabet){url_safe ? base64_url_symbols : base64_symbols, 6, 4};
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

void msstd_encoding_base64_encode(const MsBytes *data, uint8_t url_safe, MsString *out) {
  *out = encode_symbols(data, base64_alphabet(url_safe), true);
}

void msstd_encoding_base64_encode_unpadded(const MsBytes *data, uint8_t url_safe, MsString *out) {
  *out = encode_symbols(data, base64_alphabet(url_safe), false);
}
