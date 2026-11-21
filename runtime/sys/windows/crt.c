/* A symbol the folded libuv expects from the C runtime.
 *
 * The MSYS2 libuv calls `_snwprintf_s`, which the UCRT headers inline over `__local_stdio_printf_options`; the
 * archive keeps a reference to that function, and the llvm-mingw link does not define it. This weak definition
 * is the one the headers would have made (a single options word), and a CRT that provides its own wins.
 * Remove it when the libuv build stops referencing the symbol (issue: Windows libuv needs __local_stdio_printf_options).
 */
#include <stdint.h>

#ifdef __GNUC__
__attribute__((weak))
#endif
uint64_t *__local_stdio_printf_options(void) {
    static uint64_t options;
    return &options;
}

/* Stack probes. The archive is linked without compiler-rt or libgcc, and the compiler calls a probe from the
 * prologue of a function whose frame spans more than a page, so each page of the new frame is touched in order
 * (the guard page then grows the stack). These are compiler-rt's chkstk routines, weak so a program that also
 * links a builtins library keeps working. x86-64 mingw calls `___chkstk_ms` (the size in rax, no stack
 * adjustment); arm64 calls `__chkstk` (the size divided by 16 in x15). */
#if defined(__x86_64__)
__asm__(".text\n"
        ".globl ___chkstk_ms\n"
        ".weak ___chkstk_ms\n"
        "___chkstk_ms:\n"
        "    push %rax\n"
        "    push %rcx\n"
        "    cmp $0x1000, %rax\n"
        "    lea 24(%rsp), %rcx\n"
        "    jb 1f\n"
        "2:\n"
        "    sub $0x1000, %rcx\n"
        "    test %rcx, (%rcx)\n"
        "    sub $0x1000, %rax\n"
        "    cmp $0x1000, %rax\n"
        "    ja 2b\n"
        "1:\n"
        "    sub %rax, %rcx\n"
        "    test %rcx, (%rcx)\n"
        "    pop %rcx\n"
        "    pop %rax\n"
        "    ret\n");
#elif defined(__aarch64__)
__asm__(".text\n"
        ".globl __chkstk\n"
        ".weak __chkstk\n"
        "__chkstk:\n"
        "    lsl x16, x15, #4\n"
        "    mov x17, sp\n"
        "1:\n"
        "    sub x17, x17, #4096\n"
        "    subs x16, x16, #4096\n"
        "    ldr xzr, [x17]\n"
        "    b.gt 1b\n"
        "    ret\n");
#endif
