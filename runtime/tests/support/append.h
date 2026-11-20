/* Bounded text building for tests: sprintf, strcpy and strcat have no size, so `make c-lint` bans them. */
#ifndef MS_TEST_APPEND_H
#define MS_TEST_APPEND_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* Appends printf-style text to the string in dst (capacity cap, terminator included); truncates, never overruns. */
static inline void msx_append(char *dst, size_t cap, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
static inline void msx_append(char *dst, size_t cap, const char *fmt, ...) {
    size_t used = strlen(dst);
    if (used >= cap) return;
    va_list ap;
    va_start(ap, fmt);
    (void)vsnprintf(dst + used, cap - used, fmt, ap);
    va_end(ap);
}

/* Appends len bytes as lower-case hex. */
static inline void msx_append_hex(char *dst, size_t cap, const uint8_t *bytes, size_t len) {
    for (size_t i = 0; i < len; i++) msx_append(dst, cap, "%02x", bytes[i]);
}

#endif
