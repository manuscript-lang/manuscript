//! Size-class allocator.
//!
//! Small blocks (up to [`MAX_SMALL`] bytes) come from 64 KiB pages carved out of
//! one large lazily-committed reservation; each page serves a single size class
//! and the page's class is recorded in a side table, so `free` needs no size.
//! Large blocks go to the system allocator. Single threaded: no locks.
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
fn alloc_large(_s: &mut State, size: usize) -> *mut u8 {
    // SAFETY: plain malloc.
    let p = unsafe { sys::malloc(size.max(16)) } as *mut u8;
    if p.is_null() {
        crate::fault::fatal(b"out of memory");
    }
    #[cfg(any(test, feature = "stats"))]
    {
        _s.live += 1;
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
            *(p as *mut *mut u8) = s.free[class];
            s.free[class] = p;
        }
    } else {
        // SAFETY: not an arena block, so it came from malloc/realloc.
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
        let q = unsafe { sys::realloc(p.cast(), new_size) } as *mut u8;
        if q.is_null() {
            crate::fault::fatal(b"out of memory");
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
