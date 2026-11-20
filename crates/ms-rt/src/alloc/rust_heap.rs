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
use core::cell::UnsafeCell;
use core::ptr::null_mut;
use core::sync::atomic::AtomicBool;
use core::sync::atomic::{AtomicPtr, AtomicU64, AtomicUsize, Ordering};
use std::sync::Once;

use super::{LARGE_MAX, MAX_SMALL};
const PAGE_SHIFT: usize = 16;
const PAGE_SIZE: usize = 1 << PAGE_SHIFT;
/// The huge page size Linux's transparent huge pages use on the supported targets.
const HUGE_PAGE: usize = 2 << 20;
/// Bytes at the start of each heap reservation that stay on small pages (see `ensure_region`): the
/// first touch of a huge page clears all of it, so a short program would pay for memory it never
/// uses. Two huge pages keep the first allocations small and the advice aligned.
const HUGE_AFTER: usize = 2 * HUGE_PAGE;
/// Address space reserved for the small-block pages of the whole process, at most; a process that
/// cannot map that much halves it (see [`ensure_region`]), so code reads [`pages_len`].
const PAGES_SIZE: usize = if cfg!(miri) { 64 << 20 } else { 256 << 30 };
/// How many times the reservation is halved before the allocator gives up and uses the system's:
/// 1.25 GiB is left at the floor (256 MiB of pages, 1 MiB growth chunks).
const MAX_SHRINK: u32 = 10;
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
/// Smallest system block that grows by remapping rather than by copying.
const REMAP_MIN: usize = 128 << 10;
/// Address space of one growing buffer; a heap takes one on first use. Chunks come from one
/// reservation next to the pages, so a block is recognised by address. A heap that finds none
/// left grows its big buffers through the system allocator.
const GROW_SIZE: usize = if cfg!(miri) { 16 << 20 } else { 1 << 30 };
// Both sizes are powers of two, so a chunk is found by a shift.
const _: () = assert!(GROW_SIZE.is_power_of_two() && PAGES_SIZE.is_power_of_two());
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

/// A lock that never allocates. `std::sync::Mutex` boxes its `pthread_mutex_t` on first use on
/// macOS, so a mutex taken inside the global allocator calls the allocator again, forever. The
/// critical sections here are a few loads and stores, so a spin with a yield is enough.
struct Lock<T> {
    held: AtomicBool,
    value: UnsafeCell<T>,
}

// SAFETY: `held` serializes every access to `value`.
unsafe impl<T: Send> Sync for Lock<T> {}

struct Guard<'a, T>(&'a Lock<T>);

impl<T> Lock<T> {
    const fn new(value: T) -> Self {
        Lock {
            held: AtomicBool::new(false),
            value: UnsafeCell::new(value),
        }
    }

    fn lock(&self) -> Guard<'_, T> {
        while self
            .held
            .compare_exchange_weak(false, true, Ordering::Acquire, Ordering::Relaxed)
            .is_err()
        {
            std::thread::yield_now();
        }
        Guard(self)
    }
}

impl<T> core::ops::Deref for Guard<'_, T> {
    type Target = T;
    fn deref(&self) -> &T {
        // SAFETY: the guard holds the lock.
        unsafe { &*self.0.value.get() }
    }
}

impl<T> core::ops::DerefMut for Guard<'_, T> {
    fn deref_mut(&mut self) -> &mut T {
        // SAFETY: the guard holds the lock.
        unsafe { &mut *self.0.value.get() }
    }
}

impl<T> Drop for Guard<'_, T> {
    fn drop(&mut self) {
        self.0.held.store(false, Ordering::Release);
    }
}

static SHARED: Lock<Shared> = Lock::new(Shared {
    free: [null_mut(); NUM_LARGE],
    cached: 0,
});

