/* The @std/math BigInt natives against src/runtime/tests/oracle/bigint.tsv, recorded from Python's exact integers by
 * bigint_gen.py, plus direct checks of what the table cannot say (object clone, limits, the 2^24-bit boundary). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MS_TEST_OWN_FAULTS
#include <openssl/bn.h>

#include "../std/bignum_ntt.h"
#include "fake_rt.h"
#include "ms_rt/bigint.h"
#include "ms_rt/runtime.h"

static int failures;
#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures++; \
        } \
    } while (0)

_Noreturn void msrt_fault(const uint8_t *message, size_t length) {
    printf("FAULT %.*s\n", (int)length, (const char *)message);
    exit(1);
}
void msfault_raise(uint8_t kind, const void *message, size_t length) {
    printf("FAULT(%u) %.*s\n", kind, (int)length, (const char *)message);
    exit(1);
}
/* An owned string (tag bits 00): the allocation and the byte length. */

typedef MsBigCell cell;

static void drop(cell *c) {
    if (c != NULL) {
        ((MsObj *)c)->drop((MsObj *)c);
    }
}


/* Parses `text`, or returns the status in *status. */
static cell *parse(const char *text, int64_t radix, int64_t max, int has_max, uint8_t *status) {
    cell *out = NULL;
    const size_t length = strlen(text);
    uint8_t *const copy = malloc(length + 1);
    memcpy(copy, text, length + 1);
    const MsStr s = {.ptr_word = copy, .tagged = length | ((uint64_t)2 << 62)}; /* static: not freed with it */
    *status = msstd_bigint_parse(&s, radix, (HasRaw)has_max, max, &out);
    free(copy);
    return out;
}

static cell *big(const char *text) {
    uint8_t status = 0;
    cell *c = parse(text, 10, 0, 0, &status);
    CHECK(status == 0);
    return c;
}

/* The text of a value in a radix; the caller frees it. */
static char *text_of(const cell *c, int64_t radix) {
    MsStr s;
    msstd_bigint_to_string_radix(c, radix, &s);
    char *copy = malloc(ms_str_len(&s) + 1);
    memcpy(copy, ms_str_data(&s), ms_str_len(&s));
    copy[ms_str_len(&s)] = 0;
    free(s.ptr_word);
    return copy;
}

static char *read_line(FILE *f) {
    size_t cap = 4096, len = 0;
    char *line = malloc(cap);
    int ch;
    while ((ch = fgetc(f)) != EOF && ch != '\n') {
        if (len + 1 >= cap) {
            cap *= 2;
            line = realloc(line, cap);
        }
        line[len++] = (char)ch;
    }
    line[len] = 0;
    if (ch == EOF && len == 0) {
        free(line);
        return NULL;
    }
    return line;
}

/* Splits a line at tabs into five fields, in place. */
static void split(char *line, char *fields[5]) {
    for (int i = 0; i < 5; i++) {
        fields[i] = line;
        char *tab = strchr(line, '\t');
        if (tab == NULL) {
            return;
        }
        *tab = 0;
        line = tab + 1;
    }
}

typedef uint8_t (*binary_out)(const cell *, const cell *, cell **);
typedef cell *(*binary)(const cell *, const cell *);
typedef cell *(*unary)(const cell *);

static const char *op_failed;

/* Compares a result cell (or status) with the expected column. */
static void expect(const char *line_op, const char *expected, cell *result, uint8_t status) {
    char want_status[16];
    if (strncmp(expected, "ERR", 3) == 0) {
        snprintf(want_status, sizeof want_status, "%u", status);
        if (strcmp(expected + 3, want_status) != 0 || result != NULL) {
            printf("FAIL %s: want %s got status %u\n", line_op, expected, status);
            failures++;
        }
        drop(result);
        return;
    }
    char *got = result != NULL ? text_of(result, 10) : malloc(8);
    if (result == NULL) {
        snprintf(got, 8, "(none)");
    }
    if (strcmp(got, expected) != 0) {
        printf("FAIL %s: want %.60s got %.60s (status %u)\n", line_op, expected, got, status);
        failures++;
    }
    free(got);
    drop(result);
}

