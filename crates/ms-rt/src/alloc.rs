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
/// Smallest system block that grows by remapping rather than by copying.
const REMAP_MIN: usize = 128 << 10;
/// Bytes the large free lists may hold before further frees go back to the system.
const LARGE_CACHE_LIMIT: usize = 64 << 20;
/// Most blocks of one large class a thread keeps for itself; further frees go to the shared
/// lists, where threads without an arena (blocking-pool jobs, workers) find them.
const LOCAL_PER_CLASS: u8 = 4;

/// Freed large blocks for threads that have no arena of their own: a pool job reads a file into
/// a block that the runtime thread frees, so without a way back every such block would be mapped
/// anew, and faulted in page by page.
struct Shared {
    free: [*mut u8; NUM_LARGE],
    /// Usable bytes held in `free`.
    cached: usize,
}

// SAFETY: the lists link blocks that no thread uses; the lock guards the lists.
unsafe impl Send for Shared {}

static SHARED: std::sync::Mutex<Shared> = std::sync::Mutex::new(Shared {
    free: [null_mut(); NUM_LARGE],
    cached: 0,
});

fn shared() -> std::sync::MutexGuard<'static, Shared> {
    SHARED.lock().unwrap_or_else(|e| e.into_inner())
}

/// A cached block with at least `size` usable bytes for a thread without an arena, or null.
pub fn shared_take(size: usize) -> *mut u8 {
    if size <= MAX_SMALL || size > LARGE_MAX {
        return null_mut();
    }
    let class = large_class_up(size);
    let mut cache = shared();
    let head = cache.free[class];
    if head.is_null() {
        return head;
    }
    // SAFETY: cached blocks store the next pointer in their first word and have at least
    // `large_size(class)` usable bytes.
    unsafe {
        cache.free[class] = *(head as *mut *mut u8);
        cache.cached -= sys::malloc_usable_size(head.cast());
    }
    head
}

/// Keeps the system block `p` for [`shared_take`]; false when it is not a large block or the
/// lists are full, and the caller frees it.
///
/// # Safety
/// `p` is a live system block that nothing else uses.
pub unsafe fn shared_put(p: *mut u8) -> bool {
    // SAFETY: a live system block.
    let usable = unsafe { sys::malloc_usable_size(p.cast()) };
    if !(1 << LARGE_MIN_SHIFT..=LARGE_MAX).contains(&usable) {
        return false;
    }
    let mut cache = shared();
    if cache.cached + usable > LARGE_CACHE_LIMIT {
        return false;
    }
    let class = large_class_down(usable);
    // SAFETY: the block holds at least 4 KiB, so its first word can hold the link.
    unsafe { *(p as *mut *mut u8) = cache.free[class] };
    cache.free[class] = p;
    cache.cached += usable;
    true
}

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
    /// Blocks held in each `large_free` list.
    large_count: [u8; NUM_LARGE],
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
    large_count: [0; NUM_LARGE],
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
    #[cfg(target_os = "linux")]
    if crate::isolate::is_worker() {
        worker_heap::retire();
    }
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
    s.large_count = [0; NUM_LARGE];
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
                s.large_count[class] -= 1;
                s.large_cached -= sys::malloc_usable_size(head.cast());
            }
            #[cfg(any(test, feature = "stats"))]
            {
                s.live += 1;
            }
            return head;
        }
        request = large_size(class);
        let shared = shared_take(size);
        if !shared.is_null() {
            #[cfg(any(test, feature = "stats"))]
            {
                s.live += 1;
            }
            return shared;
        }
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

/// The size a large block of `size` bytes is requested from the system with, so that freeing it
/// files it under the class that a later request of the same size looks in.
pub fn large_request(size: usize) -> usize {
    if size > MAX_SMALL && size <= LARGE_MAX {
        large_size(large_class_up(size))
    } else {
        size
    }
}

