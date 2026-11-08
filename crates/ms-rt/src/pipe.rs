//! `Pipe[T]`: an in-memory stream of whole values, any number of writers and one reader.
//!
//! A pipe is one of the few objects two threads touch at once, so it synchronizes itself, and the
//! common pipe, a link from one writer to one reader, takes no lock at all. Each pipe has its own
//! cache-line-aligned cell, found by index without a lock, with two lanes for values:
//!
//! * the first lane is a single-producer, single-consumer queue of segments: while the pipe has
//!   had only its first writer, a write is one store and a read is one load;
//! * the second lane is a queue under the cell's lock, used once the pipe has had a second
//!   writer (`add_writer`): writers hand values over under the lock, and the reader takes a batch
//!   per lock acquisition into a queue only it touches.
//!
//! The reader drains the first lane before the second, so each writer's values arrive in the
//! order it wrote them (the first writer's earlier values sit in the first lane, its later ones in
//! the second). Values of different writers have no order between them beyond that. A reader that
//! finds both lanes empty and a flush that must wait publish themselves, then look once more
//! (a store, a fence, a load on each side), so a value or a wake is never lost. A value is
//! written as a block of the process heap and read by pointer, never copied deeper; a reader or
//! a flush is a promise in the table of the thread that made it, completed by event from
//! whichever thread wrote or read.
//!
//! * `write` never waits: it moves the value into the queue, or straight to a waiting reader.
//! * `read` answers a promise: ready now if a value is queued, `none` (no value) once every writer
//!   has closed and the queue is empty, otherwise pending until a write.
//! * `flush` answers a promise that finishes when no more than `capacity` values are queued, or
//!   the reader has gone.
//!
//! The pipe starts with one writer, the `Pipe` value itself; `msrt_pipe_close_writer` releases
//! it, like any other writer.
use crate::desc::slot_drop;
use crate::{alloc, promise};
use core::cell::UnsafeCell;
use core::mem::MaybeUninit;
use core::ptr::null_mut;
use ms_rt_abi::TypeDesc;
use std::collections::VecDeque;
use std::sync::atomic::{
    AtomicBool, AtomicI64, AtomicPtr, AtomicU32, AtomicUsize, Ordering, fence,
};

/// Status of `msrt_pipe_write`: the value was taken.
pub const WRITTEN: i64 = 0;
/// Status of `msrt_pipe_write`: the reader is gone, so the value was dropped.
pub const CLOSED: i64 = 1;
/// Status of `msrt_pipe_write`: the value is queued and the queue is above its capacity, so the
/// writer should wait on a flush (back pressure) without asking the pipe again.
pub const FULL: i64 = 2;

struct Item {
    ptr: usize,
    desc: usize,
}

struct Pipe {
    /// The cell this pipe lives in, to return it to the free list.
    index: usize,
    generation: u32,
    live: bool,
    queue: VecDeque<Item>,
    capacity: usize,
    writers: u32,
    reader_open: bool,
    /// Flush promises waiting for the queue to fall to `capacity`.
    flushes: Vec<i64>,
}

thread_local! {
    static OPS: std::cell::Cell<u32> = const { std::cell::Cell::new(0) };
}

/// Every 256th transfer on a thread passes a scheduler point and a cancellation check, so a task
/// that always finds work still sees timers, time limits and cancellation. Call it where the
/// operation holds nothing, because a cancel unwinds from here.
fn cancellation_point() {
    let n = OPS.with(|c| {
        c.set(c.get().wrapping_add(1));
        c.get()
    });
    if n & 0xff == 0 {
        // SAFETY: called from a task of this thread's scheduler.
        unsafe { crate::task::msrt_task_yield() };
        if crate::fault::cancel_flag().load(core::sync::atomic::Ordering::Relaxed) != 0 {
            crate::fault::msrt_cancelled();
        }
    }
}

/// A lock held for a few pointer moves, so a waiter spins instead of sleeping: a contended
/// `std::sync::Mutex` costs a futex wait and wake (microseconds) per hand-over, which made a
/// pipe between threads run 5 to 10 times slower than between tasks of one thread.
struct Spin<T> {
    locked: AtomicBool,
    value: UnsafeCell<T>,
}

// SAFETY: the flag admits one holder at a time.
unsafe impl<T: Send> Sync for Spin<T> {}

struct SpinGuard<'a, T>(&'a Spin<T>);

impl<T> Spin<T> {
    const fn new(value: T) -> Spin<T> {
        Spin {
            locked: AtomicBool::new(false),
            value: UnsafeCell::new(value),
        }
    }

    fn lock(&self) -> SpinGuard<'_, T> {
        let mut spins = 0u32;
        while self
            .locked
            .compare_exchange_weak(false, true, Ordering::Acquire, Ordering::Relaxed)
            .is_err()
        {
            // The holder may have been descheduled: give its core back after a short spin.
            while self.locked.load(Ordering::Relaxed) {
                spins += 1;
                if spins < 256 {
                    core::hint::spin_loop();
                } else {
                    std::thread::yield_now();
                }
            }
        }
        SpinGuard(self)
    }
}

impl<T> core::ops::Deref for SpinGuard<'_, T> {
    type Target = T;
    fn deref(&self) -> &T {
        // SAFETY: this guard holds the lock.
        unsafe { &*self.0.value.get() }
    }
}

