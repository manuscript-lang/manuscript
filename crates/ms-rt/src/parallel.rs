//! The compute pool: splits a range of rows across cores for the standard library's numeric
//! kernels (`@std/vec.ms`). One kernel call at a time uses it; the calling thread works too.
//!
//! The body is a compiled Manuscript closure `(start, end)` that runs on pool threads, so it
//! must only read its captures and write disjoint elements of lists the caller keeps alive: no
//! allocation, reference counts, recursion, cancellation points or faults. Only `@std` calls
//! [`msrt_parallel_rows`], and its kernels check every range before they start. A fault on a pool
//! thread anyway ends the process with its report, as an unguarded fault does.
//!
//! Scheduling. Threads claim rows from a shared cursor, each claim a fraction of what is left
//! (half of it divided by the thread count, at least an eighth of `grain`), so the first claims
//! are large and the last ones small: threads that run slower, or start later, still finish
//! close together. A chunk scheduler with equal chunks left cores idle for most of the last
//! chunk (about 12% of a 4096x4096 `matvec` on four cores).
//!
//! Protocol. `NEXT` packs the job's sequence number (high 32 bits) with the next unclaimed row
//! (low 32 bits); between jobs the row is `CLOSED`. The caller writes the job, stores the new
//! sequence with row 0 (release), bumps `EPOCH`, then claims rows like any pool thread and waits
//! for `PENDING` (rows not yet finished) to reach zero, and closes `NEXT` before the next job is
//! written. A claim is a compare-and-swap on the whole word, so a thread that read the job late
//! either fails its claim or holds rows of the job it read; that job is not rewritten until those
//! rows have finished. Idle threads spin for a few milliseconds, since kernels usually come in
//! quick succession, then park on `WAKE`.
//!
//! `MS_VEC_THREADS` sets how many threads take part, the caller included (default: one per
//! online CPU, at most 64); `MS_VEC_THREADS=1` runs every body on the caller.
use core::sync::atomic::{AtomicBool, AtomicI64, AtomicPtr, AtomicU64, AtomicUsize, Ordering};
use ms_rt_abi::Closure;
use std::sync::{Condvar, Mutex};

type Body = unsafe extern "C-unwind" fn(*mut Closure, i64, i64);

const MAX_THREADS: usize = 64;
/// The row half of `NEXT` between jobs: past any row count the pool takes.
const CLOSED: u64 = u32::MAX as u64;
/// Ranges the pool splits must fit the row half of `NEXT`; larger ones run on the caller.
const MAX_COUNT: i64 = i32::MAX as i64;
/// Spins an idle thread makes before it parks, a few milliseconds: waking a parked thread takes
/// tens of microseconds, which a kernel called again right away would wait for.
const SPINS: u32 = 1 << 16;
/// A pool thread's stack, and the part of it kept free below the recursion limit.
#[cfg(unix)]
const STACK_BYTES: usize = 1 << 20;
#[cfg(unix)]
const STACK_MARGIN: usize = 64 << 10;

static BODY: AtomicPtr<Closure> = AtomicPtr::new(core::ptr::null_mut());
static COUNT: AtomicI64 = AtomicI64::new(0);
/// The smallest claim, in rows.
static LEAST: AtomicI64 = AtomicI64::new(1);
static NEXT: AtomicU64 = AtomicU64::new(CLOSED);
static PENDING: AtomicI64 = AtomicI64::new(0);
static EPOCH: AtomicU64 = AtomicU64::new(0);
/// Set while a call owns the pool; a call that finds it set runs on its own thread.
static BUSY: AtomicBool = AtomicBool::new(false);
/// Participating threads (0 until first use) and pool threads started.
static THREADS: AtomicUsize = AtomicUsize::new(0);
static STARTED: AtomicUsize = AtomicUsize::new(0);
static SLEEPERS: AtomicUsize = AtomicUsize::new(0);
static WAKE: Mutex<()> = Mutex::new(());
static WOKEN: Condvar = Condvar::new();

