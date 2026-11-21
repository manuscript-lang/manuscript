/* The @std/math Decimal natives against src/runtime/tests/oracle/decimal.tsv, recorded by decimal_gen.py from Python's
 * decimal module (decimal128 arithmetic) and exact integer arithmetic. */
#include <math.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MS_TEST_OWN_FAULTS
#include "fake_rt.h"
#include "ms_rt/decimal.h"
#include "ms_rt/runtime.h"

static int failures;
#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures++; \
        } \
    } while (0)

static jmp_buf fault_jump;
static int fault_code; /* 0 none, otherwise the FaultKind of the last fault */

_Noreturn void msrt_fault(const uint8_t *message, size_t length) {
    printf("FAULT %.*s\n", (int)length, (const char *)message);
    exit(1);
}
void msfault_raise(uint8_t kind, const void *message, size_t length) {
    (void)message;
    (void)length;
    fault_code = kind;
    longjmp(fault_jump, 1);
}

typedef __int128 i128;
typedef unsigned __int128 u128;

/* "coefficient,exponent" -> a record. */
static MsDecimal decimal_of(const char *text) {
    const char *p = text;
    const bool negative = *p == '-';
    p += negative;
    u128 magnitude = 0;
    while (*p >= '0' && *p <= '9') {
        magnitude = magnitude * 10 + (u128)(*p++ - '0');
    }
    CHECK(*p == ',');
    const i128 coefficient = negative ? -(i128)magnitude : (i128)magnitude;
    return (MsDecimal){.low = (uint64_t)coefficient, .high = (int64_t)(coefficient >> 64),
                       .exponent = strtoll(p + 1, NULL, 10)};
}

static void write_decimal(const MsDecimal *d, char *buffer, size_t size) {
    const i128 coefficient = (i128)(((u128)(uint64_t)d->high << 64) | d->low);
    char digits[48];
    size_t n = 0;
    u128 magnitude = coefficient < 0 ? -(u128)coefficient : (u128)coefficient;
    do {
        digits[n++] = (char)('0' + (int)(magnitude % 10));
        magnitude /= 10;
    } while (magnitude != 0);
    size_t at = 0;
    if (coefficient < 0) {
        buffer[at++] = '-';
    }
    while (n > 0) {
        buffer[at++] = digits[--n];
    }
    snprintf(buffer + at, size - at, ",%lld", (long long)d->exponent);
}

static char *owned_text(MsStr *s) {
    char *const copy = malloc(ms_str_len(s) + 1);
    memcpy(copy, ms_str_data(s), ms_str_len(s));
    copy[ms_str_len(s)] = 0;
    free(s->ptr_word);
    return copy;
}

static void expect_text(const char *line, const char *got, const char *want) {
    if (strcmp(got, want) != 0) {
        printf("FAIL %s\n  got  %s\n  want %s\n", line, got, want);
        failures++;
    }
}

/* Runs a binary operator, reporting a fault as OVERFLOW or DIVZERO. */
static void binary(void (*op)(const MsDecimal *, const MsDecimal *, MsDecimal *), const MsDecimal *a,
                   const MsDecimal *b, char *result, size_t size) {
    MsDecimal out = {0};
    fault_code = 0;
    if (setjmp(fault_jump) == 0) {
        op(a, b, &out);
        write_decimal(&out, result, size);
    } else {
        snprintf(result, size, "%s", fault_code == 4 ? "DIVZERO" : "OVERFLOW");
    }
}

static void status_text(uint8_t status, const MsDecimal *out, char *result, size_t size) {
    if (status == 0) {
        write_decimal(out, result, size);
    } else {
        snprintf(result, size, "ERR%u", status);
    }
}

