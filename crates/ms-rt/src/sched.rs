//! Scheduler threads: where `promise(fn)` runs.
//!
//! The program starts on one thread. A promise started with `promise(fn)` is queued on the
//! caller's own thread and starts nowhere until someone needs it: its waiter runs it inline if
//! nobody took it, or an idle thread takes the oldest queued one. A thread starts when a promise is
//! queued and none is idle, up to the core count (`msrt_runtime_set_threads` or `MS_THREADS` change the limit), so a program that
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
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU32, AtomicU64, AtomicUsize, Ordering};

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
    me < MAX_THREADS
        && (PINNED[me].load(Ordering::Relaxed) > 0
            || (me == 0 && MAIN_AFFINE.load(Ordering::Relaxed)))
}

/// Set once the main thread has touched state only it may use (`ffi::Global`: the terminal). From
/// then on a promise started on the main thread stays there, since one that reaches that state
/// from another thread faults.
static MAIN_AFFINE: AtomicBool = AtomicBool::new(false);

#[cfg(test)]
pub(crate) fn unpin_main() {
    MAIN_AFFINE.store(false, Ordering::Relaxed);
}

/// Records that the main thread uses main-thread-only state.
pub(crate) fn pin_main() {
    if !MAIN_AFFINE.load(Ordering::Relaxed) {
        MAIN_AFFINE.store(true, Ordering::Relaxed);
    }
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
    /// When it was queued (monotonic ns); 0 for a start that is run at once.
    pub at: i64,
    /// The creator's output capture, which the task inherits (`msrt_test_capture_set`).
    pub capture: u64,
    /// When another thread took it from its creator's queue (monotonic ns); 0 if it did not.
    pub stolen_at: i64,
}

/// How long a start waits in its creator's queue before another thread may take it. Most forks
/// finish or are joined within this time, so they never pay for a task; a task start costs a few
/// microseconds, so a start that outlives the beat is worth moving.
const BEAT_NS: i64 = 20_000;

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
    /// To the owner of a promise another thread uses: run the job in a task of its own. The job
    /// answers the caller through a token it holds (see `promise::ask`).
    Call(Box<dyn FnOnce() + Send>),
}

struct Mail {
    pending: VecDeque<Start>,
}

/// Events other threads post to a thread, on a cache line of their own: they arrive while the
/// thread queues its starts and idle threads read its queue, and none of the three may share a lock or a line.
#[repr(align(64))]
struct Posted {
    /// Whether `events` may hold events.
    signalled: AtomicU32,
    events: Mutex<Vec<Event>>,
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
    /// When the oldest of them was queued, or 0 when none is.
    front_at: AtomicI64,
    /// Until when this thread takes no start from another's queue, after steals that ran for less
    /// than they cost; and the length of the pause it doubles while that keeps happening.
    steal_off_until: AtomicI64,
    steal_pause: AtomicI64,
    /// The registry slot of the thread's isolate, or `usize::MAX` before it runs.
    isolate: AtomicUsize,
    /// The token the thread's root task parks on; posting it lets the thread end.
    root: AtomicU64,
    mail: Mutex<Mail>,
    posted: Posted,
}

