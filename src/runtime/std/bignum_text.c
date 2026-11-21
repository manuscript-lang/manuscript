/* Text of the bignum in any radix 2..36: digit values, parsing and digit generation (bignum.h). */
#include <openssl/bn.h>

#include "base/alloc.h"
#include "runtime/std/bignum_internal.h"

enum { BITS_PER_BYTE = 8 };

uint8_t ms_big_digit_value(uint8_t byte) {
  if (byte >= '0' && byte <= '9') {
    return (uint8_t)(byte - '0');
  }
  if (byte >= 'a' && byte <= 'z') {
    return (uint8_t)(byte - 'a' + 10);
  }
  if (byte >= 'A' && byte <= 'Z') {
    return (uint8_t)(byte - 'A' + 10);
  }
  return 255;
}

/* The digits per BN_ULONG chunk of a radix: the largest k with radix^k in a
 * BN_ULONG, and that power. */
static size_t chunk_of(unsigned radix, uint64_t *power) {
  size_t digits = 0;
  uint64_t p = 1;
  while (p <= (uint64_t)(BN_ULONG)-1 / radix) {
    p *= radix;
    digits++;
  }
  *power = p;
  return digits;
}

/* Digits of a power-of-two radix packed straight into the little-endian bytes
 * of the value. */
static void parse_digits_by_bits(MsBig *out, MsSpan digits, unsigned radix) {
  unsigned bits_per_digit = 1;
  while ((1u << bits_per_digit) < radix) {
    bits_per_digit++;
  }
  const size_t bytes = (digits.len * bits_per_digit + BITS_PER_BYTE - 1) / BITS_PER_BYTE;
  uint8_t *const magnitude = ms_alloc_zeroed(bytes + 1);
  for (size_t i = 0; i < digits.len; i++) {
    const unsigned value = ms_big_digit_value(digits.ptr[digits.len - 1 - i]);
    for (unsigned k = 0; k < bits_per_digit; k++) {
      const size_t bit = i * bits_per_digit + k;
      magnitude[bit / BITS_PER_BYTE] |= (uint8_t)(((value >> k) & 1u) << (bit % BITS_PER_BYTE));
    }
  }
  BIGNUM *const result = ms_big_new_bn();
  ms_big_must(BN_lebin2bn(magnitude, (int)bytes, result) != NULL);
  ms_free(magnitude);
  ms_big_result_end(out, result);
}

void ms_big_parse_digits(MsBig *out, MsSpan digits, unsigned radix) {
  if ((radix & (radix - 1)) == 0) {
    parse_digits_by_bits(out, digits, radix);
    return;
  }
  BIGNUM *const result = ms_big_new_bn();
  uint64_t chunk_power;
  const size_t chunk = chunk_of(radix, &chunk_power);
  size_t at = 0;
  while (at < digits.len) {
    const size_t take = digits.len - at < chunk ? digits.len - at : chunk;
    uint64_t word = 0;
    uint64_t scale = 1;
    for (size_t i = 0; i < take; i++) {
      word = word * radix + ms_big_digit_value(digits.ptr[at + i]);
      scale *= radix;
    }
    ms_big_must(BN_mul_word(result, take == chunk ? chunk_power : scale));
    ms_big_must(BN_add_word(result, word));
    at += take;
  }
  ms_big_result_end(out, result);
}

/* Digits of `radix` of the magnitude, least significant first, by dividing a
 * copy by radix^chunk. */
static uint8_t *digits_by_division(const BIGNUM *a, unsigned radix, size_t *length) {
  uint64_t chunk_power;
  const size_t chunk = chunk_of(radix, &chunk_power);
  BIGNUM *const work = BN_dup(a);
  ms_big_must(work != NULL);
  BN_set_negative(work, 0);
  const size_t capacity = (size_t)BN_num_bits(a) + 1; /* at most one digit per bit */
  uint8_t *const reversed = ms_alloc(capacity + chunk);
  size_t count = 0;
  while (!BN_is_zero(work)) {
    BN_ULONG rest = BN_div_word(work, (BN_ULONG)chunk_power);
    ms_big_must(rest != (BN_ULONG)-1);
    for (size_t i = 0; i < chunk && (rest != 0 || !BN_is_zero(work)); i++) {
      reversed[count++] = (uint8_t)(rest % radix);
      rest /= radix;
    }
  }
  ms_big_release_bn(work);
  if (count == 0) {
    reversed[count++] = 0;
  }
  *length = count;
  return reversed;
}

/* Digits of a power-of-two radix of the magnitude, least significant first,
 * read straight from its bits. */
static uint8_t *digits_by_bits(const BIGNUM *a, unsigned radix, size_t *length) {
  unsigned bits_per_digit = 1; /* radix is at least 2 */
  while ((1u << bits_per_digit) < radix) {
    bits_per_digit++;
  }
  const size_t bits = (size_t)BN_num_bits(a);
  const size_t count = bits == 0 ? 1 : (bits + bits_per_digit - 1) / bits_per_digit;
  const size_t bytes = (count * bits_per_digit) / BITS_PER_BYTE + 1; /* zero padded past the top digit */
  uint8_t *const magnitude = ms_alloc(bytes);
  ms_big_must(BN_bn2lebinpad(a, magnitude, (int)bytes) >= 0);
  uint8_t *const digits = ms_alloc(count);
  for (size_t i = 0; i < count; i++) {
    unsigned digit = 0;
    for (unsigned k = 0; k < bits_per_digit; k++) {
      const size_t bit = i * bits_per_digit + k;
      digit |= (unsigned)((magnitude[bit / BITS_PER_BYTE] >> (bit % BITS_PER_BYTE)) & 1u) << k;
    }
    digits[i] = (uint8_t)digit;
  }
  ms_free(magnitude);
  *length = count;
  return digits;
}

static bool is_power_of_two_radix(unsigned radix) {
  return (radix & (radix - 1)) == 0;
}

uint8_t *ms_big_digits_new(const MsBig *a, unsigned radix, size_t *length) {
  uint8_t *const digits = is_power_of_two_radix(radix)
                              ? digits_by_bits(ms_big_value_of(a), radix, length)
                              : digits_by_division(ms_big_value_of(a), radix, length);
  for (size_t i = 0; i < *length / 2; i++) {
    const uint8_t swap = digits[i];
    digits[i] = digits[*length - 1 - i];
    digits[*length - 1 - i] = swap;
  }
  for (size_t i = 0; i < *length; i++) {
    digits[i] = (uint8_t) "0123456789abcdefghijklmnopqrstuvwxyz"[digits[i]];
  }
  return digits;
}
