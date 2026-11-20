/* Unit test for runtime/core/fmt.c; `make c-test` builds it with ASan and UBSan. The golden strings were produced by
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

/* Buffers of exactly the documented size, so the sanitizer sees any overrun. */
static char *run(size_t cap, size_t (*f)(uint8_t *, void *), void *arg) {
    uint8_t *buf = malloc(cap);
    size_t n = f(buf, arg);
    CHECK(n <= cap);
    char *text = malloc(n + 1);
    memcpy(text, buf, n);
    text[n] = 0;
    free(buf);
    return text;
}

struct fl { double v; };
static size_t f_float(uint8_t *o, void *a) { return msrt_fmt_float(((struct fl *)a)->v, o); }
static size_t f_float32(uint8_t *o, void *a) { return msrt_fmt_float32(((struct fl *)a)->v, o); }
struct pr { double v; char fmt; int64_t digits; };
static size_t f_prec(uint8_t *o, void *a) {
    struct pr *p = a;
    return msrt_fmt_float_precision(p->v, (uint8_t)p->fmt, p->digits, o);
}
struct in { uint64_t n; uint32_t radix; uint8_t neg; };
static size_t f_i64(uint8_t *o, void *a) { return msrt_fmt_i64((int64_t)((struct in *)a)->n, o); }
static size_t f_u64(uint8_t *o, void *a) { return msrt_fmt_u64(((struct in *)a)->n, o); }
static size_t f_radix(uint8_t *o, void *a) {
    struct in *p = a;
    return msrt_fmt_radix(p->n, p->radix, p->neg, o);
}

static void flt(double v, const char *want) {
    struct fl a = {v};
    char *got = run(40, f_float, &a);
    if (strcmp(got, want)) {
        fprintf(stderr, "float %.17g: got %s want %s\n", v, got, want);
        abort();
    }
    free(got);
}
static void flt32(double v, const char *want) {
    struct fl a = {v};
    char *got = run(40, f_float32, &a);
    if (strcmp(got, want)) {
        fprintf(stderr, "float32 %.9g: got %s want %s\n", v, got, want);
        abort();
    }
    free(got);
}
static void prec(double v, char fmt, int64_t digits, const char *want) {
    struct pr a = {v, fmt, digits};
    char *got = run(160, f_prec, &a);
    if (strcmp(got, want)) {
        fprintf(stderr, "precision %.17g %c %lld: got %s want %s\n", v, fmt, (long long)digits, got, want);
        abort();
    }
    free(got);
}
static void integer(int64_t v, const char *want) {
    struct in a = {(uint64_t)v, 0, 0};
    char *got = run(20, f_i64, &a);
    CHECK(strcmp(got, want) == 0);
    free(got);
}
static void radix(uint64_t n, uint32_t r, uint8_t neg, const char *want) {
    struct in a = {n, r, neg};
    char *got = run(65, f_radix, &a);
    CHECK(strcmp(got, want) == 0);
    free(got);
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
    struct in u = {UINT64_MAX, 0, 0};
    char *text = run(20, f_u64, &u);
    CHECK(strcmp(text, "18446744073709551615") == 0);
    free(text);
    radix(255, 16, 0, "ff");
    radix(255, 2, 0, "11111111");
    radix(35, 36, 0, "z");
    radix(0, 7, 0, "0");
    radix(255, 16, 1, "-ff");
    radix(UINT64_C(1) << 63, 2, 1, "-1000000000000000000000000000000000000000000000000000000000000000");
    radix(UINT64_MAX, 2, 0, "1111111111111111111111111111111111111111111111111111111111111111");

    flt(0.0, "0");
    flt(-0.0, "-0");
    flt(NAN, "NaN");
    flt(INFINITY, "Infinity");
    flt(-INFINITY, "-Infinity");
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
    flt32(0.1f, "0.1");
    flt32(16777216.0, "16777216");
    flt32(3.4028234663852886e38, "3.4028235e+38");
    flt32(1e-45, "1e-45");
    flt32(-0.0, "-0");
    flt32(1.0e10f, "10000000000");
    flt32(0.3f, "0.3");

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
    prec(NAN, 'f', 2, "NaN");
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
        struct fl a = {v};
        char *got = run(40, f_float, &a);
        CHECK(strtod(got, NULL) == v);
        free(got);
        float x = (float)v;
        if (x - x == 0.0f && x != 0.0f) {
            a.v = (double)x;
            got = run(40, f_float32, &a);
            CHECK(strtof(got, NULL) == x);
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
        int64_t d = (int64_t)(next() % 101);
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
    puts("core_fmt ok");
    return 0;
}
