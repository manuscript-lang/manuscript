//! Size-class allocator.
//!
//! Small blocks (up to [`MAX_SMALL`] bytes) come from 64 KiB pages carved out of
//! one large lazily-committed reservation; each page serves a single size class
//! and the page's class is recorded in a side table, so `free` needs no size.
//! Large blocks go to the system allocator, with freed blocks up to [`LARGE_MAX`] kept in
//! per-size free lists so growing and rebuilding big lists does not map and unmap memory
//! (musl's malloc does a `mmap`/`munmap` pair for every block above a few KiB). Single
//! threaded: no locks.
use crate::global::Global;
use crate::sys;
use core::ptr::null_mut;

pub const MAX_SMALL: usize = 2048;
const PAGE_SHIFT: usize = 16;
const PAGE_SIZE: usize = 1 << PAGE_SHIFT;
const ARENA_SIZE: usize = if cfg!(miri) { 64 << 20 } else { 16 << 30 };
/// Arena growth step where memory is committed explicitly.
const COMMIT_STEP: usize = 4 << 20;
const NUM_CLASSES: usize = 24;
/// Large size classes: four per doubling, from 4 KiB (class 0) up to [`LARGE_MAX`].
const NUM_LARGE: usize = 49;
const LARGE_MIN_SHIFT: usize = 12;
/// The largest block kept in a large free list.
const LARGE_MAX: usize = 16 << 20;
/// Bytes the large free lists may hold before further frees go back to the system.
const LARGE_CACHE_LIMIT: usize = 64 << 20;

/// Size of large class `class`: 4, 5, 6, 7 times 1 KiB, then doubling.
const fn large_size(class: usize) -> usize {
    (4 + class % 4) << (LARGE_MIN_SHIFT - 2 + class / 4)
}

/// The smallest large class holding `size` bytes (`size` is at most [`LARGE_MAX`]).
#[inline]
fn large_class_up(size: usize) -> usize {
    if size <= 1 << LARGE_MIN_SHIFT {
        return 0;
    }
    let s = size - 1;
    let k = (usize::BITS - 1 - s.leading_zeros()) as usize;
    (k - LARGE_MIN_SHIFT) * 4 + ((s >> (k - 2)) - 4) + 1
}

/// The largest large class that fits in `usable` bytes (`usable` is at least 4 KiB).
#[inline]
fn large_class_down(usable: usize) -> usize {
    let k = (usize::BITS - 1 - usable.leading_zeros()) as usize;
    ((k - LARGE_MIN_SHIFT) * 4 + ((usable >> (k - 2)) - 4)).min(NUM_LARGE - 1)
}

const CLASS_SIZES: [u32; NUM_CLASSES] = [
    16, 32, 48, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 640, 768, 896, 1024,
    1280, 1536, 1792, 2048,
];

/// size / 16 (rounded up) -> class index, for sizes 1..=2048.
const fn build_lookup() -> [u8; 129] {
    let mut table = [0u8; 129];
    let mut units = 1;
    while units <= 128 {
        let size = units * 16;
        let mut class = 0;
        while (CLASS_SIZES[class] as usize) < size {
            class += 1;
        }
        table[units] = class as u8;
        units += 1;
    }
    table
}
static LOOKUP: [u8; 129] = build_lookup();

struct State {
    base: usize,
    end: usize,
    next_page: usize,
    /// Bytes of the arena made usable so far (everything on Unix, grown in steps on Windows).
    committed: usize,
    /// One byte per page: class index.
    page_class: *mut u8,
    free: [*mut u8; NUM_CLASSES],
    bump: [*mut u8; NUM_CLASSES],
    bump_end: [*mut u8; NUM_CLASSES],
    large_free: [*mut u8; NUM_LARGE],
    /// Usable bytes held in `large_free`.
    large_cached: usize,
    initialized: bool,
    #[cfg(any(test, feature = "stats"))]
    live: isize,
}

static STATE: Global<State> = Global::new(State {
    base: 0,
    end: 0,
    next_page: 0,
    committed: 0,
    page_class: null_mut(),
    free: [null_mut(); NUM_CLASSES],
    bump: [null_mut(); NUM_CLASSES],
    bump_end: [null_mut(); NUM_CLASSES],
    large_free: [null_mut(); NUM_LARGE],
    large_cached: 0,
    initialized: false,
    #[cfg(any(test, feature = "stats"))]
    live: 0,
});

