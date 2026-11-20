/* Decimal text to the nearest double, over the C library's strtod, which rounds correctly on glibc, musl, macOS and
 * the Windows C runtime. The conversion reads the C locale: the runtime never calls setlocale, so the decimal
 * point is always '.'. Compiled for every platform (one portable source, like thread.c). */
#include "ms_rt/sys.h"

/* Declared by hand: one source builds against every C library (see sys.h). */
double strtod(const char *text, char **end);

/* Literals up to this many bytes are converted from the stack. */
#define MS_DECIMAL_STACK 128

bool ms_sys_parse_decimal(const uint8_t *text, size_t len, double *out) {
    char stack[MS_DECIMAL_STACK];
    char *copy = stack;
    if (len >= sizeof stack) {
        size_t bytes = 0;
        if (!ms_size_add(len, 1, &bytes)) {
            return false;
        }
        copy = ms_sys_malloc(bytes);
        if (copy == NULL) {
            return false;
        }
    }
    __builtin_memcpy(copy, text, len);
    copy[len] = '\0';
    *out = strtod(copy, NULL);
    if (copy != stack) {
        ms_sys_free(copy);
    }
    return true;
}
