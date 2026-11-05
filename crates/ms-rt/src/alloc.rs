//! Size-class allocator: one heap for the whole process.
//!
//! Small blocks (up to [`MAX_SMALL`] bytes) come from 64 KiB pages carved out of one large
//! lazily-committed reservation shared by every thread. Each page serves a single size class and
//! belongs to one heap; a side table with one word per page records the class and the owner, so
//! `free` needs no size and treats every block alike, whichever thread allocated it.
//!
//! A thread that claims a heap ([`claim_heap`]) allocates from its own pages without locks. A block
//! freed by another thread is pushed onto its owner's lock-free remote-free stack, found by the
//! owner index in the page table, and the owner drains it on its next slow-path allocation. When a
//! thread releases its heap ([`release_heap`]) the heap keeps its pages and free lists and the
//! next thread to claim one adopts it, so nothing is unmapped and a block outlives its thread.
//! Threads that never claimed a heap (pool and helper threads) allocate from the system allocator.
//!
//! Large blocks go to the system allocator, with freed blocks up to [`LARGE_MAX`] kept in
//! per-size free lists so growing and rebuilding big lists does not map and unmap memory
//! (musl's malloc does a `mmap`/`munmap` pair for every block above a few KiB).
use crate::sys;
use core::ptr::null_mut;
use core::sync::atomic::{AtomicPtr, AtomicUsize, Ordering};
use std::sync::{Mutex, Once};

pub const MAX_SMALL: usize = 2048;
const PAGE_SHIFT: usize = 16;
const PAGE_SIZE: usize = 1 << PAGE_SHIFT;
/// Address space reserved for the small-block pages of the whole process.
const PAGES_SIZE: usize = if cfg!(miri) { 64 << 20 } else { 256 << 30 };
const NUM_PAGES: usize = PAGES_SIZE >> PAGE_SHIFT;
/// Heaps that can exist at once (the owner field of the page table is 16 bits); a thread that
/// finds none left uses the system allocator.
const MAX_HEAPS: usize = 1 << 16;
/// Page-table word: owner heap in the upper bits, size class in the low byte.
const OWNER_SHIFT: u32 = 8;
/// Owner of no heap: the state of a thread that has not claimed one.
const NO_HEAP: u32 = u32::MAX;
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
/// Address space of one growing buffer; a heap takes one on first use. Chunks come from one
/// reservation next to the pages, so a block is recognised by address. A heap that finds none
/// left grows its big buffers through the system allocator.
const GROW_SIZE: usize = if cfg!(miri) { 16 << 20 } else { 1 << 30 };
const GROW_CHUNKS: usize = if cfg!(miri) { 4 } else { 1024 };
/// A block grows in the growth region once it reaches this size.
const GROW_MIN: usize = 32 << 10;
/// Resident bytes the growth region keeps after its block is freed; the rest goes back.
const GROW_KEEP: usize = 64 << 20;
/// Bytes the large free lists may hold before further frees go back to the system.
const LARGE_CACHE_LIMIT: usize = 64 << 20;
/// Most blocks of one large class a thread keeps for itself; further frees go to the shared
/// lists, where threads without a heap (blocking-pool jobs) find them.
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
    /// Index of this thread's heap, or [`NO_HEAP`].
    heap: u32,
    free: [*mut u8; NUM_CLASSES],
    bump: [*mut u8; NUM_CLASSES],
    bump_end: [*mut u8; NUM_CLASSES],
    large_free: [*mut u8; NUM_LARGE],
    /// Blocks held in each `large_free` list.
    large_count: [u8; NUM_LARGE],
    /// Usable bytes held in `large_free`.
    large_cached: usize,
    /// This heap's growth chunk (index into the growth reservation), or `usize::MAX`: address
    /// space for the one buffer that is growing, so that it extends in place instead of being
    /// copied at every doubling. Its live length is in [`GROW_LEN`].
    grow_chunk: usize,
    /// Bytes of the chunk made usable so far.
    grow_committed: usize,
    #[cfg(any(test, feature = "stats"))]
    live: isize,
    /// Allocations requested and bytes asked for since start (`stats` builds).
    #[cfg(feature = "stats")]
    requested: [u64; 2],
}