impl<T> core::ops::DerefMut for SpinGuard<'_, T> {
    fn deref_mut(&mut self) -> &mut T {
        // SAFETY: this guard holds the lock.
        unsafe { &mut *self.0.value.get() }
    }
}

impl<T> Drop for SpinGuard<'_, T> {
    fn drop(&mut self) {
        self.0.locked.store(false, Ordering::Release);
    }
}

/// The most values the reader takes from the locked lane per lock acquisition (never more than
/// the pipe's capacity, so a reader's own queue is bounded by it as the shared one is).
const BATCH: usize = 256;

/// Values per segment of the first lane.
const SEG: usize = 64;

/// Cells per chunk, and chunks in the table: a pipe lives in a cell that never moves, so a cell is
/// found from its id by two loads. The table holds up to 16M pipes at once.
const CHUNK: usize = 256;
const CHUNKS: usize = 1 << 16;

/// A run of `SEG` values of the first lane, linked to the next.
struct Seg {
    slots: [UnsafeCell<MaybeUninit<Item>>; SEG],
    next: AtomicPtr<Seg>,
}

impl Seg {
    fn new() -> *mut Seg {
        Box::into_raw(Box::new(Seg {
            slots: [const { UnsafeCell::new(MaybeUninit::uninit()) }; SEG],
            next: AtomicPtr::new(null_mut()),
        }))
    }
}

/// What the pipe's flags say, read by every writer and written rarely, on a line of their own.
#[repr(align(128))]
struct Shared {
    /// The generation of the live pipe in this cell, 0 when none.
    live_generation: AtomicU32,
    /// Set for good by the first `add_writer`: later writes use the locked lane.
    multi: AtomicBool,
    reader_open: AtomicBool,
    capacity: AtomicUsize,
    /// The id of the read promise waiting for a value, 0 when none. Whoever swaps it to 0 owns the
    /// duty to finish that read.
    waiting: AtomicI64,
    /// Whether some flush promise waits for the queue to fall to its capacity.
    flush_pending: AtomicBool,
    /// Values in the locked lane, for the writers of the first lane to count.
    queue_len: AtomicUsize,
}

/// The first lane's writer half.
#[repr(align(128))]
struct Producer {
    produced: AtomicUsize,
    /// The first segment, published once for the consumer.
    first: AtomicPtr<Seg>,
    tail: UnsafeCell<*mut Seg>,
    /// The last `consumed` the writer saw, so a write reads the reader's line only when the
    /// queue might be over capacity.
    seen_consumed: UnsafeCell<usize>,
}

/// The first lane's reader half, and the reader's own queues.
#[repr(align(128))]
struct Consumer {
    consumed: AtomicUsize,
    /// The last `produced` the reader saw, so a read reads the writer's line only when it has
    /// caught up with it.
    seen_produced: UnsafeCell<usize>,
    head: UnsafeCell<*mut Seg>,
    /// Values handed back by a dropped read: they come out first.
    front: UnsafeCell<VecDeque<Item>>,
    /// Values taken from the locked lane ahead of reading them.
    local: UnsafeCell<VecDeque<Item>>,
}

/// One pipe, its parts on cache lines of their own so a writer never invalidates a line the
/// reader works on, and two busy pipes never share a line. `producer` is touched by the first
/// writer only, `consumer` by the reader only (or, while the reader is parked and has been claimed,
/// by the writer that finishes its read).
#[repr(align(128))]
struct Cell {
    pipe: Spin<Pipe>,
    shared: Shared,
    producer: Producer,
    consumer: Consumer,
}

// SAFETY: `pipe` is a lock, `shared` is atomic, and the other two halves each have one user at a time.
unsafe impl Sync for Cell {}

impl Cell {
    fn new(index: usize) -> Cell {
        Cell {
            pipe: Spin::new(Pipe {
                index,
                generation: 0,
                live: false,
                queue: VecDeque::new(),
                capacity: 0,
                writers: 0,
                reader_open: false,
                flushes: Vec::new(),
            }),
            shared: Shared {
                live_generation: AtomicU32::new(0),
                multi: AtomicBool::new(false),
                reader_open: AtomicBool::new(false),
                capacity: AtomicUsize::new(0),
                waiting: AtomicI64::new(0),
                flush_pending: AtomicBool::new(false),
                queue_len: AtomicUsize::new(0),
            },
            producer: Producer {
                produced: AtomicUsize::new(0),
                first: AtomicPtr::new(null_mut()),
                tail: UnsafeCell::new(null_mut()),
                seen_consumed: UnsafeCell::new(0),
            },
            consumer: Consumer {
                consumed: AtomicUsize::new(0),
                seen_produced: UnsafeCell::new(0),
                head: UnsafeCell::new(null_mut()),
                front: UnsafeCell::new(VecDeque::new()),
                local: UnsafeCell::new(VecDeque::new()),
            },
        }
    }

