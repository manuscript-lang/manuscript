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
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

/// Entry of a worker: called on the worker's main task with the argument block.
pub type Entry = unsafe extern "C-unwind" fn(*mut u8);

/// Most workers alive at once; a spawn beyond it fails.
const MAX_WORKERS: usize = 256;
/// Cancellation follows the worker's lifetime, rather than a reusable isolate slot.
#[derive(Default)]
struct Cancellation {
    slot: Option<usize>,
    requested: bool,
}

struct Worker {
    thread: Mutex<Option<std::thread::JoinHandle<()>>>,
    /// Serializes cancellation with publication and retirement of the isolate.
    cancellation: Mutex<Cancellation>,
    /// The status, then a report in a system block of its own: it outlives the worker's arena.
    outcome: Mutex<(u8, usize, usize)>,
    /// The remote token of the caller that spawned through [`msrt_worker_start`].
    done: AtomicU64,
}

struct WorkerSlot {
    generation: u32,
    worker: Option<Arc<Worker>>,
}

static WORKERS: Mutex<Vec<WorkerSlot>> = Mutex::new(Vec::new());

fn slot_index(handle: u64) -> Option<usize> {
    (handle as u32 as usize).checked_sub(1)
}

fn find(handle: u64) -> Option<Arc<Worker>> {
    let table = WORKERS.lock().unwrap_or_else(|e| e.into_inner());
    let slot = table.get(slot_index(handle)?)?;
    if slot.generation != (handle >> 32) as u32 {
        return None;
    }
    slot.worker.clone()
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
        cancellation: Mutex::new(Cancellation::default()),
        outcome: Mutex::new((0, 0, 0)),
        done: AtomicU64::new(0),
    });
    let handle = {
        let mut table = WORKERS.lock().unwrap_or_else(|e| e.into_inner());
        let live = table.iter().filter(|s| s.worker.is_some()).count();
        if live >= MAX_WORKERS {
            return 0;
        }
        // Never wrap a generation: retire an exhausted slot instead of reviving stale handles.
        let at = table
            .iter()
            .position(|s| s.worker.is_none() && s.generation < u32::MAX)
            .unwrap_or_else(|| {
                table.push(WorkerSlot {
                    generation: 0,
                    worker: None,
                });
                table.len() - 1
            });
        let slot = &mut table[at];
        slot.generation += 1;
        slot.worker = Some(worker.clone());
        (u64::from(slot.generation) << 32) | (at as u64 + 1)
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
            WORKERS.lock().unwrap_or_else(|e| e.into_inner())[slot_index(handle).unwrap()].worker =
                None;
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
    isolate::mark_worker();
    crate::alloc::claim_arena(false);
    crate::start::install_thread_fault_handler();
    {
        let mut cancellation = w.cancellation.lock().unwrap_or_else(|e| e.into_inner());
        let slot = isolate::id();
        cancellation.slot = Some(slot);
        if cancellation.requested {
            isolate::raise_cancel(slot, crate::sys::SIGTERM as u8);
        }
    }
    // SAFETY: this thread is the new isolate's only one.
    let outcome = unsafe { crate::task::run_worker_task(entry, arg) };
    let (status, report) = outcome;
    let mut block = (0usize, 0usize);
    if !report.is_empty() {
        // SAFETY: a system block holding a copy of the report.
        unsafe {
            let p = crate::sys::malloc(report.len()).cast::<u8>();
            if !p.is_null() {
                core::ptr::copy_nonoverlapping(report.as_ptr(), p, report.len());
                block = (p as usize, report.len());
            }
        }
    }
    drop(report);
    *w.outcome.lock().unwrap_or_else(|e| e.into_inner()) = (status, block.0, block.1);
    {
        // A canceller must finish before teardown can free task headers or reuse the slot.
        let mut cancellation = w.cancellation.lock().unwrap_or_else(|e| e.into_inner());
        cancellation.slot = None;
        crate::task::teardown();
        isolate::unregister();
    }
    crate::alloc::release_arena();
    let end = msrt_worker_end();
    if end != 0 {
        crate::pipe::msrt_pipe_close(end);
    }
    msrt_token_post_remote(done, status as u64 + 1);
}

/// Asks the worker to stop: its main task sees a pending cancellation at its next poll or wait.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_worker_cancel(handle: u64) {
    if let Some(w) = find(handle) {
        let mut cancellation = w.cancellation.lock().unwrap_or_else(|e| e.into_inner());
        cancellation.requested = true;
        if let Some(slot) = cancellation.slot {
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
    WORKERS.lock().unwrap_or_else(|e| e.into_inner())[slot_index(handle).unwrap()].worker = None;
    let (status, ptr, len) =
        core::mem::take(&mut *w.outcome.lock().unwrap_or_else(|e| e.into_inner()));
    let report = if ptr == 0 {
        crate::string::NO_STR
    } else {
        // SAFETY: the block holds `len` bytes and is ours once.
        unsafe {
            let s = crate::string::from_bytes(core::slice::from_raw_parts(ptr as *const u8, len));
            crate::sys::free(ptr as *mut c_void);
            s
        }
    };
    if msg_out.is_null() {
        // SAFETY: an owned string nobody reads.
        unsafe { crate::string::release_opt(&report) };
    } else {
        // SAFETY: writable by contract.
        unsafe { *msg_out = report };
    }
    status
}

crate::isolate_static! {
    /// The pipe end this isolate's worker owns, or 0 outside a worker.
    static END: i64 = 0;
}

/// The pipe end the calling worker was started with, or 0 outside a worker.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_worker_end() -> i64 {
    // SAFETY: this isolate's state.
    unsafe { *END.ptr() }
}