fn shared() -> Guard<'static, Shared> {
    SHARED.lock()
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
    /// Allocations left before the allocation profiler takes its next sample.
    #[cfg(feature = "alloc-profile")]
    sample_left: i64,
    /// Allocations requested and bytes asked for since start or since the last merge into
    /// [`RELEASED`].
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
            #[cfg(feature = "alloc-profile")]
            sample_left: i64::MAX,
            #[cfg(any(test, feature = "stats"))]
            live: 0,
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
/// What every free and ownership test reads, in one object so they cost one address load (a
/// static in the runtime archive is reached through the GOT, two instructions each).
#[repr(C)]
struct Hot {
    base: AtomicUsize,
    /// One `u32` per page: owner heap and class.
    table: AtomicPtr<u32>,
    grow_base: AtomicUsize,
    /// Bytes of address space the page reservation actually got (halved from [`PAGES_SIZE`] until
    /// the system accepted it).
    pages_len: AtomicUsize,
    /// log2 of the size of one growth chunk, halved along with the pages.
    grow_bits: AtomicUsize,
}

static HOT: Hot = Hot {
    base: AtomicUsize::new(UNMAPPED),
    table: AtomicPtr::new(null_mut()),
    grow_base: AtomicUsize::new(UNMAPPED),
    pages_len: AtomicUsize::new(PAGES_SIZE),
    grow_bits: AtomicUsize::new(GROW_SIZE.trailing_zeros() as usize),
};
static REGION: Once = Once::new();

#[inline(always)]
fn pages_len() -> usize {
    HOT.pages_len.load(Ordering::Relaxed)
}

#[inline(always)]
fn num_pages() -> usize {
    pages_len() >> PAGE_SHIFT
}

#[inline(always)]
fn grow_size() -> usize {
    1 << HOT.grow_bits.load(Ordering::Relaxed)
}
/// Next page not handed to any heap.
static NEXT_PAGE: AtomicUsize = AtomicUsize::new(0);
/// Bytes of the page reservation made usable (everything on Unix, grown in steps on Windows).
static COMMITTED: AtomicUsize = AtomicUsize::new(0);
static COMMIT_LOCK: Lock<()> = Lock::new(());
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
static IDLE: Lock<Vec<State>> = Lock::new(Vec::new());

/// Maps the reservation once; false when the system refuses (everything then uses it directly).
#[cold]
fn ensure_region() -> bool {
    REGION.call_once(|| {
        let Some(region) = reserve(&sys::map_anon, &|p, len| {
            // SAFETY: a mapping made by `reserve` that nothing has used.
            unsafe { sys::unmap(p, len) }
        }) else {
            return;
        };
        // Huge pages only past the first few MiB: the kernel clears a whole 2 MiB page on the first
        // touch, which costs a short program about 0.35 ms at startup for memory it never uses.
        if region.pages_len > HUGE_AFTER {
            sys::prefer_huge_pages(
                region.pages.wrapping_add(HUGE_AFTER),
                region.pages_len - HUGE_AFTER,
            );
        }
        if region.grow_len > HUGE_AFTER {
            sys::prefer_huge_pages(
                region.grow.wrapping_add(HUGE_AFTER),
                region.grow_len - HUGE_AFTER,
            );
        }
        HOT.pages_len.store(region.pages_len, Ordering::Relaxed);
        HOT.grow_bits.store(region.grow_bits, Ordering::Relaxed);
        HOT.table.store(region.table.cast(), Ordering::Relaxed);
        HOT.grow_base.store(region.grow as usize, Ordering::Relaxed);
        // Published last: a reader that sees `BASE` sees the rest.
        HOT.base.store(region.pages as usize, Ordering::Release);
    });
    HOT.base.load(Ordering::Acquire) != UNMAPPED
}

/// The address space reserved for the heap.
struct Region {
    pages: *mut u8,
    pages_len: usize,
    table: *mut u8,
    grow: *mut u8,
    grow_len: usize,
    grow_bits: usize,
}

