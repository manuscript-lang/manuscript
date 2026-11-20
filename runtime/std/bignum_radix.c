/* Radix conversion for the bignum (see bignum.h): text to MsBig and MsBig to text for every radix from 2 to 36.
 * Powers of two read and write bits directly; other radices work a limb-sized chunk of digits at a time, which
 * is quadratic for small values and divide and conquer (on the Karatsuba product) for large ones. */
#include <string.h>

#include "bignum_mag.h"

enum { MS_LIMB_BITS = 64 };

static const char digit_chars[] = "0123456789abcdefghijklmnopqrstuvwxyz";

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

static bool is_power_of_two(unsigned radix) { return (radix & (radix - 1)) == 0; }

/* Bits of one digit of a power-of-two radix; for any radix, floor(log2(radix)). */
static unsigned digit_bits(unsigned radix) { return 31u - (unsigned)__builtin_clz(radix); }

/* The largest k with radix^k below 2^64, and radix^k itself. */
typedef struct MsChunk {
    size_t digits;
    MsLimb base;
} MsChunk;

static MsChunk chunk_of(unsigned radix) {
    MsChunk chunk = {.digits = 0, .base = 1};
    while (chunk.base <= UINT64_MAX / radix) {
        chunk.base *= radix;
        chunk.digits++;
    }
    return chunk;
}

static MsLimb *zeroed_limbs(size_t count) {
    size_t bytes = 0;
    if (!ms_size_mul(count, sizeof(MsLimb), &bytes)) {
        msrt_fault("bignum: value too large", 23);
    }
    MsLimb *const limbs = msrt_alloc(bytes);
    memset(limbs, 0, bytes);
    return limbs;
}

/* ---- parsing ---- */

static size_t parse_power_of_two(MsLimb *limbs, MsBytes digits, unsigned radix) {
    const unsigned bits = digit_bits(radix);
    size_t position = 0;
    for (size_t i = digits.len; i > 0; i--) {
        const MsLimb value = ms_big_digit_value(digits.ptr[i - 1]);
        const size_t index = position / MS_LIMB_BITS;
        const unsigned shift = (unsigned)(position % MS_LIMB_BITS);
        limbs[index] |= value << shift;
        if (shift != 0 && shift + bits > MS_LIMB_BITS) {
            limbs[index + 1] |= value >> (MS_LIMB_BITS - shift);
        }
        position += bits;
    }
    return position / MS_LIMB_BITS + 2;
}

/* limbs = limbs * radix^chunk + value for each run of up to chunk.digits digits, most significant first. */
static size_t parse_chunks(MsLimb *limbs, MsBytes digits, unsigned radix) {
    const MsChunk chunk = chunk_of(radix);
    size_t len = 0;
    size_t at = 0;
    while (at < digits.len) {
        const size_t run = digits.len - at < chunk.digits ? digits.len - at : chunk.digits;
        MsLimb value = 0;
        MsLimb scale = 1;
        for (size_t i = 0; i < run; i++) {
            value = value * radix + ms_big_digit_value(digits.ptr[at + i]);
            scale *= radix;
        }
        const MsLimb carry = ms_mag_mul_add_limb(limbs, len, scale, value);
        if (carry != 0) {
            limbs[len++] = carry;
        }
        at += run;
    }
    return len;
}

void ms_big_parse_digits(MsBig *out, MsBytes digits, unsigned radix) {
    /* Each digit adds at most six bits, so this many limbs always suffice, plus room for the final carry. */
    size_t capacity = 0;
    if (!ms_size_mul(digits.len, 6, &capacity) || !ms_size_add(capacity / MS_LIMB_BITS, 3, &capacity)) {
        msrt_fault("bignum: text too long", 21);
    }
    MsLimb *const limbs = zeroed_limbs(capacity);
    const size_t len = is_power_of_two(radix) ? parse_power_of_two(limbs, digits, radix)
                                              : parse_chunks(limbs, digits, radix);
    const size_t used = ms_mag_normal_length(limbs, len);
    ms_big_free(out);
    if (used == 0) {
        msrt_free(limbs);
        return;
    }
    *out = (MsBig){.limbs = limbs, .len = used, .negative = false};
}

