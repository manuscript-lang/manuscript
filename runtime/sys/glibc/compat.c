/* Functions the C libraries of a current distribution call, which glibc 2.28 (the floor programs link
 * against) does not export. Each is defined in terms of an older export; the linker takes a definition only
 * when a folded library member references it. Compiled for glibc targets only (folder `glibc`). The `stat`
 * family is in crates/ms-native/src/entry.rs. */
#include <stddef.h>

long strtol(const char *, char **, int);
int __cxa_atexit(void (*)(void *), void *, void *);

/* glibc 2.38 compiles strtol calls under C23 to this name. */
long __isoc23_strtol(const char *s, char **end, int base) { return strtol(s, end, base); }
unsigned long strtoul(const char *, char **, int);
unsigned long __isoc23_strtoul(const char *s, char **end, int base) { return strtoul(s, end, base); }

/* glibc before 2.34 keeps `atexit` in libc_nonshared.a, which programs do not link. */
int atexit(void (*function)(void)) { return __cxa_atexit((void (*)(void *))function, NULL, NULL); }