#[cold]
fn init(s: &mut State) {
    s.initialized = true;
    let arena = sys::map_anon(ARENA_SIZE);
    let table = sys::map_anon(ARENA_SIZE >> PAGE_SHIFT);
    if arena.is_null() || table.is_null() || !sys::commit(table, ARENA_SIZE >> PAGE_SHIFT) {
        // Everything falls back to the system allocator.
        return;
    }
    s.base = arena as usize;
    s.end = s.base + ARENA_SIZE;
    s.committed = 0;
    s.page_class = table;
}

#[cold]
fn refill(s: &mut State, class: usize) -> *mut u8 {
    let page = s.next_page;
    if s.base == 0 || s.base + (page + 1) * PAGE_SIZE > s.end {
        return null_mut();
    }
    let used = (page + 1) * PAGE_SIZE;
    if used > s.committed {
        let chunk = COMMIT_STEP
            .max(used - s.committed)
            .min(ARENA_SIZE - s.committed);
        if !sys::commit((s.base + s.committed) as *mut u8, chunk) {
            return null_mut();
        }
        s.committed += chunk;
    }
    s.next_page += 1;
    // SAFETY: `page` indexes the side table, which has ARENA_SIZE/PAGE_SIZE entries.
    unsafe { *s.page_class.add(page) = class as u8 };
    let start = (s.base + page * PAGE_SIZE) as *mut u8;
    let size = CLASS_SIZES[class] as usize;
    // SAFETY: the page lies inside the reserved arena.
    s.bump_end[class] = unsafe { start.add(PAGE_SIZE / size * size) };
    s.bump[class] = start;
    start
}

#[inline(always)]
fn class_of(size: usize) -> usize {
    LOOKUP[size.div_ceil(16)] as usize
}

/// Allocates `size` bytes (16-byte aligned, uninitialised). Faults on exhaustion.
///
/// A recycled small block is the common case. It is handled here without a call, so the
/// compiled function needs no frame; everything else is in [`alloc_slow`].
#[inline]
pub fn alloc(size: usize) -> *mut u8 {
    // SAFETY: single threaded access to the allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    if size <= MAX_SMALL && s.initialized {
        let class = class_of(size.max(1));
        let head = s.free[class];
        if !head.is_null() {
            // SAFETY: free blocks store the next pointer in their first word.
            s.free[class] = unsafe { *(head as *mut *mut u8) };
            #[cfg(any(test, feature = "stats"))]
            {
                s.live += 1;
            }
            return head;
        }
    }
    alloc_slow(size)
}

#[inline(never)]
fn alloc_slow(size: usize) -> *mut u8 {
    // SAFETY: single threaded access to the allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    if size <= MAX_SMALL {
        if !s.initialized {
            init(s);
        }
        let class = class_of(size.max(1));
        let head = s.free[class];
        if !head.is_null() {
            // SAFETY: free blocks store the next pointer in their first word.
            s.free[class] = unsafe { *(head as *mut *mut u8) };
            #[cfg(any(test, feature = "stats"))]
            {
                s.live += 1;
            }
            return head;
        }
        let mut p = s.bump[class];
        if p.is_null() || p >= s.bump_end[class] {
            p = refill(s, class);
        }
        if !p.is_null() {
            // SAFETY: `p` is below `bump_end`, so the block stays in the page.
            s.bump[class] = unsafe { p.add(CLASS_SIZES[class] as usize) };
            #[cfg(any(test, feature = "stats"))]
            {
                s.live += 1;
            }
            return p;
        }
    }
    alloc_large(s, size)
}

#[inline(never)]
fn alloc_large(s: &mut State, size: usize) -> *mut u8 {
    let mut request = size.max(16);
    if size > MAX_SMALL && size <= LARGE_MAX {
        let class = large_class_up(size);
        let head = s.large_free[class];
        if !head.is_null() {
            // SAFETY: cached blocks store the next pointer in their first word and have
            // at least `large_size(class)` usable bytes.
            unsafe {
                s.large_free[class] = *(head as *mut *mut u8);
                s.large_cached -= sys::malloc_usable_size(head.cast());
            }
            #[cfg(any(test, feature = "stats"))]
            {
                s.live += 1;
            }
            return head;
        }
        request = large_size(class);
    }
    // SAFETY: plain malloc.
    let p = unsafe { sys::malloc(request) } as *mut u8;
    if p.is_null() {
        crate::fault::fatal(b"out of memory");
    }
    #[cfg(any(test, feature = "stats"))]
    {
        s.live += 1;
    }
    p
}

