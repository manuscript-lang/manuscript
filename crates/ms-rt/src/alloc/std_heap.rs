//! Rust's global allocator over the runtime's heap, whichever implementation (Rust or C) is built.
use super::{
    LARGE_MAX, MAX_SMALL, alloc, alloc_zeroed, alloc_zeroed_cached, free, has_heap, large_request,
    owns, realloc, shared_put, shared_take,
};
#[cfg(windows)]
use crate::sys;

/// Rust's global allocator for compiled programs (installed by `ms-native` on every platform).
///
/// The standard-library natives (`Vec`, `String`, `HashMap` inside `ms-std-*`) then share the
/// runtime's size-class allocator instead of libc's, which is several times slower per call. Only
/// threads that claimed a heap (isolates) allocate from it; every other thread uses the system
/// allocator. A block any thread frees is routed to its page's owner.
pub struct StdHeap;

/// The system allocator behind [`StdHeap`]. The runtime's large blocks come from the C library's
/// `malloc` and return to its `free`, so a block must come from the same place on every platform.
/// Rust's `System` is `malloc` on Unix but `HeapAlloc` on Windows, so Windows uses the C library
/// directly for alignments it serves.
#[cfg(not(windows))]
use std::alloc::System as SysHeap;

#[cfg(windows)]
struct SysHeap;

#[cfg(windows)]
// SAFETY: C library `malloc`, `calloc`, `realloc` and `free` serve alignments up to 16; larger
// ones stay with `System`, and every call routes by the layout's alignment, so a block is
// released by the allocator that produced it.
unsafe impl core::alloc::GlobalAlloc for SysHeap {
    unsafe fn alloc(&self, l: core::alloc::Layout) -> *mut u8 {
        if l.align() <= 16 {
            // SAFETY: forwarded.
            unsafe { sys::malloc(l.size()).cast() }
        } else {
            // SAFETY: forwarded.
            unsafe { std::alloc::System.alloc(l) }
        }
    }
    unsafe fn alloc_zeroed(&self, l: core::alloc::Layout) -> *mut u8 {
        if l.align() <= 16 {
            // SAFETY: forwarded.
            unsafe { sys::calloc(1, l.size()).cast() }
        } else {
            // SAFETY: forwarded.
            unsafe { std::alloc::System.alloc_zeroed(l) }
        }
    }
    unsafe fn dealloc(&self, p: *mut u8, l: core::alloc::Layout) {
        if l.align() <= 16 {
            // SAFETY: forwarded.
            unsafe { sys::free(p.cast()) }
        } else {
            // SAFETY: forwarded.
            unsafe { std::alloc::System.dealloc(p, l) }
        }
    }
    unsafe fn realloc(&self, p: *mut u8, l: core::alloc::Layout, n: usize) -> *mut u8 {
        if l.align() <= 16 {
            // SAFETY: forwarded.
            unsafe { sys::realloc(p.cast(), n).cast() }
        } else {
            // SAFETY: forwarded.
            unsafe { std::alloc::System.realloc(p, l, n) }
        }
    }
}

mod impls {
    use super::{LARGE_MAX, MAX_SMALL, StdHeap, SysHeap as System, has_heap, owns};
    use core::alloc::{GlobalAlloc, Layout};

    /// Whether the heap may serve `layout` on this thread. Counting builds keep the standard
    /// library out of the heap so leak checks see only program allocations. Blocks outlive the
    /// thread that allocated them, so Rust code may keep them in process-wide state.
    #[inline(always)]
    fn heap_ok(layout: Layout) -> bool {
        !cfg!(feature = "stats") && layout.align() <= 16 && has_heap()
    }

    /// The size of a large request from a thread without a heap that the shared lists serve.
    #[inline(always)]
    fn shared_size(layout: Layout) -> Option<usize> {
        (layout.align() <= 16 && layout.size() > MAX_SMALL && layout.size() <= LARGE_MAX)
            .then_some(layout.size())
    }

    // SAFETY: blocks come from the heap or the system allocator, and `dealloc` and `realloc`
    // tell them apart by address, so each is released by the allocator that produced it.
    unsafe impl GlobalAlloc for StdHeap {
        #[inline]
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            #[cfg(feature = "stats")]
            super::rust_heap::add(1, layout.size() as isize);
            if heap_ok(layout) {
                super::alloc(layout.size())
            } else if let Some(size) = shared_size(layout) {
                let cached = super::shared_take(size);
                if !cached.is_null() {
                    return cached;
                }
                // SAFETY: forwarded; the size is rounded so that freeing files the block under
                // the class that the next request of this size reads.
                unsafe {
                    System.alloc(Layout::from_size_align_unchecked(
                        super::large_request(size),
                        16,
                    ))
                }
            } else {
                // SAFETY: forwarded.
                unsafe { System.alloc(layout) }
            }
        }