/* ---- formatting ---- */

/* Fills `text` from its end with the digits of a power-of-two radix; returns how many digits it wrote. */
static size_t format_power_of_two(uint8_t *text, size_t capacity, const MsBig *a, unsigned radix) {
    const unsigned bits = digit_bits(radix);
    const size_t total_bits = ms_big_bit_length(a);
    size_t count = 0;
    for (size_t position = 0; position < total_bits || count == 0; position += bits) {
        unsigned value = 0;
        for (unsigned bit = 0; bit < bits; bit++) {
            value |= (unsigned)ms_big_magnitude_bit(a, position + bit) << bit;
        }
        text[capacity - ++count] = (uint8_t)digit_chars[value];
    }
    return count;
}

/* Writes the digits of `rest` (a chunk below radix^chunk.digits) at the end of `text`, `chunk.digits` of them when
 * more chunks follow and only the significant ones for the last. */
static size_t write_chunk(uint8_t *text, size_t capacity, size_t count, MsLimb rest, unsigned radix, bool last) {
    for (size_t i = 0; i < chunk_of(radix).digits && (!last || rest != 0); i++) {
        text[capacity - ++count] = (uint8_t)digit_chars[rest % radix];
        rest /= radix;
    }
    return count;
}

/* Writes exactly `chunks` chunks of digits, zero padded, ending at text[end], for a value below
 * chunk.base^chunks that is small enough to take one limb division per chunk. Consumes `work`. */
static void fill_chunks(uint8_t *text, size_t end, MsLimb *work, size_t work_len, size_t chunks, unsigned radix) {
    const MsChunk chunk = chunk_of(radix);
    const MsLimbDivisor divisor = ms_mag_limb_divisor(chunk.base);
    for (size_t i = 0; i < chunks; i++) {
        const MsLimb rest = ms_mag_divmod_limb(work, work_len, divisor);
        work_len = ms_mag_normal_length(work, work_len);
        (void)write_chunk(text, end, i * chunk.digits, rest, radix, false);
    }
}

/* Below this many limbs a value is split by single-limb divisions; above it by halves. */
enum { MS_RADIX_SPLIT_LIMBS = 24 };

/* The powers chunk.base^(2^k) that halves of a value are split by; powers[k] is valid for k < count. */
typedef struct MsPowers {
    MsBig *items;
    size_t count;
} MsPowers;

/* Writes `chunks` (a power of two) chunks of digits of `value` < chunk.base^chunks, zero padded, ending at
 * text[end]. `level` is log2(chunks); powers[level - 1] splits the value into a high and a low half. */
static void fill_split(uint8_t *text, size_t end, const MsBig *value, size_t level, const MsPowers *powers,
                       unsigned radix) {
    const MsChunk chunk = chunk_of(radix);
    const size_t chunks = (size_t)1 << level;
    if (level == 0 || value->len <= MS_RADIX_SPLIT_LIMBS) {
        MsLimb *const work = zeroed_limbs(value->len == 0 ? 1 : value->len);
        if (value->len != 0) {
            memcpy(work, value->limbs, value->len * sizeof(MsLimb));
        }
        fill_chunks(text, end, work, value->len, chunks, radix);
        msrt_free(work);
        return;
    }
    MsBig high = MS_BIG_ZERO;
    MsBig low = MS_BIG_ZERO;
    ms_big_divmod(&high, &low, value, &powers->items[level - 1]);
    fill_split(text, end, &low, level - 1, powers, radix);
    fill_split(text, end - (chunks / 2) * chunk.digits, &high, level - 1, powers, radix);
    ms_big_free(&high);
    ms_big_free(&low);
}

