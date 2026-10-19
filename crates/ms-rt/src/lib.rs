//! Manuscript native runtime.
#![cfg_attr(not(any(test, feature = "std", panic = "unwind")), no_std)]
#![allow(clippy::missing_safety_doc)]
// The runtime is the one place that owns raw memory for compiled code.
#![allow(unsafe_code)]
// Unit tests drive the C ABI directly; the lint guards the runtime itself.
#![cfg_attr(test, allow(clippy::undocumented_unsafe_blocks))]

extern crate alloc as stdalloc;

/// Assembly symbol name for a C-visible function (Mach-O prefixes an underscore).
macro_rules! sym {
    ($n:literal) => {
        concat!(sym_prefix!(), $n)
    };
}
#[cfg(target_vendor = "apple")]
macro_rules! sym_prefix {
    () => {
        "_"
    };
}
#[cfg(not(target_vendor = "apple"))]
macro_rules! sym_prefix {
    () => {
        ""
    };
}
// Linked so its `msstd_math_*` exports ship in the runtime library.
extern crate ms_std_fs;
extern crate ms_std_io;
extern crate ms_std_math;
extern crate ms_std_process;
extern crate ms_std_time;

pub mod alloc;
pub mod bits;
pub mod buf;
pub mod desc;
pub mod fault;
pub mod global;
pub mod io;
pub mod map;
pub mod num;
pub mod obj;
pub mod poll;
pub mod process;
pub mod profile;
pub mod queue;
pub mod start;
pub mod string;
pub mod sys;
pub mod task;
pub mod trap;
pub mod utf8;
pub mod vec;

#[cfg(test)]
mod testutil;

#[cfg(test)]
mod std_natives;

#[cfg(not(any(test, feature = "std", panic = "unwind")))]
#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    use core::fmt::Write;
    // Fixed buffer: the panic may come from the allocator, so nothing here allocates.
    struct Buf([u8; 512], usize);
    impl Write for Buf {
        fn write_str(&mut self, s: &str) -> core::fmt::Result {
            let n = s.len().min(self.0.len() - self.1);
            self.0[self.1..self.1 + n].copy_from_slice(&s.as_bytes()[..n]);
            self.1 += n;
            Ok(())
        }
    }
    let mut b = Buf([0; 512], 0);
    let _ = b.write_str("internal runtime panic");
    if let Some(l) = info.location() {
        let _ = write!(b, " at {}:{}", l.file(), l.line());
    }
    let _ = write!(b, ": {}", info.message());
    crate::fault::fatal(&b.0[..b.1])
}

/// Rust allocations inside the runtime (only used by dependencies such as
/// Unicode normalization) share the runtime allocator.
#[cfg(not(any(test, feature = "std", panic = "unwind")))]
mod rust_alloc {
    use core::alloc::{GlobalAlloc, Layout};

    pub struct RtAlloc;

    // SAFETY: the runtime allocator returns 16-byte aligned blocks and is single threaded.
    unsafe impl GlobalAlloc for RtAlloc {
        unsafe fn alloc(&self, l: Layout) -> *mut u8 {
            crate::alloc::alloc(l.size().max(1))
        }
        unsafe fn dealloc(&self, p: *mut u8, _: Layout) {
            // SAFETY: `p` came from `alloc`.
            unsafe { crate::alloc::free(p) }
        }
        unsafe fn realloc(&self, p: *mut u8, _: Layout, n: usize) -> *mut u8 {
            // SAFETY: `p` came from `alloc`.
            unsafe { crate::alloc::realloc(p, n) }
        }
    }

    #[global_allocator]
    static GLOBAL: RtAlloc = RtAlloc;
}

/// Exported `extern "C-unwind"` functions reference the personality routine even
/// though the runtime aborts on panic and never unwinds; satisfy the linker.
#[cfg(not(any(test, feature = "std", panic = "unwind")))]
#[unsafe(no_mangle)]
pub extern "C" fn rust_eh_personality() {
    crate::fault::fatal(b"unexpected unwind")
}
