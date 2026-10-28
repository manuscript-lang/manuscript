#include "ms_abi.h"

#if defined(_WIN32) && defined(__clang__)
/* clang for MSVC references this symbol from any object that uses floating point. */
int _fltused = 0;
#endif

int64_t greet_double(int64_t value) { return value * 2; }

double greet_scale(double value, double factor) { return value * factor; }

uint8_t greet_is_long(const ms_str *name, int64_t limit) { return ms_str_len(name) > (size_t)limit; }

void greet_hello(const ms_str *name, ms_str *out) {
    uint8_t buffer[256] = "hello, ";
    size_t n = 7, len = ms_str_len(name);
    if (len > sizeof buffer - n) len = sizeof buffer - n;
    const uint8_t *data = ms_str_data(name);
    for (size_t i = 0; i < len; i++) buffer[n + i] = data[i];
    msrt_string_from_bytes(buffer, n + len, out);
}

#include <limits.h>

/* Status 0 is ok; 1 and 2 are the first and second cases of DivideError. */
uint8_t greet_divide(int64_t a, int64_t b, int64_t *out) {
    if (b == 0) return 1;
    if (a == INT64_MIN && b == -1) return 2;
    *out = a / b;
    return 0;
}

uint8_t greet_shout(const ms_str *name, ms_str *out) {
    size_t len = ms_str_len(name);
    if (len == 0) return 1;
    uint8_t buffer[64];
    if (len > sizeof buffer) return 2;
    const uint8_t *data = ms_str_data(name);
    for (size_t i = 0; i < len; i++) buffer[i] = (data[i] >= 'a' && data[i] <= 'z') ? data[i] - 32 : data[i];
    msrt_string_from_bytes(buffer, len, out);
    return 0;
}

uint8_t greet_check(int64_t value) { return value < 0 ? 2 : 0; }