    /// Appends to the first lane.
    ///
    /// # Safety
    /// Only the first writer may call this.
    unsafe fn lane_push(&self, item: Item) {
        let n = self.producer.produced.load(Ordering::Relaxed);
        // SAFETY: the producer owns `tail`.
        let tail = unsafe { &mut *self.producer.tail.get() };
        if n.is_multiple_of(SEG) {
            let seg = Seg::new();
            if n == 0 {
                self.producer.first.store(seg, Ordering::Release);
            } else {
                // SAFETY: `tail` is the segment this producer filled last.
                unsafe { (**tail).next.store(seg, Ordering::Release) };
            }
            *tail = seg;
        }
        // SAFETY: the slot is past `produced`, so the consumer does not read it yet.
        unsafe { (**tail).slots[n % SEG].get().write(MaybeUninit::new(item)) };
        self.producer.produced.store(n + 1, Ordering::Release);
    }

    /// Takes the oldest value of the first lane.
    ///
    /// # Safety
    /// Only the reader (or the writer finishing a claimed read) may call this.
    unsafe fn lane_pop(&self) -> Option<Item> {
        let c = self.consumer.consumed.load(Ordering::Relaxed);
        // SAFETY: the consumer owns `seen_produced`.
        let seen = unsafe { &mut *self.consumer.seen_produced.get() };
        if c == *seen {
            *seen = self.producer.produced.load(Ordering::Acquire);
            if c == *seen {
                return None;
            }
        }
        // SAFETY: the consumer owns `head`.
        let head = unsafe { &mut *self.consumer.head.get() };
        if c.is_multiple_of(SEG) {
            *head = if c == 0 {
                self.producer.first.load(Ordering::Acquire)
            } else {
                let old = *head;
                // SAFETY: `old` is fully read, and the producer linked its successor before it
                // published the value at `c`.
                unsafe {
                    let next = (*old).next.load(Ordering::Acquire);
                    drop(Box::from_raw(old));
                    next
                }
            };
        }
        // SAFETY: the producer published this slot before `produced` passed it.
        let item = unsafe { (**head).slots[c % SEG].get().read().assume_init() };
        self.consumer.consumed.store(c + 1, Ordering::Release);
        Some(item)
    }

    /// Whether the queues hold more than the capacity, after the sole writer's push. It reads the
    /// reader's progress only when the values written since the last look exceed the capacity.
    ///
    /// # Safety
    /// Only the first writer may call this.
    unsafe fn lane_over(&self) -> bool {
        let cap = self.shared.capacity.load(Ordering::Relaxed);
        let produced = self.producer.produced.load(Ordering::Relaxed);
        // SAFETY: forwarded contract.
        let seen = unsafe { &mut *self.producer.seen_consumed.get() };
        if produced - *seen + self.shared.queue_len.load(Ordering::Relaxed) <= cap {
            return false;
        }
        *seen = self.consumer.consumed.load(Ordering::Acquire);
        produced - *seen + self.shared.queue_len.load(Ordering::Relaxed) > cap
    }

    fn lane_len(&self) -> usize {
        let consumed = self.consumer.consumed.load(Ordering::Acquire);
        self.producer
            .produced
            .load(Ordering::Acquire)
            .saturating_sub(consumed)
    }

    /// Values queued and not yet read: both lanes (not the reader's own queues).
    fn backlog(&self) -> usize {
        self.lane_len() + self.shared.queue_len.load(Ordering::Relaxed)
    }

    /// The reader's queue of handed-back values.
    ///
    /// # Safety
    /// Only the reader may call this, and not while it holds another reference to the queue.
    #[allow(clippy::mut_from_ref)]
    unsafe fn front(&self) -> &mut VecDeque<Item> {
        // SAFETY: forwarded contract.
        unsafe { &mut *self.consumer.front.get() }
    }

    /// The reader's queue of values taken from the locked lane.
    ///
    /// # Safety
    /// As for `front`.
    #[allow(clippy::mut_from_ref)]
    unsafe fn local(&self) -> &mut VecDeque<Item> {
        // SAFETY: forwarded contract.
        unsafe { &mut *self.consumer.local.get() }
    }

    /// The value the reader can take without the lock: a handed-back one, then the first lane,
    /// then the batch taken from the locked lane.
    ///
    /// # Safety
    /// As for `front`.
    unsafe fn take_ready(&self) -> Option<Item> {
        // SAFETY: forwarded contract.
        unsafe {
            if let Some(item) = self.front().pop_front() {
                return Some(item);
            }
            if let Some(item) = self.lane_pop() {
                return Some(item);
            }
            self.local().pop_front()
        }
    }

    /// Frees every value still queued and both lanes' segments, and resets them for the next pipe.
    ///
    /// # Safety
    /// No writer or reader is left (every writer closed, the reader closed).
    unsafe fn clear(&self) {
        // SAFETY: forwarded contract.
        unsafe {
            while let Some(item) = self.take_ready() {
                free_block(&item);
            }
            let head = *self.consumer.head.get();
            if !head.is_null() {
                drop(Box::from_raw(head));
            }
            *self.consumer.head.get() = null_mut();
            *self.producer.tail.get() = null_mut();
        }
        self.producer.first.store(null_mut(), Ordering::Relaxed);
        self.producer.produced.store(0, Ordering::Relaxed);
        self.consumer.consumed.store(0, Ordering::Relaxed);
        // SAFETY: no writer or reader is left.
        unsafe {
            *self.producer.seen_consumed.get() = 0;
            *self.consumer.seen_produced.get() = 0;
        }
        self.shared.queue_len.store(0, Ordering::Relaxed);
    }

