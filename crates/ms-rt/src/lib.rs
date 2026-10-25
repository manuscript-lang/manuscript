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
pub mod bits;
pub mod channel;
pub mod desc;
pub mod fault;
pub mod ffi;
pub mod global;
pub mod glue;
pub mod io;
pub mod map;
#[cfg(any(test, all(target_os = "linux", target_env = "musl")))]
pub mod mem;
pub mod num;
pub mod obj;
pub mod poller;
pub mod process;
pub mod profile;
pub mod scan;
pub mod scope;
pub mod start;
pub mod string;
#[cfg(not(windows))]
pub mod sys;
#[cfg(windows)]
#[path = "sys_windows.rs"]
pub mod sys;
pub mod task;
#[cfg(not(windows))]
pub mod trap;
#[cfg(windows)]
#[path = "trap_windows.rs"]
pub mod trap;
pub mod tree;
pub mod utf8;
pub mod vec;

#[cfg(test)]
mod model_tests;

#[cfg(test)]
mod testutil;
