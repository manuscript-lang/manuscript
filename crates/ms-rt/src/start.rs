//! Process arguments and start time, from the C entry (`runtime/entry/start.c`).
#![allow(unsafe_code)]

use ms_rt_abi::VecVal;

unsafe extern "C-unwind" {
    pub fn msrt_argv(out: *mut VecVal);
    pub safe fn msrt_start_nanos() -> i64;
}

unsafe extern "C" {
    fn ms_start_attach_thread() -> bool;
}

/// Gives the calling thread a reactor and scheduler so a unit test can run tasks; once per thread.
pub fn attach_test_thread() {
    use std::cell::Cell;
    thread_local!(static DONE: Cell<bool> = const { Cell::new(false) });
    if !DONE.with(Cell::get) {
        // SAFETY: no preconditions; the thread keeps the scheduler until it ends.
        assert!(unsafe { ms_start_attach_thread() }, "cannot open the event loop");
        DONE.with(|d| d.set(true));
    }
}
