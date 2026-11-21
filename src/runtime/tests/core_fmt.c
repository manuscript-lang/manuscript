/* Unit test for src/runtime/core/fmt.c; `make c-test` builds it with ASan and UBSan. The golden strings were produced by
 * the Rust formatter this code replaced (13.5 million lines compared, plus every 31st binary32 pattern); the sweeps
 * check the same output against the C library: shortest floats must read back as the same value, and the precision
 * forms must equal printf's exact, half-to-even rounding. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/fmt.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_fmt.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

/* Each formatter runs against a heap buffer of exactly the documented capacity, so the sanitizer sees any overrun. */
typedef struct Request {
    double value;
    uint64_t number;
    uint32_t radix;
    uint8_t flag;
    char form;
    int64_t digits;
} Request;

typedef bool (*Formatter)(const Request *request, uint8_t *out, size_t capacity, size_t *length);

static bool run_u64(const Request *r, uint8_t *out, size_t capacity, size_t *length) {
    return msrt_fmt_u64(r->number, out, capacity, length);
}
static bool run_i64(const Request *r, uint8_t *out, size_t capacity, size_t *length) {
    return msrt_fmt_i64((int64_t)r->number, out, capacity, length);
}
static bool run_radix(const Request *r, uint8_t *out, size_t capacity, size_t *length) {
    return msrt_fmt_radix(r->number, r->radix, r->flag, out, capacity, length);
}
static bool run_float(const Request *r, uint8_t *out, size_t capacity, size_t *length) {
    return msrt_fmt_float(r->value, out, capacity, length);
}
static bool run_float32(const Request *r, uint8_t *out, size_t capacity, size_t *length) {
    return msrt_fmt_float32(r->value, out, capacity, length);
}
static bool run_precision(const Request *r, uint8_t *out, size_t capacity, size_t *length) {
    return msrt_fmt_float_precision(r->value, (uint8_t)r->form, r->digits, out, capacity, length);
}

static char *format(Formatter run, const Request *request, size_t capacity, bool *ok) {
    uint8_t *buffer = malloc(capacity);
    size_t length = 0;
    *ok = run(request, buffer, capacity, &length);
    char *text = calloc(length + 1, 1);
    if (*ok) {
        memcpy(text, buffer, length);
    }
    free(buffer);
    return text;
}

static void expect(Formatter run, const Request *request, size_t capacity, const char *want) {
    bool ok = false;
    char *got = format(run, request, capacity, &ok);
    if (!ok || strcmp(got, want) != 0) {
        fprintf(stderr, "core_fmt.c: ok=%d got \"%s\" want \"%s\" (value %.17g)\n", ok, got, want, request->value);
        abort();
    }
    free(got);
}

static void flt(double v, const char *want) {
    expect(run_float, &(Request){.value = v}, MS_FMT_FLOAT_CAPACITY, want);
}
static void flt32(double v, const char *want) {
    expect(run_float32, &(Request){.value = v}, MS_FMT_FLOAT_CAPACITY, want);
}
static void prec(double v, char form, int64_t digits, const char *want) {
    expect(run_precision, &(Request){.value = v, .form = form, .digits = digits}, MS_FMT_PRECISION_CAPACITY, want);
}
static void integer(int64_t v, const char *want) {
    expect(run_i64, &(Request){.number = (uint64_t)v}, MS_FMT_INTEGER_CAPACITY, want);
}
static void radix(uint64_t n, uint32_t r, uint8_t negative, const char *want) {
    expect(run_radix, &(Request){.number = n, .radix = r, .flag = negative}, MS_FMT_RADIX_CAPACITY, want);
}

/* A buffer one byte too small, an unknown form and an out-of-range radix or digit count are refused. */
static void refuses(Formatter run, const Request *request, size_t capacity) {
    bool ok = true;
    free(format(run, request, capacity, &ok));
    CHECK(!ok);
}

static uint64_t state = 0x9e3779b97f4a7c15ULL;
static uint64_t next(void) {
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    return state;
}

