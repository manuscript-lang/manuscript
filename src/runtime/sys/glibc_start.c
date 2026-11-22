/* The process entry for programs linked against the glibc 2.28 stubs, which come without `crt1.o`: `_start` hands
 * `main`, an `.init_array` runner and the kernel's stack to glibc's `__libc_start_main`, as glibc's own `start.S`
 * does. glibc 2.34 and newer still calls a non-null `init`, so the runner works on both. `fini` stays null: the
 * loader runs the executable's `.fini_array`. Linked into programs only (see glibc_stat.c). */
#include <stddef.h>
#include <stdlib.h>

typedef void (*MsInit)(int argc, char **argv, char **envp);

extern MsInit __init_array_start[]; // NOLINT(bugprone-reserved-identifier): the linker's bounds
extern MsInit __init_array_end[];   // NOLINT(bugprone-reserved-identifier)

/* Runs the executable's constructors, each once with the process arguments. */
void ms_glibc_run_init_array(int argc, char **argv, char **envp);
void ms_glibc_run_init_array(int argc, char **argv, char **envp) {
  for (MsInit *at = __init_array_start; at < __init_array_end; at++) {
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
        "lea ms_glibc_run_init_array(%rip), %rcx\n"
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
        "adrp x3, ms_glibc_run_init_array\n"
        "add x3, x3, :lo12:ms_glibc_run_init_array\n"
        "mov x4, xzr\n"
        "bl __libc_start_main\n"
        "bl abort\n"
        ".size _start, .-_start\n");
#endif

/* `atexit`, which glibc 2.28 supplies from `libc_nonshared.a` over `__cxa_atexit`; a null handle names the program. */
extern int __cxa_atexit(void (*function)(void *), void *argument, void *handle); // NOLINT(bugprone-reserved-identifier)

int atexit(void (*function)(void)) {
  return __cxa_atexit((void (*)(void *))function, NULL, NULL);
}
