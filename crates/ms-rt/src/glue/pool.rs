//! The blocking pool: a few threads, shared by every standard-library crate, for calls the
//! kernel cannot wait on (`getaddrinfo`). `MS_POOL_THREADS` sets how many (default 4); DNS jobs
//! use at most half of them, so a hung resolver cannot take every thread.
//!
//! Memory. On Linux the runtime thread allocates from an arena that only it may free: a block it
//! allocated and another thread frees is never reused. So nothing the runtime thread allocated is
//! dropped on a pool thread. A job is a plain function over a borrowed input, so it owns nothing
//! to drop; its box returns to the runtime thread, which drops the input and takes the output.
//! Pool threads allocate from the system allocator, which frees from any thread, so outputs are
//! safe to drop on the runtime thread. A list that pool threads push to is never allocated by the
//! runtime thread, which empties it by taking it whole; lists the runtime thread grows, pool
//! threads only shrink. Pool threads are started without a Rust closure, so starting one
//! allocates nothing.
//!
//! Waits. The submitting task parks on a remote token until a pool thread posts it. A timed-out
//! or cancelled wait abandons a running job: its token is freed at once, and the pool thread
//! hands the finished job back on a list that the runtime thread empties at the next submit.
//! A job still queued is removed and dropped at once.

use std::boxed::Box;
use std::collections::VecDeque;
use std::sync::{Condvar, Mutex, MutexGuard};
use std::vec::Vec;

use crate::task::{
    msrt_task_count, msrt_token_free, msrt_token_new, msrt_token_park, msrt_token_post_remote,
};

/// The runtime's `TOKEN_REMOTE` flag and park results.
const TOKEN_REMOTE: u32 = 1;
const WAIT_TIMEOUT: u32 = 8;
const WAIT_CANCELLED: u32 = 16;

/// A pool thread's stack.
#[cfg(unix)]
const STACK_BYTES: usize = 512 * 1024;
/// Threads when `MS_POOL_THREADS` is unset or invalid.
const DEFAULT_THREADS: usize = 4;
const MAX_THREADS: usize = 64;

/// Which cap a job counts against.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Lane {
    /// Name lookups: at most half the pool at once.
    Dns,
    /// Everything else.
    General,
}

/// Where a job is; changed only under the pool lock.
#[derive(Clone, Copy, PartialEq, Eq)]
enum State {
    Queued,
    Running,
    Done,
}

/// The fields every job starts with, read and written only under the pool lock.
#[repr(C)]
struct Head {
    state: State,
    token: u64,
}

/// A job; created and dropped on the runtime thread. A pool thread touches only `input`, `f`
/// and `output`, through field pointers, so the runtime thread may read `head` meanwhile.
#[repr(C)]
struct Job<I, O> {
    head: Head,
    input: I,
    f: fn(&I) -> O,
    output: Option<O>,
}

/// Runs a job's function into its output.
///
/// # Safety
/// `p` is a live `Job<I, O>` that only the calling thread uses besides its head.
unsafe fn run_job<I, O>(p: *mut Head) {
    let job = p as *mut Job<I, O>;
    // SAFETY: field reads and one field write of a live job, per the contract.
    unsafe {
        let f = (*job).f;
        let input = &*core::ptr::addr_of!((*job).input);
        *core::ptr::addr_of_mut!((*job).output) = Some(f(input));
    }
}

/// # Safety
/// `p` is a `Job<I, O>` box that no other thread can reach.
unsafe fn drop_job<I, O>(p: *mut Head) {
    // SAFETY: per the contract.
    drop(unsafe { Box::from_raw(p as *mut Job<I, O>) });
}

/// A job handed between threads by address.
#[derive(Clone, Copy)]
struct Ptr {
    head: *mut Head,
    run: unsafe fn(*mut Head),
    drop: unsafe fn(*mut Head),
    lane: Lane,
}

// SAFETY: a job is used by one thread at a time besides its head, which the pool lock guards.
unsafe impl Send for Ptr {}

