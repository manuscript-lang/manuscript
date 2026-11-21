/* The natives that turn one Int, UInt64, Float, Float32 or Bool into a string (`to_string`,
 * `to_string_radix`). The digits come from fmt.c into a stack buffer sized for the longest text; the
 * string constructor builds the value, which is inline when it fits. */
#include "fmt_fixed.h"
#include "ms_rt/string.h"
#include "text.h"

/* Writes `text` as a string value to `out`. */
MS_NONNULL static void put_text(MsBytes text, MsStr *out) { msrt_string_from_bytes(text.ptr, text.len, out); }

/* The capacities of fmt.h hold every valid argument, so a refusal is a bug in this runtime. */
MS_NONNULL MS_NORETURN static void fault_capacity(void) {
    static const char message[] = "to_string: the text does not fit its buffer";
    msrt_fault((const uint8_t *)message, sizeof message - 1);
}

/* Writes the `length` bytes of `buffer` to `out`, or faults when `fitted` is false. */
MS_NONNULL static void put_formatted(bool fitted, const uint8_t *buffer, size_t length, MsStr *out) {
    if (!fitted) {
        fault_capacity();
    }
    put_text((MsBytes){buffer, length}, out);
}

MS_NONNULL MS_NORETURN static void fault_radix(int64_t radix) {
    MsText text = {.len = 0};
    ms_text_add(&text, "to_string_radix: radix must be between 2 and 36, found ");
    ms_text_add_i64(&text, radix);
    ms_text_fault(&text, MS_FAULT_GENERIC);
}

/* The radix of `to_string_radix`, which faults outside 2..=36. */
static uint32_t checked_radix(int64_t radix) {
    if (radix < 2 || radix > 36) {
        fault_radix(radix);
    }
    return (uint32_t)radix;
}

void msrt_int_to_string(int64_t v, MsStr *out) {
    uint8_t buffer[MS_FMT_INTEGER_CAPACITY];
    size_t length = ms_fmt_i64_fixed(v, buffer);
    put_text((MsBytes){buffer, length}, out);
}

void msrt_uint_to_string(int64_t v, MsStr *out) {
    uint8_t buffer[MS_FMT_INTEGER_CAPACITY];
    size_t length = 0;
    bool fitted = msrt_fmt_u64((uint64_t)v, buffer, sizeof buffer, &length);
    put_formatted(fitted, buffer, length, out);
}

void msrt_int_to_string_radix(int64_t v, int64_t radix, MsStr *out) {
    uint32_t base = checked_radix(radix);
    uint8_t buffer[MS_FMT_RADIX_CAPACITY];
    size_t length = 0;
    /* The magnitude of INT64_MIN needs the unsigned negation. */
    uint64_t magnitude = v < 0 ? (uint64_t)0 - (uint64_t)v : (uint64_t)v;
    bool fitted = msrt_fmt_radix(magnitude, base, v < 0, buffer, sizeof buffer, &length);
    put_formatted(fitted, buffer, length, out);
}

void msrt_uint_to_string_radix(int64_t v, int64_t radix, MsStr *out) {
    uint32_t base = checked_radix(radix);
    uint8_t buffer[MS_FMT_RADIX_CAPACITY];
    size_t length = 0;
    bool fitted = msrt_fmt_radix((uint64_t)v, base, false, buffer, sizeof buffer, &length);
    put_formatted(fitted, buffer, length, out);
}

void msrt_float_to_string(double v, MsStr *out) {
    uint8_t buffer[MS_FMT_FLOAT_CAPACITY];
    size_t length = 0;
    bool fitted = msrt_fmt_float(v, buffer, sizeof buffer, &length);
    put_formatted(fitted, buffer, length, out);
}

void msrt_float32_to_string(double v, MsStr *out) {
    uint8_t buffer[MS_FMT_FLOAT_CAPACITY];
    size_t length = 0;
    bool fitted = msrt_fmt_float32(v, buffer, sizeof buffer, &length);
    put_formatted(fitted, buffer, length, out);
}

void msrt_bool_to_string(uint8_t v, MsStr *out) {
    static const uint8_t yes[] = "true";
    static const uint8_t no[] = "false";
    put_text(v != 0 ? (MsBytes){yes, sizeof yes - 1} : (MsBytes){no, sizeof no - 1}, out);
}
