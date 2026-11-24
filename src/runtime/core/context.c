/* Stack switching for tasks: one assembly block per target, and the C that builds a first frame.
 * See context.h. Owns no memory.
 *
 * Every block saves exactly the callee-saved registers of its calling convention, so the compiler treats a
 * switch as an ordinary call:
 *  - x86-64 System V: rbp rbx r12-r15. Windows x64 adds rdi rsi xmm6-xmm15 and wants 32 bytes of shadow space.
 *  - AArch64 (Linux, Apple, Windows): x19-x28 x29 x30 d8-d15.
 * A new stack starts in a trampoline that calls the entry function kept in a callee-saved register of the
 * initial frame, so the assembly names no C symbol (a symbol needs a different prefix on each object format).
 */
#include "runtime/core/context.h"

#if defined(__APPLE__)
#define MS_SYM(name) "_" #name
#else
#define MS_SYM(name) #name
#endif

/* x86-64 System V (Linux, macOS). Arguments: rdi rsi rdx rcx. */
#if defined(__x86_64__) && !defined(_WIN32)

__asm__(".text\n"
        ".globl " MS_SYM(ms_ctx_switch) "\n"
        ".globl " MS_SYM(ms_ctx_trampoline) "\n"
        ".globl " MS_SYM(ms_ctx_call_on_stack) "\n"
        MS_SYM(ms_ctx_switch) ":\n"
        "  push %rbp\n  push %rbx\n  push %r12\n  push %r13\n  push %r14\n  push %r15\n"
        "  mov %rsp, (%rdi)\n"
        "  mov %rsi, %rsp\n"
        "  pop %r15\n  pop %r14\n  pop %r13\n  pop %r12\n  pop %rbx\n  pop %rbp\n"
        "  ret\n"
        MS_SYM(ms_ctx_trampoline) ":\n"
        "  xor %ebp, %ebp\n"
        "  call *%r12\n"
        "  ud2\n"
        MS_SYM(ms_ctx_call_on_stack) ":\n"
        "  .cfi_startproc\n"
        "  push %rbp\n"
        "  .cfi_def_cfa_offset 16\n"
        "  .cfi_offset %rbp, -16\n"
        "  mov %rsp, %rbp\n"
        "  .cfi_def_cfa_register %rbp\n"
        "  mov %rsp, (%rcx)\n"
        "  mov %rdi, %rsp\n"
        "  mov %rdx, %rdi\n"
        "  call *%rsi\n"
        "  mov %rbp, %rsp\n"
        "  pop %rbp\n"
        "  .cfi_def_cfa %rsp, 8\n"
        "  ret\n"
        "  .cfi_endproc\n");

/* Initial frame: six saved registers (r15 r14 r13 r12 rbx rbp) then the return address. `ret` leaves the
 * stack pointer at `top`, so the trampoline's call sees the ABI alignment. Entry travels in r12. */
uintptr_t ms_ctx_initial_sp(uint8_t *top, MsCtxEntry entry) {
    extern void ms_ctx_trampoline(void);
    enum { SAVED_WORDS = 6, R12_WORD = 3, FRAME_WORDS = SAVED_WORDS + 1 };
    uintptr_t frame[FRAME_WORDS] = {0};
    frame[R12_WORD] = (uintptr_t)entry;
    frame[SAVED_WORDS] = (uintptr_t)ms_ctx_trampoline;
    uint8_t *const start = top - sizeof frame;
    __builtin_memcpy(start, frame, sizeof frame);
    return (uintptr_t)start;
}

/* Windows x64. Arguments: rcx rdx r8 r9, then the stack; 32 bytes of shadow space at every call. A switch
 * installs the TEB stack words of the stack it enters right after the stack pointer moves: earlier, the saves
 * on the old stack could touch its guard page while the TEB describes another stack. */
#elif defined(__x86_64__) && defined(_WIN32)

