//! Worker isolates: OS threads with an arena, scheduler and fault context of their own.
//!
//! A worker starts from a named entry function and a malloc'd argument block, runs it as the
//! main task of its own scheduler, and ends with an outcome the parent collects by joining.
//! Parents and workers share no runtime state: the argument crosses as bytes, the fault report
//! comes back as bytes, and wake-ups go through [`crate::isolate::post_remote`].
use crate::isolate;
use crate::task::msrt_token_post_remote;
use core::ffi::c_void;
use ms_rt_abi::StrVal;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

/// Entry of a worker: called on the worker's main task with the argument block.
pub type Entry = unsafe extern "C-unwind" fn(*mut u8);

/// Most workers alive at once; a spawn beyond it fails.
const MAX_WORKERS: usize = 256;
/// Registry slot of a worker that has not registered yet.
const NO_SLOT: usize = usize::MAX;

struct Worker {
    thread: Mutex<Option<std::thread::JoinHandle<()>>>,
    /// The worker's isolate slot once it runs, for cancellation.
    slot: AtomicUsize,
    outcome: Mutex<(u8, Vec<u8>)>,
}

static WORKERS: Mutex<Vec<Option<Arc<Worker>>>> = Mutex::new(Vec::new());

fn find(handle: u64) -> Option<Arc<Worker>> {
    let table = WORKERS.lock().unwrap_or_else(|e| e.into_inner());
    table.get((handle as usize).checked_sub(1)?)?.clone()
}

/// Copies `len` bytes into a system-allocated block for [`msrt_worker_spawn`]'s argument.
/// The worker takes ownership with [`msrt_worker_arg_take`].
///
/// # Safety
/// `p` is readable for `len` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_worker_arg_new(p: *const u8, len: usize) -> *mut u8 {
    // SAFETY: a plain system block of `8 + len` bytes: the length, then the bytes.
    unsafe {
        let block = crate::sys::malloc(8 + len).cast::<u8>();
        if block.is_null() {
            crate::fault::fatal(b"out of memory");
        }
        block.cast::<usize>().write_unaligned(len);
        core::ptr::copy_nonoverlapping(p, block.add(8), len);
        block
    }
}

/// Moves an argument block into the calling isolate: `*out` becomes an owned String and the
/// system block is freed.
///
/// # Safety
/// `block` came from [`msrt_worker_arg_new`] and is taken once; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_worker_arg_take(block: *mut u8, out: *mut StrVal) {
    // SAFETY: the block holds its length and that many bytes.
    unsafe {
        let len = block.cast::<usize>().read_unaligned();
        *out = crate::string::from_bytes(core::slice::from_raw_parts(block.add(8), len));
        crate::sys::free(block.cast());
    }
}

/// Starts a worker running `entry(arg)` and returns its handle, or 0 when too many workers are
/// alive or the thread cannot start (the argument block is then freed). When the worker ends it
/// posts `done` (a remote token of the caller's isolate) with its outcome plus one.
///
/// # Safety
/// `entry` is a function of this program; `arg` is null or from [`msrt_worker_arg_new`].
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_worker_spawn(entry: Entry, arg: *mut u8, done: u64) -> u64 {
    let worker = Arc::new(Worker {
        thread: Mutex::new(None),
        slot: AtomicUsize::new(NO_SLOT),
        outcome: Mutex::new((0, Vec::new())),
    });
    let handle = {
        let mut table = WORKERS.lock().unwrap_or_else(|e| e.into_inner());
        let live = table.iter().filter(|w| w.is_some()).count();
        if live >= MAX_WORKERS {
            return 0;
        }
        let at = table.iter().position(Option::is_none).unwrap_or_else(|| {
            table.push(None);
            table.len() - 1
        });
        table[at] = Some(worker.clone());
        at as u64 + 1
    };
    let (entry, arg) = (entry as usize, arg as usize);
    let w = worker.clone();
    let spawned = std::thread::Builder::new()
        .stack_size(1 << 20)
        .spawn(move || {
            // SAFETY: `entry` and `arg` were valid at spawn and move to this thread with the call.
            unsafe {
                run(
                    &w,
                    core::mem::transmute::<usize, Entry>(entry),
                    arg as *mut u8,
                    done,
                )
            }
        });
    match spawned {
        Ok(t) => {
            *worker.thread.lock().unwrap_or_else(|e| e.into_inner()) = Some(t);
            handle
        }
        Err(_) => {
            WORKERS.lock().unwrap_or_else(|e| e.into_inner())[handle as usize - 1] = None;
            if arg != 0 {
                // SAFETY: the worker never ran, so the block is still ours.
                unsafe { crate::sys::free(arg as *mut c_void) };
            }
            0
        }
    }
}

/// The worker thread: sets up its isolate, runs the entry as the main task, tears down.
///
/// # Safety
/// See [`msrt_worker_spawn`].
unsafe fn run(w: &Worker, entry: Entry, arg: *mut u8, done: u64) {
    crate::alloc::claim_arena(false);
    crate::start::install_thread_fault_handler();
    w.slot.store(isolate::id(), Ordering::Release);
    // SAFETY: this thread is the new isolate's only one.
    let outcome = unsafe { crate::task::run_worker_task(entry, arg) };
    *w.outcome.lock().unwrap_or_else(|e| e.into_inner()) = outcome.clone();
    crate::task::teardown();
    isolate::unregister();
    crate::alloc::release_arena();
    msrt_token_post_remote(done, outcome.0 as u64 + 1);
}

