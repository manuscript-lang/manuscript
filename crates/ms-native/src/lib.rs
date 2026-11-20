//! One static library for compiled programs.
//!
//! `ms-rt` exports the `msrt_*` runtime; the `msstd_*` natives are C in `runtime/`. A program links a
//! single archive, because a second Rust staticlib would repeat the Rust runtime's own symbols.
extern crate ms_rt;

mod heap;

/// Rust-side allocations of the native standard library share the runtime's allocator.
#[global_allocator]
static HEAP: heap::StdHeap = heap::StdHeap;
