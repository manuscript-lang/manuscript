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
// Linked so its `msstd_math_*` exports ship in the runtime library.
extern crate ms_std_fs;
extern crate ms_std_io;
extern crate ms_std_math;
extern crate ms_std_process;
extern crate ms_std_time;

pub mod alloc;
pub mod bits;
pub mod desc;
pub mod fault;
pub mod global;
pub mod io;
pub mod map;
pub mod num;
pub mod obj;
pub mod poller;
pub mod process;
pub mod profile;
pub mod queue;
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
pub mod utf8;
pub mod vec;

#[cfg(test)]
mod testutil;

#[cfg(test)]
mod std_natives;
