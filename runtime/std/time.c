/* The @std/time natives for durations, instants, clocks and error messages (ms_rt/time.h). A Duration is signed
 * nanoseconds; arithmetic that leaves the int64_t range faults with a message naming the operands. */
#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "time_internal.h"

enum {
    MS_FAULT_MESSAGE_MAX = 384,
    NANOS_PER_MICROSECOND = 1000,
    NANOS_PER_MILLISECOND = 1000000,
    MONOTONIC_DOMAIN = 1, /* time.clock() */
};
#define NANOS_PER_MINUTE (INT64_C(60) * MS_NANOS_PER_SECOND)

MS_NORETURN static void fault_with(const char *format, ...) MS_PRINTF(1, 2);

MS_NORETURN static void fault_with(const char *format, ...) {
    char message[MS_FAULT_MESSAGE_MAX];
    va_list arguments;
    va_start(arguments, format);
    const int length = vsnprintf(message, sizeof message, format, arguments);
    va_end(arguments);
    size_t used = length < 0 ? 0 : (size_t)length;
    if (used >= sizeof message) {
        used = sizeof message - 1; /* truncated by vsnprintf */
    }
    ms_fault_text(message, used);
}

/* The operands of a binary operation, as the overflow message names them. */
typedef struct Operation {
    const char *name;
    const char *left_label;
    const char *right_label;
} Operation;

MS_NORETURN static void overflow(Operation op, int64_t left, int64_t right) {
    const bool scale = strcmp(op.right_label, "factor") == 0 || strcmp(op.right_label, "divisor") == 0;
    fault_with("%s: overflow; found %s (nanoseconds) %" PRId64 " and %s%s %" PRId64
               "; result nanoseconds must be between %" PRId64 " and %" PRId64,
               op.name, op.left_label, left, op.right_label, scale ? "" : " (nanoseconds)", right, INT64_MIN,
               INT64_MAX);
}

MS_NORETURN static void range_fault(const char *operation, int64_t value) {
    fault_with("%s: value (nanoseconds) must be between %" PRId64 " and %" PRId64 ", found %" PRId64, operation,
               INT64_MIN + 1, INT64_MAX, value);
}

static int64_t checked_add(Operation op, int64_t left, int64_t right) {
    int64_t sum = 0;
    if (__builtin_add_overflow(left, right, &sum)) {
        overflow(op, left, right);
    }
    return sum;
}

static int64_t checked_subtract(Operation op, int64_t left, int64_t right) {
    int64_t difference = 0;
    if (__builtin_sub_overflow(left, right, &difference)) {
        overflow(op, left, right);
    }
    return difference;
}

static int64_t duration_of(const char *operation, int64_t n, int64_t scale) {
    const int64_t low = INT64_MIN / scale;
    const int64_t high = INT64_MAX / scale;
    if (n < low || n > high) {
        fault_with("%s: value must be between %" PRId64 " and %" PRId64 ", found %" PRId64, operation, low, high, n);
    }
    return n * scale;
}

int64_t msstd_time_duration_add(int64_t left, int64_t other) {
    return checked_add((Operation){"Duration.add", "value", "other"}, left, other);
}

int64_t msstd_time_duration_plus(int64_t left, int64_t right) {
    return checked_add((Operation){"Duration.+", "left", "right"}, left, right);
}

int64_t msstd_time_duration_minus(int64_t left, int64_t right) {
    return checked_subtract((Operation){"Duration.-", "left", "right"}, left, right);
}

int64_t msstd_time_duration_subtract(int64_t left, int64_t other) {
    return checked_subtract((Operation){"Duration.subtract", "value", "other"}, left, other);
}

int64_t msstd_time_int_milliseconds(int64_t n) { return duration_of("Int.milliseconds", n, NANOS_PER_MILLISECOND); }

int64_t msstd_time_int_seconds(int64_t n) { return duration_of("Int.seconds", n, MS_NANOS_PER_SECOND); }

