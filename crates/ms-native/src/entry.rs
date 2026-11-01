//! Programs linked against the system glibc get no `crt1.o` (linking needs no C toolchain or `libc6-dev`),
//! so the archive defines the process entry: it passes `main` and the kernel's stack to glibc's
//! `__libc_start_main`, as glibc's own `start.S` does. glibc 2.34 and newer runs `.init_array` itself.
#![allow(unsafe_code)]

#[cfg(all(target_os = "linux", target_env = "gnu", target_arch = "x86_64"))]
core::arch::global_asm!(
    ".globl _start",
    ".type _start,@function",
    "_start:",
    "xor ebp, ebp",
    "mov r9, rdx",
    "pop rsi",
    "mov rdx, rsp",
    "and rsp, -16",
    "push rax",
    "push rsp",
    "xor r8d, r8d",
    "xor ecx, ecx",
    "lea rdi, [rip + main]",
    "call qword ptr [rip + __libc_start_main@GOTPCREL]",
    "hlt",
    ".size _start, .-_start",
);

#[cfg(all(target_os = "linux", target_env = "gnu", target_arch = "aarch64"))]
core::arch::global_asm!(
    ".globl _start",
    ".type _start,@function",
    "_start:",
    "mov x29, xzr",
    "mov x30, xzr",
    "mov x5, x0",
    // Seed the stack guard from the kernel's AT_RANDOM bytes (auxv entry 25), as glibc does, before
    // any protected function runs: skip argv and envp to the auxiliary vector and scan it.
    "ldr x7, [sp]",
    "add x8, sp, #8",
    "add x8, x8, x7, lsl #3",
    "add x8, x8, #8",
    ".Lskip_env:",
    "ldr x9, [x8], #8",
    "cbnz x9, .Lskip_env",
    ".Lscan_auxv:",
    "ldp x9, x10, [x8], #16",
    "cbz x9, .Lguard_done",
    "cmp x9, #25",
    "b.ne .Lscan_auxv",
    "ldr x10, [x10]",
    "and x10, x10, #0xffffffffffffff00",
    "adrp x11, __stack_chk_guard",
    "str x10, [x11, :lo12:__stack_chk_guard]",
    ".Lguard_done:",
    "ldr x1, [sp]",
    "add x2, sp, #8",
    "mov x6, sp",
    "adrp x0, :got:main",
    "ldr x0, [x0, :got_lo12:main]",
    "mov x3, xzr",
    "mov x4, xzr",
    "bl __libc_start_main",
    "bl abort",
    ".size _start, .-_start",
);

/// The canary that aarch64 C compilers read when they protect a stack frame. glibc keeps it in
/// `libc_nonshared.a`, which programs do not link (only `libc` and `libm`), so the process entry
/// defines it and seeds it above.
#[cfg(target_arch = "aarch64")]
#[unsafe(no_mangle)]
#[used]
pub static __stack_chk_guard: core::sync::atomic::AtomicUsize =
    core::sync::atomic::AtomicUsize::new(0);
