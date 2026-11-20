/* Functions the C libraries of a current distribution call, which glibc 2.28 (the floor programs link
 * against) does not export. Each is defined in terms of an older export; the linker takes a definition only
 * when a folded library member references it. Compiled for glibc targets only (folder `glibc`). The `stat`
 * family is in crates/ms-native/src/entry.rs. */
#include <stddef.h>

int __cxa_atexit(void (*)(void *), void *, void *);

/* glibc 2.38 headers compile the strtol and scanf families under C23 (and under _GNU_SOURCE, which libuv defines) to
 * these names. They differ from the older functions only in accepting a 0b prefix; the libraries never rely on it.
 * toolchain/check-glibc-archives.sh fails the library build when one more such name appears. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

long __isoc23_strtol(const char *s, char **end, int base) { return strtol(s, end, base); }
unsigned long __isoc23_strtoul(const char *s, char **end, int base) { return strtoul(s, end, base); }
long long __isoc23_strtoll(const char *s, char **end, int base) { return strtoll(s, end, base); }
unsigned long long __isoc23_strtoull(const char *s, char **end, int base) { return strtoull(s, end, base); }
int __isoc23_vsscanf(const char *s, const char *format, va_list ap) { return vsscanf(s, format, ap); }
int __isoc23_vfscanf(FILE *f, const char *format, va_list ap) { return vfscanf(f, format, ap); }
int __isoc23_vscanf(const char *format, va_list ap) { return vscanf(format, ap); }
int __isoc23_sscanf(const char *s, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int n = vsscanf(s, format, ap);
    va_end(ap);
    return n;
}
int __isoc23_fscanf(FILE *f, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int n = vfscanf(f, format, ap);
    va_end(ap);
    return n;
}
int __isoc23_scanf(const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int n = vscanf(format, ap);
    va_end(ap);
    return n;
}

/* glibc before 2.34 keeps `atexit` in libc_nonshared.a, which programs do not link. */
int atexit(void (*function)(void)) { return __cxa_atexit((void (*)(void *))function, NULL, NULL); }

#if defined(__aarch64__)
/* glibc before 2.34 keeps `pthread_atfork` in libpthread_nonshared.a, and the aarch64 stubs export only the
 * `__register_atfork` it calls (x86-64 stubs export `pthread_atfork` itself). A program is never dlclosed, so
 * the handle is null. libuv registers its fork handlers with it. */
int __register_atfork(void (*)(void), void (*)(void), void (*)(void), void *);
int pthread_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void)) {
    return __register_atfork(prepare, parent, child, NULL);
}
#endif