__asm__(".text\n"
        ".globl ms_ctx_switch\n"
        ".globl ms_ctx_trampoline\n"
        ".globl ms_ctx_call_on_stack\n"
        "ms_ctx_switch:\n"
        "  push %rbp\n  push %rbx\n  push %rdi\n  push %rsi\n  push %r12\n  push %r13\n  push %r14\n  push %r15\n"
        "  sub $160, %rsp\n"
        "  movups %xmm6, 0(%rsp)\n  movups %xmm7, 16(%rsp)\n  movups %xmm8, 32(%rsp)\n"
        "  movups %xmm9, 48(%rsp)\n  movups %xmm10, 64(%rsp)\n  movups %xmm11, 80(%rsp)\n"
        "  movups %xmm12, 96(%rsp)\n  movups %xmm13, 112(%rsp)\n  movups %xmm14, 128(%rsp)\n"
        "  movups %xmm15, 144(%rsp)\n"
        "  mov %rsp, (%rcx)\n"
        "  mov %rdx, %rsp\n"
        "  mov (%r8), %rax\n  mov %rax, %gs:0x08\n"
        "  mov 8(%r8), %rax\n  mov %rax, %gs:0x10\n"
        "  mov 16(%r8), %rax\n  mov %rax, %gs:0x1478\n"
        "  movups 0(%rsp), %xmm6\n  movups 16(%rsp), %xmm7\n  movups 32(%rsp), %xmm8\n"
        "  movups 48(%rsp), %xmm9\n  movups 64(%rsp), %xmm10\n  movups 80(%rsp), %xmm11\n"
        "  movups 96(%rsp), %xmm12\n  movups 112(%rsp), %xmm13\n  movups 128(%rsp), %xmm14\n"
        "  movups 144(%rsp), %xmm15\n"
        "  add $160, %rsp\n"
        "  pop %r15\n  pop %r14\n  pop %r13\n  pop %r12\n  pop %rsi\n  pop %rdi\n  pop %rbx\n  pop %rbp\n"
        "  ret\n"
        "ms_ctx_trampoline:\n"
        "  xor %ebp, %ebp\n"
        "  sub $32, %rsp\n"
        "  call *%r12\n"
        "  ud2\n"
        /* The fifth argument (teb) is the first stack argument: [rbp + 48] once rbp is pushed. */
        "ms_ctx_call_on_stack:\n"
        "  push %rbp\n"
        "  mov %rsp, %rbp\n"
        "  mov %rsp, (%r9)\n"
        "  mov %rcx, %rsp\n"
        "  mov 48(%rbp), %rax\n"
        "  mov (%rax), %r10\n  mov %r10, %gs:0x08\n"
        "  mov 8(%rax), %r10\n  mov %r10, %gs:0x10\n"
        "  mov 16(%rax), %r10\n  mov %r10, %gs:0x1478\n"
        "  sub $32, %rsp\n"
        "  mov %r8, %rcx\n"
        "  call *%rdx\n"
        "  mov %rbp, %rsp\n"
        "  mov 48(%rbp), %rax\n"
        "  mov 24(%rax), %r10\n  mov %r10, %gs:0x08\n"
        "  mov 32(%rax), %r10\n  mov %r10, %gs:0x10\n"
        "  mov 40(%rax), %r10\n  mov %r10, %gs:0x1478\n"
        "  pop %rbp\n"
        "  ret\n");

/* Ten vector registers (160 bytes), eight saved registers (r15 r14 r13 r12 rsi rdi rbx rbp), the return
 * address. Entry travels in r12. */
uintptr_t ms_ctx_initial_sp(uint8_t *top, MsCtxEntry entry) {
    extern void ms_ctx_trampoline(void);
    enum { VECTOR_WORDS = 20, SAVED_WORDS = 8, R12_WORD = VECTOR_WORDS + 3, FRAME_WORDS = VECTOR_WORDS + SAVED_WORDS + 1 };
    uintptr_t frame[FRAME_WORDS] = {0};
    frame[R12_WORD] = (uintptr_t)entry;
    frame[FRAME_WORDS - 1] = (uintptr_t)ms_ctx_trampoline;
    uint8_t *const start = top - sizeof frame;
    __builtin_memcpy(start, frame, sizeof frame);
    return (uintptr_t)start;
}

/* AArch64: Linux, macOS and Windows share the callee-saved set. Windows (x18 is the TEB) installs the stack
 * words from x2 after a switch or jump, and in ms_ctx_call_on_stack from x4 (kept in the frame). */
#elif defined(__aarch64__)

#if defined(_WIN32)
#define MS_A64_INSTALL_X2 \
    "  ldr x3, [x2]\n  str x3, [x18, #0x08]\n  ldr x3, [x2, #8]\n  str x3, [x18, #0x10]\n" \
    "  ldr x3, [x2, #16]\n  str x3, [x18, #0x1478]\n"
#define MS_A64_ENTER_X4 \
    "  ldr x9, [x4]\n  str x9, [x18, #0x08]\n  ldr x9, [x4, #8]\n  str x9, [x18, #0x10]\n" \
    "  ldr x9, [x4, #16]\n  str x9, [x18, #0x1478]\n"
#define MS_A64_LEAVE \
    "  ldr x9, [sp, #16]\n  ldr x10, [x9, #24]\n  str x10, [x18, #0x08]\n  ldr x10, [x9, #32]\n" \
    "  str x10, [x18, #0x10]\n  ldr x10, [x9, #40]\n  str x10, [x18, #0x1478]\n"
#else
#define MS_A64_INSTALL_X2 ""
#define MS_A64_ENTER_X4 ""
#define MS_A64_LEAVE ""
#endif

