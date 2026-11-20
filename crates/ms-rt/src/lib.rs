//! Manuscript native runtime.
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

pub mod alloc;
pub mod cancel;
pub mod desc;
/// The drop worklist is C (`runtime/core/dropq.c`); the fault module resets it through this.
#[cfg(not(test))]
pub mod dropq {
    unsafe extern "C" {
        fn msdrop_reset();
    }
    /// Only the non-test `guard_exit` calls this, so unit tests do not compile it.
    #[cfg(not(test))]
    pub(crate) fn reset() {
        // SAFETY: the state belongs to the calling thread.
        unsafe { msdrop_reset() }
    }
}
pub mod fault;
pub mod ffi;
pub mod global;
pub mod glue;
pub mod io;
pub mod isolate;
pub mod map;
#[cfg(any(test, all(target_os = "linux", target_env = "musl")))]
pub mod mem;
pub mod num;
pub mod obj;
pub mod poller;
pub mod process;
pub mod profile;
pub mod promise;
pub mod sched;
pub mod start;
pub mod string;
#[cfg(not(windows))]
pub mod sys;
#[cfg(windows)]
#[path = "sys_windows.rs"]
pub mod sys;
mod sys_c;
pub mod task;
pub mod vec;
pub mod watch;

#[cfg(test)]
mod model_tests;

#[cfg(test)]
mod testutil;