static void run_case(char *line, char *fields[5]) {
    const char *const op = fields[0], *const a = fields[1], *const b = fields[2], *const want = fields[4];
    char got[256];
    const MsDecimal x = strchr(a, ',') != NULL ? decimal_of(a) : (MsDecimal){0};
    if (strcmp(op, "add") == 0 || strcmp(op, "subtract") == 0 || strcmp(op, "multiply") == 0 ||
        strcmp(op, "divide") == 0) {
        const MsDecimal y = decimal_of(b);
        void (*const fn)(const MsDecimal *, const MsDecimal *, MsDecimal *) =
            op[0] == 'a'   ? msstd_decimal_add
            : op[0] == 's' ? msstd_decimal_subtract
            : op[0] == 'm' ? msstd_decimal_multiply
                           : msstd_decimal_divide;
        binary(fn, &x, &y, got, sizeof got);
    } else if (strcmp(op, "compare") == 0) {
        const MsDecimal y = decimal_of(b);
        snprintf(got, sizeof got, "%lld", (long long)msstd_decimal_compare(&x, &y));
    } else if (strcmp(op, "negate") == 0) {
        MsDecimal out;
        msstd_decimal_negate(&x, &out);
        write_decimal(&out, got, sizeof got);
    } else if (strcmp(op, "to_float") == 0) {
        const double value = msstd_decimal_to_float(&x), expected = strtod(want, NULL);
        if (value != expected) {
            printf("FAIL %s\n  got %a want %a\n", line, value, expected);
            failures++;
        }
        return;
    } else if (strcmp(op, "truncate") == 0) {
        int64_t n = 0;
        const bool fits = msstd_decimal_truncate_to_int(&x, &n) != 0;
        if (fits) {
            snprintf(got, sizeof got, "%lld", (long long)n);
        } else {
            snprintf(got, sizeof got, "NONE");
        }
    } else if (strcmp(op, "from_int") == 0 || strcmp(op, "from_uint") == 0) {
        MsDecimal out;
        if (op[5] == 'i') {
            msstd_decimal_from_int(strtoll(a, NULL, 10), &out);
        } else {
            msstd_decimal_from_uint((int64_t)strtoull(a, NULL, 10), &out);
        }
        write_decimal(&out, got, sizeof got);
    } else if (strcmp(op, "to_string") == 0) {
        MsStr s;
        msstd_decimal_to_string(&x, &s);
        char *const text = owned_text(&s);
        expect_text(line, text, want);
        free(text);
        return;
    } else if (strcmp(op, "round") == 0 || strcmp(op, "to_fixed") == 0) {
        long long places = 0;
        int has = 0, mode = 0;
        sscanf(b, "%lld,%d,%d", &places, &has, &mode);
        if (strcmp(op, "round") == 0) {
            MsDecimal out = {0};
            const uint8_t status = msstd_decimal_round(&x, places, (HasRaw)has, mode, &out);
            status_text(status, &out, got, sizeof got);
        } else {
            MsStr s;
            const uint8_t status = msstd_decimal_to_fixed(&x, places, (HasRaw)has, mode, &s);
            if (status == 0) {
                char *const text = owned_text(&s);
                expect_text(line, text, want);
                free(text);
                return;
            }
            snprintf(got, sizeof got, "ERR%u", status);
        }
    } else if (strcmp(op, "parse") == 0) {
        MsStr source = {.ptr_word = (uint8_t *)fields[1], .tagged = strlen(a) | ((uint64_t)2 << 62)};
        if (strcmp(a, "-empty-") == 0) {
            source.tagged = (uint64_t)2 << 62;
        }
        MsDecimal out = {0};
        const uint8_t status = msstd_decimal_parse(&source, &out);
        status_text(status, &out, got, sizeof got);
    } else {
        printf("FAIL unknown op %s\n", op);
        failures++;
        return;
    }
    expect_text(line, got, want);
}

int main(int argc, char **argv) {
    FILE *const file = fopen(argc > 1 ? argv[1] : "src/runtime/tests/oracle/decimal.tsv", "r");
    if (file == NULL) {
        printf("cannot open oracle\n");
        return 1;
    }
    char line[32768], original[32768];
    int cases = 0;
    while (fgets(line, sizeof line, file) != NULL) {
        line[strcspn(line, "\n")] = 0;
        memcpy(original, line, sizeof original);
        char *fields[5];
        char *cursor = line;
        for (int i = 0; i < 5; i++) {
            fields[i] = cursor;
            char *const tab = strchr(cursor, '\t');
            if (tab != NULL) {
                *tab = 0;
                cursor = tab + 1;
            }
        }
        run_case(original, fields);
        cases++;
    }
    fclose(file);
    printf("%d cases, %d failures\n", cases, failures);
    return failures != 0;
}