impl State {
    const fn new() -> State {
        State {
            heap: NO_HEAP,
            free: [null_mut(); NUM_CLASSES],
            bump: [null_mut(); NUM_CLASSES],
            bump_end: [null_mut(); NUM_CLASSES],
            large_free: [null_mut(); NUM_LARGE],
            large_count: [0; NUM_LARGE],
            large_cached: 0,
            grow_chunk: usize::MAX,
            grow_committed: 0,
            #[cfg(any(test, feature = "stats"))]
            live: 0,
            #[cfg(feature = "stats")]
            requested: [0; 2],
        }
    }
}

// SAFETY: a saved state holds block pointers that no thread uses until it is adopted.
unsafe impl Send for State {}

crate::isolate_static! {
static STATE: State = State::new();
}

/// The process's reservation: small-block pages, their table, and the growth chunks.
/// Until it is mapped they sit at an address no pointer reaches, so no block is ever inside them.
const UNMAPPED: usize = 1 << (usize::BITS - 1);
static BASE: AtomicUsize = AtomicUsize::new(UNMAPPED);
/// One `u32` per page: owner heap and class.
static TABLE: AtomicPtr<u32> = AtomicPtr::new(null_mut());
static GROW_BASE: AtomicUsize = AtomicUsize::new(UNMAPPED);
static REGION: Once = Once::new();
/// Next page not handed to any heap.
static NEXT_PAGE: AtomicUsize = AtomicUsize::new(0);
/// Bytes of the page reservation made usable (everything on Unix, grown in steps on Windows).
static COMMITTED: AtomicUsize = AtomicUsize::new(0);
static COMMIT_LOCK: Mutex<()> = Mutex::new(());
/// Next growth chunk not taken.
static NEXT_CHUNK: AtomicUsize = AtomicUsize::new(0);
/// Length of the block living in each growth chunk, 0 when the chunk is free. Any thread frees a
/// block by clearing its length; the heap owning the chunk takes it again.
static GROW_LEN: [AtomicUsize; GROW_CHUNKS] = [const { AtomicUsize::new(0) }; GROW_CHUNKS];
/// Head of the blocks other threads freed into each heap.
static REMOTE: [AtomicPtr<u8>; MAX_HEAPS] = [const { AtomicPtr::new(null_mut()) }; MAX_HEAPS];
/// Heaps handed out so far.
static HEAP_COUNT: AtomicUsize = AtomicUsize::new(0);
/// Heaps whose thread ended, with their free lists and partly used pages.
static IDLE: Mutex<Vec<State>> = Mutex::new(Vec::new());

/// Maps the reservation once; false when the system refuses (everything then uses it directly).
#[cold]
fn ensure_region() -> bool {
    REGION.call_once(|| {
        let pages = sys::map_anon(PAGES_SIZE);
        let table = sys::map_anon(NUM_PAGES * 4);
        let grow = sys::map_anon(GROW_SIZE * GROW_CHUNKS);
        if pages.is_null() || table.is_null() || grow.is_null() {
            return;
        }
        if !sys::commit(table, NUM_PAGES * 4) {
            return;
        }
        TABLE.store(table.cast(), Ordering::Relaxed);
        GROW_BASE.store(grow as usize, Ordering::Relaxed);
        // Published last: a reader that sees `BASE` sees the rest.
        BASE.store(pages as usize, Ordering::Release);
    });
    BASE.load(Ordering::Acquire) != UNMAPPED
}

/// Gives the calling thread a heap: an idle one when there is one, else a new one. Threads that
/// never call this use the system allocator.
pub fn claim_heap() {
    // SAFETY: this thread's allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    if s.heap != NO_HEAP || !ensure_region() {
        return;
    }
    let idle = IDLE.lock().unwrap_or_else(|e| e.into_inner()).pop();
    if let Some(adopted) = idle {
        *s = adopted;
        return;
    }
    let heap = HEAP_COUNT.fetch_add(1, Ordering::Relaxed);
    if heap >= MAX_HEAPS {
        HEAP_COUNT.store(MAX_HEAPS, Ordering::Relaxed);
        return;
    }
    s.heap = heap as u32;
}