/// Reserves the pages, their table and the growth chunks with `map`. A process with an
/// address-space limit (`ulimit -v`, a container, valgrind) cannot map the full size: the
/// reservation is halved until `map` accepts it, rather than serving every allocation from the
/// system allocator. The first size that fits would take nearly all the space left and starve what
/// comes later (thread and task stacks, the system allocator's maps), so after a refusal the heap
/// keeps a quarter of what fit. `None` when even the smallest is refused.
fn reserve(map: &dyn Fn(usize) -> *mut u8, unmap: &dyn Fn(*mut u8, usize)) -> Option<Region> {
    let try_shrink = |shrink: u32| {
        let pages_len = PAGES_SIZE >> shrink;
        let grow_size = GROW_SIZE >> shrink;
        let grow_len = grow_size * GROW_CHUNKS;
        let table_len = (pages_len >> PAGE_SHIFT) * 4;
        let (pages, table, grow) = (map(pages_len), map(table_len), map(grow_len));
        if !pages.is_null() && !table.is_null() && !grow.is_null() && sys::commit(table, table_len)
        {
            return Some(Region {
                pages,
                pages_len,
                table,
                grow,
                grow_len,
                grow_bits: grow_size.trailing_zeros() as usize,
            });
        }
        for (p, len) in [(pages, pages_len), (table, table_len), (grow, grow_len)] {
            if !p.is_null() {
                unmap(p, len);
            }
        }
        None
    };
    let fit = (0..=MAX_SHRINK).find_map(|shrink| try_shrink(shrink).map(|r| (shrink, r)))?;
    let (shrink, region) = fit;
    if shrink == 0 {
        return Some(region);
    }
    // Hand the first fit back and map a quarter of it (which the space just freed always holds).
    let smaller = (shrink + 2).min(MAX_SHRINK);
    for (p, len) in [
        (region.pages, region.pages_len),
        (region.table, (region.pages_len >> PAGE_SHIFT) * 4),
        (region.grow, region.grow_len),
    ] {
        unmap(p, len);
    }
    (smaller..=MAX_SHRINK).find_map(try_shrink)
}

/// Gives the calling thread a heap: an idle one when there is one, else a new one. Threads that
/// never call this use the system allocator.
pub fn claim_heap() {
    // SAFETY: this thread's allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    if s.heap != NO_HEAP || !ensure_region() {
        return;
    }
    let idle = IDLE.lock().pop();
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
    RELEASED[0].fetch_add(s.requested[0], Ordering::Relaxed);
    RELEASED[1].fetch_add(s.requested[1], Ordering::Relaxed);
    s.requested = [0; 2];
    #[cfg(any(test, feature = "stats"))]
    {
        s.live = 0;
    }
    // This thread has no heap from here on, so growing the list below allocates from the system.
    let saved = core::mem::replace(s, State::new());
    IDLE.lock().push(saved);
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
    let off = (p as usize).wrapping_sub(HOT.base.load(Ordering::Relaxed));
    if off >= pages_len() {
        return None;
    }
    // SAFETY: the table has one word per page of the reservation, and a block of the pages implies
    // the table was published.
    Some(unsafe { *HOT.table.load(Ordering::Relaxed).add(off >> PAGE_SHIFT) })
}

/// The growth chunk holding `p`, if any.
#[inline(always)]
fn grow_chunk_of(p: *mut u8) -> Option<usize> {
    let off = (p as usize).wrapping_sub(HOT.grow_base.load(Ordering::Relaxed));
    let chunk = off >> HOT.grow_bits.load(Ordering::Relaxed);
    (chunk < GROW_CHUNKS).then_some(chunk)
}

fn grow_base(chunk: usize) -> usize {
    HOT.grow_base.load(Ordering::Relaxed) + chunk * grow_size()
}