int64_t msstd_time_int_minutes(int64_t n) { return duration_of("Int.minutes", n, NANOS_PER_MINUTE); }

int64_t msstd_time_duration_multiply(int64_t value, int64_t factor) {
    int64_t product = 0;
    if (__builtin_mul_overflow(value, factor, &product)) {
        overflow((Operation){"Duration.multiply", "value", "factor"}, value, factor);
    }
    return product;
}

int64_t msstd_time_duration_divide(int64_t value, int64_t divisor) {
    if (divisor == 0) {
        fault_with("Duration.divide: division by zero; divisor must be nonzero, found 0");
    }
    if (value == INT64_MIN && divisor == -1) {
        overflow((Operation){"Duration.divide", "value", "divisor"}, value, divisor);
    }
    return value / divisor;
}

int64_t msstd_time_duration_negate(int64_t value) {
    if (value == INT64_MIN) {
        range_fault("Duration.negate", value);
    }
    return -value;
}

int64_t msstd_time_duration_abs(int64_t value) {
    if (value == INT64_MIN) {
        range_fault("Duration.abs", value);
    }
    return value < 0 ? -value : value;
}

int64_t msstd_time_duration_compare(int64_t left, int64_t other) { return (left > other) - (left < other); }

int64_t msstd_time_duration_to_microseconds(int64_t value) { return value / NANOS_PER_MICROSECOND; }

int64_t msstd_time_duration_to_milliseconds(int64_t value) { return value / NANOS_PER_MILLISECOND; }

double msstd_time_duration_to_seconds(int64_t value) { return (double)value / 1e9; }

double msstd_time_duration_to_minutes(int64_t value) { return (double)value / 6e10; }

double msstd_time_duration_to_hours(int64_t value) { return (double)value / 3.6e12; }

/* ---- instants and clocks ---- */

static void same_clock(const MsInstant *a, const MsInstant *b) {
    if (a->domain != b->domain) {
        fault_with("instants belong to different clock domains");
    }
}

void msstd_time_instant_shift(const MsInstant *value, int64_t duration, MsInstant *out) {
    const int64_t tick = checked_add((Operation){"Instant.shift", "value", "duration"}, value->tick, duration);
    *out = (MsInstant){.domain = value->domain, .tick = tick};
}

void msstd_time_instant_unshift(const MsInstant *value, int64_t duration, MsInstant *out) {
    const int64_t tick = checked_subtract((Operation){"Instant.-", "value", "duration"}, value->tick, duration);
    *out = (MsInstant){.domain = value->domain, .tick = tick};
}

int64_t msstd_time_instant_difference(const MsInstant *left, const MsInstant *other) {
    same_clock(left, other);
    return checked_subtract((Operation){"Instant.difference", "value", "other"}, left->tick, other->tick);
}

int64_t msstd_time_instant_compare(const MsInstant *left, const MsInstant *other) {
    same_clock(left, other);
    return (left->tick > other->tick) - (left->tick < other->tick);
}

uint8_t msstd_time_instant_equal(const MsInstant *left, const MsInstant *other) {
    same_clock(left, other);
    return left->tick == other->tick;
}

void msstd_time_clock_now(MsInstant *out) {
    *out = (MsInstant){.domain = MONOTONIC_DOMAIN, .tick = ms_clock_monotonic_since_start()};
}

void msstd_time_wall_clock_now(MsTimestamp *out) { *out = ms_clock_realtime(); }

/* ---- errors ---- */

void msstd_time_error_message(uint8_t status, MsStr *out) {
    const char *text = "time: operation failed";
    switch (status) {
    case MS_STATUS_INVALID_INPUT:
        text = "time: invalid input";
        break;
    case MS_STATUS_INVALID_DATA:
        text = "time: invalid data";
        break;
    case MS_STATUS_OUT_OF_RANGE:
        text = "time: value out of range";
        break;
    default:
        break;
    }
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), out);
}
