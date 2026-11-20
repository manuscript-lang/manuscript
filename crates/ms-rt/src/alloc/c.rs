//! Binding to the C allocator (`runtime/core/alloc.c`), which the archive builds link. Every function
//! of the Rust allocator's interface forwards to its `msrt_*` symbol, so the rest of the runtime is
//! unchanged and one allocator serves programs, the runtime and Rust's global allocator.
unsafe extern "C-unwind" {
    pub fn msrt_alloc(size: usize) -> *mut u8;
    pub fn msrt_alloc_zeroed(size: usize) -> *mut u8;
    pub fn msrt_realloc(p: *mut u8, size: usize) -> *mut u8;
    pub fn msrt_free(p: *mut u8);
    pub fn msrt_heap_stats(out: *mut i64);
}

/// Called by the C allocator when the system cannot give a block.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msalloc_rust_oom(bytes: usize) -> ! {
    crate::fault::out_of_memory(bytes)
}

/// Allocates `size` bytes (16-byte aligned, uninitialised). Faults on exhaustion.
#[inline]
pub fn alloc(size: usize) -> *mut u8 {
    // SAFETY: any size is valid.
    unsafe { msrt_alloc(size) }
}

/// Allocates zeroed memory.
#[inline]
pub fn alloc_zeroed(size: usize) -> *mut u8 {
    // SAFETY: any size is valid.
    unsafe { msrt_alloc_zeroed(size) }
}

/// Frees a block returned by [`alloc`] or [`realloc`] on any thread. Null is ignored.
///
/// # Safety
/// `p` must be null or a live block from this allocator.
#[inline]
pub unsafe fn free(p: *mut u8) {
    // SAFETY: caller contract.
    unsafe { msrt_free(p) }
}

/// Resizes a block, preserving the common prefix.
///
/// # Safety
/// `p` must be null or a live block from this allocator.
#[inline]
pub unsafe fn realloc(p: *mut u8, new_size: usize) -> *mut u8 {
    // SAFETY: caller contract.
    unsafe { msrt_realloc(p, new_size) }
}