/// Whether `p` lies in this heap's reservation (small pages or a growth chunk).
#[inline(always)]
pub fn owns(p: *mut u8) -> bool {
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
    if page >= num_pages() {
        NEXT_PAGE.store(num_pages(), Ordering::Relaxed);
        return null_mut();
    }
    let base = HOT.base.load(Ordering::Relaxed);
    let used = (page + 1) * PAGE_SIZE;
    if used > COMMITTED.load(Ordering::Acquire) {
        let _g = COMMIT_LOCK.lock();
        let committed = COMMITTED.load(Ordering::Relaxed);
        if used > committed {
            let chunk = COMMIT_STEP
                .max(used - committed)
                .min(pages_len() - committed);
            if !sys::commit((base + committed) as *mut u8, chunk) {
                return null_mut();
            }
            COMMITTED.store(committed + chunk, Ordering::Release);
        }
    }
    // SAFETY: `page` indexes the table, which has one word per page.
    unsafe {
        *HOT.table.load(Ordering::Relaxed).add(page) = (s.heap << OWNER_SHIFT) | class as u32;
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
    s.requested[0] += 1;
    s.requested[1] += size as u64;
    #[cfg(feature = "alloc-profile")]
    {
        s.sample_left -= 1;
        if s.sample_left <= 0 {
            sample_alloc(s, size);
        }
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
                live_bucket(class, 1);
            }
            return head;
        }
    }
    alloc_slow(size)
}

/// Hands the allocation profiler one sample and arms the next. `s` is the calling thread's state.
#[cfg(feature = "alloc-profile")]
#[cold]
#[inline(never)]
fn sample_alloc(s: &mut State, size: usize) {
    s.sample_left = crate::profile::alloc_sample(size);
}

/// Starts allocation sampling on the calling thread: every `period`th allocation is a sample.
///
/// A runtime built without the `alloc-profile` feature takes no samples.
pub fn sample_every(period: i64) {
    #[cfg(feature = "alloc-profile")]
    // SAFETY: this thread's allocator state.
    unsafe {
        (*STATE.ptr()).sample_left = period
    };
    #[cfg(not(feature = "alloc-profile"))]
    let _ = period;
}

#[inline(never)]
fn alloc_slow(size: usize) -> *mut u8 {
    // Claim before borrowing the state: `claim_heap` borrows it too, which would invalidate `s`.
    if cfg!(test) && !has_heap() {
        claim_heap();
    }
    // SAFETY: this thread's allocator state.
    let s = unsafe { &mut *STATE.ptr() };
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
                live_bucket(class, 1);
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
                live_bucket(class, 1);
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
                live_bucket(NUM_CLASSES, 1);
            }
            return head;
        }
        request = large_size(class);
        let shared = shared_take(size);
        if !shared.is_null() {
            #[cfg(any(test, feature = "stats"))]
            {
                live_add(s, 1);
                live_bucket(NUM_CLASSES, 1);
            }
            return shared;
        }
    }
    // SAFETY: plain malloc.
    let p = unsafe { sys::malloc(request) } as *mut u8;
    if p.is_null() {
        crate::fault::out_of_memory(request);
    }
    if request > LARGE_MAX {
        advise_huge(p, request);
    }
    #[cfg(any(test, feature = "stats"))]
    {
        live_add(s, 1);
        live_bucket(NUM_CLASSES, 1);
    }
    p
}