/// Asks the worker to stop: its main task sees a pending cancellation at its next poll or wait.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_worker_cancel(handle: u64) {
    if let Some(w) = find(handle) {
        let slot = w.slot.load(Ordering::Acquire);
        if slot != NO_SLOT {
            isolate::raise_cancel(slot, crate::sys::SIGTERM as u8);
        }
    }
}

/// Waits for the worker's thread to end and returns its outcome: 0 returned, 1 fault (report in
/// `*msg_out`, owned by the caller), 2 cancelled. Each worker is joined once.
///
/// # Safety
/// `msg_out` is null or writable.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_worker_join(handle: u64, msg_out: *mut StrVal) -> u8 {
    let Some(w) = find(handle) else {
        crate::fault::fault(b"join: no such worker");
    };
    if let Some(t) = w.thread.lock().unwrap_or_else(|e| e.into_inner()).take() {
        let _ = t.join();
    }
    WORKERS.lock().unwrap_or_else(|e| e.into_inner())[handle as usize - 1] = None;
    let (status, report) =
        core::mem::take(&mut *w.outcome.lock().unwrap_or_else(|e| e.into_inner()));
    if !msg_out.is_null() {
        // SAFETY: writable by contract.
        unsafe {
            *msg_out = if report.is_empty() {
                crate::string::NO_STR
            } else {
                crate::string::from_bytes(&report)
            };
        }
    }
    status
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::task::{
        TOKEN_REMOTE, msrt_task_sleep, msrt_token_free, msrt_token_new, msrt_token_park,
    };
    use core::sync::atomic::AtomicU64;

    static SUM: AtomicU64 = AtomicU64::new(0);

    unsafe extern "C-unwind" fn adds(arg: *mut u8) {
        let mut s = crate::string::NO_STR;
        // SAFETY: `arg` is a block from `msrt_worker_arg_new`.
        unsafe { msrt_worker_arg_take(arg, &mut s) };
        // Allocate and free in this isolate's own arena across a sleep.
        let v: Vec<u8> = (0..1000u32).map(|i| i as u8).collect();
        // SAFETY: sleeps this isolate's main task.
        unsafe { msrt_task_sleep(1_000_000) };
        // SAFETY: `s` is a live owned string.
        let n = unsafe { crate::string::bytes(&s) }.len() as u64 + v.len() as u64;
        SUM.fetch_add(n, Ordering::SeqCst);
        // SAFETY: owned string of this isolate.
        unsafe { crate::string::release_opt(&s) };
    }

    unsafe extern "C-unwind" fn sleeps(_: *mut u8) {
        for _ in 0..1000 {
            // SAFETY: sleeps this isolate's main task.
            unsafe { msrt_task_sleep(10_000_000) };
            if crate::fault::cancel_flag().load(Ordering::Relaxed) != 0 {
                crate::fault::msrt_cancelled();
            }
        }
    }

    unsafe extern "C-unwind" fn faults(_: *mut u8) {
        crate::fault::fault(b"worker boom");
    }

    /// Spawns `entry`, waits for its completion token, and returns the join outcome.
    fn run_worker(entry: Entry, bytes: &[u8], cancel_after_ms: Option<i64>) -> (u8, Vec<u8>) {
        // SAFETY: parks the test thread's flow on a token the worker posts.
        unsafe {
            let done = msrt_token_new(TOKEN_REMOTE);
            let arg = msrt_worker_arg_new(bytes.as_ptr(), bytes.len());
            let h = msrt_worker_spawn(entry, arg, done);
            assert_ne!(h, 0);
            if let Some(ms) = cancel_after_ms {
                msrt_task_sleep(ms * 1_000_000);
                msrt_worker_cancel(h);
            }
            let mut v = 0;
            assert_eq!(msrt_token_park(done, -1, &mut v), 0);
            msrt_token_free(done);
            let mut msg = crate::string::NO_STR;
            let status = msrt_worker_join(h, &mut msg);
            let report = if msg.is_empty() {
                Vec::new()
            } else {
                crate::string::bytes(&msg).to_vec()
            };
            crate::string::release_opt(&msg);
            (status, report)
        }
    }

    #[test]
    fn a_worker_runs_in_its_own_isolate_and_returns() {
        let _g = crate::testutil::lock();
        SUM.store(0, Ordering::SeqCst);
        crate::task::teardown();
        let before = crate::alloc::live_blocks();
        let r = run_worker(adds, b"hello", None);
        assert_eq!(r.0, 0, "{}", String::from_utf8_lossy(&r.1));
        assert_eq!(SUM.load(Ordering::SeqCst), 1005);
        crate::task::teardown();
        assert_eq!(crate::alloc::live_blocks(), before);
    }

    #[test]
    fn a_fault_in_a_worker_comes_back_as_a_report() {
        let _g = crate::testutil::lock();
        let (status, report) = run_worker(faults, b"", None);
        assert_eq!(status, 1);
        assert!(String::from_utf8_lossy(&report).contains("worker boom"));
        crate::task::teardown();
    }

    #[test]
    fn cancelling_a_worker_ends_its_main_task() {
        let _g = crate::testutil::lock();
        assert_eq!(run_worker(sleeps, b"", Some(30)).0, 2);
        crate::task::teardown();
    }
}
