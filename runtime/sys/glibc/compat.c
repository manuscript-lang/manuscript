/* Functions the C libraries of a current distribution call, which glibc 2.28 (the floor programs link
 * against) does not export. Each is defined in terms of an older export; the linker takes a definition only
 * when a folded library member references it. Compiled for glibc targets only (folder `glibc`). The `stat`
 * family is in crates/ms-native/src/entry.rs. */
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
