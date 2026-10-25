//! Size-class allocator.
//!
//! Small blocks (up to [`MAX_SMALL`] bytes) come from 64 KiB pages carved out of
//! one large lazily-committed reservation; each page serves a single size class
//! and the page's class is recorded in a side table, so `free` needs no size.
//! Large blocks go to the system allocator, with freed blocks up to [`LARGE_MAX`] kept in
//! per-size free lists so growing and rebuilding big lists does not map and unmap memory
//! (musl's malloc does a `mmap`/`munmap` pair for every block above a few KiB).
//!
//! Each isolate thread owns one arena and allocates from it without locks. A thread that never
//! claimed an arena (pool and helper threads) allocates from the system allocator. A block
//! freed on a thread other than its owner is pushed onto the owner's lock-free remote-free
//! stack, found by address in a small registry, and the owner drains it on its next slow-path
//! allocation (see `proposals/worker-threads.md`).
use crate::sys;
use core::ptr::null_mut;
use core::sync::atomic::{AtomicPtr, AtomicUsize, Ordering};

pub const MAX_SMALL: usize = 2048;
const PAGE_SHIFT: usize = 16;
const PAGE_SIZE: usize = 1 << PAGE_SHIFT;
/// Address space reserved for the main isolate's arena.
const MAIN_ARENA_SIZE: usize = if cfg!(miri) { 64 << 20 } else { 16 << 30 };
/// Address space reserved for a worker isolate's arena (committed on demand).
const WORKER_ARENA_SIZE: usize = if cfg!(miri) { 64 << 20 } else { 2 << 30 };
/// Most arenas the registry can hold; further claims fall back to the system allocator.
const MAX_ARENAS: usize = 256;
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
    /// The arena is mapped (or mapping failed and the system allocator serves everything).
    initialized: bool,
    /// This thread asked for an arena; set by [`claim_arena`].
    claimed: bool,
    /// [`release_arena`] ran: any later release of a runtime object on this thread is a bug.
    released: bool,
    /// Whether the claim is the main isolate's (a larger arena).
    main: bool,
    /// Registry slot of this thread's arena (valid once `initialized` and `base != 0`).
    slot: usize,
    #[cfg(any(test, feature = "stats"))]
    live: isize,
}

/// One registered arena: what another thread needs to free a block into it.
struct Arena {
    base: AtomicUsize,
    end: AtomicUsize,
    page_class: AtomicPtr<u8>,
    /// Head of the blocks other threads freed into this arena.
    remote: AtomicPtr<u8>,
}

impl Arena {
    const fn new() -> Self {
        Arena {
            base: AtomicUsize::new(0),
            end: AtomicUsize::new(0),
            page_class: AtomicPtr::new(null_mut()),
            remote: AtomicPtr::new(null_mut()),
        }
    }
}

static ARENAS: [Arena; MAX_ARENAS] = [const { Arena::new() }; MAX_ARENAS];
/// Slots handed out so far (never reused: a retired arena stays registered, see the proposal).
static ARENA_COUNT: AtomicUsize = AtomicUsize::new(0);

crate::isolate_static! {
static STATE: State = State {
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
    claimed: false,
    released: false,
    main: false,
    slot: 0,
    #[cfg(any(test, feature = "stats"))]
    live: 0,
};
}

#[cold]
fn init(s: &mut State) {
    s.initialized = true;
    let size = if s.main {
        MAIN_ARENA_SIZE
    } else {
        WORKER_ARENA_SIZE
    };
    let slot = ARENA_COUNT.fetch_add(1, Ordering::Relaxed);
    if slot >= MAX_ARENAS {
        ARENA_COUNT.store(MAX_ARENAS, Ordering::Relaxed);
        // Everything falls back to the system allocator.
        return;
    }
    let arena = sys::map_anon(size);
    let table = sys::map_anon(size >> PAGE_SHIFT);
    if arena.is_null() || table.is_null() || !sys::commit(table, size >> PAGE_SHIFT) {
        // Everything falls back to the system allocator.
        return;
    }
    s.base = arena as usize;
    s.end = s.base + size;
    s.committed = 0;
    s.page_class = table;
    s.slot = slot;
    let a = &ARENAS[slot];
    a.page_class.store(table, Ordering::Relaxed);
    a.end.store(s.end, Ordering::Relaxed);
    // Published last: a reader that sees `base` sees the rest.
    a.base.store(s.base, Ordering::Release);
}

