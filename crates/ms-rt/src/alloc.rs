//! The runtime's heap: size-class allocator and regions, one heap for the whole process. The allocator is C
//! (`runtime/core/alloc.c`); `c` is the thin binding and `std_heap` is Rust's global allocator over it.

/// The largest block a collection counts as small.
pub const MAX_SMALL: usize = 2048;

mod c;
mod std_heap;

pub use c::*;
pub use std_heap::*;
