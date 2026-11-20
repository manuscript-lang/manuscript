//! The scheduler's descriptor poller. A task parks on one descriptor at a time; each
//! registration is one-shot and level-like: registering an already-ready descriptor reports
//! it at once. The poller is the libuv reactor of the C runtime, in `poller_uv.rs`.

use crate::fault;
use core::mem::MaybeUninit;

/// A descriptor that became ready, with the `WAIT_*` bits it reports.
#[derive(Clone, Copy)]
#[repr(C)]
pub struct Ready {
    pub fd: usize,
    pub bits: u32,
}

/// What registering a descriptor came to.
pub enum Watch {
    Armed,
    /// The descriptor cannot be polled (a regular file): ready at once.
    Always,
    Failed,
}

#[path = "poller_uv.rs"]
mod imp;
pub use imp::{close, create, forget, kick, unwatch, wait, watch};
#[cfg(windows)]
pub use imp::{
    object_drop, object_watch, pipe_adopt, pipe_adopted, pipe_drop, pipe_group, pipe_read,
    pipe_write,
};