/// Gives the calling thread an arena; the first allocation maps it. `main` selects the
/// main isolate's larger reservation. Threads that never call this use the system allocator.
pub fn claim_arena(main: bool) {
    // SAFETY: this isolate's allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    s.claimed = true;
    s.main = main;
}

/// Returns the calling thread's arena to the system as its isolate ends. Blocks still live in
/// it are gone; the owner registry forgets the arena first, so a late free of one of its blocks
/// falls through to the system allocator's path and must not happen (isolates copy what they
/// hand out).
pub fn release_arena() {
    // SAFETY: this isolate's allocator state; nothing allocates from it afterwards.
    let s = unsafe { &mut *STATE.ptr() };
    if s.base != 0 {
        let a = &ARENAS[s.slot];
        a.base.store(0, Ordering::Release);
        a.remote.store(null_mut(), Ordering::Relaxed);
        let size = s.end - s.base;
        // SAFETY: the mappings were made by `init` and are no longer reachable.
        unsafe {
            sys::unmap(s.base as *mut u8, size);
            sys::unmap(s.page_class, size >> PAGE_SHIFT);
        }
    }
    for class in 0..NUM_LARGE {
        let mut p = s.large_free[class];
        while !p.is_null() {
            // SAFETY: cached large blocks are live system blocks linked through word 0.
            unsafe {
                let next = *(p as *mut *mut u8);
                sys::free(p.cast());
                p = next;
            }
        }
        s.large_free[class] = null_mut();
    }
    s.large_cached = 0;
    s.free = [null_mut(); NUM_CLASSES];
    s.bump = [null_mut(); NUM_CLASSES];
    s.bump_end = [null_mut(); NUM_CLASSES];
    s.base = 0;
    s.end = 0;
    s.initialized = true;
    s.claimed = false;
    s.released = true;
}

/// Whether the calling thread's arena was already returned to the system (its isolate ended).
#[inline(always)]
pub fn arena_released() -> bool {
    // SAFETY: this isolate's allocator state.
    unsafe { (*STATE.ptr()).released }
}

/// Whether the calling thread has an arena (or will map one on its first small allocation).
#[inline(always)]
pub fn has_arena() -> bool {
    // SAFETY: this isolate's allocator state.
    unsafe { (*STATE.ptr()).claimed }
}

/// The registered arena holding `p`, if any thread's. `own` is the caller's state: its own
/// arena was already checked, and when it is the only arena nothing else can hold `p`.
#[inline(never)]
fn arena_of(own: &State, p: *mut u8) -> Option<&'static Arena> {
    let n = ARENA_COUNT.load(Ordering::Relaxed).min(MAX_ARENAS);
    if n == 0 || (n == 1 && own.base != 0) {
        return None;
    }
    let addr = p as usize;
    ARENAS[..n].iter().find(|a| {
        let base = a.base.load(Ordering::Acquire);
        base != 0 && addr.wrapping_sub(base) < a.end.load(Ordering::Relaxed) - base
    })
}

/// Pushes a block onto its owning arena's remote-free stack.
///
/// # Safety
/// `p` is a live small block inside `arena`, owned by the caller.
unsafe fn remote_free(arena: &Arena, p: *mut u8) {
    let mut head = arena.remote.load(Ordering::Relaxed);
    loop {
        // SAFETY: a freed block is at least 16 bytes and holds the link in its first word.
        unsafe { *(p as *mut *mut u8) = head };
        match arena
            .remote
            .compare_exchange_weak(head, p, Ordering::Release, Ordering::Relaxed)
        {
            Ok(_) => return,
            Err(h) => head = h,
        }
    }
}

