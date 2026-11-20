/* Functions the C libraries of a current distribution call, which glibc 2.28 (the floor programs link
 * against) does not export. Each is defined in terms of an older export; the linker takes a definition only
 * when a folded library member references it. Compiled for glibc targets only (folder `glibc`). The process entry and the
 * `stat` family are in start.c. */
#include <stddef.h>

int __cxa_atexit(void (*)(void *), void *, void *);

/* glibc 2.38 headers compile the strtol and scanf families under C23 (and under _GNU_SOURCE, which libuv defines) to
 * `__isoc23_*` names. They differ from the older functions only in accepting a 0b prefix, which the libraries never rely
 * on. The old functions are bound by assembler name, so no header redirects them back here.
 * toolchain/check-glibc-archives.sh fails the library build when one more such name appears. */
long old_strtol(const char *, char **, int) __asm__("strtol");
unsigned long old_strtoul(const char *, char **, int) __asm__("strtoul");
long long old_strtoll(const char *, char **, int) __asm__("strtoll");
unsigned long long old_strtoull(const char *, char **, int) __asm__("strtoull");
long __isoc23_strtol(const char *s, char **end, int base) { return old_strtol(s, end, base); }
unsigned long __isoc23_strtoul(const char *s, char **end, int base) { return old_strtoul(s, end, base); }
long long __isoc23_strtoll(const char *s, char **end, int base) { return old_strtoll(s, end, base); }
unsigned long long __isoc23_strtoull(const char *s, char **end, int base) { return old_strtoull(s, end, base); }

/* The same for scanf: libuv's /proc parsers (uv_cpu_info, uv_uptime) call these two names when compiled against
 * glibc 2.38 or newer. The prototypes are written out bound by assembler name so no header redirects vsscanf and vfscanf in turn. */
int old_vsscanf(const char *, const char *, __builtin_va_list) __asm__("vsscanf");
int old_vfscanf(void *, const char *, __builtin_va_list) __asm__("vfscanf");
int __isoc23_sscanf(const char *s, const char *format, ...) {
    __builtin_va_list args;
    __builtin_va_start(args, format);
    const int count = old_vsscanf(s, format, args);
    __builtin_va_end(args);
    return count;
}
int __isoc23_fscanf(void *file, const char *format, ...) {
    __builtin_va_list args;
    __builtin_va_start(args, format);
    const int count = old_vfscanf(file, format, args);
    __builtin_va_end(args);
    return count;
}

/* glibc before 2.34 keeps `atexit` in libc_nonshared.a, which programs do not link. */
int atexit(void (*function)(void)) { return __cxa_atexit((void (*)(void *))function, NULL, NULL); }

#if defined(__aarch64__)
#include <stdint.h>
#include <string.h>
/* aarch64's long double is IEEE binary128, and libcurl's printf (a `%Lf` argument cast to double) and OpenSSL's BIO_printf
 * convert it with this compiler-support routine, which the link has no libgcc or compiler-rt to supply. Round to nearest, ties
 * to even; the same results as libgcc's. */
double __trunctfdf2(long double value) {
    unsigned __int128 bits;
    memcpy(&bits, &value, sizeof bits);
    const uint64_t sign = (uint64_t)(bits >> 127) << 63;
    const int exponent = (int)((bits >> 112) & 0x7fff);
    const unsigned __int128 fraction = bits & (((unsigned __int128)1 << 112) - 1);
    uint64_t out;
    if (exponent == 0x7fff) {
        out = fraction == 0 ? 0x7ff0000000000000ull : (0x7ff8000000000000ull | (uint64_t)(fraction >> 60));
    } else if (exponent == 0) {
        out = 0; /* binary128 subnormals are far below the smallest double */
    } else {
        int biased = exponent - 16383 + 1023;
        if (biased >= 2047) {
            out = 0x7ff0000000000000ull;
        } else {
            const unsigned __int128 significand = fraction | ((unsigned __int128)1 << 112);
            int shift = 60;
            if (biased <= 0) {
                shift += 1 - biased;
                biased = 0;
            }
            if (shift > 113) {
                out = 0;
            } else {
                uint64_t kept = (uint64_t)(significand >> shift);
                const unsigned __int128 rest = significand & (((unsigned __int128)1 << shift) - 1);
                const unsigned __int128 half = (unsigned __int128)1 << (shift - 1);
                if (rest > half || (rest == half && (kept & 1))) kept++;
                out = biased == 0 ? kept : ((uint64_t)(biased - 1) << 52) + kept;
                if (out > 0x7ff0000000000000ull) out = 0x7ff0000000000000ull;
            }
        }
    }
    out |= sign;
    double result;
    memcpy(&result, &out, sizeof result);
    return result;
}
#endif

#if defined(__aarch64__)
/* glibc before 2.34 keeps `pthread_atfork` in libpthread_nonshared.a, and the aarch64 stubs export only the
 * `__register_atfork` it calls (x86-64 stubs export `pthread_atfork` itself). A program is never dlclosed, so
 * the handle is null. libuv registers its fork handlers with it. */
int __register_atfork(void (*)(void), void (*)(void), void (*)(void), void *);
int pthread_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void)) {
    return __register_atfork(prepare, parent, child, NULL);
}
#endif
