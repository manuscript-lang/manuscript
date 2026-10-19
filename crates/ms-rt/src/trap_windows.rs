//! Catching a programming fault on Windows, which cannot fork.
//!
//! `msrt_trap_begin` behaves like `setjmp`: it saves the callee-saved registers, the stack
//! pointer and its return address, and returns 0. The operation runs in the caller's frame. When
//! it returns, `msrt_trap_end` restores the registers and `msrt_trap_begin` returns again, with 1;
//! when it faults, the guard machinery does the same through `leave` after running the cleanups
//! registered inside the operation. `msrt_trap_wait` then reports whether it faulted and the first
//! line of the report. Unlike the forked child on Unix, the operation's side effects (memory,
//! open files) stay in this process.

use crate::buf::ByteBuf;
use crate::fault;
use crate::global::Global;
use crate::string;
use ms_rt_abi::StrObj;

/// Registers saved by `msrt_trap_begin`: callee-saved integer and vector registers, the stack
/// pointer and the return address (30 words on x64, 21 on arm64).
static BUF: Global<[usize; 32]> = Global::new([0; 32]);
/// Whether the operation faulted, and the report it produced.
static FAULTED: Global<bool> = Global::new(false);
static REPORT: Global<ByteBuf> = Global::new(ByteBuf::new());

extern "C" fn prepare() {
    crate::io::flush_stdout();
    // SAFETY: single threaded runtime state.
    unsafe {
        *FAULTED.ptr() = false;
        (*REPORT.ptr()).clear();
        fault::push_trap_guard((*BUF.ptr()).as_mut_ptr());
    }
}

unsafe extern "C" {
    /// Resumes after `msrt_trap_begin` with its second return (the value 1).
    fn msrt_trap_restore(buf: *mut usize, status: usize) -> !;
}

// Windows x64: arguments in rcx and rdx, 32 bytes of shadow space at calls, rdi, rsi and
// xmm6-xmm15 callee-saved.
#[cfg(target_arch = "x86_64")]
core::arch::global_asm!(
    ".text",
    concat!(".globl ", sym!("msrt_trap_begin")),
    concat!(sym!("msrt_trap_begin"), ":"),
    "sub rsp, 40",
    "call {prepare}",
    "add rsp, 40",
    "lea rcx, [rip + {buf}]",
    "mov [rcx], rbx",
    "mov [rcx + 8], rbp",
    "mov [rcx + 16], rdi",
    "mov [rcx + 24], rsi",
    "mov [rcx + 32], r12",
    "mov [rcx + 40], r13",
    "mov [rcx + 48], r14",
    "mov [rcx + 56], r15",
    "lea rax, [rsp + 8]",
    "mov [rcx + 64], rax",
    "mov rax, [rsp]",
    "mov [rcx + 72], rax",
    "movups [rcx + 80], xmm6",
    "movups [rcx + 96], xmm7",
    "movups [rcx + 112], xmm8",
    "movups [rcx + 128], xmm9",
    "movups [rcx + 144], xmm10",
    "movups [rcx + 160], xmm11",
    "movups [rcx + 176], xmm12",
    "movups [rcx + 192], xmm13",
    "movups [rcx + 208], xmm14",
    "movups [rcx + 224], xmm15",
    "xor eax, eax",
    "ret",
    concat!(".globl ", sym!("msrt_trap_restore")),
    concat!(sym!("msrt_trap_restore"), ":"),
    "mov rbx, [rcx]",
    "mov rbp, [rcx + 8]",
    "mov rdi, [rcx + 16]",
    "mov rsi, [rcx + 24]",
    "mov r12, [rcx + 32]",
    "mov r13, [rcx + 40]",
    "mov r14, [rcx + 48]",
    "mov r15, [rcx + 56]",
    "movups xmm6, [rcx + 80]",
    "movups xmm7, [rcx + 96]",
    "movups xmm8, [rcx + 112]",
    "movups xmm9, [rcx + 128]",
    "movups xmm10, [rcx + 144]",
    "movups xmm11, [rcx + 160]",
    "movups xmm12, [rcx + 176]",
    "movups xmm13, [rcx + 192]",
    "movups xmm14, [rcx + 208]",
    "movups xmm15, [rcx + 224]",
    "mov rsp, [rcx + 64]",
    "mov rax, rdx",
    "jmp [rcx + 72]",
    prepare = sym prepare,
    buf = sym BUF,
);

