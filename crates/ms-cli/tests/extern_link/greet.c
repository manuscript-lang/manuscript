#include "ms_abi.h"

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