/// Hands the calling thread's heap to the next thread that claims one as its thread ends. Blocks
/// allocated from it stay valid and may be freed from any thread.
pub fn release_heap() {
    // SAFETY: this thread's allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    if s.heap == NO_HEAP {
        return;
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
    #[cfg(any(test, feature = "stats"))]
    {
        s.live = 0;
    }
    // This thread has no heap from here on, so growing the list below allocates from the system.
    let saved = core::mem::replace(s, State::new());
    IDLE.lock().unwrap_or_else(|e| e.into_inner()).push(saved);
}

/// Whether the calling thread has a heap.
#[inline(always)]
pub fn has_heap() -> bool {
    // SAFETY: this thread's allocator state.
    unsafe { (*STATE.ptr()).heap != NO_HEAP }
}

/// Page-table word of the small-block page holding `p`, or `None` when `p` is not in the pages.
#[inline(always)]
fn page_word(p: *mut u8) -> Option<u32> {
    let off = (p as usize).wrapping_sub(BASE.load(Ordering::Relaxed));
    if off >= PAGES_SIZE {
        return None;
    }
    // SAFETY: the table has one word per page of the reservation, and a block of the pages implies
    // the table was published.
    Some(unsafe { *TABLE.load(Ordering::Relaxed).add(off >> PAGE_SHIFT) })
}

/// The growth chunk holding `p`, if any.
#[inline(always)]
fn grow_chunk_of(p: *mut u8) -> Option<usize> {
    let off = (p as usize).wrapping_sub(GROW_BASE.load(Ordering::Relaxed));
    (off < GROW_SIZE * GROW_CHUNKS).then_some(off / GROW_SIZE)
}

fn grow_base(chunk: usize) -> usize {
    GROW_BASE.load(Ordering::Relaxed) + chunk * GROW_SIZE
}

/// Whether `p` lies in this heap's reservation (small pages or a growth chunk).
#[cfg(target_os = "linux")]
#[inline(always)]
fn owns(p: *mut u8) -> bool {
    page_word(p).is_some() || grow_chunk_of(p).is_some()
}

/// Pushes a block onto its owning heap's remote-free stack.
///
/// # Safety
/// `p` is a live small block owned by the caller, in a page of heap `heap`.
unsafe fn remote_free(heap: usize, p: *mut u8) {
    let stack = &REMOTE[heap];
    let mut head = stack.load(Ordering::Relaxed);
    loop {
        // SAFETY: a freed block is at least 16 bytes and holds the link in its first word.
        unsafe { *(p as *mut *mut u8) = head };
        match stack.compare_exchange_weak(head, p, Ordering::Release, Ordering::Relaxed) {
            Ok(_) => return,
            Err(h) => head = h,
        }
    }
}

/// Moves the blocks other threads freed into this heap onto its free lists.
#[cold]
fn drain_remote(s: &mut State) {
    let mut p = REMOTE[s.heap as usize].swap(null_mut(), Ordering::Acquire);
    while !p.is_null() {
        // SAFETY: remote blocks are small blocks of this heap with the link in word 0.
        unsafe {
            let next = *(p as *mut *mut u8);
            let class = page_word(p).unwrap_unchecked() as u8 as usize;
            *(p as *mut *mut u8) = s.free[class];
            s.free[class] = p;
            p = next;
        }
    }
}

