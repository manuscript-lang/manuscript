/* The process entry and the `stat` family for programs linked against the glibc 2.28 stubs. Those programs get no
 * `crt1.o` or `libc_nonshared.a` (linking needs no C toolchain or `libc6-dev`), so the archive supplies what those
 * would: `_start`, which passes `main`, an `.init_array` runner and the kernel's stack to glibc's
 * `__libc_start_main` as glibc's own `start.S` does, and `stat` and its relatives, which glibc before 2.33
 * provides only as wrappers over `__xstat64` and friends. glibc 2.34 and newer still calls a non-null `init`
 * (`csu/libc-start.c`). Compiled for glibc targets only (folder `glibc`); the linker takes `_start` only from a
 * program link that has no `crt1.o`, so the unit tests and the Rust test binaries never see it. */
#include <stddef.h>

typedef void (*MsInitFn)(int, char **, char **);

// NOLINTBEGIN(bugprone-reserved-identifier,readability-identifier-naming): the names are the linker's and glibc's
extern const MsInitFn __init_array_start[];
extern const MsInitFn __init_array_end[];
// NOLINTEND(bugprone-reserved-identifier,readability-identifier-naming)

void ms_run_init_array(int argc, char **argv, char **envp); /* called from the `_start` assembly below */

/* Runs the executable's `.init_array` (Rust `std` records the arguments there). glibc runs the loaded libraries'
 * own; `fini` stays null because the loader runs the executable's `.fini_array`. */
void ms_run_init_array(int argc, char **argv, char **envp);
void ms_run_init_array(int argc, char **argv, char **envp) {
    for (const MsInitFn *at = __init_array_start; at < __init_array_end; at++) {
        (*at)(argc, argv, envp);
    }
}

#if defined(__x86_64__)
__asm__(".globl _start\n"
        ".type _start,@function\n"
        "_start:\n"
        "xor %ebp, %ebp\n"
        "mov %rdx, %r9\n"
        "pop %rsi\n"
        "mov %rsp, %rdx\n"
        "and $-16, %rsp\n"
        "push %rax\n"
        "push %rsp\n"
        "xor %r8d, %r8d\n"
        "lea ms_run_init_array(%rip), %rcx\n"
        "lea main(%rip), %rdi\n"
        "call *__libc_start_main@GOTPCREL(%rip)\n"
        "hlt\n"
        ".size _start, .-_start\n");
#elif defined(__aarch64__)
__asm__(".globl _start\n"
        ".type _start,@function\n"
        "_start:\n"
        "mov x29, xzr\n"
        "mov x30, xzr\n"
        "mov x5, x0\n"
        "ldr x1, [sp]\n"
        "add x2, sp, #8\n"
        "mov x6, sp\n"
        "adrp x0, :got:main\n"
        "ldr x0, [x0, :got_lo12:main]\n"
        "adrp x3, ms_run_init_array\n"
        "add x3, x3, :lo12:ms_run_init_array\n"
        "mov x4, xzr\n"
        "bl __libc_start_main\n"
        "bl abort\n"
        ".size _start, .-_start\n");
#else
#error "no process entry for this glibc architecture"
#endif

/* The `_STAT_VER` that glibc's `__xstat64` family takes: the kernel's `struct stat` layout. */
#if defined(__x86_64__)
enum { STAT_VERSION = 1 };
#else
enum { STAT_VERSION = 0 };
#endif

// NOLINTBEGIN(bugprone-reserved-identifier): glibc's versioned stat entry points
int __xstat64(int version, const char *path, void *buffer);
int __lxstat64(int version, const char *path, void *buffer);
int __fxstat64(int version, int descriptor, void *buffer);
int __fxstatat64(int version, int directory, const char *path, void *buffer, int flags);
// NOLINTEND(bugprone-reserved-identifier)

/* Declared here because the C library's own headers give these other types and are not included. */
int stat64(const char *path, void *buffer);
int stat(const char *path, void *buffer);
int lstat64(const char *path, void *buffer);
int lstat(const char *path, void *buffer);
int fstat64(int descriptor, void *buffer);
int fstat(int descriptor, void *buffer);
int fstatat64(int directory, const char *path, void *buffer, int flags);
int fstatat(int directory, const char *path, void *buffer, int flags);

int stat64(const char *path, void *buffer);
int stat(const char *path, void *buffer);
int lstat64(const char *path, void *buffer);
int lstat(const char *path, void *buffer);
int fstat64(int descriptor, void *buffer);
int fstat(int descriptor, void *buffer);
int fstatat64(int directory, const char *path, void *buffer, int flags);
int fstatat(int directory, const char *path, void *buffer, int flags);

/* `stat64` and its plain-named twin (the same layout on 64-bit Linux, for objects passed with `--link`) over the
 * versioned glibc call, as `libc_nonshared.a` does. */
int stat64(const char *path, void *buffer) { return __xstat64(STAT_VERSION, path, buffer); }
int stat(const char *path, void *buffer) { return __xstat64(STAT_VERSION, path, buffer); }
int lstat64(const char *path, void *buffer) { return __lxstat64(STAT_VERSION, path, buffer); }
int lstat(const char *path, void *buffer) { return __lxstat64(STAT_VERSION, path, buffer); }
int fstat64(int descriptor, void *buffer) { return __fxstat64(STAT_VERSION, descriptor, buffer); }
int fstat(int descriptor, void *buffer) { return __fxstat64(STAT_VERSION, descriptor, buffer); }
int fstatat64(int directory, const char *path, void *buffer, int flags) {
    return __fxstatat64(STAT_VERSION, directory, path, buffer, flags);
}
int fstatat(int directory, const char *path, void *buffer, int flags) {
    return __fxstatat64(STAT_VERSION, directory, path, buffer, flags);
}