/// Asks for huge pages over the whole 2 MiB units inside a block the system allocator mapped: a
/// block above [`LARGE_MAX`] is a big list or buffer whose first touch otherwise costs one page
/// fault per 4 KiB (13,000 faults and about 25 ms for a 48 MiB list on the maze workload).
fn advise_huge(p: *mut u8, len: usize) {
    let start = (p as usize).next_multiple_of(HUGE_PAGE);
    let end = (p as usize + len) & !(HUGE_PAGE - 1);
    if end > start {
        sys::prefer_huge_pages(start as *mut u8, end - start);
    }
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
    s.requested[0] += 1;
    s.requested[1] += size as u64;
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
        live_bucket(NUM_CLASSES, 1);
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
        #[cfg(any(test, feature = "stats"))]
        live_bucket(class, -1);
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
        #[cfg(any(test, feature = "stats"))]
        live_bucket(NUM_CLASSES, -1);
        grow_release(s, chunk);
    } else {
        #[cfg(any(test, feature = "stats"))]
        live_bucket(NUM_CLASSES, -1);
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

/// [`realloc`] for a block that is shrinking: a small block whose class already fits `new_size`
/// (more than half used) stays where it is, decided by one page-table read without entering
/// `realloc`.
///
/// # Safety
/// `p` is a live block from this allocator.
#[inline]
pub unsafe fn trim(p: *mut u8, new_size: usize) -> *mut u8 {
    if let Some(old) = small_size(p)
        && new_size <= old
        && new_size > old / 2
    {
        return p;
    }
    // SAFETY: caller contract.
    unsafe { realloc(p, new_size) }
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
            return grow_resize(p, new_size);
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
            unsafe { core::ptr::copy_nonoverlapping(p, q, old) };
            // The old block goes straight back: it was this buffer's own size class, and the
            // buffer now grows in the region, so a cached copy would stay resident unused (8 MiB
            // for a list that grew from a presized block).
            #[cfg(any(test, feature = "stats"))]
            {
                live_add(s, -1);
                live_bucket(NUM_CLASSES, -1);
            }
            // SAFETY: `p` is a live system block that nothing else uses.
            unsafe { sys::free(p.cast()) };
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
                crate::fault::out_of_memory(new_size);
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
        let to = len.next_multiple_of(COMMIT_STEP).min(grow_size());
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
    if (s.grow_chunk == usize::MAX && !grow_map(s)) || size > grow_size() {
        return None;
    }
    if GROW_LEN[s.grow_chunk].load(Ordering::Acquire) != 0 || !grow_commit(s, size) {
        return None;
    }
    GROW_LEN[s.grow_chunk].store(size, Ordering::Release);
    #[cfg(any(test, feature = "stats"))]
    {
        live_add(s, 1);
        live_bucket(NUM_CLASSES, 1);
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
fn grow_resize(p: *mut u8, new_size: usize) -> *mut u8 {
    // The state is borrowed in scopes that end before `alloc`, which borrows it again; a borrow
    // passed in as an argument would be live across that call.
    let chunk = {
        // SAFETY: this thread's allocator state.
        let s = unsafe { &mut *STATE.ptr() };
        if (GROW_MIN..=grow_size()).contains(&new_size) && grow_commit(s, new_size) {
            GROW_LEN[s.grow_chunk].store(new_size, Ordering::Release);
            return p;
        }
        s.grow_chunk
    };
    let old = GROW_LEN[chunk].load(Ordering::Acquire);
    let q = alloc(new_size);
    // SAFETY: `q` holds `new_size` bytes and `p` holds `old`; the blocks are disjoint.
    unsafe { core::ptr::copy_nonoverlapping(p, q, old.min(new_size)) };
    // SAFETY: this thread's allocator state.
    let s = unsafe { &mut *STATE.ptr() };
    grow_release(s, chunk);
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
    let table = HOT.table.load(Ordering::Relaxed);
    let mut carved = 0usize;
    let mut pages = 0usize;
    for page in 0..NEXT_PAGE.load(Ordering::Relaxed).min(num_pages()) {
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
    // Blocks other threads freed wait on the remote-free stack until this thread's next slow-path
    // allocation; they are free, and counting them as used made the figure depend on thread timing.
    // Only this thread drains the stack, so the chain from a loaded head stays valid.
    let mut p = REMOTE[s.heap as usize].load(Ordering::Acquire);
    while !p.is_null() {
        // SAFETY: remote blocks are small blocks of this heap with the link in word 0.
        unsafe {
            spare += CLASS_SIZES[page_word(p).unwrap_unchecked() as u8 as usize] as usize;
            p = *(p as *mut *mut u8);
        }
    }
    [
        carved.saturating_sub(spare) as i64,
        (pages * PAGE_SIZE) as i64,
    ]
}

/// `[allocations, bytes]` requested by the calling thread and by every thread that has finished
/// (released its heap). Threads still running are not included.
pub fn requested() -> [u64; 2] {
    // SAFETY: this thread's allocator state.
    let own = unsafe { (*STATE.ptr()).requested };
    [
        own[0] + RELEASED[0].load(Ordering::Relaxed),
        own[1] + RELEASED[1].load(Ordering::Relaxed),
    ]
}

/// Requests of threads that have released their heap, so that work done on a worker thread
/// stays in [`requested`].
static RELEASED: [AtomicU64; 2] = [AtomicU64::new(0), AtomicU64::new(0)];

/// Starts the `requested` counters over: called as the program's `main` begins, so that the
/// counts a gate reads cover the program and not the runtime's own start-up records (the main
/// task, its stack region), which differ by platform and change with the runtime.
#[cfg(feature = "stats")]
pub fn reset_requested() {
    // SAFETY: this thread's allocator state.
    unsafe { (*STATE.ptr()).requested = [0; 2] };
    RELEASED[0].store(0, Ordering::Relaxed);
    RELEASED[1].store(0, Ordering::Relaxed);
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

/// Live blocks per size class, the last slot counting large blocks (`stats` builds). A block that
/// `realloc` moved to another class is freed from the new one, so a bucket can read below zero;
/// the leak report shows the nonzero ones to say what kind of block outlived the program.
#[cfg(feature = "stats")]
static LIVE_BUCKETS: [core::sync::atomic::AtomicIsize; NUM_CLASSES + 1] =
    [const { core::sync::atomic::AtomicIsize::new(0) }; NUM_CLASSES + 1];

#[cfg(any(test, feature = "stats"))]
#[inline]
fn live_bucket(_bucket: usize, _delta: isize) {
    #[cfg(feature = "stats")]
    LIVE_BUCKETS[_bucket].fetch_add(_delta, Ordering::Relaxed);
}

/// `(block size, live count)` for each size class with a nonzero count; the size is 0 for large
/// blocks (`stats` builds).
#[cfg(feature = "stats")]
pub fn live_by_size() -> Vec<(usize, isize)> {
    (0..=NUM_CLASSES)
        .filter_map(|bucket| {
            let n = LIVE_BUCKETS[bucket].load(Ordering::Relaxed);
            let size = if bucket < NUM_CLASSES {
                CLASS_SIZES[bucket] as usize
            } else {
                0
            };
            (n != 0).then_some((size, n))
        })
        .collect()
}

#[cfg(any(test, feature = "stats"))]
fn live_add(s: &mut State, delta: isize) {
    s.live += delta;
    #[cfg(feature = "stats")]
    LIVE_ALL.fetch_add(delta, Ordering::Relaxed);
}

// The `msrt_heap_*` exports below mirror the C allocator's interface (runtime/include/ms_rt/alloc.h) so the
// signature table and `cargo xtask symbols --check` see them; archive builds compile this module out.

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_heap_claim() {
    claim_heap()
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_heap_release() {
    release_heap()
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_heap_has() -> u8 {
    has_heap() as u8
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_heap_owns(p: *const u8) -> u8 {
    owns(p as *mut u8) as u8
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_heap_usable_size(p: *mut u8) -> usize {
    // SAFETY: forwarded contract.
    unsafe { usable_size(p) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_heap_trim(p: *mut u8, new_size: usize) -> *mut u8 {
    // SAFETY: forwarded contract.
    unsafe { trim(p, new_size) }
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_heap_alloc_zeroed_cached(size: usize) -> *mut u8 {
    alloc_zeroed_cached(size)
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_heap_large_request(size: usize) -> usize {
    large_request(size)
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_heap_shared_take(size: usize) -> *mut u8 {
    shared_take(size)
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_heap_shared_put(p: *mut u8) -> u8 {
    // SAFETY: forwarded contract.
    unsafe { shared_put(p) as u8 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_heap_requested(out: *mut u64) {
    // SAFETY: the caller passes two writable words.
    unsafe { out.cast::<[u64; 2]>().write(requested()) }
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_heap_sample_every(period: i64, _hook: *mut u8) {
    sample_every(period)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    /// A reservation the system refuses above `limit` bytes per mapping: it is halved until the
    /// sizes fit and then quartered again to leave room, every refused attempt gives back what it mapped, and the smallest still works.
    #[test]
    #[cfg_attr(miri, ignore = "reserves address space with the real mapper")]
    fn a_refused_reservation_is_halved_until_it_fits() {
        for shrink in [0, 3, MAX_SHRINK] {
            let limit = (GROW_SIZE * GROW_CHUNKS) >> shrink;
            let live = RefCell::new(Vec::<(usize, usize)>::new());
            let map = |len: usize| {
                if len > limit {
                    return core::ptr::null_mut();
                }
                let p = sys::map_anon(len);
                live.borrow_mut().push((p as usize, len));
                p
            };
            let unmap = |p: *mut u8, len: usize| {
                // SAFETY: a mapping `map` made and `reserve` has not used.
                unsafe { sys::unmap(p, len) };
                live.borrow_mut().retain(|&(q, _)| q != p as usize);
            };
            let region = reserve(&map, &unmap).expect("a reservation that fits");
            let kept = if shrink == 0 {
                0
            } else {
                (shrink + 2).min(MAX_SHRINK)
            };
            assert_eq!(region.pages_len, PAGES_SIZE >> kept);
            assert_eq!(1usize << region.grow_bits, GROW_SIZE >> kept);
            assert_eq!(live.borrow().len(), 3, "only the accepted mappings stay");
            for (p, len) in live.borrow().iter() {
                // SAFETY: the mappings made above.
                unsafe { sys::unmap(*p as *mut u8, *len) };
            }
        }
        let refuse = |_: usize| core::ptr::null_mut();
        assert!(reserve(&refuse, &|_, _| unreachable!()).is_none());
    }

    /// Under a real address-space limit the custom allocator still serves small blocks.
    #[cfg(target_os = "linux")]
    #[test]
    #[cfg_attr(miri, ignore = "spawns a process")]
    fn the_heap_is_used_under_an_address_space_limit() {
        if std::env::var_os("MS_ALLOC_LIMIT_CHILD").is_some() {
            claim_heap();
            let p = alloc(64);
            assert!(owns(p), "the block came from the system allocator");
            assert!(pages_len() < PAGES_SIZE, "the reservation was not reduced");
            // SAFETY: a block just allocated.
            unsafe { free(p) };
            return;
        }
        let exe = std::env::current_exe().expect("test binary");
        let status = std::process::Command::new("sh")
            .arg("-c")
            .arg("ulimit -v 3000000 && exec \"$0\" --exact alloc::tests::the_heap_is_used_under_an_address_space_limit --nocapture")
            .arg(exe)
            .env("MS_ALLOC_LIMIT_CHILD", "1")
            .status()
            .expect("run the child");
        assert!(status.success(), "child failed: {status}");
    }

    use crate::testutil::lock;

    #[cfg(feature = "stats")]
    #[test]
    fn live_blocks_are_counted_by_size_class() {
        let _guard = lock();
        let class_size = |n: &[(usize, isize)], size: usize| {
            n.iter().find(|(s, _)| *s == size).map_or(0, |(_, c)| *c)
        };
        let before = live_by_size();
        let a = alloc(40);
        let b = alloc(40);
        let big = alloc(MAX_SMALL + 1);
        let held = live_by_size();
        let size = CLASS_SIZES[class_of(40)] as usize;
        assert_eq!(class_size(&held, size) - class_size(&before, size), 2);
        assert_eq!(class_size(&held, 0) - class_size(&before, 0), 1);
        // SAFETY: the blocks were allocated above and are freed once.
        unsafe {
            free(a);
            free(b);
            free(big);
        }
        let after = live_by_size();
        assert_eq!(class_size(&after, size), class_size(&before, size));
        assert_eq!(class_size(&after, 0), class_size(&before, 0));
    }

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

    /// Every byte of a 4 KiB page of a test block holds the page's tag, so a block can be filled
    /// with `write_bytes` (Miri runs a byte loop over megabytes for minutes) and still tell
    /// pages apart.
    fn tag(i: usize) -> u8 {
        (i / 4096 % 250) as u8 + 1
    }

    /// Fills `[from, to)` of `p` with the tags; `from` is a multiple of the page or zero.
    ///
    /// # Safety
    /// `p` must be valid for `to` bytes.
    unsafe fn fill(p: *mut u8, from: usize, to: usize) {
        for lo in (from..to).step_by(4096) {
            // SAFETY: the caller's range.
            unsafe { p.add(lo).write_bytes(tag(lo), (lo + 4096).min(to) - lo) };
        }
    }

    #[test]
    fn growing_a_big_block_keeps_its_bytes() {
        let _g = lock();
        let before = live_blocks();
        let mut size = REMAP_MIN;
        let mut p = alloc(size);
        // SAFETY: each block is live and holds `size` bytes when written and read.
        unsafe {
            fill(p, 0, size);
            for _ in 0..6 {
                let old = size;
                size *= 2;
                p = realloc(p, size);
                for i in (0..old).step_by(97) {
                    assert_eq!(*p.add(i), tag(i));
                }
                fill(p, old, size);
            }
            free(p);
        }
        assert_eq!(live_blocks(), before);
    }

    #[test]
    fn a_block_that_moves_into_the_growth_region_is_not_cached() {
        let _g = lock();
        let small = alloc(64); // claims the heap
        // SAFETY: this thread's allocator state.
        let cached = unsafe { (*STATE.ptr()).large_cached };
        let p = alloc(1 << 20);
        // SAFETY: `p` is a live block of 1 MiB; the grown block holds its bytes.
        unsafe {
            fill(p, 0, 1 << 20);
            let q = realloc(p, 2 << 20);
            assert!(grow_chunk_of(q).is_some());
            assert_eq!(
                (*STATE.ptr()).large_cached,
                cached,
                "the old block went back"
            );
            for i in (0..1 << 20).step_by(89) {
                assert_eq!(*q.add(i), tag(i));
            }
            free(q);
            free(small);
        }
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
            fill(p, 0, size);
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
                    assert_eq!(*p.add(i), tag(i), "byte {i} at {size}");
                }
                fill(p, old, size);
            }
            // A second big block does not get the region while the first lives.
            let other = realloc(alloc(GROW_MIN / 2), GROW_MIN);
            assert_ne!(other, home);
            free(other);
            // Shrinking below the threshold moves the bytes out and frees the region.
            let q = realloc(p, 1000);
            assert_ne!(q, home);
            for i in (0..1000).step_by(7) {
                assert_eq!(*q.add(i), tag(i));
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
        // Miri interprets every step; 2000 blocks still span many pages.
        let count = if cfg!(miri) { 2000 } else { 20000 };
        for i in 0..count as usize {
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

    /// The shared large-block lists and the heap-idle list sit behind a spin lock that yields:
    /// many more threads than cores allocating and freeing large blocks, and claiming and
    /// releasing heaps, must all finish (no livelock, no lost block).
    #[test]
    fn the_spin_lock_survives_more_threads_than_cores() {
        let _g = lock();
        let threads = 4 * std::thread::available_parallelism().map_or(4, |n| n.get());
        let handles: Vec<_> = (0..threads)
            .map(|t| {
                std::thread::spawn(move || {
                    for round in 0..40 {
                        claim_heap();
                        for i in 0..200usize {
                            let size = MAX_SMALL + 1 + (i * 37 + t) % 20_000;
                            let p = alloc(size);
                            assert!(!p.is_null());
                            // SAFETY: `p` has `size` usable bytes; freed once.
                            unsafe {
                                p.write(round as u8);
                                p.add(size - 1).write(i as u8);
                                free(p);
                            }
                        }
                        release_heap();
                    }
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
    fn heap_stats_count_a_remote_free_before_the_owner_drains_it() {
        let _g = lock();
        let p = alloc(48) as usize;
        let before = heap_stats()[0];
        std::thread::spawn(move || {
            // SAFETY: a live block of the spawning thread's arena, freed once.
            unsafe { free(p as *mut u8) };
        })
        .join()
        .unwrap();
        // No allocation has drained the remote stack, yet the block no longer counts as used.
        let size = CLASS_SIZES[class_of(48)] as i64;
        assert_eq!(before - heap_stats()[0], size);
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