#[cold]
fn refill(s: &mut State, class: usize) -> *mut u8 {
    let page = NEXT_PAGE.fetch_add(1, Ordering::Relaxed);
    if page >= NUM_PAGES {
        NEXT_PAGE.store(NUM_PAGES, Ordering::Relaxed);
        return null_mut();
    }
    let base = BASE.load(Ordering::Relaxed);
    let used = (page + 1) * PAGE_SIZE;
    if used > COMMITTED.load(Ordering::Acquire) {
        let _g = COMMIT_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let committed = COMMITTED.load(Ordering::Relaxed);
        if used > committed {
            let chunk = COMMIT_STEP
                .max(used - committed)
                .min(PAGES_SIZE - committed);
            if !sys::commit((base + committed) as *mut u8, chunk) {
                return null_mut();
            }
            COMMITTED.store(committed + chunk, Ordering::Release);
        }
    }
    // SAFETY: `page` indexes the table, which has one word per page.
    unsafe {
        *TABLE.load(Ordering::Relaxed).add(page) = (s.heap << OWNER_SHIFT) | class as u32;
    }
    let start = (base + page * PAGE_SIZE) as *mut u8;
    let size = CLASS_SIZES[class] as usize;
    // SAFETY: the page lies inside the reserved pages.
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
    // SAFETY: this thread's allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    #[cfg(feature = "stats")]
    {
        s.requested[0] += 1;
        s.requested[1] += size as u64;
    }
    if size <= MAX_SMALL {
        let class = class_of(size.max(1));
        let head = s.free[class];
        if !head.is_null() {
            // SAFETY: free blocks store the next pointer in their first word.
            s.free[class] = unsafe { *(head as *mut *mut u8) };
            #[cfg(any(test, feature = "stats"))]
            {
                live_add(s, 1);
            }
            return head;
        }
    }
    alloc_slow(size)
}

