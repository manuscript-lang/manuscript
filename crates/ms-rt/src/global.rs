//! Runtime state cells. Every runtime `static` that is not an atomic is one of two kinds:
//!
//! - [`Process`]: one copy for the whole process, written only before other isolates start or
//!   by the main isolate. It is `Sync` by that convention, not by a lock.
//! - [`isolate_static!`]: one copy per isolate (thread-local). A worker isolate starts with the
//!   `const` initial value, so isolates share nothing through these.
//!
//! See `proposals/worker-threads.md` for the classification of each static.
use core::cell::UnsafeCell;

/// A `static`-friendly cell shared by the whole process. The runtime executes user code on the
/// main isolate's thread, so no synchronization is needed; the signal handlers only touch
/// atomics and preallocated buffers. Unit tests serialize access with a lock (see `testutil`).
pub struct Process<T>(UnsafeCell<T>);

// SAFETY: access is by the main isolate only, or before other isolates start (see above).
unsafe impl<T> Sync for Process<T> {}

impl<T> Process<T> {
    pub const fn new(value: T) -> Self {
        Process(UnsafeCell::new(value))
    }

    /// Raw pointer to the contents.
    #[inline(always)]
    pub fn ptr(&self) -> *mut T {
        self.0.get()
    }
}

/// Declares per-isolate state with the same `NAME.ptr()` access as [`Process`].
///
/// ```ignore
/// isolate_static! { static DEPTH: usize = 0; }
/// unsafe { *DEPTH.ptr() += 1 };
/// ```
///
/// The cell is a `const`-initialized `thread_local!` wrapped in `ManuallyDrop`, so access is a
/// single thread-pointer-relative address with no lazy-initialization or destructor check. The
/// value is never dropped at thread exit (isolates are torn down by the runtime).
#[macro_export]
macro_rules! isolate_static {
    ($($(#[$meta:meta])* $vis:vis static $name:ident : $ty:ty = $init:expr;)+) => {$(
        #[allow(non_snake_case)]
        $vis mod $name {
            #[allow(unused_imports)]
            use super::*;

            ::std::thread_local! {
                static CELL: ::core::cell::UnsafeCell<::core::mem::ManuallyDrop<$ty>> =
                    const { ::core::cell::UnsafeCell::new(::core::mem::ManuallyDrop::new($init)) };
            }

            pub struct Ref;

            impl Ref {
                /// Raw pointer to this isolate's copy.
                #[inline(always)]
                pub fn ptr(&self) -> *mut $ty {
                    CELL.with(|c| c.get().cast::<$ty>())
                }
            }
        }
        $(#[$meta])* $vis static $name: $name::Ref = $name::Ref;
    )+};
}