impl Ptr {
    /// The job's token; set before the job is queued and never changed.
    fn token(&self) -> u64 {
        // SAFETY: the head lives as long as the job, and the token is never written again.
        unsafe { (*self.head).token }
    }
}

struct Pool {
    /// Grown only by the runtime thread.
    queue: VecDeque<Ptr>,
    /// Running jobs whose waiter gave up; grown only by the runtime thread.
    abandoned: Vec<*mut Head>,
    /// Abandoned jobs that finished; grown only by pool threads.
    finished: Vec<Ptr>,
    threads: usize,
    idle: usize,
    /// Idle threads already signalled for a queued job but not yet awake.
    wakes: usize,
    dns_running: usize,
}

// SAFETY: the raw pointers are only followed under the rules above.
unsafe impl Send for Pool {}

static POOL: Mutex<Pool> = Mutex::new(Pool {
    queue: VecDeque::new(),
    abandoned: Vec::new(),
    finished: Vec::new(),
    threads: 0,
    idle: 0,
    wakes: 0,
    dns_running: 0,
});
static READY: Condvar = Condvar::new();
/// Signalled whenever a job is done, for a shielded wait that cannot park.
static FINISHED: Condvar = Condvar::new();

fn lock() -> MutexGuard<'static, Pool> {
    POOL.lock().unwrap_or_else(|e| e.into_inner())
}

/// `MS_POOL_THREADS`, read once.
pub fn threads() -> usize {
    static N: std::sync::OnceLock<usize> = std::sync::OnceLock::new();
    *N.get_or_init(|| {
        std::env::var("MS_POOL_THREADS")
            .ok()
            .and_then(|v| v.trim().parse::<usize>().ok())
            .filter(|&n| n > 0)
            .map_or(DEFAULT_THREADS, |n| n.min(MAX_THREADS))
    })
}

/// Whether the program has a single task: a blocking call then has nothing to overlap with, so
/// it runs inline and a command-line program starts no thread.
pub fn alone() -> bool {
    // SAFETY: reads the scheduler's task count on the runtime thread.
    unsafe { msrt_task_count() <= 1 }
}

fn dns_cap() -> usize {
    (threads() / 2).max(1)
}

impl Pool {
    /// The first queued job a thread may start under the DNS cap.
    fn next(&mut self) -> Option<Ptr> {
        let dns_full = self.dns_running >= dns_cap();
        let at = self
            .queue
            .iter()
            .position(|p| p.lane != Lane::Dns || !dns_full)?;
        let p = self.queue.remove(at)?;
        if p.lane == Lane::Dns {
            self.dns_running += 1;
        }
        // SAFETY: a queued job is owned by the pool until a thread takes it here.
        unsafe { (*p.head).state = State::Running };
        Some(p)
    }
}

/// Queues `f(&input)` and starts a thread when none is idle; the job and its token.
fn submit<I: Send + Sync + 'static, O: Send + 'static>(
    lane: Lane,
    input: I,
    f: fn(&I) -> O,
) -> (*mut Job<I, O>, Ptr) {
    reap();
    // SAFETY: creates a token on the runtime thread.
    let token = unsafe { msrt_token_new(TOKEN_REMOTE) };
    let job = Box::into_raw(Box::new(Job {
        head: Head {
            state: State::Queued,
            token,
        },
        input,
        f,
        output: None,
    }));
    let ptr = Ptr {
        head: job as *mut Head,
        run: run_job::<I, O>,
        drop: drop_job::<I, O>,
        lane,
    };
    let start = {
        let mut pool = lock();
        pool.queue.push_back(ptr);
        // An idle thread already signalled for an earlier job will not take this one too.
        let wake = pool.idle > pool.wakes;
        if wake {
            pool.wakes += 1;
        }
        let start = !wake && pool.threads < threads();
        if start {
            pool.threads += 1;
        }
        start
    };
    READY.notify_one();
    if start && !spawn_thread() {
        lock().threads -= 1;
    }
    (job, ptr)
}