    /// Takes over the read promise that waits, if any.
    fn claim_reader(&self) -> Option<i64> {
        if self.shared.waiting.load(Ordering::Acquire) == 0 {
            return None;
        }
        let id = self.shared.waiting.swap(0, Ordering::AcqRel);
        (id != 0).then_some(id)
    }
}

/// The cells of the live and retired pipes, and the indexes of the retired ones. Only creating and
/// retiring a pipe take this lock.
struct Registry {
    count: usize,
    free: Vec<usize>,
}

static REGISTRY: Spin<Registry> = Spin::new(Registry {
    count: 0,
    free: Vec::new(),
});

static TABLE: [AtomicPtr<Cell>; CHUNKS] = [const { AtomicPtr::new(null_mut()) }; CHUNKS];

fn cell_at(index: usize) -> Option<&'static Cell> {
    let chunk = TABLE.get(index / CHUNK)?.load(Ordering::Acquire);
    if chunk.is_null() {
        return None;
    }
    // SAFETY: a published chunk holds `CHUNK` cells and is never freed.
    Some(unsafe { &*chunk.add(index % CHUNK) })
}

fn index_of(id: i64) -> Option<usize> {
    usize::try_from((id & 0xffff_ffff) - 1).ok()
}

/// The cell of pipe `id`, when that pipe is live.
fn cell_for(id: i64) -> Option<&'static Cell> {
    let cell = cell_at(index_of(id)?)?;
    (i64::from(cell.shared.live_generation.load(Ordering::Acquire)) == id >> 32).then_some(cell)
}

/// The cell of pipe `id` with its lock held, when that pipe is still live.
fn locked(id: i64) -> Option<(&'static Cell, SpinGuard<'static, Pipe>)> {
    let cell = cell_at(index_of(id)?)?;
    let p = cell.pipe.lock();
    (p.live && i64::from(p.generation) == id >> 32).then_some((cell, p))
}

fn free_block(item: &Item) {
    // SAFETY: the block holds an owned value of its descriptor that nobody took.
    unsafe {
        slot_drop(&*(item.desc as *const TypeDesc), item.ptr as *mut u8);
        alloc::free(item.ptr as *mut u8);
    }
}

/// Frees the pipe when its last writer and its reader are gone.
fn retire(cell: &Cell, p: &mut Pipe) {
    if p.writers == 0 && !p.reader_open {
        for item in p.queue.drain(..) {
            free_block(&item);
        }
        p.live = false;
        p.queue = VecDeque::new();
        cell.shared.live_generation.store(0, Ordering::Release);
        // SAFETY: no writer and no reader is left.
        unsafe { cell.clear() };
        if p.generation < 0x7fff_ffff {
            REGISTRY.lock().free.push(p.index);
        }
    }
}

/// The next value for the reader from the locked lane, with a batch behind it moved into the
/// reader's own queue, so the following reads need no lock.
fn take_batch(cell: &Cell, p: &mut Pipe) -> Option<Item> {
    let item = p.queue.pop_front()?;
    let more = p.queue.len().min(p.capacity.clamp(1, BATCH) - 1);
    // SAFETY: this is the reader, and nothing else holds its queue here.
    unsafe { cell.local().extend(p.queue.drain(..more)) };
    cell.shared
        .queue_len
        .store(p.queue.len(), Ordering::Relaxed);
    Some(item)
}

/// The flushes that no longer wait, once the queues have fallen to the capacity.
fn take_flushes(cell: &Cell, p: &mut Pipe) -> Vec<i64> {
    if cell.backlog() > p.capacity {
        return Vec::new();
    }
    let ids = core::mem::take(&mut p.flushes);
    cell.shared.flush_pending.store(false, Ordering::SeqCst);
    ids
}

fn complete_flushes(ids: Vec<i64>) {
    for id in ids {
        promise::io_done_unit(id);
    }
}

/// After the reader took a value: lets the flushes that now fit go.
fn after_consume(cell: &Cell) {
    fence(Ordering::SeqCst);
    if cell.shared.flush_pending.load(Ordering::Relaxed) {
        let released = {
            let mut p = cell.pipe.lock();
            take_flushes(cell, &mut p)
        };
        complete_flushes(released);
    }
}

/// Creates a pipe whose writers' `flush` waits above `capacity` queued values.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_new(capacity: i64) -> i64 {
    let index = {
        let mut registry = REGISTRY.lock();
        match registry.free.pop() {
            Some(i) => i,
            None => {
                let i = registry.count;
                if i.is_multiple_of(CHUNK) {
                    let Some(slot) = TABLE.get(i / CHUNK) else {
                        drop(registry);
                        crate::fault::fault(b"pipe: too many pipes are open at once");
                    };
                    let chunk: Box<[Cell]> = (i..i + CHUNK).map(Cell::new).collect();
                    slot.store(Box::leak(chunk).as_mut_ptr(), Ordering::Release);
                }
                registry.count += 1;
                i
            }
        }
    };
    let cell = cell_at(index).expect("a pipe cell exists once its index is handed out");
    let mut p = cell.pipe.lock();
    p.generation += 1;
    p.live = true;
    p.capacity = capacity.max(0) as usize;
    p.writers = 1;
    p.reader_open = true;
    p.flushes.clear();
    cell.shared.capacity.store(p.capacity, Ordering::Relaxed);
    cell.shared.multi.store(false, Ordering::Relaxed);
    cell.shared.reader_open.store(true, Ordering::Relaxed);
    cell.shared.waiting.store(0, Ordering::Relaxed);
    cell.shared.flush_pending.store(false, Ordering::Relaxed);
    cell.shared
        .live_generation
        .store(p.generation, Ordering::Release);
    (i64::from(p.generation) << 32) | (index as i64 + 1)
}

