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
