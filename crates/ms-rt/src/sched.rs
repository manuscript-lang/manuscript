//! Scheduler threads: where `promise(fn)` runs.
//!
//! The program starts on one thread. A promise started with `promise(fn)` is placed on a thread:
//! the caller's own, or the next one in round-robin order when that one has less to do (the
//! caller itself is not counted). A thread starts the first time a promise is placed on it, up to
//! the core count (`msrt_runtime_set_threads` or `MS_THREADS` change the limit), so a program that
//! never overlaps work stays on one thread.
//!
//! Each thread is an isolate with its own task scheduler and poller. Its only shared state is its
//! `Slot`: a load figure other threads read, a queue of promises that have not started, and a
//! mailbox of events. A promise that has started never moves; one that has not can be taken by an
//! idle thread. Values cross by pointer through the one process heap, never copied.
//!
//! The promise itself (state, waiter, result) stays in the table of the thread that created it.
//! The thread that runs the work reports to it by event: `Started`, `Done` with the result block,
//! and `Ended` when the task is over. The creator applies events when its scheduler next looks,
//! and is woken for them like for any remote post.
use crate::isolate;
use std::collections::VecDeque;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU32, AtomicU64, AtomicUsize, Ordering};

/// Most scheduler threads. The thread index lives in six bits of a promise id.
pub const MAX_THREADS: usize = 63;
/// The index of a thread that is not a scheduler thread (a worker isolate): it runs its own
/// promises itself.
pub const NONE: usize = 63;

/// Per scheduler thread: how many native streams last used there are still alive.
static PINNED: [AtomicUsize; MAX_THREADS] = [const { AtomicUsize::new(0) }; MAX_THREADS];

/// Whether a live native stream was last used on the calling thread. A promise started from such
/// a thread runs on it: a stream's two ends share one non-atomic session, so every task that
/// might use it stays on the thread that does.
pub(crate) fn pinned_here() -> bool {
    let me = current();
    me < MAX_THREADS && PINNED[me].load(Ordering::Relaxed) > 0
}

/// A native stream's place: the thread that last used it. A fresh stream has none, so promises
/// that capture it stay free to be placed anywhere until it is first used.
pub struct Pin(core::cell::Cell<usize>);

impl Pin {
    pub const fn new() -> Pin {
        Pin(core::cell::Cell::new(usize::MAX))
    }

    /// Records a use on the calling thread; the pin follows the stream to where it is used.
    pub fn touch(&self) {
        let now = current();
        let before = self.0.get();
        if before == now {
            return;
        }
        if before < MAX_THREADS {
            PINNED[before].fetch_sub(1, Ordering::Relaxed);
        }
        if now < MAX_THREADS {
            PINNED[now].fetch_add(1, Ordering::Relaxed);
        }
        self.0.set(now);
    }
}

impl Default for Pin {
    fn default() -> Pin {
        Pin::new()
    }
}

impl Drop for Pin {
    fn drop(&mut self) {
        let at = self.0.get();
        if at < MAX_THREADS {
            PINNED[at].fetch_sub(1, Ordering::Relaxed);
        }
    }
}

/// A promise that has not started: its id and its closure.
pub(crate) struct Start {
    pub id: i64,
    pub closure: usize,
}

/// What a thread tells another about a promise.
pub(crate) enum Event {
    /// To the creator: the work runs as task `task` on `thread`.
    Started { id: i64, thread: u8, task: u64 },
    /// To the creator: the work produced a value (or the operation's own error). The result block
    /// is in the process heap and now belongs to the promise.
    /// A null `ptr` completes without a value (the end of a pipe, a finished flush). `pipe` names
    /// the pipe the value was read from, or 0: if the promise is gone by the time this arrives,
    /// the value goes back to the front of that pipe, since a cancelled read takes no value.
    Done {
        id: i64,
        failed: bool,
        ptr: usize,
        desc: usize,
        pipe: i64,
    },
    /// To the creator: the task is over, by return (0), fault (1, with the report) or
    /// cancellation (2). The creator may release the closure now.
    Ended {
        id: i64,
        status: u8,
        report: Vec<u8>,
    },
    /// To the creator: a cancel switch fired; stop the promise if it has not finished.
    Stop { id: i64 },
    /// To the runner: cancel the promise's task `task` (a stale handle is ignored).
    Cancel { task: u64 },
}

struct Mail {
    pending: VecDeque<Start>,
    events: Vec<Event>,
}