static void run_binary(const char *op, const char *a, const char *b, const char *expected) {
    cell *x = big(a), *y = big(b), *r = NULL;
    uint8_t status = 0;
    static const struct { const char *name; binary fn; } plain[] = {
        {"add", msstd_bigint_add}, {"subtract", msstd_bigint_subtract}, {"multiply", msstd_bigint_multiply},
        {"and", msstd_bigint_bit_and}, {"or", msstd_bigint_bit_or}, {"xor", msstd_bigint_bit_xor},
        {"gcd", msstd_bigint_gcd}, {"lcm", msstd_bigint_lcm},
    };
    static const struct { const char *name; binary_out fn; } fallible[] = {
        {"divide", msstd_bigint_divide}, {"remainder", msstd_bigint_remainder},
        {"inverse_mod", msstd_bigint_inverse_mod},
    };
    for (size_t i = 0; i < sizeof plain / sizeof plain[0]; i++) {
        if (strcmp(op, plain[i].name) == 0) {
            r = plain[i].fn(x, y);
        }
    }
    for (size_t i = 0; i < sizeof fallible / sizeof fallible[0]; i++) {
        if (strcmp(op, fallible[i].name) == 0) {
            status = fallible[i].fn(x, y, &r);
            if (strcmp(op, "inverse_mod") == 0) {
                status = 0; /* inverse_mod answers 1 when found and 0 when there is none: only r matters */
            }
        }
    }
    if (strcmp(op, "compare") == 0) {
        int64_t c = msstd_bigint_compare(x, y);
        CHECK(c == atoi(expected));
        CHECK((msstd_bigint_equal(x, y) != 0) == (c == 0));
    } else if (r != NULL || status != 0 || strncmp(expected, "ERR", 3) == 0) {
        expect(op, expected, r, status);
    } else {
        printf("FAIL unknown op %s\n", op);
        failures++;
    }
    drop(x);
    drop(y);
}

static void run_unary(const char *op, const char *a, const char *expected) {
    cell *x = big(a);
    static const struct { const char *name; unary fn; } table[] = {
        {"negate", msstd_bigint_negate}, {"abs", msstd_bigint_abs}, {"not", msstd_bigint_bit_not},
    };
    for (size_t i = 0; i < sizeof table / sizeof table[0]; i++) {
        if (strcmp(op, table[i].name) == 0) {
            expect(op, expected, table[i].fn(x), 0);
        }
    }
    if (strcmp(op, "sign") == 0) {
        CHECK(msstd_bigint_sign(x) == atoi(expected));
    } else if (strcmp(op, "to_float") == 0) {
        const double want = strtod(expected, NULL), got = msstd_bigint_to_float(x);
        CHECK(memcmp(&want, &got, sizeof want) == 0);
    } else if (strcmp(op, "to_int") == 0) {
        int64_t v = 0;
        const uint8_t fits = msstd_bigint_to_int(x, &v);
        CHECK(fits == (strcmp(expected, "ERR0") != 0));
        if (fits) {
            char text[32];
            snprintf(text, sizeof text, "%lld", (long long)v);
            CHECK(strcmp(text, expected) == 0);
        }
    } else if (strcmp(op, "sqrt") == 0) {
        cell *r = NULL;
        const uint8_t status = msstd_bigint_sqrt(x, &r);
        expect(op, expected, r, status);
    }
    drop(x);
}

static void run_shift_pow(const char *op, const char *a, const char *n, const char *expected) {
    cell *x = big(a), *r = NULL;
    uint8_t status = 0;
    const int64_t count = atoll(n);
    if (strcmp(op, "shift_left") == 0) {
        status = msstd_bigint_shift_left(x, count, &r);
    } else if (strcmp(op, "shift_right") == 0) {
        status = msstd_bigint_shift_right(x, count, &r);
    } else {
        status = msstd_bigint_pow(x, count, &r);
    }
    if (strcmp(expected, "-") == 0) { /* 2^(2^24 - 1): only its length is recorded */
        char *bits = text_of(r, 2);
        CHECK(status == 0 && strlen(bits) == (size_t)1 << 24);
        free(bits);
        drop(r);
    } else {
        expect(op, expected, r, status);
    }
    drop(x);
}

static void run_modular(const char *op, const char *a, const char *b, const char *c, const char *expected) {
    cell *x = big(a), *y = big(b), *z = big(c), *r = NULL;
    const uint8_t status = msstd_bigint_pow_mod(x, y, z, &r);
    expect(op, expected, r, status);
    drop(x);
    drop(y);
    drop(z);
}

static void run_text(const char *op, const char *a, const char *b, const char *c, const char *expected) {
    uint8_t status = 0;
    if (strcmp(op, "format") == 0) {
        cell *x = big(a);
        char *text = text_of(x, atoi(b));
        CHECK(strcmp(text, expected) == 0);
        free(text);
        drop(x);
    } else if (strcmp(op, "parse") == 0) {
        cell *r = parse(strcmp(a, "-empty-") == 0 ? "" : a, atoi(b), 0, 0, &status);
        expect(op, expected, r, status);
    } else {
        cell *r = parse(a, atoi(b), atoll(c), 1, &status);
        expect(op, expected, r, status);
    }
}