/// Takes a finished job back: frees its token and returns its output.
///
/// # Safety
/// The job is done and no pool thread holds it.
unsafe fn take<I, O>(job: *mut Job<I, O>) -> Option<O> {
    // SAFETY: per the contract, the box returns to this thread.
    let mut job = unsafe { Box::from_raw(job) };
    // SAFETY: the token is this job's.
    unsafe { msrt_token_free(job.head.token) };
    job.output.take()
}

/// Runs `f(&input)` on a pool thread and parks the task until it finishes or `timeout_ns`
/// passes (negative: no limit). `None` on timeout; a running job is then
/// abandoned and its result dropped later. A stop request abandons the job and unwinds.
///
/// `f` must not call into the runtime, must not panic (shipped programs abort on a panic), and
/// must not grow or free anything `input` owns through interior mutability, since `input` was
/// allocated on the runtime thread. `input` is dropped on the calling thread.
pub fn run<I: Send + Sync + 'static, O: Send + 'static>(
    lane: Lane,
    input: I,
    f: fn(&I) -> O,
    timeout_ns: i64,
) -> Option<O> {
    let (job, ptr) = submit(lane, input, f);
    let mut value = 0u64;
    // SAFETY: parks the current task on its own token.
    let got = unsafe { msrt_token_park(ptr.token(), timeout_ns, &mut value) };
    // A job that finished as the wait ended is complete, so it is taken all the same.
    let gave_up = got & (WAIT_TIMEOUT | WAIT_CANCELLED) != 0 && give_up(ptr);
    // SAFETY: not given up, so the job is done.
    let output = if gave_up { None } else { unsafe { take(job) } };
    if got & WAIT_CANCELLED != 0 {
        crate::glue::cancelled();
    }
    output
}

/// A shielded job's input and the caller's bytes it borrows.
struct Lent<I, O> {
    input: I,
    ptr: *const u8,
    len: usize,
    f: fn(&I, &[u8]) -> O,
}

// SAFETY: the bytes are only read, and they outlive the job because its wait is shielded.
unsafe impl<I: Send, O> Send for Lent<I, O> {}
// SAFETY: as above.
unsafe impl<I: Sync, O> Sync for Lent<I, O> {}

fn call_lent<I, O>(lent: &Lent<I, O>) -> O {
    // SAFETY: the caller of `run_shielded` keeps the bytes alive until the job is done.
    let bytes = unsafe { core::slice::from_raw_parts(lent.ptr, lent.len) };
    (lent.f)(&lent.input, bytes)
}

/// The job's state, read under the pool lock.
fn state(_pool: &Pool, ptr: Ptr) -> State {
    // SAFETY: written only under the lock the caller holds.
    unsafe { (*ptr.head).state }
}

/// Runs `f(&input, bytes)` on a pool thread and parks the task until it finishes, however long
/// that takes. A stop request takes effect once the job is done, which is
/// what lets the job borrow `bytes`. For jobs that always finish (a regular-file read or write),
/// never for ones that can hang. `f` follows the rules of [`run`].
pub fn run_shielded<I: Send + Sync + 'static, O: Send + 'static>(
    lane: Lane,
    input: I,
    bytes: &[u8],
    f: fn(&I, &[u8]) -> O,
) -> O {
    let lent = Lent {
        input,
        ptr: bytes.as_ptr(),
        len: bytes.len(),
        f,
    };
    let (job, ptr) = submit(lane, lent, call_lent::<I, O>);
    let mut value = 0u64;
    // SAFETY: parks the current task on its own token.
    let got = unsafe { msrt_token_park(ptr.token(), -1, &mut value) };
    if got & WAIT_CANCELLED != 0 {
        // A pending stop ends every park at once: block the thread until the job is done.
        let mut pool = lock();
        while state(&pool, ptr) != State::Done {
            pool = FINISHED.wait(pool).unwrap_or_else(|e| e.into_inner());
        }
    }
    // SAFETY: the job is done: the park ended with its post, or the loop above saw it.
    let output = unsafe { take(job) }.expect("a finished job holds its output");
    if got & WAIT_CANCELLED != 0 {
        crate::glue::cancelled();
    }
    output
}