/// Allocates zeroed memory.
pub fn alloc_zeroed(size: usize) -> *mut u8 {
    let p = alloc(size);
    // SAFETY: `p` has at least `size` writable bytes.
    unsafe { core::ptr::write_bytes(p, 0, size) };
    p
}

#[inline(always)]
fn in_arena(s: &State, p: *mut u8) -> bool {
    (p as usize).wrapping_sub(s.base) < s.end.wrapping_sub(s.base)
}

/// Frees a block returned by [`alloc`] or [`realloc`]. Null is ignored.
///
/// # Safety
/// `p` must be null or a live block from this allocator.
#[inline]
pub unsafe fn free(p: *mut u8) {
    if p.is_null() {
        return;
    }
    // SAFETY: single threaded access to the allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    #[cfg(any(test, feature = "stats"))]
    {
        s.live -= 1;
    }
    if in_arena(s, p) {
        let page = (p as usize - s.base) >> PAGE_SHIFT;
        // SAFETY: arena pointers have a recorded class; a freed block is at
        // least 16 bytes, so it can hold the free-list link in its first word.
        unsafe {
            let class = *s.page_class.add(page) as usize;
            // The counting runtime scribbles over freed blocks so a use after free shows up.
            #[cfg(any(test, feature = "stats"))]
            core::ptr::write_bytes(p, 0xDD, CLASS_SIZES[class] as usize);
            *(p as *mut *mut u8) = s.free[class];
            s.free[class] = p;
        }
    } else {
        // SAFETY: not an arena block, so it came from malloc/realloc.
        unsafe { free_large(s, p) };
    }
}

/// Keeps a freed system block in its large free list, or returns it to the system.
///
/// # Safety
/// `p` is a live block from `sys::malloc`/`sys::realloc`.
unsafe fn free_large(s: &mut State, p: *mut u8) {
    // SAFETY: `p` is a live system block.
    let usable = unsafe { sys::malloc_usable_size(p.cast()) };
    if (1 << LARGE_MIN_SHIFT..=LARGE_MAX).contains(&usable)
        && s.large_cached + usable <= LARGE_CACHE_LIMIT
    {
        let class = large_class_down(usable);
        // SAFETY: the block holds at least 4 KiB, so its first word can hold the link.
        unsafe { *(p as *mut *mut u8) = s.large_free[class] };
        s.large_free[class] = p;
        s.large_cached += usable;
    } else {
        // SAFETY: `p` is a live system block.
        unsafe { sys::free(p.cast()) };
    }
}

/// Usable size of a live block.
///
/// # Safety
/// `p` must be a live block from this allocator.
pub unsafe fn usable_size(p: *mut u8) -> usize {
    // SAFETY: single threaded access to the allocator state.
    let s = unsafe { &*STATE.ptr() };
    if in_arena(s, p) {
        let page = (p as usize - s.base) >> PAGE_SHIFT;
        // SAFETY: arena pointers have a recorded class.
        unsafe { CLASS_SIZES[*s.page_class.add(page) as usize] as usize }
    } else {
        usize::MAX
    }
}

/// Resizes a block, preserving the common prefix.
///
/// # Safety
/// `p` must be null or a live block from this allocator.
pub unsafe fn realloc(p: *mut u8, new_size: usize) -> *mut u8 {
    if p.is_null() {
        return alloc(new_size);
    }
    // SAFETY: single threaded access to the allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    if in_arena(s, p) {
        // SAFETY: `p` is a live arena block.
        let old = unsafe { usable_size(p) };
        if new_size <= old && new_size > old / 2 {
            return p;
        }
        let q = alloc(new_size);
        // SAFETY: both blocks are valid for the copied length and do not overlap.
        unsafe {
            core::ptr::copy_nonoverlapping(p, q, old.min(new_size));
            free(p);
        }
        q
    } else if new_size <= MAX_SMALL {
        let q = alloc(new_size);
        // SAFETY: `q` holds `new_size` bytes; the old large block is at least that
        // large only when shrinking, so copy the smaller of the two via realloc'd size.
        unsafe {
            let old = sys::malloc_usable_size(p.cast());
            core::ptr::copy_nonoverlapping(p, q, old.min(new_size));
            free(p);
        }
        q
    } else {
        // SAFETY: `p` came from malloc/realloc.
        let old = unsafe { sys::malloc_usable_size(p.cast()) };
        if old > LARGE_MAX && new_size > LARGE_MAX {
            // SAFETY: `p` came from malloc/realloc.
            let q = unsafe { sys::realloc(p.cast(), new_size) } as *mut u8;
            if q.is_null() {
                crate::fault::fatal(b"out of memory");
            }
            return q;
        }
        if new_size <= old && new_size > old / 2 {
            return p;
        }
        let q = alloc(new_size);
        // SAFETY: both blocks are valid for the copied length and do not overlap.
        unsafe {
            core::ptr::copy_nonoverlapping(p, q, old.min(new_size));
            free(p);
        }
        q
    }
}