/// Runs `body(start, end)` over `0..count` in ranges spread across the pool, and returns when
/// every range has finished. Runs `body(0, count)` on the calling thread when the range is no
/// bigger than `grain`, the pool has one thread, or another call holds it.
///
/// # Safety
/// `body` is a live closure taking `(Int, Int)` that obeys the module contract.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_parallel_rows(count: i64, grain: i64, body: *mut Closure) {
    if count <= 0 {
        return;
    }
    // SAFETY: `body` is a live closure by contract.
    let code: Body = unsafe { core::mem::transmute((*body).code) };
    let grain = grain.max(1);
    let threads = threads();
    if threads <= 1 || count <= grain || count > MAX_COUNT || BUSY.swap(true, Ordering::Acquire) {
        // SAFETY: per the contract.
        unsafe { code(body, 0, count) };
        return;
    }
    start_threads(threads - 1);
    BODY.store(body, Ordering::Relaxed);
    COUNT.store(count, Ordering::Relaxed);
    LEAST.store((grain / 8).max(1), Ordering::Relaxed);
    PENDING.store(count, Ordering::Relaxed);
    let job = (NEXT.load(Ordering::Relaxed) >> 32).wrapping_add(1) & 0xffff_ffff;
    NEXT.store(job << 32, Ordering::Release);
    EPOCH.fetch_add(1, Ordering::SeqCst);
    if SLEEPERS.load(Ordering::SeqCst) > 0 {
        let _held = WAKE.lock().unwrap_or_else(|e| e.into_inner());
        WOKEN.notify_all();
    }
    run_rows();
    let mut spins = 0u32;
    while PENDING.load(Ordering::Acquire) != 0 {
        if spins < SPINS {
            spins += 1;
            core::hint::spin_loop();
        } else {
            std::thread::yield_now();
        }
    }
    NEXT.store(job << 32 | CLOSED, Ordering::Relaxed);
    BUSY.store(false, Ordering::Release);
}

/// Claims and runs rows of the current job until none is left.
fn run_rows() {
    let threads = threads() as i64;
    loop {
        let cur = NEXT.load(Ordering::Acquire);
        let row = (cur & CLOSED) as i64;
        // Read after `NEXT`: either this job's fields, or a later job's, in which case `NEXT`
        // has changed and the claim below fails.
        let (count, least) = (COUNT.load(Ordering::Relaxed), LEAST.load(Ordering::Relaxed));
        if row >= count {
            return;
        }
        let left = count - row;
        let take = (left / (2 * threads)).max(least).min(left);
        let claimed = cur & !CLOSED | (row + take) as u64;
        if NEXT
            .compare_exchange_weak(cur, claimed, Ordering::AcqRel, Ordering::Relaxed)
            .is_err()
        {
            continue;
        }
        // The claim succeeded, so the job is the one read above and stays put until these
        // rows are counted off.
        let body = BODY.load(Ordering::Relaxed);
        // SAFETY: the caller keeps `body` alive until `PENDING` reaches zero.
        unsafe {
            let code: Body = core::mem::transmute((*body).code);
            code(body, row, row + take);
        }
        PENDING.fetch_sub(take, Ordering::Release);
    }
}

/// The participating thread count, read once.
fn threads() -> usize {
    let known = THREADS.load(Ordering::Relaxed);
    if known != 0 {
        return known;
    }
    let n = std::env::var("MS_VEC_THREADS")
        .ok()
        .and_then(|v| v.parse::<usize>().ok())
        .filter(|&n| n > 0)
        .unwrap_or_else(online_cpus)
        .min(MAX_THREADS);
    THREADS.store(n, Ordering::Relaxed);
    n
}

#[cfg(unix)]
fn online_cpus() -> usize {
    // SAFETY: plain sysconf query.
    let n = unsafe { libc::sysconf(libc::_SC_NPROCESSORS_ONLN) };
    usize::try_from(n).unwrap_or(1).max(1)
}

#[cfg(not(unix))]
fn online_cpus() -> usize {
    std::thread::available_parallelism().map_or(1, |n| n.get())
}