#[cfg(target_arch = "aarch64")]
core::arch::global_asm!(
    ".text",
    concat!(".globl ", sym!("msrt_trap_begin")),
    concat!(sym!("msrt_trap_begin"), ":"),
    "stp x29, x30, [sp, #-16]!",
    "bl {prepare}",
    "ldp x29, x30, [sp], #16",
    "adrp x1, {buf}",
    "add x1, x1, :lo12:{buf}",
    "stp x19, x20, [x1, #0]",
    "stp x21, x22, [x1, #16]",
    "stp x23, x24, [x1, #32]",
    "stp x25, x26, [x1, #48]",
    "stp x27, x28, [x1, #64]",
    "stp x29, x30, [x1, #80]",
    "mov x2, sp",
    "str x2, [x1, #96]",
    "stp d8, d9, [x1, #104]",
    "stp d10, d11, [x1, #120]",
    "stp d12, d13, [x1, #136]",
    "stp d14, d15, [x1, #152]",
    "mov x0, #0",
    "ret",
    concat!(".globl ", sym!("msrt_trap_restore")),
    concat!(sym!("msrt_trap_restore"), ":"),
    "mov x2, x0",
    "ldp x19, x20, [x2, #0]",
    "ldp x21, x22, [x2, #16]",
    "ldp x23, x24, [x2, #32]",
    "ldp x25, x26, [x2, #48]",
    "ldp x27, x28, [x2, #64]",
    "ldp x29, x30, [x2, #80]",
    "ldp d8, d9, [x2, #104]",
    "ldp d10, d11, [x2, #120]",
    "ldp d12, d13, [x2, #136]",
    "ldp d14, d15, [x2, #152]",
    "ldr x3, [x2, #96]",
    "mov sp, x3",
    "mov x0, x1",
    "ret",
    prepare = sym prepare,
    buf = sym BUF,
);

/// Leaves the operation when a fault (or a stop request) ends it inside the guard.
///
/// # Safety
/// `buf` is the buffer `msrt_trap_begin` filled, whose caller frame is still live.
pub(crate) unsafe fn leave(buf: *mut usize, faulted: bool, message: &[u8]) -> ! {
    // SAFETY: single threaded runtime state.
    unsafe {
        *FAULTED.ptr() = faulted;
        if faulted {
            (*REPORT.ptr()).extend(message);
        }
        msrt_trap_restore(buf, 1)
    }
}

/// Ends the operation after it returned without a fault; execution continues after
/// `msrt_trap_begin` with its second return.
#[unsafe(no_mangle)]
pub extern "C" fn msrt_trap_end() -> ! {
    crate::io::flush_stdout();
    // SAFETY: single threaded runtime state; the frame of `msrt_trap_begin`'s caller is live.
    unsafe {
        fault::pop_trap_guard();
        *FAULTED.ptr() = false;
        msrt_trap_restore((*BUF.ptr()).as_mut_ptr(), 1)
    }
}

/// Reports whether the operation faulted (the message is written to `out`).
///
/// # Safety
/// `out` must be writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_trap_wait(out: *mut *mut StrObj) -> u8 {
    // SAFETY: single threaded runtime state; `out` is writable.
    unsafe {
        if !*FAULTED.ptr() {
            return 0;
        }
        let text = (*REPORT.ptr()).as_slice();
        let line = text.split(|b| *b == b'\n').next().unwrap_or(text);
        *out = string::from_bytes(line);
        1
    }
}