/// Ends the wait for an unfinished job: a queued one is removed and dropped, a running one is
/// abandoned. False when the job finished meanwhile and the caller takes it.
fn give_up(ptr: Ptr) -> bool {
    let mut pool = lock();
    // SAFETY: the state is read under the lock.
    let state = unsafe { (*ptr.head).state };
    // SAFETY: the token is this job's, read under the lock.
    let token = unsafe { (*ptr.head).token };
    match state {
        State::Done => return false,
        State::Queued => {
            if let Some(at) = pool.queue.iter().position(|p| p.head == ptr.head) {
                pool.queue.remove(at);
            }
            drop(pool);
            // SAFETY: removed from the queue, so no thread can reach it.
            unsafe { (ptr.drop)(ptr.head) };
        }
        State::Running => {
            pool.abandoned.push(ptr.head);
            drop(pool);
        }
    }
    // SAFETY: frees this call's token; the job will not post it.
    unsafe { msrt_token_free(token) };
    true
}

/// Drops abandoned jobs that have finished. Runs on the runtime thread.
fn reap() {
    let finished = core::mem::take(&mut lock().finished);
    for p in &finished {
        // SAFETY: an abandoned job that finished belongs to no thread but this one.
        unsafe { (p.drop)(p.head) };
    }
    // The list itself was allocated by a pool thread; the system allocator frees it here.
    drop(finished);
}

std::thread_local! {
    static ON_POOL: core::cell::Cell<bool> = const { core::cell::Cell::new(false) };
}

/// Whether the caller is a pool thread, where a job must not call into the runtime.
pub fn on_pool_thread() -> bool {
    ON_POOL.with(|on| on.get())
}

/// The body of a pool thread.
fn work() -> ! {
    ON_POOL.with(|on| on.set(true));
    loop {
        let ptr = {
            let mut pool = lock();
            loop {
                if let Some(p) = pool.next() {
                    break p;
                }
                pool.idle += 1;
                pool = READY.wait(pool).unwrap_or_else(|e| e.into_inner());
                pool.idle -= 1;
                pool.wakes = pool.wakes.saturating_sub(1);
            }
        };
        // SAFETY: this thread runs the job until it marks it done.
        unsafe { (ptr.run)(ptr.head) };
        let post = {
            let mut pool = lock();
            if ptr.lane == Lane::Dns {
                pool.dns_running -= 1;
            }
            // SAFETY: state and token are written and read under the lock.
            unsafe { (*ptr.head).state = State::Done };
            if let Some(at) = pool.abandoned.iter().position(|&h| h == ptr.head) {
                pool.abandoned.swap_remove(at);
                pool.finished.push(ptr);
                None
            } else {
                // SAFETY: as above.
                Some(unsafe { (*ptr.head).token })
            }
        };
        FINISHED.notify_all();
        if ptr.lane == Lane::Dns {
            // A DNS job may have waited for this one's slot.
            READY.notify_one();
        }
        if let Some(token) = post {
            msrt_token_post_remote(token, 1);
        }
    }
}