/// Another writing end, like `dup` on a descriptor. From now on every write goes to the locked
/// lane, the first lane only draining.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_add_writer(pipe: i64) {
    if let Some((cell, mut p)) = locked(pipe) {
        p.writers += 1;
        cell.shared.multi.store(true, Ordering::Release);
    }
}

/// Moves `value` into the pipe and answers `WRITTEN` (`FULL` when the queue now exceeds the capacity), or `CLOSED` (the value is dropped) when the
/// reader is gone. It never waits.
///
/// # Safety
/// `value` holds an owned value of `d`, which the callee takes.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_pipe_write(
    pipe: i64,
    value: *mut u8,
    d: ms_rt_abi::ValueDesc,
) -> i64 {
    // SAFETY: forwarded contract.
    let ptr = unsafe {
        let size = (*d).size as usize;
        let block = alloc::alloc(size.max(1));
        core::ptr::copy_nonoverlapping(value, block, size);
        block as usize
    };
    let item = Item {
        ptr,
        desc: d as usize,
    };
    let Some(cell) = cell_for(pipe) else {
        free_block(&item);
        return CLOSED;
    };
    if !cell.shared.multi.load(Ordering::Acquire) {
        // The only writer: the first lane, with no lock.
        if !cell.shared.reader_open.load(Ordering::Acquire) {
            free_block(&item);
            return CLOSED;
        }
        // SAFETY: while the pipe has had one writer, this is it.
        unsafe { cell.lane_push(item) };
        fence(Ordering::SeqCst);
        if let Some(reader) = cell.claim_reader() {
            // The reader is parked and claimed: finish its read with the oldest value.
            // SAFETY: the claim makes this the only user of the reader's side.
            let first =
                unsafe { cell.lane_pop() }.expect("a claimed reader finds the value just written");
            promise::io_done_block(reader, first.ptr, first.desc, pipe);
            return WRITTEN;
        }
        // SAFETY: the sole writer owns `seen_consumed`.
        let over = unsafe { cell.lane_over() };
        cancellation_point();
        return if over { FULL } else { WRITTEN };
    }
    let reader = match locked(pipe) {
        Some((cell, mut p)) if p.reader_open => {
            p.queue.push_back(item);
            cell.shared
                .queue_len
                .store(p.queue.len(), Ordering::Relaxed);
            match cell.claim_reader() {
                Some(reader) => {
                    // The reader was parked, so the queue held nothing else.
                    let first = p.queue.pop_front().expect("the value just queued");
                    cell.shared
                        .queue_len
                        .store(p.queue.len(), Ordering::Relaxed);
                    (reader, first)
                }
                None => {
                    let status = if cell.backlog() > p.capacity {
                        FULL
                    } else {
                        WRITTEN
                    };
                    drop(p);
                    cancellation_point();
                    return status;
                }
            }
        }
        _ => {
            free_block(&item);
            return CLOSED;
        }
    };
    promise::io_done_block(reader.0, reader.1.ptr, reader.1.desc, pipe);
    WRITTEN
}

/// The read promise's cancel hook: the reader leaves the pipe's wait.
fn reader_cancelled(id: i64, pipe: usize, _bits: u32) -> bool {
    if let Some(cell) = cell_for(pipe as i64) {
        let _ = cell
            .shared
            .waiting
            .compare_exchange(id, 0, Ordering::AcqRel, Ordering::Relaxed);
    }
    false
}

/// Starts a read: answers a promise for the next value. It finishes with the value (take it with
/// `msrt_promise_take`), or with none once every writer has closed and the queues are empty. A pipe
/// has one reader, so a second read while one is pending faults.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_read(pipe: i64) -> i64 {
    let id = promise::io_new();
    let Some(cell) = cell_for(pipe) else {
        promise::io_done(id);
        return id;
    };
    enum Next {
        Value(Item, Vec<i64>),
        End,
        Wait,
        Again,
    }
    loop {
        // SAFETY: this is the reader.
        if let Some(item) = unsafe { cell.take_ready() } {
            after_consume(cell);
            promise::io_done_block(id, item.ptr, item.desc, pipe);
            return id;
        }
        let next = {
            let Some((cell, mut p)) = locked(pipe) else {
                promise::io_done(id);
                return id;
            };
            if cell.shared.waiting.load(Ordering::Acquire) != 0 {
                drop(p);
                crate::fault::fault(b"pipe: a read is already waiting");
            }
            if let Some(item) = take_batch(cell, &mut p) {
                let released = take_flushes(cell, &mut p);
                Next::Value(item, released)
            } else if p.writers == 0 {
                // Every writer closed; what they wrote before closing is visible by now.
                if cell.lane_len() == 0 {
                    Next::End
                } else {
                    Next::Again
                }
            } else {
                cell.shared.waiting.store(id, Ordering::SeqCst);
                fence(Ordering::SeqCst);
                if cell.lane_len() == 0 {
                    Next::Wait
                } else if cell
                    .shared
                    .waiting
                    .compare_exchange(id, 0, Ordering::AcqRel, Ordering::Relaxed)
                    .is_ok()
                {
                    Next::Again
                } else {
                    // A writer claimed this read first and will finish it.
                    Next::Wait
                }
            }
        };
        match next {
            Next::Again => {}
            Next::Value(item, released) => {
                complete_flushes(released);
                promise::io_done_block(id, item.ptr, item.desc, pipe);
                return id;
            }
            Next::End => {
                promise::io_done(id);
                return id;
            }
            Next::Wait => {
                promise::on_drop(id, reader_cancelled, pipe as usize);
                return id;
            }
        }
    }
}

