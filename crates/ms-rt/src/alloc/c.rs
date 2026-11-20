//! Binding to the C allocator (`runtime/core/alloc.c`), which the archive builds link. Every function
//! of the Rust allocator's interface forwards to its `msrt_*` symbol, so the rest of the runtime is
//! unchanged and one allocator serves programs, the runtime and Rust's global allocator.
unsafe extern "C-unwind" {
    pub fn msrt_alloc(size: usize) -> *mut u8;
    pub fn msrt_alloc_zeroed(size: usize) -> *mut u8;
    pub fn msrt_realloc(p: *mut u8, size: usize) -> *mut u8;
    pub fn msrt_free(p: *mut u8);
    fn msrt_heap_claim();
    fn msrt_heap_release();
    fn msrt_heap_has() -> u8;
    fn msrt_heap_usable_size(p: *mut u8) -> usize;
    fn msrt_heap_trim(p: *mut u8, new_size: usize) -> *mut u8;
    pub fn msrt_heap_stats(out: *mut i64);
    #[cfg(feature = "stats")]
    fn msrt_heap_requested_reset();
    #[cfg(feature = "stats")]
    fn msrt_heap_live_total() -> i64;
    #[cfg(feature = "stats")]
    fn msrt_heap_live_by_size(sizes: *mut usize, counts: *mut i64, capacity: usize) -> usize;
    #[cfg(all(test, not(feature = "stats")))]
    fn msalloc_live_blocks() -> i64;
    fn msrt_heap_requested(out: *mut u64);
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

/// [`realloc`] for a block that is shrinking and usually stays where it is.
///
/// # Safety
/// `p` is a live block from this allocator.
#[inline]
pub unsafe fn trim(p: *mut u8, new_size: usize) -> *mut u8 {
    // SAFETY: caller contract.
    unsafe { msrt_heap_trim(p, new_size) }
}

/// Usable size of a live block.
///
/// # Safety
/// `p` must be a live block from this allocator.
#[inline]
pub unsafe fn usable_size(p: *mut u8) -> usize {
    // SAFETY: caller contract.
    unsafe { msrt_heap_usable_size(p) }
}

/// Gives the calling thread a heap; threads that never call this use the system allocator.
pub fn claim_heap() {
    // SAFETY: no preconditions.
    unsafe { msrt_heap_claim() }
}

/// Hands the calling thread's heap to the next thread that claims one as its thread ends.
pub fn release_heap() {
    // SAFETY: no preconditions.
    unsafe { msrt_heap_release() }
}

/// Whether the calling thread has a heap.
#[inline]
pub fn has_heap() -> bool {
    // SAFETY: no preconditions.
    unsafe { msrt_heap_has() != 0 }
}

/// Small-block heap figures in bytes for the calling thread's heap: `[used, in_use_pages]`.
pub fn heap_stats() -> [i64; 2] {
    let mut out = [0i64; 2];
    // SAFETY: two writable words.
    unsafe { msrt_heap_stats(out.as_mut_ptr()) };
    out
}

/// `[allocations, bytes]` requested by the calling thread and by every thread that has finished.
pub fn requested() -> [u64; 2] {
    let mut out = [0u64; 2];
    // SAFETY: two writable words.
    unsafe { msrt_heap_requested(out.as_mut_ptr()) };
    out
}

/// Starts the `requested` counters over: called as the program's `main` begins, so the counts a gate reads
/// cover the program and not the runtime's own start-up records, which differ by platform.
#[cfg(feature = "stats")]
pub fn reset_requested() {
    // SAFETY: no preconditions.
    unsafe { msrt_heap_requested_reset() }
}

/// Live blocks of the whole process (the counting runtime).
#[cfg(feature = "stats")]
pub fn live_blocks() -> isize {
    // SAFETY: no preconditions.
    unsafe { msrt_heap_live_total() as isize }
}

/// Live blocks of the calling thread's heap (unit tests, which the C archive counts).
#[cfg(all(test, not(feature = "stats")))]
pub fn live_blocks() -> isize {
    // SAFETY: no preconditions.
    unsafe { msalloc_live_blocks() as isize }
}

/// `(block size, live count)` for each size class with a nonzero count; the size is 0 for large blocks.
#[cfg(feature = "stats")]
pub fn live_by_size() -> Vec<(usize, isize)> {
    let mut sizes = [0usize; 128];
    let mut counts = [0i64; 128];
    // SAFETY: both arrays hold `capacity` entries.
    let n = unsafe { msrt_heap_live_by_size(sizes.as_mut_ptr(), counts.as_mut_ptr(), sizes.len()) };
    (0..n).map(|i| (sizes[i], counts[i] as isize)).collect()
}
