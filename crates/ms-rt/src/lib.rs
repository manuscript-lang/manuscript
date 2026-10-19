//! Manuscript native runtime.
#![cfg_attr(not(any(test, feature = "std", panic = "unwind")), no_std)]
#![allow(clippy::missing_safety_doc)]
// The runtime is the one place that owns raw memory for compiled code.
#![allow(unsafe_code)]
// Unit tests drive the C ABI directly; the lint guards the runtime itself.
#![cfg_attr(test, allow(clippy::undocumented_unsafe_blocks))]

extern crate alloc as stdalloc;
// Linked so its `msstd_math_*` exports ship in the runtime library.
extern crate ms_std_math;

pub mod alloc;
pub mod buf;
pub mod desc;
pub mod fault;
pub mod global;
pub mod io;
pub mod map;
pub mod num;
pub mod obj;
pub mod process;
pub mod profile;
pub mod start;
pub mod string;
pub mod sys;
pub mod utf8;
pub mod vec;

#[cfg(test)]
mod testutil;

#[cfg(not(any(test, feature = "std", panic = "unwind")))]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    crate::fault::fatal(b"internal runtime panic")
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