/// Small-block heap figures in bytes: `[used, in_use_pages]`. `used` counts
/// blocks handed out and not on a free list; large blocks belong to the system allocator and are
/// not included. Walks the free lists, so it is meant for occasional diagnostics.
pub fn heap_stats() -> [i64; 2] {
    // SAFETY: single threaded access to the allocator state.
    let s = unsafe { &*STATE.ptr() };
    if !s.initialized || s.page_class.is_null() {
        return [0; 2];
    }
    let mut carved = 0usize;
    for page in 0..s.next_page {
        // SAFETY: `page < next_page`, which the side table covers.
        let class = unsafe { *s.page_class.add(page) } as usize;
        carved += PAGE_SIZE / CLASS_SIZES[class] as usize * CLASS_SIZES[class] as usize;
    }
    let mut spare = 0usize;
    for (class, &size) in CLASS_SIZES.iter().enumerate() {
        let size = size as usize;
        spare += (s.bump_end[class] as usize).saturating_sub(s.bump[class] as usize);
        let mut p = s.free[class];
        while !p.is_null() {
            spare += size;
            // SAFETY: free blocks store the next pointer in their first word.
            p = unsafe { *(p as *mut *mut u8) };
        }
    }
    [
        carved.saturating_sub(spare) as i64,
        (s.next_page * PAGE_SIZE) as i64,
    ]
}

/// Live allocation count (tests and the `stats` feature).
#[cfg(any(test, feature = "stats"))]
pub fn live_blocks() -> isize {
    // SAFETY: single threaded access to the allocator state.
    unsafe { (*STATE.ptr()).live }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::lock;

    #[test]
    fn classes_cover_sizes() {
        for size in 1..=MAX_SMALL {
            let c = class_of(size);
            assert!(CLASS_SIZES[c] as usize >= size);
            if c > 0 {
                assert!((CLASS_SIZES[c - 1] as usize) < size);
            }
        }
    }

    #[test]
    fn alloc_free_reuse_and_realloc() {
        let _g = lock();
        let before = live_blocks();
        let a = alloc(40);
        let b = alloc(40);
        assert_ne!(a, b);
        assert_eq!(a as usize % 16, 0);
        // SAFETY: blocks are live and of sufficient size.
        unsafe {
            for i in 0..40 {
                *a.add(i) = i as u8;
            }
            let c = realloc(a, 5000);
            for i in 0..40 {
                assert_eq!(*c.add(i), i as u8);
            }
            let d = realloc(c, 100);
            for i in 0..40 {
                assert_eq!(*d.add(i), i as u8);
            }
            free(d);
            free(b);
        }
        let e = alloc(40);
        // SAFETY: `e` is live.
        unsafe { free(e) };
        assert_eq!(live_blocks(), before);
    }

    #[test]
    fn large_classes_round_trip() {
        assert_eq!(large_size(0), 4096);
        assert_eq!(large_size(1), 5120);
        assert_eq!(large_size(4), 8192);
        assert_eq!(large_size(NUM_LARGE - 1), LARGE_MAX);
        for size in (MAX_SMALL + 1..=LARGE_MAX).step_by(997) {
            let c = large_class_up(size);
            assert!(large_size(c) >= size, "{size}");
            assert!(c == 0 || large_size(c - 1) < size, "{size}");
            assert_eq!(large_class_down(large_size(c)), c);
        }
    }

    #[test]
    fn large_blocks_are_reused() {
        let _g = lock();
        let a = alloc(100_000);
        // The system may round a block up past its class (macOS does), and a freed block is
        // filed under the largest class that fits its usable size.
        // SAFETY: `a` is live.
        let usable = unsafe { sys::malloc_usable_size(a.cast()) };
        let size = large_size(large_class_down(usable));
        // SAFETY: `a` is live and holds 100000 bytes.
        unsafe {
            *a.add(99_999) = 7;
            free(a);
        }
        let b = alloc(size);
        assert_eq!(a, b);
        // SAFETY: `b` is live.
        unsafe { free(b) };
    }

    #[test]
    fn many_blocks_across_pages() {
        let _g = lock();
        let before = live_blocks();
        let mut v = std::vec::Vec::new();
        for i in 0..20000usize {
            let p = alloc(16 + (i % 17) * 16);
            // SAFETY: freshly allocated block.
            unsafe { *p = i as u8 };
            v.push(p);
        }
        for (i, p) in v.iter().enumerate() {
            // SAFETY: still live.
            assert_eq!(unsafe { **p }, i as u8);
        }
        for p in v {
            // SAFETY: allocated above, freed once.
            unsafe { free(p) };
        }
        assert_eq!(live_blocks(), before);
    }
}