#[inline(never)]
fn alloc_slow(size: usize) -> *mut u8 {
    // SAFETY: this thread's allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    if cfg!(test) && s.heap == NO_HEAP {
        claim_heap();
    }
    if size <= MAX_SMALL && s.heap != NO_HEAP {
        if !REMOTE[s.heap as usize].load(Ordering::Relaxed).is_null() {
            drain_remote(s);
        }
        let class = class_of(size.max(1));
        let head = s.free[class];
        if !head.is_null() {
            // SAFETY: free blocks store the next pointer in their first word.
            s.free[class] = unsafe { *(head as *mut *mut u8) };
            #[cfg(any(test, feature = "stats"))]
            {
                live_add(s, 1);
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
                live_add(s, 1);
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
                live_add(s, 1);
            }
            return head;
        }
        request = large_size(class);
        let shared = shared_take(size);
        if !shared.is_null() {
            #[cfg(any(test, feature = "stats"))]
            {
                live_add(s, 1);
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
        live_add(s, 1);
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
    #[cfg(feature = "stats")]
    {
        s.requested[0] += 1;
        s.requested[1] += size as u64;
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
        live_add(s, 1);
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

/// Frees a block returned by [`alloc`] or [`realloc`] on any thread. Null is ignored.
///
/// # Safety
/// `p` must be null or a live block from this allocator.
#[inline]
pub unsafe fn free(p: *mut u8) {
    if p.is_null() {
        return;
    }
    // SAFETY: this thread's allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    #[cfg(any(test, feature = "stats"))]
    {
        live_add(s, -1);
    }
    if let Some(word) = page_word(p) {
        let class = word as u8 as usize;
        let owner = word >> OWNER_SHIFT;
        if owner == s.heap {
            // SAFETY: a freed block is at least 16 bytes, so it can hold the free-list link in its
            // first word.
            unsafe {
                // The counting runtime scribbles over freed blocks so a use after free shows up.
                #[cfg(any(test, feature = "stats"))]
                core::ptr::write_bytes(p, 0xDD, CLASS_SIZES[class] as usize);
                *(p as *mut *mut u8) = s.free[class];
            }
            s.free[class] = p;
        } else {
            // SAFETY: a live small block of another heap's page, owned by the caller.
            unsafe { remote_free(owner as usize, p) };
        }
    } else if let Some(chunk) = grow_chunk_of(p) {
        grow_release(s, chunk);
    } else {
        // SAFETY: not a block of the reservation, so it came from malloc/realloc.
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
    if s.heap != NO_HEAP
        && (1 << LARGE_MIN_SHIFT..=LARGE_MAX).contains(&usable)
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
    if let Some(chunk) = grow_chunk_of(p) {
        return GROW_LEN[chunk].load(Ordering::Acquire);
    }
    match small_size(p) {
        Some(n) => n,
        // SAFETY: not a block of the pages, so it came from malloc/realloc.
        None => unsafe { sys::malloc_usable_size(p.cast()) },
    }
}

/// Block size when `p` is a small block of any heap.
fn small_size(p: *mut u8) -> Option<usize> {
    page_word(p).map(|word| CLASS_SIZES[word as u8 as usize] as usize)
}

/// Resizes a block, preserving the common prefix.
///
/// # Safety
/// `p` must be null or a live block from this allocator.
pub unsafe fn realloc(p: *mut u8, new_size: usize) -> *mut u8 {
    if p.is_null() {
        return alloc(new_size);
    }
    // SAFETY: this thread's allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    if let Some(chunk) = grow_chunk_of(p) {
        if chunk == s.grow_chunk {
            return grow_resize(s, p, new_size);
        }
        // Another heap's growing buffer: the bytes move out and its chunk is freed.
        let old = GROW_LEN[chunk].load(Ordering::Acquire);
        let q = alloc(new_size);
        // SAFETY: `q` holds `new_size` bytes and `p` holds `old`; the blocks are disjoint.
        unsafe {
            core::ptr::copy_nonoverlapping(p, q, old.min(new_size));
            free(p);
        }
        return q;
    }
    if let Some(old) = small_size(p) {
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
        // A big block that is growing moves into the growth region once, and extends there in
        // place from then on.
        if new_size > old
            && new_size >= GROW_MIN
            && let Some(q) = grow_take(s, new_size)
        {
            // SAFETY: both blocks are valid for `old` bytes and do not overlap.
            unsafe {
                core::ptr::copy_nonoverlapping(p, q, old);
                free(p);
            }
            return q;
        }
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

/// Takes a growth chunk for this heap; false when none is left.
#[cold]
fn grow_map(s: &mut State) -> bool {
    if s.heap == NO_HEAP {
        return false;
    }
    let chunk = NEXT_CHUNK.fetch_add(1, Ordering::Relaxed);
    if chunk >= GROW_CHUNKS {
        NEXT_CHUNK.store(GROW_CHUNKS, Ordering::Relaxed);
        return false;
    }
    s.grow_chunk = chunk;
    s.grow_committed = 0;
    true
}

/// Makes the first `len` bytes of the growth chunk usable; false when the system refuses.
fn grow_commit(s: &mut State, len: usize) -> bool {
    if len > s.grow_committed {
        let to = len.next_multiple_of(COMMIT_STEP).min(GROW_SIZE);
        if !sys::commit(
            (grow_base(s.grow_chunk) + s.grow_committed) as *mut u8,
            to - s.grow_committed,
        ) {
            return false;
        }
        s.grow_committed = to;
    }
    true
}

/// A block of `size` bytes at the start of this heap's growth chunk, or none when it is taken or
/// too small.
fn grow_take(s: &mut State, size: usize) -> Option<*mut u8> {
    if (s.grow_chunk == usize::MAX && !grow_map(s)) || size > GROW_SIZE {
        return None;
    }
    if GROW_LEN[s.grow_chunk].load(Ordering::Acquire) != 0 || !grow_commit(s, size) {
        return None;
    }
    GROW_LEN[s.grow_chunk].store(size, Ordering::Release);
    #[cfg(any(test, feature = "stats"))]
    {
        live_add(s, 1);
    }
    Some(grow_base(s.grow_chunk) as *mut u8)
}

/// Frees the block in growth chunk `chunk`, from any thread. Its pages stay resident for the next
/// buffer unless there are many and the chunk is this heap's.
fn grow_release(s: &mut State, chunk: usize) {
    if chunk == s.grow_chunk && s.grow_committed > GROW_KEEP {
        // SAFETY: the owner trims, and nothing lives in the chunk once its length is cleared.
        unsafe { sys::release(grow_base(chunk) as *mut u8, s.grow_committed) };
        s.grow_committed = 0;
    }
    GROW_LEN[chunk].store(0, Ordering::Release);
}

/// Resizes the block in this heap's growth chunk: in place while it stays big, otherwise out of it.
fn grow_resize(s: &mut State, p: *mut u8, new_size: usize) -> *mut u8 {
    if (GROW_MIN..=GROW_SIZE).contains(&new_size) && grow_commit(s, new_size) {
        GROW_LEN[s.grow_chunk].store(new_size, Ordering::Release);
        return p;
    }
    let old = GROW_LEN[s.grow_chunk].load(Ordering::Acquire);
    let q = alloc(new_size);
    // SAFETY: `q` holds `new_size` bytes and `p` holds `old`; the blocks are disjoint.
    unsafe { core::ptr::copy_nonoverlapping(p, q, old.min(new_size)) };
    grow_release(s, s.grow_chunk);
    #[cfg(any(test, feature = "stats"))]
    {
        live_add(s, -1);
    }
    q
}

/// Small-block heap figures in bytes for the calling thread's heap: `[used, in_use_pages]`. `used`
/// counts blocks handed out and not on a free list; large blocks belong to the system allocator and
/// are not included. Walks the page table and the free lists, so it is meant for occasional
/// diagnostics.
pub fn heap_stats() -> [i64; 2] {
    // SAFETY: this thread's allocator state.
    let s = unsafe { &*STATE.ptr() };
    if s.heap == NO_HEAP {
        return [0; 2];
    }
    let table = TABLE.load(Ordering::Relaxed);
    let mut carved = 0usize;
    let mut pages = 0usize;
    for page in 0..NEXT_PAGE.load(Ordering::Relaxed).min(NUM_PAGES) {
        // SAFETY: `page` is below the pages handed out, which the table covers.
        let word = unsafe { *table.add(page) };
        if word >> OWNER_SHIFT == s.heap {
            let size = CLASS_SIZES[word as u8 as usize] as usize;
            carved += PAGE_SIZE / size * size;
            pages += 1;
        }
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
        (pages * PAGE_SIZE) as i64,
    ]
}

/// `[allocations, bytes]` requested since start (the `stats` feature).
#[cfg(feature = "stats")]
pub fn requested() -> [u64; 2] {
    // SAFETY: this thread's allocator state.
    unsafe { (*STATE.ptr()).requested }
}

/// Starts the `requested` counters over: called as the program's `main` begins, so that the
/// counts a gate reads cover the program and not the runtime's own start-up records (the main
/// task, its stack region), which differ by platform and change with the runtime.
#[cfg(feature = "stats")]
pub fn reset_requested() {
    // SAFETY: this thread's allocator state.
    unsafe { (*STATE.ptr()).requested = [0; 2] };
}

/// Live allocation count (tests and the `stats` feature). Counting builds count the whole
/// process, since a block may be freed on another thread than the one that allocated it.
#[cfg(feature = "stats")]
pub fn live_blocks() -> isize {
    LIVE_ALL.load(Ordering::Relaxed)
}

/// Live allocation count of the calling thread (tests).
#[cfg(all(test, not(feature = "stats")))]
pub fn live_blocks() -> isize {
    // SAFETY: this thread's allocator state.
    unsafe { (*STATE.ptr()).live }
}

/// Live blocks of the whole process (the `stats` feature).
#[cfg(feature = "stats")]
static LIVE_ALL: core::sync::atomic::AtomicIsize = core::sync::atomic::AtomicIsize::new(0);

#[cfg(any(test, feature = "stats"))]
fn live_add(s: &mut State, delta: isize) {
    s.live += delta;
    #[cfg(feature = "stats")]
    LIVE_ALL.fetch_add(delta, Ordering::Relaxed);
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
    fn a_growing_block_extends_in_place_and_shrinks_out() {
        let _g = lock();
        let before = live_blocks();
        let small = alloc(64); // maps the arena
        let mut size = 4096;
        let mut p = alloc(size);
        // SAFETY: each block is live and holds `size` bytes when written and read.
        unsafe {
            for i in 0..size {
                *p.add(i) = (i % 251) as u8;
            }
            let mut home: *mut u8 = null_mut();
            while size < 8 << 20 {
                let old = size;
                size *= 2;
                p = realloc(p, size);
                if size >= GROW_MIN {
                    if home.is_null() {
                        home = p;
                    }
                    assert_eq!(p, home, "grew in place at {size}");
                    assert_eq!(usable_size(p), size);
                }
                for i in (0..old).step_by(89) {
                    assert_eq!(*p.add(i), (i % 251) as u8, "byte {i} at {size}");
                }
                for i in old..size {
                    *p.add(i) = (i % 251) as u8;
                }
            }
            // A second big block does not get the region while the first lives.
            let other = realloc(alloc(GROW_MIN / 2), GROW_MIN);
            assert_ne!(other, home);
            free(other);
            // Shrinking below the threshold moves the bytes out and frees the region.
            let q = realloc(p, 1000);
            assert_ne!(q, home);
            for i in (0..1000).step_by(7) {
                assert_eq!(*q.add(i), (i % 251) as u8);
            }
            let again = realloc(alloc(GROW_MIN / 2), GROW_MIN);
            assert_eq!(again, home, "the region is free again");
            free(again);
            free(q);
            free(small);
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

    #[test]
    fn a_released_heap_is_adopted_with_its_blocks() {
        let _g = lock();
        // A thread's blocks stay valid after it ends, any thread frees them, and the next thread
        // to claim a heap takes over its free blocks.
        let (heap, block) = std::thread::spawn(|| {
            claim_heap();
            let p = alloc(64) as usize;
            // SAFETY: a live block of 64 bytes.
            unsafe { core::ptr::write_bytes(p as *mut u8, 0xAB, 64) };
            let keep = alloc(64);
            // SAFETY: `keep` is live and freed once.
            unsafe { free(keep) };
            let heap = unsafe { (*STATE.ptr()).heap };
            release_heap();
            (heap, (p, keep as usize))
        })
        .join()
        .unwrap();
        let (p, keep) = block;
        // SAFETY: the block outlived its thread; this is the only free.
        unsafe {
            assert_eq!(*(p as *const u8), 0xAB);
            assert_eq!(small_size(p as *mut u8), Some(64));
            free(p as *mut u8);
        }
        std::thread::spawn(move || {
            claim_heap();
            // SAFETY: this thread's state.
            assert_eq!(unsafe { (*STATE.ptr()).heap }, heap);
            // The adopted free list hands back the block freed before the thread ended.
            assert_eq!(alloc(64) as usize, keep);
        })
        .join()
        .unwrap();
    }

    #[test]
    fn more_than_256_heaps_exist_at_once() {
        let _g = lock();
        let gate = std::sync::Arc::new(std::sync::Barrier::new(300));
        let handles: Vec<_> = (0..300)
            .map(|_| {
                let gate = gate.clone();
                std::thread::spawn(move || {
                    claim_heap();
                    let p = alloc(100);
                    assert!(has_heap());
                    gate.wait();
                    // SAFETY: allocated above, freed once.
                    unsafe { free(p) };
                    gate.wait();
                    release_heap();
                })
            })
            .collect();
        for h in handles {
            h.join().unwrap();
        }
    }

    #[test]
    fn every_kind_of_block_frees_and_resizes_on_any_thread() {
        let _g = lock();
        let small = alloc(48) as usize;
        let large = alloc(100_000) as usize;
        let mut grown = alloc(GROW_MIN / 2);
        // SAFETY: live blocks; each resized and freed once.
        unsafe {
            grown = realloc(grown, GROW_MIN * 2);
            assert!(grow_chunk_of(grown).is_some());
            core::ptr::write_bytes(grown, 0x5A, GROW_MIN * 2);
        }
        let grown = grown as usize;
        std::thread::spawn(move || {
            claim_heap();
            // SAFETY: blocks of another heap, each resized or freed once.
            unsafe {
                let small = realloc(small as *mut u8, 3000);
                free(small);
                free(large as *mut u8);
                let g = realloc(grown as *mut u8, GROW_MIN * 3);
                assert_eq!(*g.add(GROW_MIN * 2 - 1), 0x5A);
                free(g);
            }
            release_heap();
        })
        .join()
        .unwrap();
        // The foreign free cleared the growth chunk, so its owner can grow a buffer again.
        // SAFETY: live and freed once.
        unsafe {
            let again = realloc(alloc(GROW_MIN / 2), GROW_MIN);
            assert!(grow_chunk_of(again).is_some());
            free(again);
        }
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
/// threads that claimed a heap (isolates) allocate from it; every other thread uses the system
/// allocator. A block any thread frees is routed to its page's owner.
#[cfg(target_os = "linux")]
pub struct StdHeap;

#[cfg(target_os = "linux")]
mod std_heap {
    use super::{LARGE_MAX, MAX_SMALL, StdHeap, has_heap, owns};
    use core::alloc::{GlobalAlloc, Layout};
    use std::alloc::System;

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