/// Takes the next queued value without a promise: moves it to `out` and answers 1, or answers 0
/// when nothing is queued (the reader then waits through `msrt_pipe_read`, or ends if
/// `msrt_pipe_ended`). Like `msrt_pipe_read` it makes room for flushes waiting on the capacity.
///
/// # Safety
/// `out` is writable memory for a value of `d`, the descriptor the writer used.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_pipe_try(
    pipe: i64,
    d: ms_rt_abi::ValueDesc,
    out: *mut u8,
) -> u8 {
    cancellation_point();
    let Some(cell) = cell_for(pipe) else {
        return 0;
    };
    // SAFETY: this is the reader.
    let item = match unsafe { cell.take_ready() } {
        Some(item) => {
            after_consume(cell);
            item
        }
        None => {
            let (item, released) = {
                let Some((cell, mut p)) = locked(pipe) else {
                    return 0;
                };
                let Some(item) = take_batch(cell, &mut p) else {
                    return 0;
                };
                (item, take_flushes(cell, &mut p))
            };
            complete_flushes(released);
            item
        }
    };
    // SAFETY: the block holds an owned value of the writer's descriptor, which has the size `d`
    // names; it moves out and the block is freed.
    unsafe {
        core::ptr::copy_nonoverlapping(item.ptr as *const u8, out, (*d).size as usize);
        alloc::free(item.ptr as *mut u8);
    }
    1
}

/// Whether a read would finish with no value: every writer has closed and nothing is queued.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_ended(pipe: i64) -> i64 {
    let Some((cell, p)) = locked(pipe) else {
        return 1;
    };
    // SAFETY: this is the reader.
    let held = unsafe { !cell.front().is_empty() || !cell.local().is_empty() };
    (p.writers == 0 && p.queue.is_empty() && cell.lane_len() == 0 && !held) as i64
}

/// Starts a flush: answers a promise that finishes when no more than `capacity` values are queued
/// or the reader is gone.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_flush(pipe: i64) -> i64 {
    let id = promise::io_new();
    let waits = match locked(pipe) {
        Some((cell, mut p)) if p.reader_open && cell.backlog() > p.capacity => {
            p.flushes.push(id);
            cell.shared.flush_pending.store(true, Ordering::SeqCst);
            fence(Ordering::SeqCst);
            if cell.backlog() > p.capacity {
                true
            } else {
                // The reader caught up while this flush registered.
                p.flushes.retain(|&f| f != id);
                if p.flushes.is_empty() {
                    cell.shared.flush_pending.store(false, Ordering::SeqCst);
                }
                false
            }
        }
        _ => false,
    };
    if waits {
        promise::on_drop(id, flush_cancelled, pipe as usize);
    } else {
        promise::io_done_unit(id);
    }
    id
}

/// The flush promise's cancel hook: it leaves the pipe's list.
fn flush_cancelled(id: i64, pipe: usize, _bits: u32) -> bool {
    if let Some((cell, mut p)) = locked(pipe as i64) {
        p.flushes.retain(|&f| f != id);
        if p.flushes.is_empty() {
            cell.shared.flush_pending.store(false, Ordering::SeqCst);
        }
    }
    false
}

/// Closes one writing end. When the last one closes, a waiting read finishes with none.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_close_writer(pipe: i64) {
    let reader = {
        let Some((cell, mut p)) = locked(pipe) else {
            return;
        };
        p.writers = p.writers.saturating_sub(1);
        // A parked reader means both lanes were empty when it parked, and a write since would
        // have claimed it, so it ends.
        let reader = if p.writers == 0 && p.queue.is_empty() && cell.lane_len() == 0 {
            cell.claim_reader()
        } else {
            None
        };
        retire(cell, &mut p);
        reader
    };
    if let Some(reader) = reader {
        promise::io_done(reader);
    }
}