/// Moves the blocks other threads freed into this arena onto its free lists.
#[cold]
fn drain_remote(s: &mut State) {
    let mut p = ARENAS[s.slot].remote.swap(null_mut(), Ordering::Acquire);
    while !p.is_null() {
        // SAFETY: remote blocks are small arena blocks of this arena with the link in word 0.
        unsafe {
            let next = *(p as *mut *mut u8);
            let class = *s.page_class.add((p as usize - s.base) >> PAGE_SHIFT) as usize;
            *(p as *mut *mut u8) = s.free[class];
            s.free[class] = p;
            p = next;
        }
    }
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
            .min(s.end - s.base - s.committed);
        if !sys::commit((s.base + s.committed) as *mut u8, chunk) {
            return null_mut();
        }
        s.committed += chunk;
    }
    s.next_page += 1;
    // SAFETY: `page` indexes the side table, which has one entry per arena page.
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
    if size <= MAX_SMALL && (s.initialized || s.claimed || cfg!(test)) {
        if !s.initialized {
            s.claimed = true;
            init(s);
        }
        if s.base != 0 && !ARENAS[s.slot].remote.load(Ordering::Relaxed).is_null() {
            drain_remote(s);
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
    } else if let Some(a) = arena_of(s, p) {
        // SAFETY: a live small block of another isolate's arena, owned by the caller.
        unsafe { remote_free(a, p) };
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
    match small_size(s, p) {
        Some(n) => n,
        // SAFETY: not an arena block, so it came from malloc/realloc.
        None => unsafe { sys::malloc_usable_size(p.cast()) },
    }
}

/// Block size when `p` is a small block of any isolate's arena.
fn small_size(s: &State, p: *mut u8) -> Option<usize> {
    let (base, table) = if in_arena(s, p) {
        (s.base, s.page_class)
    } else {
        let a = arena_of(s, p)?;
        (
            a.base.load(Ordering::Relaxed),
            a.page_class.load(Ordering::Relaxed),
        )
    };
    // SAFETY: arena pointers have a recorded class.
    Some(unsafe { CLASS_SIZES[*table.add((p as usize - base) >> PAGE_SHIFT) as usize] as usize })
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
    if let Some(old) = small_size(s, p) {
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

    #[test]
    fn remote_free_returns_to_owner() {
        let _g = lock();
        let p = alloc(48) as usize;
        std::thread::spawn(move || {
            // SAFETY: a live block of the spawning thread's arena, freed once.
            unsafe { free(p as *mut u8) };
        })
        .join()
        .unwrap();
        // The owner's next slow-path allocation drains the remote stack.
        let mut got = false;
        let mut v = Vec::new();
        for _ in 0..4096 {
            let q = alloc(48);
            got |= q as usize == p;
            v.push(q);
        }
        assert!(got);
        for q in v {
            // SAFETY: allocated above, freed once.
            unsafe { free(q) };
        }
    }
}

/// Rust's global allocator for compiled programs (installed by `ms-native` on Linux).
///
/// The standard-library natives (`Vec`, `String`, `HashMap` inside `ms-std-*`) then share the
/// runtime's size-class allocator instead of libc's, which is several times slower per call. Only
/// threads that claimed an arena (isolates) use it; every other thread uses the system allocator.
/// A block that another thread frees is routed to its owner's remote-free stack.
#[cfg(target_os = "linux")]
pub struct StdHeap;

#[cfg(target_os = "linux")]
mod std_heap {
    use super::{MAX_SMALL, STATE, StdHeap, arena_of, has_arena, in_arena};
    use core::alloc::{GlobalAlloc, Layout};
    use std::alloc::System;

    /// Native zeroed blocks must consume the same size classes that deallocation
    /// fills. Cold misses still use calloc so untouched pages stay lazy.
    fn zeroed_large(size: usize) -> *mut u8 {
        // SAFETY: this is the current isolate's state; arena_ok checked that
        // the thread owns an arena and that the requested alignment is <= 16.
        let state = unsafe { &mut *STATE.ptr() };
        let mut request = size;
        if size <= super::LARGE_MAX {
            let class = super::large_class_up(size);
            if !state.large_free[class].is_null() {
                let block = super::alloc_large(state, size);
                // SAFETY: the selected class holds at least size bytes.
                unsafe { core::ptr::write_bytes(block, 0, size) };
                return block;
            }
            request = super::large_size(class);
        }
        // SAFETY: calloc provides the required alignment and zeroed storage.
        let block = unsafe { crate::sys::calloc(1, request) }.cast::<u8>();
        #[cfg(any(test, feature = "stats"))]
        if !block.is_null() {
            state.live += 1;
        }
        block
    }

    #[cfg(all(test, not(feature = "stats")))]
    #[test]
    fn zeroed_large_blocks_reuse_cached_storage_and_clear_dirty_bytes() {
        let _guard = crate::testutil::lock();
        super::claim_arena(true);
        let heap = StdHeap;
        for size in [2049, 4097, 8193, 16385, 1 << 20] {
            let layout = Layout::from_size_align(size, 16).unwrap();
            // SAFETY: each allocation is accessed within its requested size and
            // released once through the same allocator and layout.
            unsafe {
                let first = heap.alloc_zeroed(layout);
                assert!(!first.is_null());
                core::ptr::write_bytes(first, 0xA5, size);
                heap.dealloc(first, layout);
                let cached = (*STATE.ptr()).large_cached;
                for _ in 0..8 {
                    let next = heap.alloc_zeroed(layout);
                    assert_eq!(next, first, "size {size} did not reuse its cache bin");
                    assert!(
                        core::slice::from_raw_parts(next, size)
                            .iter()
                            .all(|&b| b == 0)
                    );
                    core::ptr::write_bytes(next, 0x5A, size);
                    heap.dealloc(next, layout);
                    assert_eq!((*STATE.ptr()).large_cached, cached);
                }
            }
        }
    }

    #[cfg(all(test, not(feature = "stats")))]
    #[test]
    fn zeroed_large_boundaries_and_high_alignment_remain_valid() {
        let _guard = crate::testutil::lock();
        super::claim_arena(true);
        let heap = StdHeap;
        for (size, alignment) in [
            (super::LARGE_MAX - 1, 16),
            (super::LARGE_MAX, 16),
            (super::LARGE_MAX + 1, 16),
            (8193, 64),
        ] {
            let layout = Layout::from_size_align(size, alignment).unwrap();
            // SAFETY: accesses are in bounds, followed by one matching free.
            unsafe {
                let block = heap.alloc_zeroed(layout);
                assert!(!block.is_null());
                assert_eq!(block as usize % alignment, 0);
                for index in [0, size / 2, size - 1] {
                    assert_eq!(*block.add(index), 0);
                    *block.add(index) = 0xA5;
                }
                heap.dealloc(block, layout);
                assert!((*STATE.ptr()).large_cached <= super::LARGE_CACHE_LIMIT);
            }
        }
    }

    /// Whether the arena may serve `layout` on this thread. Counting builds keep the standard
    /// library out of the arena so leak checks see only program allocations. A worker's arena
    /// ends with the worker, and Rust code can keep what it allocates in process-wide state
    /// (a cache, a buffer another isolate reads), so Rust code in a worker uses the system allocator.
    #[inline(always)]
    fn arena_ok(layout: Layout) -> bool {
        !cfg!(feature = "stats")
            && layout.align() <= 16
            && has_arena()
            && !crate::isolate::is_worker()
    }

    /// Whether `p` is a small block of any isolate's arena.
    #[inline(always)]
    fn owns(p: *mut u8) -> bool {
        // SAFETY: single field reads of this isolate's allocator state.
        let s = unsafe { &*STATE.ptr() };
        in_arena(s, p) || arena_of(s, p).is_some()
    }

    // SAFETY: blocks come from an arena or the system allocator, and `dealloc` and `realloc`
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
            if arena_ok(layout) {
                if layout.size() <= MAX_SMALL {
                    return super::alloc_zeroed(layout.size());
                }
                return zeroed_large(layout.size());
            }
            // SAFETY: forwarded for threads/alignment not served by the arena.
            unsafe { System.alloc_zeroed(layout) }
        }

        #[inline]
        unsafe fn dealloc(&self, p: *mut u8, layout: Layout) {
            if owns(p) {
                // SAFETY: an arena block; `free` routes it to its owner.
                unsafe { super::free(p) };
            } else if layout.size() > MAX_SMALL && arena_ok(layout) {
                // SAFETY: a large block is a system block either way; the runtime keeps
                // freed ones for reuse, where the system allocator would unmap them and
                // fault the next block in again.
                unsafe { super::free(p) };
            } else {
                // SAFETY: not an arena block, so the system allocator produced it.
                unsafe { System.dealloc(p, layout) };
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