/// Starts pool threads until `wanted` are running; only the call holding `BUSY` gets here.
fn start_threads(wanted: usize) {
    while STARTED.load(Ordering::Relaxed) < wanted {
        if !spawn_thread() {
            // Fewer threads only means fewer helpers; the caller still does every row left.
            return;
        }
        STARTED.fetch_add(1, Ordering::Relaxed);
    }
}

/// A pool thread: waits for each new job and helps run it.
fn work() -> ! {
    let mut seen = EPOCH.load(Ordering::Acquire);
    loop {
        let mut spins = 0u32;
        while EPOCH.load(Ordering::Acquire) == seen {
            if spins < SPINS {
                spins += 1;
                core::hint::spin_loop();
                continue;
            }
            let mut held = WAKE.lock().unwrap_or_else(|e| e.into_inner());
            SLEEPERS.fetch_add(1, Ordering::SeqCst);
            while EPOCH.load(Ordering::SeqCst) == seen {
                held = WOKEN.wait(held).unwrap_or_else(|e| e.into_inner());
            }
            SLEEPERS.fetch_sub(1, Ordering::SeqCst);
        }
        seen = EPOCH.load(Ordering::Acquire);
        run_rows();
    }
}

/// Starts a pool thread with every signal blocked, so signals reach the runtime thread.
///
/// Generated code finds the running task's `fault::Hdr` by masking the stack pointer, so the
/// thread runs on the top `STACK_BYTES` of a `STACK_SLOT`-aligned slot whose first page holds a
/// header of its own, laid out like a task stack (`task::stack::create`).
#[cfg(unix)]
fn spawn_thread() -> bool {
    use crate::task::STACK_SLOT;
    extern "C" fn start(_: *mut libc::c_void) -> *mut libc::c_void {
        work()
    }
    // SAFETY: a fresh private reservation, trimmed to one aligned slot that only this thread
    // uses; plain pthread calls, and the thread takes no argument.
    unsafe {
        let raw = crate::sys::map_anon(2 * STACK_SLOT);
        if raw.is_null() {
            return false;
        }
        let start_addr = raw as usize;
        let base = start_addr.next_multiple_of(STACK_SLOT);
        if base > start_addr {
            crate::sys::unmap(raw, base - start_addr);
        }
        let tail = base + STACK_SLOT;
        if start_addr + 2 * STACK_SLOT > tail {
            crate::sys::unmap(tail as *mut u8, start_addr + 2 * STACK_SLOT - tail);
        }
        let low = tail - STACK_BYTES;
        // Recursion faults well before the stack's unguarded bottom.
        (base as *mut crate::fault::Hdr).write(crate::fault::Hdr::new(low + STACK_MARGIN));
        let mut all: libc::sigset_t = core::mem::zeroed();
        let mut old: libc::sigset_t = core::mem::zeroed();
        libc::sigfillset(&mut all);
        libc::pthread_sigmask(libc::SIG_SETMASK, &all, &mut old);
        let mut attr: libc::pthread_attr_t = core::mem::zeroed();
        libc::pthread_attr_init(&mut attr);
        libc::pthread_attr_setdetachstate(&mut attr, libc::PTHREAD_CREATE_DETACHED);
        libc::pthread_attr_setstack(&mut attr, low as *mut libc::c_void, STACK_BYTES);
        let mut id: libc::pthread_t = core::mem::zeroed();
        let ok = libc::pthread_create(&mut id, &attr, start, core::ptr::null_mut()) == 0;
        libc::pthread_attr_destroy(&mut attr);
        libc::pthread_sigmask(libc::SIG_SETMASK, &old, core::ptr::null_mut());
        if !ok {
            crate::sys::unmap(base as *mut u8, STACK_SLOT);
        }
        ok
    }
}

#[cfg(not(unix))]
fn spawn_thread() -> bool {
    std::thread::Builder::new()
        .name("ms-vec".into())
        .spawn(|| work())
        .is_ok()
}