/// One thread's shared state, on its own cache line.
#[repr(align(64))]
struct Slot {
    /// Tasks ready or running, published by the thread at each switch.
    busy: AtomicU32,
    /// Promise tasks started here and not yet ended, running or waiting. A thread with none is free
    /// to take work from another; one with some is not, so a sleeper's thread is not given a spinner.
    live: AtomicU32,
    /// Promises waiting in `mail.pending`.
    pending: AtomicU32,
    /// Whether `mail.events` may hold events.
    signalled: AtomicU32,
    /// The registry slot of the thread's isolate, or `usize::MAX` before it runs.
    isolate: AtomicUsize,
    /// The token the thread's root task parks on; posting it lets the thread end.
    root: AtomicU64,
    mail: Mutex<Mail>,
}

impl Slot {
    const fn new() -> Self {
        Slot {
            busy: AtomicU32::new(0),
            live: AtomicU32::new(0),
            pending: AtomicU32::new(0),
            signalled: AtomicU32::new(0),
            isolate: AtomicUsize::new(usize::MAX),
            root: AtomicU64::new(0),
            mail: Mutex::new(Mail {
                pending: VecDeque::new(),
                events: Vec::new(),
            }),
        }
    }
}

static SLOTS: [Slot; MAX_THREADS] = [const { Slot::new() }; MAX_THREADS];
/// How many threads have been started (index 0 is the main thread, started with the program).
static STARTED: AtomicUsize = AtomicUsize::new(1);
/// Bit `i` is set while thread `i` blocks in its poller with nothing to run.
static IDLE: AtomicU64 = AtomicU64::new(0);
/// The most threads to start; 0 until the first promise is placed.
static LIMIT: AtomicUsize = AtomicUsize::new(0);
/// Set when the program ends: scheduler threads leave their loop.
static STOP: AtomicU32 = AtomicU32::new(0);
static HANDLES: Mutex<Vec<std::thread::JoinHandle<()>>> = Mutex::new(Vec::new());

crate::isolate_static! {
    /// This thread's index, or `usize::MAX` before it has one.
    static INDEX: usize = usize::MAX;
    /// The thread after which the next promise is offered.
    static CURSOR: usize = 0;
}

fn lock(m: &Mutex<Mail>) -> std::sync::MutexGuard<'_, Mail> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// The calling thread's index: 0 for the main thread, the thread's own for a scheduler thread,
/// `NONE` for any other isolate.
pub(crate) fn current() -> usize {
    // SAFETY: this isolate's state.
    let index = unsafe { &mut *INDEX.ptr() };
    if *index == usize::MAX {
        if isolate::is_main() {
            *index = 0;
            SLOTS[0].isolate.store(isolate::id(), Ordering::Release);
        } else {
            *index = NONE;
        }
    }
    *index
}

/// The most scheduler threads the program may run.
pub(crate) fn limit() -> usize {
    let n = LIMIT.load(Ordering::SeqCst);
    if n != 0 {
        return n;
    }
    let from_env = std::env::var("MS_THREADS")
        .ok()
        .and_then(|v| v.parse::<usize>().ok());
    let n = from_env
        .or_else(|| std::thread::available_parallelism().ok().map(|n| n.get()))
        .unwrap_or(1)
        .clamp(1, MAX_THREADS);
    LIMIT.store(n, Ordering::SeqCst);
    n
}

/// Sets the most threads the runtime starts (at least 1). Threads already started keep running.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_runtime_set_threads(n: i64) {
    LIMIT.store((n.max(1) as usize).min(MAX_THREADS), Ordering::SeqCst);
}

/// The most scheduler threads the program may run: the core count unless `msrt_runtime_set_threads` or `MS_THREADS` lowered it.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_runtime_limit() -> i64 {
    limit() as i64
}

fn load_of(thread: usize) -> u32 {
    SLOTS[thread].live.load(Ordering::SeqCst) + SLOTS[thread].pending.load(Ordering::SeqCst)
}

/// Chooses the thread for a new promise: the caller's, or the next one in round-robin order if
/// it has less to do. A thread's load is its promise tasks (running or waiting) plus the starts
/// queued for it.
fn place(me: usize) -> usize {
    let n = limit();
    if n <= 1 {
        return me;
    }
    // SAFETY: this isolate's state.
    let cursor = unsafe { &mut *CURSOR.ptr() };
    let mut next = (*cursor + 1) % n;
    if next == me {
        next = (next + 1) % n;
    }
    *cursor = next;
    let mine = load_of(me);
    if load_of(next) < mine { next } else { me }
}

