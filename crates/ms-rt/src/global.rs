//! Single-threaded global state cell.
use core::cell::UnsafeCell;

/// A `static`-friendly cell. The runtime executes user code on one thread (the
/// dedicated main thread) so no synchronization is needed; the signal handlers
/// only touch atomics and preallocated buffers. Unit tests serialize access with
/// a lock (see `testutil`).
pub struct Global<T>(UnsafeCell<T>);

// SAFETY: access is single threaded by the runtime's execution model (see above).
unsafe impl<T> Sync for Global<T> {}

impl<T> Global<T> {
    pub const fn new(value: T) -> Self {
        Global(UnsafeCell::new(value))
    }

    /// Raw pointer to the contents.
    #[inline(always)]
    pub fn ptr(&self) -> *mut T {
        self.0.get()
    }
}