/// A zeroed large block taken from the free lists, or null when none is cached. The system's
/// lazily zeroed pages cost a page fault per page on first use, more than clearing a block that
/// is already mapped.
pub fn alloc_zeroed_cached(size: usize) -> *mut u8 {
    if size <= MAX_SMALL || size > LARGE_MAX {
        return null_mut();
    }
    // SAFETY: single threaded access to the allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    let class = large_class_up(size);
    let head = s.large_free[class];
    if head.is_null() {
        return head;
    }
    // SAFETY: cached blocks store the next pointer in their first word and have at least
    // `large_size(class)` usable bytes, so `size` bytes are writable.
    unsafe {
        s.large_free[class] = *(head as *mut *mut u8);
        s.large_count[class] -= 1;
        s.large_cached -= sys::malloc_usable_size(head.cast());
        core::ptr::write_bytes(head, 0, size);
    }
    #[cfg(any(test, feature = "stats"))]
    {
        s.live += 1;
    }
    head
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
    let class = large_class_down(usable.max(1 << LARGE_MIN_SHIFT));
    if (1 << LARGE_MIN_SHIFT..=LARGE_MAX).contains(&usable)
        && s.large_cached + usable <= LARGE_CACHE_LIMIT
        && s.large_count[class] < LOCAL_PER_CLASS
    {
        // SAFETY: the block holds at least 4 KiB, so its first word can hold the link.
        unsafe { *(p as *mut *mut u8) = s.large_free[class] };
        s.large_free[class] = p;
        s.large_count[class] += 1;
        s.large_cached += usable;
    } else {
        // SAFETY: `p` is a live system block that nothing else uses.
        let kept = unsafe { shared_put(p) };
        if !kept {
            // SAFETY: `p` is a live system block.
            unsafe { sys::free(p.cast()) };
        }
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
        // Growing a big block with no cached block to move into: let the system remap its
        // pages instead of copying them into fresh (page-faulting) memory.
        let uncached = new_size > old
            && old >= REMAP_MIN
            && (new_size > LARGE_MAX || s.large_free[large_class_up(new_size)].is_null());
        if (old > LARGE_MAX && new_size > LARGE_MAX) || uncached {
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
    fn growing_a_big_block_keeps_its_bytes() {
        let _g = lock();
        let before = live_blocks();
        let mut size = REMAP_MIN;
        let mut p = alloc(size);
        // SAFETY: each block is live and holds `size` bytes when written and read.
        unsafe {
            for i in 0..size {
                *p.add(i) = (i % 251) as u8;
            }
            for _ in 0..6 {
                let old = size;
                size *= 2;
                p = realloc(p, size);
                for i in (0..old).step_by(97) {
                    assert_eq!(*p.add(i), (i % 251) as u8);
                }
                for i in old..size {
                    *p.add(i) = (i % 251) as u8;
                }
            }
            free(p);
        }
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

    #[cfg(target_os = "linux")]
    #[test]
    fn worker_heap_blocks_cross_threads_and_are_reused() {
        use super::worker_heap;
        let p = worker_heap::alloc(100);
        assert!(!p.is_null() && worker_heap::owns(p));
        // SAFETY: a live block of at least 100 bytes.
        unsafe { core::ptr::write_bytes(p, 0xAB, 100) };
        let addr = p as usize;
        // A thread that is not a worker hands the block to the shared list; the next
        // allocation of its class on this thread takes it back.
        std::thread::spawn(move || worker_heap::free(addr as *mut u8, 100))
            .join()
            .unwrap();
        let mut got = false;
        for _ in 0..4 {
            got |= worker_heap::alloc(100) as usize == addr;
        }
        assert!(got);
        assert!(!worker_heap::owns(alloc(100)));
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

/// The small-block heap for Rust code on worker threads (Linux).
///
/// The system allocator (musl) serves every thread through one lock, so workers that allocate in
/// Rust natives (connection buffers, headers) slowed each other down. A worker cannot use its own
/// arena for that: Rust code keeps blocks in process-wide state that outlives the isolate and its
/// arena. This heap lives in one reservation shared by the process and is never unmapped: blocks
/// are carved in per-thread slabs, freed to the freeing worker's lists (any thread may free any
/// block), and a worker that ends hands its lists to the next one.
#[cfg(target_os = "linux")]
mod worker_heap {
    use super::{CLASS_SIZES, NUM_CLASSES, class_of, sys};
    use core::ptr::null_mut;
    use core::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Mutex;

    /// Address space reserved for the heap; pages commit on first touch.
    const REGION: usize = 16 << 30;
    /// Bytes a thread takes from the region at a time for one class.
    const SLAB: usize = 64 << 10;

    static BASE: AtomicUsize = AtomicUsize::new(0);
    static NEXT: AtomicUsize = AtomicUsize::new(0);

    /// Free blocks handed over by ended workers and by threads that are not workers.
    struct Shared([*mut u8; NUM_CLASSES]);
    // SAFETY: the lists link blocks of the immortal region and are only touched under the lock.
    unsafe impl Send for Shared {}
    static SHARED: Mutex<Shared> = Mutex::new(Shared([null_mut(); NUM_CLASSES]));

    struct Local {
        free: [*mut u8; NUM_CLASSES],
        bump: [*mut u8; NUM_CLASSES],
        bump_end: [*mut u8; NUM_CLASSES],
    }

    crate::isolate_static! {
    static LOCAL: Local = Local {
        free: [null_mut(); NUM_CLASSES],
        bump: [null_mut(); NUM_CLASSES],
        bump_end: [null_mut(); NUM_CLASSES],
    };
    }

    /// Whether `p` is a block of this heap.
    #[inline(always)]
    pub fn owns(p: *mut u8) -> bool {
        let base = BASE.load(Ordering::Relaxed);
        base != 0 && (p as usize).wrapping_sub(base) < REGION
    }

    fn reserve() -> usize {
        let base = BASE.load(Ordering::Acquire);
        if base != 0 {
            return base;
        }
        let p = sys::map_anon(REGION) as usize;
        if p == 0 {
            return 0;
        }
        match BASE.compare_exchange(0, p, Ordering::AcqRel, Ordering::Acquire) {
            Ok(_) => p,
            Err(won) => {
                // SAFETY: the mapping was made here and nothing used it.
                unsafe { sys::unmap(p as *mut u8, REGION) };
                won
            }
        }
    }

    /// A block for `size` bytes (at most `MAX_SMALL`), or null when the region is full.
    pub fn alloc(size: usize) -> *mut u8 {
        // SAFETY: this thread's lists.
        let l = unsafe { &mut *LOCAL.ptr() };
        let class = class_of(size.max(1));
        let head = l.free[class];
        if !head.is_null() {
            // SAFETY: free blocks hold the next link in word 0.
            l.free[class] = unsafe { *(head as *mut *mut u8) };
            return head;
        }
        refill(l, class)
    }

    #[cold]
    fn refill(l: &mut Local, class: usize) -> *mut u8 {
        {
            let mut shared = SHARED.lock().unwrap_or_else(|e| e.into_inner());
            l.free[class] = core::mem::replace(&mut shared.0[class], null_mut());
        }
        let head = l.free[class];
        if !head.is_null() {
            // SAFETY: as above.
            l.free[class] = unsafe { *(head as *mut *mut u8) };
            return head;
        }
        let size = CLASS_SIZES[class] as usize;
        if l.bump[class].is_null() || l.bump[class] >= l.bump_end[class] {
            let base = reserve();
            if base == 0 {
                return null_mut();
            }
            let at = NEXT.fetch_add(SLAB, Ordering::Relaxed);
            if at + SLAB > REGION {
                return null_mut();
            }
            let start = (base + at) as *mut u8;
            // SAFETY: the slab lies inside the region.
            l.bump_end[class] = unsafe { start.add(SLAB / size * size) };
            l.bump[class] = start;
        }
        let p = l.bump[class];
        // SAFETY: `p` is below `bump_end`, so the block stays inside the slab.
        l.bump[class] = unsafe { p.add(size) };
        p
    }

    /// Frees a block of `size` bytes (the size it was requested with).
    pub fn free(p: *mut u8, size: usize) {
        let class = class_of(size.max(1));
        if crate::isolate::is_worker() {
            // SAFETY: this thread's lists; a freed block is at least 16 bytes.
            unsafe {
                let l = &mut *LOCAL.ptr();
                *(p as *mut *mut u8) = l.free[class];
                l.free[class] = p;
            }
        } else {
            // A thread that never allocates here must not hoard blocks.
            let mut shared = SHARED.lock().unwrap_or_else(|e| e.into_inner());
            // SAFETY: as above.
            unsafe { *(p as *mut *mut u8) = shared.0[class] };
            shared.0[class] = p;
        }
    }

    /// Hands the calling worker's free blocks to the next worker as its isolate ends.
    pub fn retire() {
        // SAFETY: this thread's lists.
        let l = unsafe { &mut *LOCAL.ptr() };
        let mut shared = SHARED.lock().unwrap_or_else(|e| e.into_inner());
        for class in 0..NUM_CLASSES {
            let mut p = core::mem::replace(&mut l.free[class], null_mut());
            while !p.is_null() {
                // SAFETY: free blocks hold the next link in word 0.
                unsafe {
                    let next = *(p as *mut *mut u8);
                    *(p as *mut *mut u8) = shared.0[class];
                    shared.0[class] = p;
                    p = next;
                }
            }
        }
    }
}

#[cfg(target_os = "linux")]
mod std_heap {
    use super::{LARGE_MAX, MAX_SMALL, STATE, StdHeap, arena_of, has_arena, in_arena, worker_heap};
    use core::alloc::{GlobalAlloc, Layout};
    use std::alloc::System;

    /// Whether the arena may serve `layout` on this thread. Counting builds keep the standard
    /// library out of the arena so leak checks see only program allocations. A worker's arena
    /// ends with the worker, and Rust code can keep what it allocates in process-wide state
    /// (a cache, a buffer another isolate reads), so Rust code in a worker uses the system allocator
    /// for small blocks. Large blocks are system blocks in any case, and the worker keeps freed ones
    /// for reuse (as the main isolate does), so an 8 MiB body buffer is not mapped and faulted in
    /// again by every request.
    #[inline(always)]
    fn arena_ok(layout: Layout) -> bool {
        !cfg!(feature = "stats")
            && layout.align() <= 16
            && has_arena()
            && (!crate::isolate::is_worker() || layout.size() > MAX_SMALL)
    }

    /// Whether the worker heap serves `layout` on this thread: Rust code in a worker, small blocks.
    #[inline(always)]
    fn worker_ok(layout: Layout) -> bool {
        !cfg!(feature = "stats")
            && layout.align() <= 16
            && layout.size() <= MAX_SMALL
            && crate::isolate::is_worker()
    }

    /// The size of a large request from a thread without an arena that the shared lists serve.
    #[inline(always)]
    fn shared_size(layout: Layout) -> Option<usize> {
        (layout.align() <= 16 && layout.size() > MAX_SMALL && layout.size() <= LARGE_MAX)
            .then_some(layout.size())
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
            if worker_ok(layout) {
                let p = worker_heap::alloc(layout.size());
                if !p.is_null() {
                    return p;
                }
            }
            if arena_ok(layout) {
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
            if worker_ok(layout) {
                let p = worker_heap::alloc(layout.size());
                if !p.is_null() {
                    // SAFETY: a block of at least `layout.size()` bytes.
                    unsafe { core::ptr::write_bytes(p, 0, layout.size()) };
                    return p;
                }
            }
            if arena_ok(layout) {
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
                    Ok(rounded) if arena_ok(layout) || shared_size(layout).is_some() => {
                        System.alloc_zeroed(rounded)
                    }
                    _ => System.alloc_zeroed(layout),
                }
            }
        }

        #[inline]
        unsafe fn dealloc(&self, p: *mut u8, layout: Layout) {
            if worker_heap::owns(p) {
                worker_heap::free(p, layout.size());
            } else if owns(p) {
                // SAFETY: an arena block; `free` routes it to its owner.
                unsafe { super::free(p) };
            } else if layout.size() > MAX_SMALL && arena_ok(layout) {
                // SAFETY: a large block is a system block either way; the runtime keeps
                // freed ones for reuse, where the system allocator would unmap them and
                // fault the next block in again.
                unsafe { super::free(p) };
            } else {
                // SAFETY: not an arena block, so the system allocator produced it; a large one
                // is kept for the next thread without an arena to reuse.
                unsafe {
                    if shared_size(layout).is_none() || !super::shared_put(p) {
                        System.dealloc(p, layout);
                    }
                }
            }
        }

        unsafe fn realloc(&self, p: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
            let target = Layout::from_size_align(new_size, layout.align());
            let Ok(target) = target else {
                return core::ptr::null_mut();
            };
            if worker_heap::owns(p) && new_size <= layout.size() && new_size > layout.size() / 2 {
                // Shrinking a little keeps the block (its class is the same or the next one down).
                if super::class_of(new_size.max(1)) == super::class_of(layout.size().max(1)) {
                    return p;
                }
            }
            if worker_heap::owns(p) {
                // SAFETY: moves between blocks by copy; the old block is released by `dealloc`.
                unsafe {
                    let q = self.alloc(target);
                    if !q.is_null() {
                        core::ptr::copy_nonoverlapping(p, q, layout.size().min(new_size));
                        self.dealloc(p, layout);
                    }
                    return q;
                }
            }
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