impl Slot {
    const fn new() -> Self {
        Slot {
            busy: AtomicU32::new(0),
            live: AtomicU32::new(0),
            pending: AtomicU32::new(0),
            front_at: AtomicI64::new(0),
            steal_off_until: AtomicI64::new(0),
            steal_pause: AtomicI64::new(0),
            isolate: AtomicUsize::new(usize::MAX),
            root: AtomicU64::new(0),
            mail: Mutex::new(Mail {
                pending: VecDeque::new(),
            }),
            posted: Posted {
                signalled: AtomicU32::new(0),
                events: Mutex::new(Vec::new()),
            },
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
}

/// Publishes the length and oldest age of a queue, under its lock.
fn publish(slot: &Slot, mail: &Mail) {
    slot.pending
        .store(mail.pending.len() as u32, Ordering::SeqCst);
    let at = mail.pending.front().map_or(0, |s| s.at);
    slot.front_at.store(at, Ordering::SeqCst);
}

fn lock_events(m: &Mutex<Vec<Event>>) -> std::sync::MutexGuard<'_, Vec<Event>> {
    m.lock().unwrap_or_else(|e| e.into_inner())
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

/// How many scheduler threads exist, the main thread included.
pub(crate) fn started() -> usize {
    STARTED.load(Ordering::Acquire)
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

/// Queues a start on the calling thread's own queue. Nothing is sent anywhere: a promise that
/// nobody takes is run by its waiter (`promise::run_unstarted`), which costs about a call. An idle
/// thread takes the oldest queued start; when none is idle and the limit allows, one more thread is
/// started so there is someone to take it.
pub(crate) fn submit(start: Start) {
    let me = current();
    if me == NONE {
        unreachable!("submit is for scheduler threads");
    }
    let first;
    {
        let mut mail = lock(&SLOTS[me].mail);
        first = mail.pending.is_empty();
        mail.pending.push_back(start);
        // Only the count changes for a queue that was not empty: its oldest start is the same, so
        // `front_at` stays untouched and idle threads polling it keep the cache line.
        if first {
            publish(&SLOTS[me], &mail);
        } else {
            SLOTS[me]
                .pending
                .store(mail.pending.len() as u32, Ordering::Release);
        }
    }
    if first && IDLE.load(Ordering::Acquire) & !(1u64 << me) != 0 {
        wake_idle(me);
    } else {
        let next = STARTED.load(Ordering::Acquire);
        if next < limit() {
            ensure_started(next);
        }
    }
}

/// Places `start` on the least loaded thread instead of queueing it here to age: for long-lived
/// work, such as one worker per core, where the creator parks right after making them and would
/// otherwise start every one itself. Starts one more thread when the limit allows and every started
/// thread already has work. Answers `Some(start)` when the calling thread is the one to run it.
pub(crate) fn submit_spread(start: Start) -> Option<Start> {
    let me = current();
    if me == NONE {
        return Some(start);
    }
    let load = |t: usize| {
        SLOTS[t].live.load(Ordering::SeqCst) as usize
            + SLOTS[t].pending.load(Ordering::SeqCst) as usize
    };
    let started = STARTED.load(Ordering::Acquire);
    let (mut target, mut best) = (me, load(me));
    for t in (0..started).filter(|&t| t != me) {
        if load(t) < best {
            (target, best) = (t, load(t));
        }
    }
    if best > 0 && started < limit() {
        ensure_started(started);
        target = started;
    }
    if target == me {
        return Some(start);
    }
    {
        let mut mail = lock(&SLOTS[target].mail);
        // Already aged, so any idle thread may take it if the target is busy.
        mail.pending.push_back(Start {
            at: crate::sys::monotonic_ns() - BEAT_NS,
            ..start
        });
        publish(&SLOTS[target], &mail);
    }
    wake(target);
    None
}

/// Removes the promise `id` if it has not started; answers whether it did. A promise is only
/// ever queued on its creator's thread, and only its creator asks, so only that queue is looked
/// at. A waiter usually wants either the one it just made (newest) or, waiting in creation order,
/// the oldest; both ends are tried before the scan from the newest end.
pub(crate) fn remove_pending(id: i64) -> Option<usize> {
    let me = current();
    if me == NONE || SLOTS[me].pending.load(Ordering::SeqCst) == 0 {
        return None;
    }
    let slot = &SLOTS[me];
    let mut mail = lock(&slot.mail);
    let start = if mail.pending.front().is_some_and(|s| s.id == id) {
        mail.pending.pop_front().expect("front exists")
    } else {
        let at = mail.pending.iter().rposition(|s| s.id == id)?;
        mail.pending.remove(at).expect("position is in range")
    };
    publish(slot, &mail);
    Some(start.closure)
}

/// Frees the buffers of this thread's mailbox, whose capacity grows with the promises it queued:
/// the leak sweep's exit teardown, so kept capacity does not read as a leak.
pub(crate) fn release_mail() {
    let me = current();
    if me == NONE {
        return;
    }
    let mut mail = lock(&SLOTS[me].mail);
    if mail.pending.is_empty() {
        mail.pending = VecDeque::new();
    }
    let mut events = lock_events(&SLOTS[me].posted.events);
    if events.is_empty() {
        *events = Vec::new();
    }
}

/// Sends `event` to `thread` and wakes it.
pub(crate) fn post(thread: usize, event: Event) {
    {
        lock_events(&SLOTS[thread].posted.events).push(event);
        SLOTS[thread].posted.signalled.store(1, Ordering::Release);
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
    me != NONE && SLOTS[me].posted.signalled.load(Ordering::Acquire) != 0
}

/// Takes the events queued for the calling thread.
pub(crate) fn take_events() -> Vec<Event> {
    let me = current();
    if me == NONE || SLOTS[me].posted.signalled.swap(0, Ordering::Acquire) == 0 {
        return Vec::new();
    }
    core::mem::take(&mut *lock_events(&SLOTS[me].posted.events))
}

/// The next promise for the calling thread to start: its own oldest, else one taken from the
/// oldest end of the longest queue of another thread.
pub(crate) fn next_pending() -> Option<Start> {
    let me = current();
    if me == NONE {
        return None;
    }
    if SLOTS[me].pending.load(Ordering::SeqCst) != 0 {
        let mut mail = lock(&SLOTS[me].mail);
        let start = mail.pending.pop_front();
        publish(&SLOTS[me], &mail);
        if start.is_some() {
            return start;
        }
    }
    if SLOTS[me].live.load(Ordering::SeqCst) != 0 {
        return None;
    }
    let now = crate::sys::monotonic_ns();
    if now < SLOTS[me].steal_off_until.load(Ordering::Relaxed) {
        return None;
    }
    let started = STARTED.load(Ordering::Acquire);
    let (mut best, mut most) = (usize::MAX, 0);
    for thread in (0..started).filter(|&t| t != me) {
        let n = SLOTS[thread].pending.load(Ordering::SeqCst);
        if n > most && aged(thread, now) {
            (best, most) = (thread, n);
        }
    }
    if best == usize::MAX {
        return None;
    }
    let mut mail = lock(&SLOTS[best].mail);
    let start = if mail.pending.front().is_some_and(|s| now - s.at >= BEAT_NS) {
        mail.pending.pop_front()
    } else {
        None
    };
    publish(&SLOTS[best], &mail);
    start.map(|s| Start {
        stolen_at: now,
        ..s
    })
}

/// A stolen promise that was started at `at` has ended. One that ran for less than a steal costs
/// (a task and three events) made the work slower, so this thread stops stealing for a pause that
/// doubles each time that repeats; a promise worth moving resets it.
pub(crate) fn steal_feedback(at: i64) {
    let me = current();
    if me == NONE {
        return;
    }
    let now = crate::sys::monotonic_ns();
    let slot = &SLOTS[me];
    if now - at >= STEAL_WORTH_NS {
        slot.steal_pause.store(0, Ordering::Relaxed);
        return;
    }
    let pause = (slot.steal_pause.load(Ordering::Relaxed) * 2)
        .clamp(STEAL_PAUSE_MIN_NS, STEAL_PAUSE_MAX_NS);
    slot.steal_pause.store(pause, Ordering::Relaxed);
    slot.steal_off_until.store(now + pause, Ordering::Relaxed);
}

/// A stolen promise that runs shorter than this was not worth the steal.
const STEAL_WORTH_NS: i64 = 5_000;
const STEAL_PAUSE_MIN_NS: i64 = 50_000;
const STEAL_PAUSE_MAX_NS: i64 = 2_000_000;

/// Whether the oldest start queued on `thread` has waited a beat.
fn aged(thread: usize, now: i64) -> bool {
    let at = SLOTS[thread].front_at.load(Ordering::SeqCst);
    at != 0 && now - at >= BEAT_NS
}

/// How long until some queued start can be taken by the calling thread, which is free to take one:
/// 0 when one can be now, negative when none is queued.
pub(crate) fn steal_wait_ns() -> i64 {
    let me = current();
    if me == NONE || SLOTS[me].live.load(Ordering::SeqCst) != 0 {
        return -1;
    }
    // The clock is read only once a queued start exists: an idle thread polls this in a spin.
    let off = SLOTS[me].steal_off_until.load(Ordering::Relaxed);
    let mut now = 0;
    let mut wait = -1;
    for thread in (0..STARTED.load(Ordering::Acquire)).filter(|&t| t != me) {
        let at = SLOTS[thread].front_at.load(Ordering::SeqCst);
        if at != 0 {
            if now == 0 {
                now = crate::sys::monotonic_ns();
            }
            let w = (at + BEAT_NS - now).max(off - now).max(0);
            wait = if wait < 0 { w } else { wait.min(w) };
        }
    }
    wait
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
    steal_wait_ns() == 0
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
            // The root task's wait is the scheduler's, not an await point of the program.
            crate::task::sweep::internal(true);
            crate::task::msrt_token_park(token, -1, &mut value);
            crate::task::sweep::internal(false);
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
        // Fresh buffers, not `clear`: the capacity grew with the promises queued and would stay.
        let mut mail = lock(&slot.mail);
        mail.pending = VecDeque::new();
        *lock_events(&slot.posted.events) = Vec::new();
        slot.pending.store(0, Ordering::SeqCst);
        slot.front_at.store(0, Ordering::SeqCst);
        slot.steal_off_until.store(0, Ordering::SeqCst);
        slot.steal_pause.store(0, Ordering::SeqCst);
        slot.posted.signalled.store(0, Ordering::SeqCst);
        slot.busy.store(0, Ordering::SeqCst);
        slot.live.store(0, Ordering::SeqCst);
    }
    IDLE.store(0, Ordering::SeqCst);
}
