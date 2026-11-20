//! The C runtime (runtime/) is the Manuscript runtime. This crate is what remains for the Rust natives of
//! `ms-std-net`: the ABI helpers of `ffi` and imports of the C scheduler. It goes away with `ms-std-net`.
#![allow(clippy::missing_safety_doc)]
// The runtime is the one place that owns raw memory for compiled code.
#![allow(unsafe_code)]
// Unit tests drive the C ABI directly; the lint guards the runtime itself.
#![cfg_attr(test, allow(clippy::undocumented_unsafe_blocks))]

extern crate alloc as stdalloc;

pub mod alloc;
pub mod desc;
pub mod fault;
pub mod ffi;
pub mod global;
pub mod glue;
pub mod isolate;
pub mod map;
pub mod num;
pub mod obj;
pub mod sched;
pub mod start;
pub mod string;
pub mod sys;
pub mod task;
pub mod vec;
pub mod watch;