/// What a started entry needs: the pipe end and a capture-free closure's code and drop entries.
#[repr(C)]
struct StartArg {
    end: i64,
    code: *const u8,
    drop: Option<ms_rt_abi::DropFn>,
}

/// The worker's main task: rebuilds the entry closure in this isolate's arena and calls it.
unsafe extern "C-unwind" fn closure_main(arg: *mut u8) {
    // SAFETY: `arg` is the system block `msrt_worker_start` made; the closure has no captures,
    // so a header and the code pointer are all of it.
    unsafe {
        let a = arg.cast::<StartArg>().read();
        crate::sys::free(arg.cast());
        *END.ptr() = a.end;
        let size = core::mem::size_of::<ms_rt_abi::Closure>();
        let c = crate::alloc::alloc(size).cast::<ms_rt_abi::Closure>();
        c.write(ms_rt_abi::Closure {
            hdr: ms_rt_abi::Obj {
                rc: 1,
                drop: a.drop,
            },
            code: a.code,
        });
        let code: unsafe extern "C-unwind" fn(*mut ms_rt_abi::Closure) =
            core::mem::transmute(a.code);
        code(c);
        crate::obj::release(c.cast());
    }
}

/// Starts a worker that runs `entry`, a closure without captures (a named `def`), and owns the
/// pipe end `end`, which is closed when the worker ends. Returns the handle, or 0 when the
/// worker could not start. [`msrt_worker_wait`] collects it.
///
/// # Safety
/// `entry` is a live capture-free closure.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_worker_start(entry: *mut ms_rt_abi::Closure, end: i64) -> i64 {
    // SAFETY: `entry` is live by contract; the block is freed by the worker or on failure.
    unsafe {
        let block = crate::sys::malloc(core::mem::size_of::<StartArg>()).cast::<StartArg>();
        if block.is_null() {
            crate::fault::fatal(b"out of memory");
        }
        block.write(StartArg {
            end,
            code: (*entry).code,
            drop: (*entry).hdr.drop,
        });
        let done = crate::task::msrt_token_new(crate::task::TOKEN_REMOTE);
        let handle = msrt_worker_spawn(closure_main, block.cast(), done);
        if handle == 0 {
            crate::task::msrt_token_free(done);
            return 0;
        }
        if let Some(w) = find(handle) {
            w.done.store(done, Ordering::Release);
        }
        handle as i64
    }
}

