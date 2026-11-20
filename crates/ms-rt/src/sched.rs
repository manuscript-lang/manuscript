//! Where the calling code runs, and what must stay on its thread, over `runtime/include/ms_sched.h`.
#![allow(unsafe_code)]

/// Most scheduler threads.
pub const MAX_THREADS: usize = 63;

unsafe extern "C" {
    fn ms_sched_thread() -> u32;
    fn ms_sched_pin_adjust(thread: u32, delta: i32);
    fn ms_sched_pin_main();
}

/// The calling thread's scheduler index, or `MAX_THREADS` for a thread that is not a scheduler thread.
pub fn thread() -> usize {
    // SAFETY: reads the thread's registration.
    let index = unsafe { ms_sched_thread() };
    (index as usize).min(MAX_THREADS)
}

/// A native stream's place: while one is alive, promises started on the thread that last used it run there, since
/// the Rust session of a stream is not thread-safe.
pub struct Pin(core::cell::Cell<u32>);

const UNPLACED: u32 = u32::MAX;

impl Pin {
    pub const fn new() -> Pin {
        Pin(core::cell::Cell::new(UNPLACED))
    }

    /// Records a use on the calling thread; the pin follows the stream to where it is used.
    pub fn touch(&self) {
        let now = thread() as u32;
        let before = self.0.get();
        if before == now {
            return;
        }
        // SAFETY: counts by thread index.
        unsafe {
            if before != UNPLACED {
                ms_sched_pin_adjust(before, -1);
            }
            ms_sched_pin_adjust(now, 1);
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
        if at != UNPLACED {
            // SAFETY: undoes the count `touch` made.
            unsafe { ms_sched_pin_adjust(at, -1) };
        }
    }
}

/// Records that the main thread uses state only it may use (`ffi::Global`): promises started there stay there.
pub(crate) fn pin_main() {
    // SAFETY: sets a process flag.
    unsafe { ms_sched_pin_main() }
}
