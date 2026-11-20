//! The blocking pool of the C runtime (`runtime/std/pool.c`) for jobs written in Rust: a job is a plain function
//! over a borrowed input, run on a pool thread while the submitting task parks. The pool is the C one, so a
//! `Lane` no longer caps name lookups at half the threads.
#![allow(unsafe_code)]

use core::ffi::c_void;

/// Which cap a job counts against (the C pool has one cap for all).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Lane {
    /// Name lookups.
    Dns,
    /// Everything else.
    General,
}

/// The wait ended because the task was cancelled.
#[derive(Debug, PartialEq, Eq)]
pub struct Cancelled;

const DONE: i32 = 0;
const CANCELLED: i32 = 2;

unsafe extern "C" {
    fn ms_sched_pool_run(
        run: unsafe extern "C" fn(*mut c_void),
        release: unsafe extern "C" fn(*mut c_void),
        data: *mut c_void,
        timeout_ns: i64,
    ) -> i32;
}

struct Job<I, O> {
    input: I,
    f: fn(&I) -> O,
    output: Option<O>,
}

unsafe extern "C" fn run<I, O>(data: *mut c_void) {
    // SAFETY: `data` is the live `Job` the submitter leaked; only the pool thread runs it.
    let job = unsafe { &mut *data.cast::<Job<I, O>>() };
    job.output = Some((job.f)(&job.input));
}

unsafe extern "C" fn release<I, O>(data: *mut c_void) {
    // SAFETY: the pool owns an abandoned job and frees it once.
    drop(unsafe { Box::from_raw(data.cast::<Job<I, O>>()) });
}

/// Runs `f(&input)` on the pool and parks until it finishes, or `timeout_ns` passes (negative: no limit):
/// `Ok(None)` then, and the late result is dropped. `f` must not call into the runtime.
pub fn try_run<I: Send + Sync + 'static, O: Send + 'static>(
    _lane: Lane,
    input: I,
    f: fn(&I) -> O,
    timeout_ns: i64,
) -> Result<Option<O>, Cancelled> {
    let job = Box::into_raw(Box::new(Job {
        input,
        f,
        output: None,
    }));
    // SAFETY: on DONE the job is ours again; otherwise the pool frees it through `release`.
    let result = unsafe { ms_sched_pool_run(run::<I, O>, release::<I, O>, job.cast(), timeout_ns) };
    if result != DONE {
        return if result == CANCELLED {
            Err(Cancelled)
        } else {
            Ok(None)
        };
    }
    // SAFETY: the job finished and nothing else holds it.
    let job = unsafe { Box::from_raw(job) };
    Ok(job.output)
}