/// Waits for the worker `handle` to end and collects it. Returns a string: the outcome digit
/// (`0` returned, `1` fault, `2` cancelled) followed by the fault report, if any.
///
/// # Safety
/// `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_worker_wait(handle: i64, out: *mut StrVal) {
    let Some(w) = find(handle as u64) else {
        crate::fault::fault(b"wait: no such worker");
    };
    let done = w.done.load(Ordering::Acquire);
    // SAFETY: the token is this isolate's; parked once, then freed.
    let cancelled = unsafe {
        let woke = crate::task::msrt_token_park(done, -1, core::ptr::null_mut());
        crate::task::msrt_token_free(done);
        woke != 0
    };
    let mut report = crate::string::NO_STR;
    // SAFETY: `report` is writable.
    let status = unsafe { msrt_worker_join(handle as u64, &mut report) };
    let mut text = vec![b'0' + status];
    // SAFETY: an owned string or the empty one.
    unsafe {
        if !report.is_empty() {
            text.extend_from_slice(crate::string::bytes(&report));
        }
        crate::string::release_opt(&report);
    }
    // SAFETY: `out` is writable by contract.
    unsafe { *out = crate::string::from_bytes(&text) };
    if cancelled {
        crate::fault::msrt_cancelled();
    }
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

    unsafe extern "C-unwind" fn returns(_: *mut u8) {}

    #[test]
    fn collected_handles_do_not_address_replacement_workers() {
        let _g = crate::testutil::lock();
        // SAFETY: entries need no arguments; each worker is joined once.
        unsafe {
            let old = msrt_worker_spawn(returns, core::ptr::null_mut(), 0);
            assert_ne!(old, 0);
            assert_eq!(msrt_worker_join(old, core::ptr::null_mut()), 0);
            let new = msrt_worker_spawn(returns, core::ptr::null_mut(), 0);
            assert_ne!(new, 0);
            let stale_matches = find(old).is_some();
            assert_eq!(msrt_worker_join(new, core::ptr::null_mut()), 0);
            assert!(
                !stale_matches,
                "a collected handle must not name a replacement worker"
            );
        }
        crate::task::teardown();
    }

    static RELEASE_ENTRY: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
    static ENTERED: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

    unsafe extern "C-unwind" fn briefly_waits(_: *mut u8) {
        ENTERED.store(true, Ordering::Release);
        let until = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while !RELEASE_ENTRY.load(Ordering::Acquire) && std::time::Instant::now() < until {
            std::thread::yield_now();
        }
        for _ in 0..5 {
            // SAFETY: this worker owns its scheduler.
            unsafe { msrt_task_sleep(1_000_000) };
            if crate::fault::cancel_flag().load(Ordering::Relaxed) != 0 {
                crate::fault::msrt_cancelled();
            }
        }
    }

    #[test]
    fn cancellation_immediately_after_spawn_is_remembered() {
        let _g = crate::testutil::lock();
        let mut returned = 0;
        for _ in 0..32 {
            // SAFETY: entry ignores its argument and each handle is joined once.
            unsafe {
                RELEASE_ENTRY.store(false, Ordering::Release);
                let h = msrt_worker_spawn(briefly_waits, core::ptr::null_mut(), 0);
                assert_ne!(h, 0);
                msrt_worker_cancel(h);
                RELEASE_ENTRY.store(true, Ordering::Release);
                returned += usize::from(msrt_worker_join(h, core::ptr::null_mut()) == 0);
            }
        }
        crate::task::teardown();
        assert_eq!(returned, 0, "startup lost cancellation requests");
    }

    #[test]
    fn cancelling_completed_worker_does_not_cancel_reused_isolate() {
        let _g = crate::testutil::lock();
        // SAFETY: entries ignore their arguments and each handle is joined once.
        unsafe {
            let old = msrt_worker_spawn(returns, core::ptr::null_mut(), 0);
            let old_worker = find(old).unwrap();
            let until = std::time::Instant::now() + std::time::Duration::from_secs(5);
            while !old_worker
                .thread
                .lock()
                .unwrap()
                .as_ref()
                .unwrap()
                .is_finished()
            {
                assert!(
                    std::time::Instant::now() < until,
                    "old worker did not finish"
                );
                std::thread::yield_now();
            }
            RELEASE_ENTRY.store(false, Ordering::Release);
            ENTERED.store(false, Ordering::Release);
            let new = msrt_worker_spawn(briefly_waits, core::ptr::null_mut(), 0);
            let until = std::time::Instant::now() + std::time::Duration::from_secs(5);
            while !ENTERED.load(Ordering::Acquire) && std::time::Instant::now() < until {
                std::thread::yield_now();
            }
            let entered = ENTERED.load(Ordering::Acquire);
            msrt_worker_cancel(old);
            RELEASE_ENTRY.store(true, Ordering::Release);
            let status = msrt_worker_join(new, core::ptr::null_mut());
            assert_eq!(msrt_worker_join(old, core::ptr::null_mut()), 0);
            crate::task::teardown();
            assert!(
                entered,
                "replacement worker did not start within five seconds"
            );
            assert_eq!(status, 0, "completed worker cancelled a different isolate");
        }
    }

    unsafe extern "C-unwind" fn empty_closure(_: *mut ms_rt_abi::Closure) {}

    unsafe extern "C" fn drop_empty_closure(obj: *mut ms_rt_abi::Obj) {
        // SAFETY: the worker owns this capture-free allocation.
        unsafe { crate::alloc::free(obj.cast()) };
    }

    #[test]
    fn worker_closes_pipe_before_parent_publishes_handle_metadata() {
        let _g = crate::testutil::lock();
        // Reproduce the schedule where the worker finishes before msrt_worker_start can
        // publish metadata after spawn. The argument already transfers ownership of the end.
        // SAFETY: the entry is capture-free and the worker takes the allocated argument once.
        unsafe {
            let parent = crate::pipe::msrt_pipe_new();
            let end = crate::pipe::msrt_pipe_peer(parent);
            let block = crate::sys::malloc(core::mem::size_of::<StartArg>()).cast::<StartArg>();
            assert!(!block.is_null());
            block.write(StartArg {
                end,
                code: empty_closure as *const u8,
                drop: Some(drop_empty_closure),
            });
            let h = msrt_worker_spawn(closure_main, block.cast(), 0);
            assert_ne!(h, 0);
            assert_eq!(msrt_worker_join(h, core::ptr::null_mut()), 0);
            let message = crate::string::from_bytes(b"probe");
            let send = crate::pipe::msrt_pipe_send(parent, &message);
            crate::string::release_opt(&message);
            crate::pipe::msrt_pipe_close(end);
            crate::pipe::msrt_pipe_close(parent);
            crate::task::teardown();
            assert_eq!(send, 1, "exited worker left its pipe end open");
        }
    }

    #[test]
    fn cancelling_a_worker_ends_its_main_task() {
        let _g = crate::testutil::lock();
        assert_eq!(run_worker(sleeps, b"", Some(30)).0, 2);
        crate::task::teardown();
    }
}
