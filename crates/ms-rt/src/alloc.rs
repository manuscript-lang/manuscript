//! The runtime's heap: size-class allocator and regions, one heap for the whole process. The allocator is C
//! (`runtime/core/alloc.c`); `c` is the thin binding and `std_heap` is Rust's global allocator over it.

/// The largest small block: a larger request goes to the system allocator and the large-block lists.
pub const MAX_SMALL: usize = 2048;
/// The largest block kept in a large free list.
pub(crate) const LARGE_MAX: usize = 16 << 20;

mod c;
mod std_heap;

pub use c::*;
pub use std_heap::*;