static void run_table(const char *path) {
    FILE *f = fopen(path, "r");
    CHECK(f != NULL);
    if (f == NULL) {
        return;
    }
    char *line;
    int cases = 0;
    while ((line = read_line(f)) != NULL) {
        char dash[2] = "-";
        char *fields[5] = {dash, dash, dash, dash, dash};
        split(line, fields);
        const char *op = fields[0];
        op_failed = op;
        if (strcmp(op, "shift_left") == 0 || strcmp(op, "shift_right") == 0 || strcmp(op, "pow") == 0) {
            run_shift_pow(op, fields[1], fields[2], fields[4]);
        } else if (strcmp(op, "pow_mod") == 0) {
            run_modular(op, fields[1], fields[2], fields[3], fields[4]);
        } else if (strcmp(op, "format") == 0 || strcmp(op, "parse") == 0 || strcmp(op, "parse_max") == 0) {
            run_text(op, fields[1], fields[2], fields[3], fields[4]);
        } else if (strcmp(fields[2], "-") == 0) {
            run_unary(op, fields[1], fields[4]);
        } else {
            run_binary(op, fields[1], fields[2], fields[4]);
        }
        free(line);
        cases++;
    }
    fclose(f);
    CHECK(cases > 1000);
}

static void run_direct(void) {
    cell *seven = big("7"), *copy = (cell *)((MsObj *)seven)->clone((MsObj *)seven);
    char *text = text_of(copy, 10);
    CHECK(strcmp(text, "7") == 0);
    free(text);
    drop(copy);
    drop(seven);
    cell *nanos = msstd_bigint_from_seconds_nanos(-2, 5);
    text = text_of(nanos, 10);
    CHECK(strcmp(text, "-1999999995") == 0);
    free(text);
    drop(nanos);
    cell *top = msstd_bigint_from_u64(-1);
    text = text_of(top, 10);
    CHECK(strcmp(text, "18446744073709551615") == 0);
    free(text);
    drop(top);
    cell *a = big("-9"), *b = big("4");
    cell *q = msstd_bigint_quotient(a, b), *m = msstd_bigint_modulo(a, b);
    char *qt = text_of(q, 10), *mt = text_of(m, 10);
    CHECK(strcmp(qt, "-2") == 0 && strcmp(mt, "-1") == 0);
    free(qt);
    free(mt);
    drop(q);
    drop(m);
    drop(a);
    drop(b);
    /* The top octal digit of 127 spans bits past the last stored byte. */
    cell *edge = big("127");
    text = text_of(edge, 8);
    CHECK(strcmp(text, "177") == 0);
    free(text);
    drop(edge);
}

/* The transform product equals OpenSSL's for operands of unequal and equal widths, and for a square. */
static void run_transform_product(void) {
    static const int widths[][2] = {{70000, 70000}, {300000, 65537}, {1000, 200000}, {1500000, 1500000}};
    BN_CTX *const ctx = BN_CTX_new();
    for (size_t i = 0; i < sizeof widths / sizeof widths[0]; i++) {
        BIGNUM *const a = BN_new(), *const b = BN_new(), *const want = BN_new(), *const got = BN_new();
        CHECK(BN_rand(a, widths[i][0], BN_RAND_TOP_ONE, BN_RAND_BOTTOM_ANY) == 1);
        CHECK(BN_rand(b, widths[i][1], BN_RAND_TOP_ONE, BN_RAND_BOTTOM_ANY) == 1);
        CHECK(BN_mul(want, a, b, ctx) == 1);
        CHECK(ms_ntt_multiply(got, a, b));
        CHECK(BN_cmp(want, got) == 0);
        CHECK(BN_sqr(want, a, ctx) == 1);
        CHECK(ms_ntt_multiply(got, a, a));
        CHECK(BN_cmp(want, got) == 0);
        BN_free(a);
        BN_free(b);
        BN_free(want);
        BN_free(got);
    }
    BN_CTX_free(ctx);
}

int main(void) {
    run_transform_product();
    run_direct();
    run_table("src/runtime/tests/oracle/bigint.tsv");
    (void)op_failed;
    printf("std_bigint: %d failures\n", failures);
    return failures == 0 ? 0 : 1;
}