#define MS_A64_SAVE \
    "  sub sp, sp, #160\n" \
    "  stp x29, x30, [sp, #0]\n  stp x19, x20, [sp, #16]\n  stp x21, x22, [sp, #32]\n" \
    "  stp x23, x24, [sp, #48]\n  stp x25, x26, [sp, #64]\n  stp x27, x28, [sp, #80]\n" \
    "  stp d8, d9, [sp, #96]\n  stp d10, d11, [sp, #112]\n  stp d12, d13, [sp, #128]\n" \
    "  stp d14, d15, [sp, #144]\n"
#define MS_A64_RESTORE \
    "  ldp x29, x30, [sp, #0]\n  ldp x19, x20, [sp, #16]\n  ldp x21, x22, [sp, #32]\n" \
    "  ldp x23, x24, [sp, #48]\n  ldp x25, x26, [sp, #64]\n  ldp x27, x28, [sp, #80]\n" \
    "  ldp d8, d9, [sp, #96]\n  ldp d10, d11, [sp, #112]\n  ldp d12, d13, [sp, #128]\n" \
    "  ldp d14, d15, [sp, #144]\n  add sp, sp, #160\n"

__asm__(".text\n"
        ".globl " MS_SYM(ms_ctx_switch) "\n"
        ".globl " MS_SYM(ms_ctx_trampoline) "\n"
        ".globl " MS_SYM(ms_ctx_call_on_stack) "\n"
        MS_SYM(ms_ctx_switch) ":\n"
        MS_A64_SAVE
        "  mov x3, sp\n"
        "  str x3, [x0]\n"
        "  mov sp, x1\n"
        MS_A64_INSTALL_X2
        MS_A64_RESTORE
        "  ret\n"
        MS_SYM(ms_ctx_trampoline) ":\n"
        "  mov x29, #0\n"
        "  blr x19\n"
        "  brk #0\n"
        MS_SYM(ms_ctx_call_on_stack) ":\n"
        "  .cfi_startproc\n"
        "  stp x29, x30, [sp, #-32]!\n"
        "  .cfi_def_cfa_offset 32\n"
        "  .cfi_offset x29, -32\n"
        "  .cfi_offset x30, -24\n"
        "  str x4, [sp, #16]\n"
        "  mov x29, sp\n"
        "  .cfi_def_cfa_register x29\n"
        "  mov x9, sp\n"
        "  str x9, [x3]\n"
        "  mov sp, x0\n"
        MS_A64_ENTER_X4
        "  mov x0, x2\n"
        "  blr x1\n"
        "  mov sp, x29\n"
        MS_A64_LEAVE
        "  ldp x29, x30, [sp], #32\n"
        "  .cfi_def_cfa sp, 0\n"
        "  ret\n"
        "  .cfi_endproc\n");

/* The frame ms_ctx_switch restores: x29 x30 at the bottom, then x19-x28 and d8-d15. Entry travels in x19. */
uintptr_t ms_ctx_initial_sp(uint8_t *top, MsCtxEntry entry) {
    extern void ms_ctx_trampoline(void);
    enum { FRAME_WORDS = 20, LINK_WORD = 1, X19_WORD = 2 };
    uintptr_t frame[FRAME_WORDS] = {0};
    frame[X19_WORD] = (uintptr_t)entry;
    frame[LINK_WORD] = (uintptr_t)ms_ctx_trampoline;
    uint8_t *const start = top - sizeof frame;
    __builtin_memcpy(start, frame, sizeof frame);
    return (uintptr_t)start;
}

#else
#error "src/runtime/core/context.c: tasks need an assembly switch for this target (x86-64 or AArch64)"
#endif

/* The three TEB stack words: Windows keeps them at gs:[0x08], gs:[0x10] and gs:[0x1478] (x86-64), or at the same
 * offsets from x18 (AArch64). */
void ms_ctx_teb_stack(uintptr_t out[MS_CTX_TEB_WORDS]) {
    out[0] = 0;
    out[1] = 0;
    out[2] = 0;
#if defined(_WIN32) && defined(__x86_64__)
    __asm__ volatile("movq %%gs:0x08, %0" : "=r"(out[0]));
    __asm__ volatile("movq %%gs:0x10, %0" : "=r"(out[1]));
    __asm__ volatile("movq %%gs:0x1478, %0" : "=r"(out[2]));
#elif defined(_WIN32) && defined(__aarch64__)
    __asm__ volatile("ldr %0, [x18, #0x08]" : "=r"(out[0]));
    __asm__ volatile("ldr %0, [x18, #0x10]" : "=r"(out[1]));
    __asm__ volatile("ldr %0, [x18, #0x1478]" : "=r"(out[2]));
#endif
}
