/* The number natives that fault, format text or build strings: UInt64 division, error messages and the precision
 * forms of Float. Ported from crates/ms-rt/src/num.rs. Apart from num.c, which has no runtime dependencies. */
#include "ms_rt/fmt.h"
#include "ms_rt/num.h"
#include "ms_rt/strbuild.h"
#include "rt_calls.h"
#include "text.h"

/* ---- Faulting division, error messages and precision text ---- */

/* UInt64./: the operands are bit patterns. */
int64_t msrt_uint_div(int64_t a, int64_t b) {
    if (b == 0) {
        msrt_fault_div_zero();
    }
    return (int64_t)((uint64_t)a / (uint64_t)b);
}

/* UInt64.%: the operands are bit patterns. */
int64_t msrt_uint_rem(int64_t a, int64_t b) {
    if (b == 0) {
        msrt_fault_rem_zero();
    }
    return (int64_t)((uint64_t)a % (uint64_t)b);
}

/* The error message for a number status code. */
void msrt_numbers_error_message(uint8_t status, MsStr *out) {
    const char *message = "number: operation failed";
    switch (status) {
    case MS_STATUS_INVALID_INPUT: message = "number: invalid input"; break;
    case MS_STATUS_INVALID_DATA: message = "number: invalid data"; break;
    case MS_STATUS_OUT_OF_RANGE: message = "number: value out of range"; break;
    default: break;
    }
    ms_str_write(ms_str_from_bytes((const uint8_t *)message, __builtin_strlen(message)), out);
}

/* Formats `v` as `format` ('g', 'e' or 'f') with `digits` in `minimum..=100`, otherwise a fault naming `name`. */
static void precision_out(double v, uint8_t format, int64_t digits, int64_t minimum, const char *name, MsStr *out) {
    if (digits < minimum || digits > 100) {
        MsText text = {0};
        ms_text_add(&text, name);
        ms_text_add(&text, ": digits must be at least ");
        ms_text_add_i64(&text, minimum);
        ms_text_add(&text, " and at most 100, found ");
        ms_text_add_i64(&text, digits);
        ms_text_fault(&text, MS_FAULT_GENERIC);
    }
    uint8_t buffer[MS_FMT_PRECISION_CAPACITY];
    size_t length = 0;
    if (!msrt_fmt_float_precision(v, format, digits, buffer, sizeof buffer, &length)) {
        MsText text = {0};
        ms_text_add(&text, name);
        ms_text_add(&text, ": formatting buffer too small");
        ms_text_fault(&text, MS_FAULT_GENERIC);
    }
    ms_str_write(ms_str_from_bytes(buffer, length), out);
}

/* Float.to_precision(digits): digits in 1..=100, otherwise a fault. */
void msrt_float_to_precision(double v, int64_t digits, MsStr *out) { precision_out(v, 'g', digits, 1, "to_precision", out); }

/* Float.to_exponential(digits): digits in 0..=100, otherwise a fault. */
void msrt_float_to_exponential(double v, int64_t digits, MsStr *out) { precision_out(v, 'e', digits, 0, "to_exponential", out); }

/* Float.to_fixed(digits): digits in 0..=100, otherwise a fault. */
void msrt_float_to_fixed(double v, int64_t digits, MsStr *out) { precision_out(v, 'f', digits, 0, "to_fixed", out); }