/// Makes thread `index` exist.
fn ensure_started(index: usize) {
    let mut handles = HANDLES.lock().unwrap_or_else(|e| e.into_inner());
    if index < STARTED.load(Ordering::Acquire) {
        return;
    }
    // Threads start in index order, so `index` is the next one or an earlier one is still missing.
    while STARTED.load(Ordering::Acquire) <= index {
        let i = STARTED.load(Ordering::Acquire);
        let spawned = std::thread::Builder::new()
            .name(format!("ms-sched-{i}"))
            .stack_size(1 << 20)
            .spawn(move || thread_main(i));
        match spawned {
            Ok(h) => handles.push(h),
            Err(_) => crate::fault::fatal(b"cannot start a scheduler thread"),
        }
        STARTED.store(i + 1, Ordering::Release);
    }
}

/// Starts threads `1..n` and waits until each is idle. Tests use it so that placement is not
/// decided by how quickly the operating system gets a new thread running.
#[cfg(test)]
pub(crate) fn warm(n: usize) {
    for i in 1..n {
        ensure_started(i);
    }
    let want = (1..n).fold(0u64, |m, i| m | 1 << i);
    let end = crate::sys::monotonic_ns() + 5_000_000_000;
    while IDLE.load(Ordering::Acquire) & want != want && crate::sys::monotonic_ns() < end {
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
}

/// Sends a start to a scheduler thread, placed by load.
pub(crate) fn submit(start: Start) {
    let me = current();
    let target = if me == NONE { me } else { place(me) };
    debug_assert!(target < MAX_THREADS || me == NONE);
    if target == NONE {
        unreachable!("submit is for scheduler threads");
    }
    if target != me {
        ensure_started(target);
    }
    {
        let mut mail = lock(&SLOTS[target].mail);
        mail.pending.push_back(start);
        SLOTS[target]
            .pending
            .store(mail.pending.len() as u32, Ordering::SeqCst);
    }
    if target != me {
        wake(target);
    }
    if SLOTS[target].busy.load(Ordering::SeqCst) > 0 || target == me {
        wake_idle(target);
    }
}

/// Removes the promise `id` if it has not started; answers whether it did.
pub(crate) fn remove_pending(id: i64) -> Option<usize> {
    for slot in &SLOTS[..STARTED.load(Ordering::Acquire)] {
        if slot.pending.load(Ordering::SeqCst) == 0 {
            continue;
        }
        let mut mail = lock(&slot.mail);
        if let Some(at) = mail.pending.iter().position(|s| s.id == id) {
            let start = mail.pending.remove(at).expect("position is in range");
            slot.pending
                .store(mail.pending.len() as u32, Ordering::SeqCst);
            return Some(start.closure);
        }
    }
    None
}

/// Sends `event` to `thread` and wakes it.
pub(crate) fn post(thread: usize, event: Event) {
    {
        let mut mail = lock(&SLOTS[thread].mail);
        mail.events.push(event);
        SLOTS[thread].signalled.store(1, Ordering::Release);
    }
    wake(thread);
}

/// Interrupts the poller of `thread`, if it runs.
fn wake(thread: usize) {
    let slot = SLOTS[thread].isolate.load(Ordering::Acquire);
    if slot != usize::MAX {
        isolate::kick(slot);
    }
}

/// Wakes one idle thread other than `except`, so it can take an unstarted promise.
fn wake_idle(except: usize) {
    let idle = IDLE.load(Ordering::Acquire) & !(1u64 << except);
    if idle != 0 {
        wake(idle.trailing_zeros() as usize);
    }
}

/// Whether events wait for the calling thread.
pub(crate) fn signalled() -> bool {
    let me = current();
    me != NONE && SLOTS[me].signalled.load(Ordering::Acquire) != 0
}

/// Takes the events queued for the calling thread.
pub(crate) fn take_events() -> Vec<Event> {
    let me = current();
    if me == NONE || SLOTS[me].signalled.swap(0, Ordering::Acquire) == 0 {
        return Vec::new();
    }
    core::mem::take(&mut lock(&SLOTS[me].mail).events)
}

/// The next promise for the calling thread to start: its own oldest, else one taken from the
/// newest end of the longest queue of another thread.
pub(crate) fn next_pending() -> Option<Start> {
    let me = current();
    if me == NONE {
        return None;
    }
    if SLOTS[me].pending.load(Ordering::SeqCst) != 0 {
        let mut mail = lock(&SLOTS[me].mail);
        let start = mail.pending.pop_front();
        SLOTS[me]
            .pending
            .store(mail.pending.len() as u32, Ordering::SeqCst);
        if start.is_some() {
            return start;
        }
    }
    if SLOTS[me].live.load(Ordering::SeqCst) != 0 {
        return None;
    }
    let started = STARTED.load(Ordering::Acquire);
    let (mut best, mut most) = (usize::MAX, 0);
    for thread in (0..started).filter(|&t| t != me) {
        let n = SLOTS[thread].pending.load(Ordering::SeqCst);
        if n > most {
            (best, most) = (thread, n);
        }
    }
    if best == usize::MAX {
        return None;
    }
    let mut mail = lock(&SLOTS[best].mail);
    let start = mail.pending.pop_back();
    SLOTS[best]
        .pending
        .store(mail.pending.len() as u32, Ordering::SeqCst);
    start
}

/// Whether the calling thread has a promise it could start now.
pub(crate) fn work_available() -> bool {
    let me = current();
    if me == NONE {
        return false;
    }
    if SLOTS[me].pending.load(Ordering::SeqCst) != 0 {
        return true;
    }
    SLOTS[me].live.load(Ordering::SeqCst) == 0
        && (0..STARTED.load(Ordering::Acquire))
            .any(|t| SLOTS[t].pending.load(Ordering::SeqCst) != 0)
}

/// Counts a promise task started (`1`) or ended (`-1`) on the calling thread.
pub(crate) fn live_add(delta: i32) {
    let me = current();
    if me != NONE {
        if delta > 0 {
            SLOTS[me].live.fetch_add(1, Ordering::SeqCst);
        } else {
            SLOTS[me].live.fetch_sub(1, Ordering::SeqCst);
        }
    }
}

/// Publishes how many tasks are ready or running on the calling thread.
pub(crate) fn publish_busy(n: usize) {
    let me = current();
    if me != NONE {
        SLOTS[me].busy.store(n as u32, Ordering::SeqCst);
    }
}

/// The calling thread is about to block in its poller with nothing to run (`true`), or has left it.
pub(crate) fn set_idle(idle: bool) {
    let me = current();
    if me == NONE {
        return;
    }
    if idle {
        if SLOTS[me].live.load(Ordering::SeqCst) == 0 {
            IDLE.fetch_or(1 << me, Ordering::AcqRel);
        }
    } else {
        IDLE.fetch_and(!(1 << me), Ordering::AcqRel);
    }
}

fn root(_: *mut u8) {
    // SAFETY: runs as the isolate's main task; the token is this task's own.
    unsafe {
        let token = crate::task::msrt_token_new(crate::task::TOKEN_REMOTE);
        SLOTS[current()].root.store(token, Ordering::SeqCst);
        let mut value = 0;
        while STOP.load(Ordering::Acquire) == 0 {
            crate::task::msrt_token_park(token, -1, &mut value);
        }
        crate::task::msrt_token_free(token);
    }
}

unsafe extern "C-unwind" fn root_entry(arg: *mut u8) {
    root(arg);
}

fn thread_main(index: usize) {
    isolate::mark_worker();
    crate::alloc::claim_heap();
    crate::start::install_thread_fault_handler();
    // SAFETY: this isolate's state.
    unsafe { *INDEX.ptr() = index };
    SLOTS[index].isolate.store(isolate::id(), Ordering::Release);
    // SAFETY: this thread is the new isolate's only one.
    unsafe {
        let _ = crate::task::run_worker_task(root_entry, core::ptr::null_mut());
    }
    crate::task::teardown();
    SLOTS[index].isolate.store(usize::MAX, Ordering::Release);
    isolate::unregister();
    crate::alloc::release_heap();
}

/// Ends the scheduler threads and waits for them. The program calls it as it ends, when no
/// promise is left running (a promise is cancelled and joined when it is dropped).
pub fn shutdown() {
    let started = STARTED.load(Ordering::Acquire);
    if started <= 1 {
        return;
    }
    STOP.store(1, Ordering::Release);
    let handles = core::mem::take(&mut *HANDLES.lock().unwrap_or_else(|e| e.into_inner()));
    for (thread, slot) in SLOTS.iter().enumerate().take(started).skip(1) {
        // A thread that has not reached its root task yet sees `STOP` when it does.
        let token = slot.root.load(Ordering::SeqCst);
        if token != 0 {
            isolate::post_remote(token, 1);
        }
        wake(thread);
    }
    for h in handles {
        let _ = h.join();
    }
    STARTED.store(1, Ordering::Release);
    STOP.store(0, Ordering::Release);
    for slot in SLOTS.iter() {
        slot.root.store(0, Ordering::SeqCst);
        let mut mail = lock(&slot.mail);
        mail.pending.clear();
        mail.events.clear();
        slot.pending.store(0, Ordering::SeqCst);
        slot.signalled.store(0, Ordering::SeqCst);
        slot.busy.store(0, Ordering::SeqCst);
        slot.live.store(0, Ordering::SeqCst);
    }
    IDLE.store(0, Ordering::SeqCst);
}