/// Starts a pool thread with every signal blocked, so signals reach the runtime thread.
#[cfg(unix)]
fn spawn_thread() -> bool {
    extern "C" fn start(_: *mut libc::c_void) -> *mut libc::c_void {
        work()
    }
    // SAFETY: plain pthread calls; the thread takes no argument, so nothing is allocated for it.
    unsafe {
        let mut all: libc::sigset_t = core::mem::zeroed();
        let mut old: libc::sigset_t = core::mem::zeroed();
        libc::sigfillset(&mut all);
        libc::pthread_sigmask(libc::SIG_SETMASK, &all, &mut old);
        let mut attr: libc::pthread_attr_t = core::mem::zeroed();
        libc::pthread_attr_init(&mut attr);
        libc::pthread_attr_setdetachstate(&mut attr, libc::PTHREAD_CREATE_DETACHED);
        // musl's default is 128 KiB; resolvers and file calls get room to spare.
        libc::pthread_attr_setstacksize(&mut attr, STACK_BYTES);
        let mut id: libc::pthread_t = core::mem::zeroed();
        let ok = libc::pthread_create(&mut id, &attr, start, core::ptr::null_mut()) == 0;
        libc::pthread_attr_destroy(&mut attr);
        libc::pthread_sigmask(libc::SIG_SETMASK, &old, core::ptr::null_mut());
        ok
    }
}

#[cfg(windows)]
fn spawn_thread() -> bool {
    std::thread::Builder::new()
        .name("ms-pool".into())
        .spawn(|| work())
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::{Duration, Instant};

    static NOW_DNS: AtomicUsize = AtomicUsize::new(0);
    static MOST_DNS: AtomicUsize = AtomicUsize::new(0);

    fn slow_dns(ms: &u64) -> u64 {
        let now = NOW_DNS.fetch_add(1, Ordering::SeqCst) + 1;
        MOST_DNS.fetch_max(now, Ordering::SeqCst);
        std::thread::sleep(Duration::from_millis(*ms));
        NOW_DNS.fetch_sub(1, Ordering::SeqCst);
        *ms
    }

    #[expect(clippy::ptr_arg, reason = "a job takes `&I` for its input type")]
    fn doubled(v: &Vec<u8>) -> Vec<u8> {
        v.iter().map(|b| b * 2).collect()
    }

    fn summed(extra: &usize, bytes: &[u8]) -> usize {
        bytes.iter().map(|&b| b as usize).sum::<usize>() + extra
    }

    fn pool_threads() -> usize {
        lock().threads
    }

    /// One test: the scheduler runs on one thread, and parks happen on the test thread.
    #[test]
    #[cfg_attr(miri, ignore = "context switches use inline assembly")]
    fn the_pool_runs_caps_abandons_and_reaps() {
        assert_eq!(
            run(Lane::General, std::vec![1u8, 2, 3], doubled, -1),
            Some(std::vec![2, 4, 6])
        );
        let caller = std::vec![7u8; 1 << 20];
        assert_eq!(
            run_shielded(Lane::General, 3usize, &caller, summed),
            7 * (1 << 20) + 3
        );

        // A timed-out wait returns at once; the job is abandoned and reaped after it finishes.
        let start = Instant::now();
        assert_eq!(run(Lane::Dns, 300u64, slow_dns, 20_000_000), None);
        assert!(start.elapsed() < Duration::from_millis(250));
        std::thread::sleep(Duration::from_millis(400));
        assert_eq!(lock().finished.len(), 1);
        assert_eq!(
            run(Lane::General, std::vec![1u8], doubled, -1),
            Some(std::vec![2])
        );
        assert!(lock().finished.is_empty() && lock().abandoned.is_empty());

        // Fill the DNS lane with abandoned jobs: no more than half the pool runs DNS at once,
        // and general jobs still run.
        for _ in 0..threads() * 2 {
            assert_eq!(run(Lane::Dns, 200u64, slow_dns, 1_000_000), None);
        }
        assert_eq!(
            run(Lane::General, std::vec![5u8], doubled, -1),
            Some(std::vec![10])
        );
        std::thread::sleep(Duration::from_millis(200 * (threads() as u64 + 2)));
        assert!(MOST_DNS.load(Ordering::SeqCst) <= dns_cap());
        assert!(pool_threads() <= threads());
        let _ = run(Lane::General, std::vec![0u8], doubled, -1);
        let pool = lock();
        assert!(pool.queue.is_empty() && pool.abandoned.is_empty() && pool.finished.is_empty());
    }
}
