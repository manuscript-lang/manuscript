//! Rust's global allocator over the C heap (`runtime/core/alloc.c`, mimalloc).
// The allocator binding is the only unsafe code here.
#![allow(unsafe_code)]
use core::alloc::{GlobalAlloc, Layout};
use std::alloc::System;

unsafe extern "C-unwind" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_alloc_zeroed(size: usize) -> *mut u8;
    fn msrt_realloc(p: *mut u8, size: usize) -> *mut u8;
    fn msrt_free(p: *mut u8);
}

/// Rust's global allocator for compiled programs (installed on every platform).
///
/// The standard-library natives (`Vec`, `String`, `HashMap` inside `ms-std-*`) share the runtime's
/// heap, from any thread. Alignments above 16 go to the system allocator, and the layout tells
/// `dealloc` and `realloc` which one produced a block.
pub struct StdHeap;

// SAFETY: every block comes from the C heap (alignment up to 16) or from the system allocator
// (larger alignments), and the layout's alignment routes each later call to the same one.
unsafe impl GlobalAlloc for StdHeap {
    #[inline]
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        if layout.align() <= 16 {
            // SAFETY: any size is valid.
            unsafe { msrt_alloc(layout.size()) }
        } else {
            // SAFETY: forwarded.
            unsafe { System.alloc(layout) }
        }
    }

    #[inline]
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        if layout.align() <= 16 {
            // SAFETY: any size is valid.
            unsafe { msrt_alloc_zeroed(layout.size()) }
        } else {
            // SAFETY: forwarded.
            unsafe { System.alloc_zeroed(layout) }
        }
    }

    #[inline]
    unsafe fn dealloc(&self, p: *mut u8, layout: Layout) {
        // SAFETY: `p` came from the allocator that `layout.align()` selects.
        unsafe {
            if layout.align() <= 16 {
                msrt_free(p);
            } else {
                System.dealloc(p, layout);
            }
        }
    }

    #[inline]
    unsafe fn realloc(&self, p: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        // SAFETY: `p` came from the allocator that `layout.align()` selects.
        unsafe {
            if layout.align() <= 16 {
                msrt_realloc(p, new_size)
            } else {
                System.realloc(p, layout, new_size)
            }
        }
    }
}