/// Closes the reading end: queued values are dropped, waiting flushes finish, and later writes
/// answer `CLOSED`.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_pipe_close_reader(pipe: i64) {
    let flushes = {
        let Some((cell, mut p)) = locked(pipe) else {
            return;
        };
        p.reader_open = false;
        cell.shared.reader_open.store(false, Ordering::Release);
        cell.shared.waiting.store(0, Ordering::Release);
        for item in p.queue.drain(..) {
            free_block(&item);
        }
        cell.shared.queue_len.store(0, Ordering::Relaxed);
        // SAFETY: this is the reader.
        while let Some(item) = unsafe { cell.take_ready() } {
            free_block(&item);
        }
        let flushes = core::mem::take(&mut p.flushes);
        cell.shared.flush_pending.store(false, Ordering::SeqCst);
        retire(cell, &mut p);
        flushes
    };
    complete_flushes(flushes);
}

/// Gives a value that was read but never taken (its promise was dropped first) back to the front
/// of the pipe, or drops it when the pipe has no reader.
pub(crate) fn unread(pipe: i64, ptr: usize, desc: usize) {
    let item = Item { ptr, desc };
    match locked(pipe) {
        // SAFETY: the dropped read was the reader's.
        Some((cell, p)) if p.reader_open => unsafe { cell.front().push_front(item) },
        _ => free_block(&item),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::desc::msrt_desc_int;
    use crate::promise::{
        msrt_promise_drop, msrt_promise_put, msrt_promise_start, msrt_promise_take,
        msrt_promise_wait,
    };
    use crate::sched;
    use crate::testutil::lock;
    use ms_rt_abi::Closure;

    /// How many values are queued and not yet read.
    fn msrt_pipe_buffered(pipe: i64) -> i64 {
        locked(pipe).map_or(0, |(cell, _)| cell.backlog() as i64)
    }

    fn write_int(pipe: i64, mut v: i64) -> i64 {
        // SAFETY: `v` is an Int slot the call takes.
        unsafe { msrt_pipe_write(pipe, (&raw mut v).cast(), &msrt_desc_int) }
    }

    /// Waits for a read promise: the value, or `None` at the end.
    fn finish(read: i64) -> Option<i64> {
        assert_eq!(msrt_promise_wait(read, -1), promise::OK);
        let mut v = 0i64;
        // SAFETY: `v` is an Int slot.
        let some = unsafe { msrt_promise_take(read, &msrt_desc_int, (&raw mut v).cast()) } == 1;
        msrt_promise_drop(read);
        some.then_some(v)
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn values_come_out_whole_and_in_order_then_the_end() {
        let _g = lock();
        let pipe = msrt_pipe_new(4);
        for v in [1, 2, 3] {
            assert_eq!(write_int(pipe, v), WRITTEN);
        }
        assert_eq!(msrt_pipe_buffered(pipe), 3);
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(1));
        // A read that finds nothing waits for the write.
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(2));
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(3));
        let waiting = msrt_pipe_read(pipe);
        assert_eq!(promise::msrt_promise_done(waiting), 0);
        assert_eq!(write_int(pipe, 4), WRITTEN);
        assert_eq!(finish(waiting), Some(4));
        // The end: every writer closed and the queue empty.
        let end = msrt_pipe_read(pipe);
        msrt_pipe_close_writer(pipe);
        assert_eq!(finish(end), None);
        assert_eq!(finish(msrt_pipe_read(pipe)), None);
        msrt_pipe_close_reader(pipe);
        crate::task::teardown();
    }

    fn try_int(pipe: i64) -> Option<i64> {
        let mut v = 0i64;
        // SAFETY: `v` is an Int slot.
        let some = unsafe { msrt_pipe_try(pipe, &msrt_desc_int, (&raw mut v).cast()) } == 1;
        some.then_some(v)
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn try_takes_queued_values_without_a_promise_and_releases_flushes() {
        let _g = lock();
        let pipe = msrt_pipe_new(1);
        assert_eq!(try_int(pipe), None);
        assert_eq!(msrt_pipe_ended(pipe), 0);
        write_int(pipe, 1);
        write_int(pipe, 2);
        write_int(pipe, 3);
        let waiting = msrt_pipe_flush(pipe);
        assert_eq!(promise::msrt_promise_done(waiting), 0);
        assert_eq!(try_int(pipe), Some(1));
        assert_eq!(try_int(pipe), Some(2));
        assert_eq!(finish_unit(waiting), promise::OK);
        assert_eq!(try_int(pipe), Some(3));
        assert_eq!(try_int(pipe), None);
        msrt_pipe_close_writer(pipe);
        assert_eq!(msrt_pipe_ended(pipe), 1);
        assert_eq!(try_int(pipe), None);
        msrt_pipe_close_reader(pipe);
        crate::task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_flush_waits_above_capacity_and_a_closed_reader_refuses_writes() {
        let _g = lock();
        let pipe = msrt_pipe_new(1);
        assert_eq!(write_int(pipe, 1), WRITTEN);
        let at_capacity = msrt_pipe_flush(pipe);
        assert_eq!(finish_unit(at_capacity), promise::OK);
        assert_eq!(write_int(pipe, 2), FULL);
        assert_eq!(write_int(pipe, 3), FULL);
        let waiting = msrt_pipe_flush(pipe);
        assert_eq!(promise::msrt_promise_done(waiting), 0);
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(1));
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(2));
        assert_eq!(finish_unit(waiting), promise::OK);
        msrt_pipe_close_reader(pipe);
        assert_eq!(write_int(pipe, 9), CLOSED);
        msrt_pipe_close_writer(pipe);
        crate::task::teardown();
    }

    fn finish_unit(id: i64) -> i64 {
        let code = msrt_promise_wait(id, -1);
        msrt_promise_drop(id);
        code
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_dropped_read_leaves_the_queue_alone() {
        let _g = lock();
        let pipe = msrt_pipe_new(4);
        let read = msrt_pipe_read(pipe);
        msrt_promise_drop(read);
        // The next write queues the value instead of handing it to the dropped read.
        assert_eq!(write_int(pipe, 7), WRITTEN);
        assert_eq!(msrt_pipe_buffered(pipe), 1);
        assert_eq!(finish(msrt_pipe_read(pipe)), Some(7));
        msrt_pipe_close_writer(pipe);
        msrt_pipe_close_reader(pipe);
        crate::task::teardown();
    }

    unsafe extern "C-unwind" fn writer(closure: *mut Closure) {
        // SAFETY: the closure carries its promise's id and the pipe after the header.
        unsafe {
            let data = closure.add(1).cast::<i64>();
            let (id, pipe) = (data.read(), data.add(1).read());
            for v in 0..50 {
                write_int(pipe, v);
                crate::task::msrt_task_yield();
            }
            msrt_pipe_close_writer(pipe);
            let mut done = 1i64;
            msrt_promise_put(id, (&raw mut done).cast(), &msrt_desc_int, 0);
        }
    }

    unsafe extern "C" fn drop_closure(obj: *mut ms_rt_abi::Obj) {
        // SAFETY: the test closure has no captures and owns this allocation.
        unsafe { crate::alloc::free(obj.cast()) };
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn writers_on_other_threads_feed_one_reader() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        let pipe = msrt_pipe_new(8);
        let writers: Vec<i64> = (0..3).map(|_| promise::msrt_promise_new()).collect();
        for &id in &writers {
            msrt_pipe_add_writer(pipe);
            // SAFETY: the promise owns the closure it is handed until its task has ended.
            unsafe {
                let size = size_of::<Closure>() + 16;
                let closure = crate::obj::new_obj(size, None, drop_closure).cast::<Closure>();
                (*closure).code = writer as *const u8;
                let data = closure.add(1).cast::<i64>();
                data.write(id);
                data.add(1).write(pipe);
                msrt_promise_start(id, closure);
            }
        }
        // The Pipe value's own writer goes: the three writers keep the pipe open.
        msrt_pipe_close_writer(pipe);
        let mut seen = vec![0usize; 50];
        let mut count = 0;
        while let Some(v) = finish(msrt_pipe_read(pipe)) {
            seen[v as usize] += 1;
            count += 1;
        }
        assert_eq!(count, 150);
        assert!(seen.iter().all(|&n| n == 3));
        for id in writers {
            msrt_promise_drop(id);
        }
        msrt_pipe_close_reader(pipe);
        sched::shutdown();
        crate::task::teardown();
    }

    unsafe extern "C-unwind" fn counting_writer(closure: *mut Closure) {
        // SAFETY: as for `writer`.
        unsafe {
            let data = closure.add(1).cast::<i64>();
            let (id, pipe) = (data.read(), data.add(1).read());
            for v in 0..100_000 {
                write_int(pipe, v);
            }
            msrt_pipe_close_writer(pipe);
            let mut done = 1i64;
            msrt_promise_put(id, (&raw mut done).cast(), &msrt_desc_int, 0);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_sole_writer_on_another_thread_keeps_order_without_a_lock() {
        let _g = lock();
        sched::msrt_runtime_set_threads(4);
        let pipe = msrt_pipe_new(64);
        let id = promise::msrt_promise_new();
        // SAFETY: the promise owns the closure it is handed until its task has ended.
        unsafe {
            let size = size_of::<Closure>() + 16;
            let closure = crate::obj::new_obj(size, None, drop_closure).cast::<Closure>();
            (*closure).code = counting_writer as *const u8;
            let data = closure.add(1).cast::<i64>();
            data.write(id);
            data.add(1).write(pipe);
            msrt_promise_start(id, closure);
        }
        let mut next = 0;
        while let Some(v) = finish(msrt_pipe_read(pipe)) {
            assert_eq!(v, next);
            next += 1;
        }
        assert_eq!(next, 100_000);
        msrt_promise_drop(id);
        msrt_pipe_close_reader(pipe);
        sched::shutdown();
        crate::task::teardown();
    }

    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn a_second_writer_after_writes_keeps_each_writers_order() {
        let _g = lock();
        let pipe = msrt_pipe_new(64);
        for v in 0..3 {
            write_int(pipe, v);
        }
        msrt_pipe_add_writer(pipe);
        for v in 3..6 {
            write_int(pipe, v);
        }
        assert_eq!(msrt_pipe_buffered(pipe), 6);
        msrt_pipe_close_writer(pipe);
        msrt_pipe_close_writer(pipe);
        let got: Vec<i64> = std::iter::from_fn(|| finish(msrt_pipe_read(pipe))).collect();
        assert_eq!(got, [0, 1, 2, 3, 4, 5]);
        msrt_pipe_close_reader(pipe);
        crate::task::teardown();
    }
}
