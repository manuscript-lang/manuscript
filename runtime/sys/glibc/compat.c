/* Functions the C libraries of a current distribution call, which glibc 2.28 (the floor programs link
 * against) does not export. Each is defined in terms of an older export; the linker takes a definition only
 * when a folded library member references it. Compiled for glibc targets only (folder `glibc`). The `stat`
 * family is in crates/ms-native/src/entry.rs. */
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>

long strtol(const char *, char **, int);
int __cxa_atexit(void (*)(void *), void *, void *);

/* glibc 2.38 compiles strtol calls under C23 to this name. */
long __isoc23_strtol(const char *s, char **end, int base) { return strtol(s, end, base); }
unsigned long strtoul(const char *, char **, int);
unsigned long __isoc23_strtoul(const char *s, char **end, int base) { return strtoul(s, end, base); }

/* The same for the scanf family (libuv reads /proc with them). */
int __isoc23_sscanf(const char *text, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    const int count = vsscanf(text, format, arguments);
    va_end(arguments);
    return count;
}
int __isoc23_fscanf(FILE *stream, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    const int count = vfscanf(stream, format, arguments);
    va_end(arguments);
    return count;
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