/// Rust's global allocator for compiled programs (installed by `ms-native` on Linux).
///
/// The standard-library natives (`Vec`, `String`, `HashMap` inside `ms-std-*`) then share the
/// runtime's size-class allocator instead of libc's, which is several times slower per call. The
/// arena is single threaded: only the thread that runs `main` touches it, and every other thread
/// uses the system allocator. A block that another thread frees from the arena is leaked.
#[cfg(target_os = "linux")]
pub struct StdHeap;

#[cfg(target_os = "linux")]
mod owner {
    use core::sync::atomic::{AtomicUsize, Ordering};

    /// The thread that owns the arena; 0 until the runtime thread starts, when any thread may use it.
    static OWNER: AtomicUsize = AtomicUsize::new(0);

    pub fn claim() {
        OWNER.store(crate::sys::thread_self(), Ordering::Relaxed);
    }

    #[inline(always)]
    pub fn is_current() -> bool {
        let owner = OWNER.load(Ordering::Relaxed);
        owner == 0 || owner == crate::sys::thread_self()
    }
}

/// Makes the calling thread the only one that allocates from the arena.
#[cfg(target_os = "linux")]
pub fn claim_arena() {
    owner::claim();
}

#[cfg(target_os = "linux")]
mod std_heap {
    use super::{MAX_SMALL, STATE, StdHeap, in_arena, owner};
    use core::alloc::{GlobalAlloc, Layout};
    use std::alloc::System;

    /// Whether the arena may serve `layout` on this thread. Counting builds keep the standard
    /// library out of the arena so leak checks see only program allocations.
    #[inline(always)]
    fn arena_ok(layout: Layout) -> bool {
        !cfg!(feature = "stats") && layout.align() <= 16 && owner::is_current()
    }

    #[inline(always)]
    fn owns(p: *mut u8) -> bool {
        // SAFETY: single field reads of the allocator state.
        in_arena(unsafe { &*STATE.ptr() }, p)
    }

    // SAFETY: blocks come from the arena or the system allocator, and `dealloc` and `realloc`
    // tell them apart by address, so each is released by the allocator that produced it.
    unsafe impl GlobalAlloc for StdHeap {
        #[inline]
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            if arena_ok(layout) {
                super::alloc(layout.size())
            } else {
                // SAFETY: forwarded.
                unsafe { System.alloc(layout) }
            }
        }

        #[inline]
        unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
            if arena_ok(layout) && layout.size() <= MAX_SMALL {
                super::alloc_zeroed(layout.size())
            } else {
                // SAFETY: forwarded; the system allocator hands out lazily zeroed pages for big blocks.
                unsafe { System.alloc_zeroed(layout) }
            }
        }

        #[inline]
        unsafe fn dealloc(&self, p: *mut u8, layout: Layout) {
            if !owns(p) {
                // SAFETY: not an arena block, so the system allocator produced it.
                unsafe { System.dealloc(p, layout) };
            } else if owner::is_current() {
                // SAFETY: an arena block freed on the arena's thread.
                unsafe { super::free(p) };
            }
        }

        unsafe fn realloc(&self, p: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
            let target = Layout::from_size_align(new_size, layout.align());
            let Ok(target) = target else {
                return core::ptr::null_mut();
            };
            if arena_ok(layout) && (owns(p) || new_size > MAX_SMALL) {
                // SAFETY: `p` is a live block of this heap (arena, or a large system block).
                return unsafe { super::realloc(p, new_size) };
            }
            if !owns(p) && layout.align() <= 16 {
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