/* Builds chunk.base^(2^k) while it stays at most `value`; the smallest level whose power exceeds it is the
 * count. */
static size_t build_powers(MsPowers *powers, const MsBig *value, MsLimb base) {
    size_t capacity = 2;
    while (capacity < 2 * value->len + 2 && capacity < 64) { /* 2^64 chunks exceeds any memory */
        capacity *= 2;
    }
    powers->items = msrt_alloc(capacity * sizeof(MsBig));
    powers->count = 1;
    powers->items[0] = MS_BIG_ZERO;
    ms_big_set_u64(&powers->items[0], base);
    while (ms_big_cmp(&powers->items[powers->count - 1], value) <= 0) {
        MsBig *const next = &powers->items[powers->count];
        *next = MS_BIG_ZERO;
        ms_big_mul(next, &powers->items[powers->count - 1], &powers->items[powers->count - 1]);
        powers->count++;
    }
    return powers->count - 1; /* value < base^(2^level) */
}

/* Fills `text` from its end with the digits of a value that needs a divide and conquer split; returns how many
 * digits it wrote (leading zeros trimmed). */
static size_t format_split(uint8_t *text, size_t capacity, const MsBig *signed_value, unsigned radix) {
    const MsChunk chunk = chunk_of(radix);
    MsBig magnitude = MS_BIG_ZERO; /* the sign is not written, and division must see a positive value */
    ms_big_abs(&magnitude, signed_value);
    const MsBig *const a = &magnitude;
    MsPowers powers;
    const size_t level = build_powers(&powers, a, chunk.base);
    const size_t padded = ((size_t)1 << level) * chunk.digits;
    uint8_t *const scratch = msrt_alloc(padded);
    fill_split(scratch, padded, a, level, &powers, radix);
    size_t skip = 0;
    while (skip + 1 < padded && scratch[skip] == '0') {
        skip++;
    }
    const size_t count = padded - skip;
    memcpy(text + capacity - count, scratch + skip, count);
    msrt_free(scratch);
    for (size_t i = 0; i < powers.count; i++) {
        ms_big_free(&powers.items[i]);
    }
    msrt_free(powers.items);
    ms_big_free(&magnitude);
    return count;
}

static size_t format_chunks(uint8_t *text, size_t capacity, const MsBig *a, unsigned radix) {
    if (a->len > MS_RADIX_SPLIT_LIMBS) {
        return format_split(text, capacity, a, radix);
    }
    const MsChunk chunk = chunk_of(radix);
    const MsLimbDivisor divisor = ms_mag_limb_divisor(chunk.base);
    MsLimb *const work = zeroed_limbs(a->len);
    if (a->len > 0) {
        memcpy(work, a->limbs, a->len * sizeof(MsLimb));
    }
    size_t work_len = a->len;
    size_t count = 0;
    while (work_len > 0) {
        const MsLimb rest = ms_mag_divmod_limb(work, work_len, divisor);
        work_len = ms_mag_normal_length(work, work_len);
        count = write_chunk(text, capacity, count, rest, radix, work_len == 0);
    }
    msrt_free(work);
    if (count == 0) {
        text[capacity - ++count] = '0';
    }
    return count;
}

uint8_t *ms_big_digits_new(const MsBig *a, unsigned radix, size_t *length) {
    /* A value below 2^bits has at most bits / floor(log2 radix) + 1 digits; a chunk may write a few extra zeros. */
    size_t capacity = ms_big_bit_length(a) / digit_bits(radix) + chunk_of(radix).digits + 2;
    uint8_t *const text = msrt_alloc(capacity);
    const size_t count = is_power_of_two(radix) ? format_power_of_two(text, capacity, a, radix)
                                                : format_chunks(text, capacity, a, radix);
    uint8_t *const result = msrt_alloc(count);
    memcpy(result, text + capacity - count, count);
    msrt_free(text);
    *length = count;
    return result;
}
