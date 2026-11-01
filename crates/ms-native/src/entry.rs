//! Programs link against stubs of glibc 2.28 and get no `crt1.o` or `libc_nonshared.a` (linking needs no
//! C toolchain or `libc6-dev`), so the archive supplies what those would: the process entry, which passes
//! `main`, an `.init_array` runner and the kernel's stack to glibc's `__libc_start_main` as glibc's own
//! `start.S` does, and the `stat` family, which glibc before 2.33 provides only as wrappers over
//! `__xstat64` and friends. glibc 2.34 and newer still calls a non-null `init` (`csu/libc-start.c`).
#![allow(unsafe_code)]

use core::ffi::{c_char, c_int, c_void};

type Init = unsafe extern "C" fn(c_int, *mut *mut c_char, *mut *mut c_char);

unsafe extern "C" {
    static __init_array_start: [Init; 0];
    static __init_array_end: [Init; 0];
}

/// Runs the executable's `.init_array` (Rust `std` records the arguments there). glibc runs the
/// loaded libraries' own; `fini` stays null because the loader runs the executable's `.fini_array`.
unsafe extern "C" fn run_init_array(argc: c_int, argv: *mut *mut c_char, envp: *mut *mut c_char) {
    // SAFETY: the linker bounds the array of constructors, each called once with the process arguments.
    unsafe {
        let mut at = (&raw const __init_array_start).cast::<Init>();
        let end = (&raw const __init_array_end).cast::<Init>();
        while at < end {
            (*at)(argc, argv, envp);
            at = at.add(1);
        }
    }
}

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
    "lea rcx, [rip + {init}]",
    "lea rdi, [rip + main]",
    "call qword ptr [rip + __libc_start_main@GOTPCREL]",
    "hlt",
    ".size _start, .-_start",
    init = sym run_init_array,
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
    "adrp x3, {init}",
    "add x3, x3, :lo12:{init}",
    "mov x4, xzr",
    "bl __libc_start_main",
    "bl abort",
    ".size _start, .-_start",
    init = sym run_init_array,
);

/// The `_STAT_VER` that glibc's `__xstat64` family takes: the kernel's `struct stat` layout.
#[cfg(target_arch = "x86_64")]
const STAT_VER: c_int = 1;
#[cfg(target_arch = "aarch64")]
const STAT_VER: c_int = 0;

unsafe extern "C" {
    fn __xstat64(ver: c_int, path: *const c_char, buf: *mut c_void) -> c_int;
    fn __lxstat64(ver: c_int, path: *const c_char, buf: *mut c_void) -> c_int;
    fn __fxstat64(ver: c_int, fd: c_int, buf: *mut c_void) -> c_int;
    fn __fxstatat64(
        ver: c_int,
        dir: c_int,
        path: *const c_char,
        buf: *mut c_void,
        flags: c_int,
    ) -> c_int;
}

/// Defines `stat64` and its plain-named twin (the same layout on 64-bit Linux, for objects passed with
/// `--link`) over the versioned glibc call, as `libc_nonshared.a` does.
macro_rules! stat_wrappers {
    ($($name:ident, $twin:ident ($($arg:ident: $ty:ty),*) => $call:ident;)*) => {$(
        #[unsafe(no_mangle)]
        unsafe extern "C" fn $name($($arg: $ty),*) -> c_int {
            // SAFETY: the caller's arguments pass through unchanged.
            unsafe { $call(STAT_VER, $($arg),*) }
        }
        #[unsafe(no_mangle)]
        unsafe extern "C" fn $twin($($arg: $ty),*) -> c_int {
            // SAFETY: as above.
            unsafe { $call(STAT_VER, $($arg),*) }
        }
    )*};
}

stat_wrappers! {
    stat64, stat(path: *const c_char, buf: *mut c_void) => __xstat64;
    lstat64, lstat(path: *const c_char, buf: *mut c_void) => __lxstat64;
    fstat64, fstat(fd: c_int, buf: *mut c_void) => __fxstat64;
    fstatat64, fstatat(dir: c_int, path: *const c_char, buf: *mut c_void, flags: c_int) => __fxstatat64;
}
