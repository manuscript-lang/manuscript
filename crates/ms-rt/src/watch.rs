//! The watcher that told one scheduler thread to hand connections to another. The C scheduler places work
//! itself, so these are inert: a thread never reads as held up, and `ms-std-net` shares nothing between threads
//! (see `may_share`). Goes away with `ms-std-net`.

/// One look of the watcher at the threads.
#[derive(Clone, Copy, Debug)]
pub struct Look {
    pub now: u64,
    pub last: u64,
}

pub type Hook = fn(Look, u64) -> bool;

/// The watcher's tick count; it never advances.
pub fn epoch() -> u64 {
    0
}

/// Registers a hook the watcher would call each tick; nothing calls it.
pub fn add_hook(_hook: Hook) {}

/// The tick at which `thread` last woke.
pub fn stirred(_thread: usize) -> u64 {
    0
}