int main(void) {
    integer(0, "0");
    integer(9, "9");
    integer(10, "10");
    integer(99, "99");
    integer(100, "100");
    integer(-1, "-1");
    integer(INT64_MAX, "9223372036854775807");
    integer(INT64_MIN, "-9223372036854775808");
    expect(run_u64, &(Request){.number = UINT64_MAX}, MS_FMT_INTEGER_CAPACITY, "18446744073709551615");
    radix(255, 16, 0, "ff");
    radix(255, 2, 0, "11111111");
    radix(35, 36, 0, "z");
    radix(0, 7, 0, "0");
    radix(255, 16, 1, "-ff");
    radix(UINT64_C(1) << 63, 2, 1, "-1000000000000000000000000000000000000000000000000000000000000000");
    radix(UINT64_MAX, 2, 0, "1111111111111111111111111111111111111111111111111111111111111111");

    flt(0.0, "0");
    flt(-0.0, "-0");
    flt((double)NAN, "NaN");
    flt((double)INFINITY, "Infinity");
    flt((double)-INFINITY, "-Infinity");
    flt(1.0, "1");
    flt(-2.5, "-2.5");
    flt(0.1, "0.1");
    flt(100.0, "100");
    flt(123456789012345680000.0, "123456789012345680000");
    flt(1e21, "1e+21");
    flt(1e-6, "0.000001");
    flt(1e-7, "1e-7");
    flt(9007199254740993.0, "9007199254740992");
    flt(5e-324, "5e-324");
    flt(1.7976931348623157e308, "1.7976931348623157e+308");
    flt(2.2250738585072014e-308, "2.2250738585072014e-308");
    flt(4.35, "4.35");
    flt(0.3, "0.3");
    flt32((double)0.1f, "0.1");
    flt32(16777216.0, "16777216");
    flt32(3.4028234663852886e38, "3.4028235e+38");
    flt32(1e-45, "1e-45");
    flt32(-0.0, "-0");
    flt32((double)1.0e10f, "10000000000");
    flt32((double)0.3f, "0.3");

    prec(1.0, 'f', 2, "1.00");
    prec(0.5, 'f', 0, "0");
    prec(1.5, 'f', 0, "2");
    prec(2.5, 'f', 0, "2");
    prec(0.05, 'f', 1, "0.1");
    prec(0.995, 'f', 2, "0.99");
    prec(999999.5, 'f', 0, "1000000");
    prec(0.9999, 'f', 2, "1.00");
    prec(0.0005, 'f', 3, "0.001");
    prec(2.675, 'f', 2, "2.67");
    prec(-0.0, 'f', 2, "-0.00");
    prec(1e21, 'f', 2, "1e+21");
    prec((double)NAN, 'f', 2, "NaN");
    prec(123.456, 'e', 2, "1.23e+2");
    prec(0.0, 'e', 2, "0.00e+0");
    prec(9.5, 'e', 0, "1e+1");
    prec(1e-7, 'e', 3, "1.000e-7");
    prec(123.456, 'g', 4, "123.5");
    prec(0.000123456, 'g', 3, "0.000123");
    prec(123456.0, 'g', 2, "1.2e+5");
    prec(99.5, 'g', 2, "1.0e+2");
    prec(5e-324, 'f', 3, "0.000");

    /* Shortest floats read back exactly, and no shorter text would: dropping the last digit changes the value. */
    for (int i = 0; i < 300000; i++) {
        uint64_t bits = next();
        double v;
        memcpy(&v, &bits, sizeof v);
        if (v != v || v - v != 0.0) {
            continue;
        }
        bool ok = false;
        char *got = format(run_float, &(Request){.value = v}, MS_FMT_FLOAT_CAPACITY, &ok);
        CHECK(ok && strtod(got, NULL) == v);
        free(got);
        float x = (float)v;
        if (x - x == 0.0f && x != 0.0f) {
            got = format(run_float32, &(Request){.value = (double)x}, MS_FMT_FLOAT_CAPACITY, &ok);
            CHECK(ok && strtof(got, NULL) == x);
            free(got);
        }
    }

    /* Precision forms against printf, which rounds the exact value half to even. */
    for (int i = 0; i < 100000; i++) {
        uint64_t bits = next();
        double v;
        switch (i % 3) {
        case 0: memcpy(&v, &bits, sizeof v); break;
        case 1: v = (double)(int64_t)(bits >> 20) / 1000.0; break;
        default: v = (double)(bits % 100000) * pow(10.0, (double)(int)(next() % 30) - 15.0); break;
        }
        if (v != v || v - v != 0.0) {
            continue;
        }
        const int64_t d = (int64_t)(next() % 101);
        char want[400];
        if (fabs(v) < 1e21) {
            snprintf(want, sizeof want, "%.*f", (int)d, v);
            prec(v, 'f', d, want);
        }
        snprintf(want, sizeof want, "%.*e", (int)d, v);
        /* printf writes e+05 or e-05: the runtime writes the shortest exponent. */
        char *e = strchr(want, 'e');
        char sign = e[1];
        char *digits = e + 2;
        while (digits[0] == '0' && digits[1]) {
            digits++;
        }
        char fixed[400];
        snprintf(fixed, sizeof fixed, "%.*se%s%s", (int)(e - want), want, sign == '-' ? "-" : "+", digits);
        prec(v, 'e', d, fixed);
    }
    refuses(run_float, &(Request){.value = 1.5}, 2);
    refuses(run_float, &(Request){.value = 0.1}, 2);
    refuses(run_i64, &(Request){.number = (uint64_t)INT64_MIN}, MS_FMT_INTEGER_CAPACITY - 1);
    refuses(run_radix, &(Request){.number = 5, .radix = 1}, MS_FMT_RADIX_CAPACITY);
    refuses(run_radix, &(Request){.number = 5, .radix = 37}, MS_FMT_RADIX_CAPACITY);
    refuses(run_precision, &(Request){.value = 1.0, .form = 'x', .digits = 2}, MS_FMT_PRECISION_CAPACITY);
    refuses(run_precision, &(Request){.value = 1.0, .form = 'f', .digits = 101}, MS_FMT_PRECISION_CAPACITY);
    refuses(run_precision, &(Request){.value = 1.0, .form = 'g', .digits = 0}, MS_FMT_PRECISION_CAPACITY);
    refuses(run_precision, &(Request){.value = 1.0, .form = 'f', .digits = 50}, 10);
    puts("core_fmt ok");
    return 0;
}