        #[inline]
        unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
            #[cfg(feature = "stats")]
            super::rust_heap::add(1, layout.size() as isize);
            if heap_ok(layout) {
                if layout.size() <= MAX_SMALL {
                    return super::alloc_zeroed(layout.size());
                }
                let cached = super::alloc_zeroed_cached(layout.size());
                if !cached.is_null() {
                    return cached;
                }
            }
            if let Some(size) = shared_size(layout) {
                let cached = super::shared_take(size);
                if !cached.is_null() {
                    // SAFETY: a cached block has at least `size` writable bytes.
                    unsafe { core::ptr::write_bytes(cached, 0, size) };
                    return cached;
                }
            }
            // SAFETY: forwarded; the system allocator hands out lazily zeroed pages for big blocks.
            // A request rounded to its class lands in the free list that the next request reads.
            unsafe {
                match Layout::from_size_align(super::large_request(layout.size()), layout.align()) {
                    Ok(rounded) if heap_ok(layout) || shared_size(layout).is_some() => {
                        System.alloc_zeroed(rounded)
                    }
                    _ => System.alloc_zeroed(layout),
                }
            }
        }

        #[inline]
        unsafe fn dealloc(&self, p: *mut u8, layout: Layout) {
            #[cfg(feature = "stats")]
            super::rust_heap::add(-1, -(layout.size() as isize));
            if owns(p) {
                // SAFETY: a heap block; `free` routes it to its owner.
                unsafe { super::free(p) };
            } else if layout.size() > MAX_SMALL && heap_ok(layout) {
                // SAFETY: a large block is a system block either way; the runtime keeps
                // freed ones for reuse, where the system allocator would unmap them and
                // fault the next block in again.
                unsafe { super::free(p) };
            } else {
                // SAFETY: not a heap block, so the system allocator produced it; a large one
                // is kept for the next thread without a heap to reuse.
                unsafe {
                    if shared_size(layout).is_none() || !super::shared_put(p) {
                        System.dealloc(p, layout);
                    }
                }
            }
        }

        unsafe fn realloc(&self, p: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
            #[cfg(feature = "stats")]
            super::rust_heap::add(0, new_size as isize - layout.size() as isize);
            let target = Layout::from_size_align(new_size, layout.align());
            let Ok(target) = target else {
                return core::ptr::null_mut();
            };
            if layout.align() <= 16 && (owns(p) || (heap_ok(layout) && new_size > MAX_SMALL)) {
                // SAFETY: `p` is a live block of this heap (small, growing, or a large system
                // block); `realloc` treats every block alike.
                return unsafe { super::realloc(p, new_size) };
            }
            if layout.align() <= 16 {
                // SAFETY: a system block stays with the system allocator.
                return unsafe { System.realloc(p, layout, new_size) };
            }
            // SAFETY: moves between allocators by copy; the old block is released by `dealloc`.
            unsafe {
                let q = self.alloc(target);
                if !q.is_null() {
                    core::ptr::copy_nonoverlapping(p, q, layout.size().min(new_size));
                    self.dealloc(p, layout);
                }
                q
            }
        }
    }
}

/// Counters of Rust's own heap (`Vec`, `Box`, `Rc` in the `ms-std-*` natives), which counting
/// builds keep apart from the runtime's blocks. A cancelled task that leaves such a value on a
/// skipped frame shows up as a live count above the uncancelled run (`make cancel-sweep`).
#[cfg(feature = "stats")]
pub(crate) mod rust_heap {
    use core::sync::atomic::{AtomicIsize, Ordering};

    static BLOCKS: AtomicIsize = AtomicIsize::new(0);
    static BYTES: AtomicIsize = AtomicIsize::new(0);

    pub(crate) fn add(blocks: isize, bytes: isize) {
        BLOCKS.fetch_add(blocks, Ordering::Relaxed);
        BYTES.fetch_add(bytes, Ordering::Relaxed);
    }

    /// Live Rust heap blocks and bytes.
    pub fn live() -> (isize, isize) {
        (
            BLOCKS.load(Ordering::Relaxed),
            BYTES.load(Ordering::Relaxed),
        )
    }
}

#[cfg(feature = "stats")]
pub use rust_heap::live as rust_heap_live;
