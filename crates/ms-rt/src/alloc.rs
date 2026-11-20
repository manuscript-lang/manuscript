//! The runtime's heap: size-class allocator and regions, one heap for the whole process.
//!
//! The archive builds (`cargo xtask runtime`, `MS_C_RUNTIME`) use the C allocator in
//! `runtime/core/alloc.c`; `c` is the thin binding. `rust` is the original Rust implementation, kept
//! for `cargo test` and clippy until the Rust runtime is deleted (`runtime/symbols/alloc.txt` lists the
//! C symbols; the whole module switches on `msrt_alloc`). `std_heap` is Rust's global allocator over
//! either one.

/// The largest small block: a larger request goes to the system allocator and the large-block lists.
pub const MAX_SMALL: usize = 2048;
/// The largest block kept in a large free list.
pub(crate) const LARGE_MAX: usize = 16 << 20;

#[cfg(ms_c = "msrt_alloc")]
mod c;
#[cfg(not(ms_c = "msrt_alloc"))]
mod rust_heap;
mod std_heap;

#[cfg(ms_c = "msrt_alloc")]
pub use c::*;
#[cfg(not(ms_c = "msrt_alloc"))]
pub use rust_heap::*;
pub use std_heap::*;
